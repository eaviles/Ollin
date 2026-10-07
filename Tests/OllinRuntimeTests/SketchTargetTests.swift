import Foundation
@testable import OllinRuntime
import Testing

/// A sketch split across a SwiftPM target, read the way the live hosts read
/// it: the manifest's targets, the files a compile takes in, the flags the
/// target's settings ask for, the resources laid out as the bundle lays them
/// out, and what runs for a folder or a file a person names.
///
/// Most checks read a manifest description handed over as JSON, the shape
/// `swift package dump-package` writes. The ones under *A real package* write
/// a package to a scratch folder and let SwiftPM read it, which is the proof
/// that the shape is still the one SwiftPM writes.
@Suite
struct SketchTargetTests {

    // MARK: Scratch folders

    /// A fresh folder for one test, spelled the way `SketchTarget` spells
    /// paths, so a comparison against it is a comparison of one spelling.
    private func scratch() -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("SketchTargetTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return SketchTarget.resolved(dir)
    }

    private func write(_ text: String, _ path: String) {
        try! FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func path(_ root: String, _ relative: String) -> String {
        (root as NSString).appendingPathComponent(relative)
    }

    private func manifest(_ json: String, root: String) throws -> SketchTarget.Manifest {
        try SketchTarget.Manifest.parse(Data(json.utf8), root: root)
    }

    /// The description SwiftPM writes for a package with a library, an
    /// executable that depends on it, a test target, and a plugin.
    private let described = #"""
    {
      "name": "Garden",
      "toolsVersion": {"_version": "6.0.0"},
      "swiftLanguageVersions": ["5", "6"],
      "targets": [
        {"name": "Shared", "type": "regular", "dependencies": [], "exclude": [],
         "resources": [], "settings": []},
        {"name": "Garden", "type": "executable", "path": "Sketches/Garden",
         "dependencies": [{"byName": ["Shared", null]}, {"target": ["Leaves", null]},
                          {"product": ["Ollin", "Ollin", null, null]}],
         "exclude": ["Old"], "sources": ["Main", "Extra.swift"],
         "resources": [{"path": "Images", "rule": {"process": {}}},
                       {"path": "ripple.metal", "rule": {"copy": {}}},
                       {"path": "data.bin", "rule": {"embedInCode": {}}}],
         "settings": [
           {"tool": "swift", "kind": {"define": {"_0": "GARDEN"}}},
           {"tool": "swift", "kind": {"defaultIsolation": {"_0": "MainActor"}}},
           {"tool": "linker", "kind": {"unsafeFlags": {"_0": ["-Xlinker", "-export_dynamic"]}}}
         ]},
        {"name": "GardenTests", "type": "test", "dependencies": [], "exclude": [],
         "resources": [], "settings": []},
        {"name": "Tool", "type": "plugin", "dependencies": [], "exclude": [],
         "resources": [], "settings": []}
      ]
    }
    """#

    // MARK: Reading the manifest

    @Test func theManifestReadsTargetsSourcesResourcesAndDependencies() throws {
        let root = scratch()
        let targets = try manifest(described, root: root).targets
        #expect(targets.map(\.name) == ["Shared", "Garden"])

        let garden = try #require(targets.last)
        let folder = path(root, "Sketches/Garden")
        #expect(garden.packageRoot == root)
        #expect(garden.directory == folder)
        #expect(garden.excluded == [path(folder, "Old")])
        #expect(garden.declaredSources == [path(folder, "Main"), path(folder, "Extra.swift")])
        #expect(garden.resources == [
            .init(rule: .process, path: path(folder, "Images")),
            .init(rule: .copy, path: path(folder, "ripple.metal")),
            .init(rule: .embedInCode, path: path(folder, "data.bin")),
        ])
        #expect(garden.dependencies == ["Shared", "Leaves", "Ollin"])
        // Only the compiler's settings: a linker flag is not a sketch compile's.
        #expect(garden.settings.map(\.kind) == ["define", "defaultIsolation"])
        #expect(garden.packageLanguageMode == "6")
    }

    @Test func aTargetWithNoPathLivesUnderTheFirstConventionalFolderThatExists() throws {
        let root = scratch()
        try FileManager.default.createDirectory(atPath: path(root, "src/Shared"), withIntermediateDirectories: true)
        let targets = try manifest(described, root: root).targets
        #expect(targets.first?.directory == path(root, "src/Shared"))

        // With none of them there, SwiftPM's first choice.
        let bare = try manifest(described, root: scratch()).targets
        #expect(bare.first?.directory.hasSuffix("/Sources/Shared") == true)
    }

    @Test func theLanguageModeIsTheNewestListedOrTheToolsVersions() {
        typealias M = SketchTarget.Manifest
        #expect(M.languageMode(listed: ["5", "6"], toolsVersion: "5.9.0") == "6")
        #expect(M.languageMode(listed: ["5"], toolsVersion: "6.2.0") == "5")
        #expect(M.languageMode(listed: ["4.2", "4"], toolsVersion: "6.0.0") == "4.2")
        #expect(M.languageMode(listed: nil, toolsVersion: "6.0.0") == "6")
        #expect(M.languageMode(listed: [], toolsVersion: "5.10.0") == "5")
        // A mode this compiler does not have is passed over, as SwiftPM does.
        #expect(M.languageMode(listed: ["7", "6"], toolsVersion: "6.0.0") == "6")
    }

    @Test func aDescriptionThatIsNotJSONIsAReadableFailure() {
        #expect(throws: ManifestError.self) {
            try manifest("error: no such file", root: "/tmp/Nowhere")
        }
    }

    // MARK: The target's settings

    private func target(settings: [SketchTarget.Setting], mode: String = "6") -> SketchTarget {
        SketchTarget(packageRoot: "/p", name: "T", directory: "/p/Sources/T", excluded: [],
                     declaredSources: nil, resources: [], settings: settings,
                     packageLanguageMode: mode, dependencies: [])
    }

    private func setting(_ kind: String, _ values: [String] = [],
                         configuration: String? = nil, platforms: [String] = []) -> SketchTarget.Setting {
        .init(kind: kind, values: values, configuration: configuration, platforms: platforms)
    }

    @Test func theTargetsSwiftSettingsBecomeCompilerFlags() {
        let flags = target(settings: [
            setting("define", ["GARDEN"]),
            setting("enableUpcomingFeature", ["ExistentialAny"]),
            setting("enableExperimentalFeature", ["Lifetimes"]),
            setting("defaultIsolation", ["MainActor"]),
            setting("strictMemorySafety"),
            setting("unsafeFlags", ["-Xfrontend", "-warn-long-function-bodies=100"]),
            setting("interoperabilityMode", ["Cxx"]),
        ]).compilerFlags(debug: false)
        #expect(flags == [
            "-swift-version", "6",
            "-DGARDEN",
            "-enable-upcoming-feature", "ExistentialAny",
            "-enable-experimental-feature", "Lifetimes",
            "-default-isolation", "MainActor",
            "-strict-memory-safety",
            "-Xfrontend", "-warn-long-function-bodies=100",
        ])
    }

    /// The manifest writes nonisolated default isolation as no actor at all.
    @Test func nonisolatedDefaultIsolationIsSpelledOut() {
        let flags = target(settings: [setting("defaultIsolation")]).compilerFlags(debug: false)
        #expect(flags.suffix(2) == ["-default-isolation", "nonisolated"])
    }

    @Test func aConditionedSettingAppliesOnlyWhereItsConditionHolds() {
        let conditioned = target(settings: [
            setting("define", ["IN_DEBUG"], configuration: "debug"),
            setting("define", ["IN_RELEASE"], configuration: "release"),
            setting("define", ["ON_MAC"], platforms: ["macos"]),
            setting("define", ["ON_PHONE"], platforms: ["ios"]),
        ])
        #expect(conditioned.compilerFlags(debug: false) == ["-swift-version", "6", "-DIN_RELEASE", "-DON_MAC"])
        #expect(conditioned.compilerFlags(debug: true) == ["-swift-version", "6", "-DIN_DEBUG", "-DON_MAC"])
    }

    @Test func aTargetsOwnLanguageModeWinsOverThePackages() {
        let flags = target(settings: [setting("swiftLanguageMode", ["5"])], mode: "6")
            .compilerFlags(debug: false)
        #expect(flags == ["-swift-version", "5"])
    }

    // MARK: The files a compile takes in

    @Test func everySwiftFileCompilesButMainHiddenExcludedAndResources() {
        let root = scratch()
        let folder = path(root, "Sources/T")
        for file in ["Sketch.swift", "Shapes/Ring.swift", "Shapes/Deep/Leaf.swift", "main.swift",
                     ".Hidden.swift", ".git/Stray.swift", "Old/Retired.swift", "Images/Generated.swift",
                     "notes.md", "Images/photo.png"] {
            write("// \(file)", path(folder, file))
        }
        let target = SketchTarget(
            packageRoot: root, name: "T", directory: folder,
            excluded: [path(folder, "Old")], declaredSources: nil,
            resources: [.init(rule: .process, path: path(folder, "Images"))],
            settings: [], packageLanguageMode: "6", dependencies: [])
        #expect(target.swiftSources() == [
            path(folder, "Shapes/Deep/Leaf.swift"),
            path(folder, "Shapes/Ring.swift"),
            path(folder, "Sketch.swift"),
        ])

        // A file added since is in the next walk; nothing is remembered.
        write("// later", path(folder, "Later.swift"))
        #expect(target.swiftSources().contains(path(folder, "Later.swift")))
    }

    @Test func declaredSourcesNarrowTheWalk() {
        let root = scratch()
        let folder = path(root, "Sources/T")
        for file in ["Main/Sketch.swift", "Main/Inner/Helper.swift", "Extra.swift", "Elsewhere.swift"] {
            write("// \(file)", path(folder, file))
        }
        let target = SketchTarget(
            packageRoot: root, name: "T", directory: folder, excluded: [],
            declaredSources: [path(folder, "Main"), path(folder, "Extra.swift")],
            resources: [], settings: [], packageLanguageMode: "6", dependencies: [])
        #expect(target.swiftSources() == [
            path(folder, "Extra.swift"),
            path(folder, "Main/Inner/Helper.swift"),
            path(folder, "Main/Sketch.swift"),
        ])
        #expect(target.holds(path(folder, "Main/Sketch.swift")))
        #expect(!target.holds(path(folder, "Elsewhere.swift")))
    }

    @Test func aFolderHoldsWhatIsInsideItByWholeComponents() {
        let target = SketchTarget(
            packageRoot: "/p", name: "A", directory: "/p/Sources/A", excluded: ["/p/Sources/A/Old"],
            declaredSources: nil, resources: [], settings: [], packageLanguageMode: "6", dependencies: [])
        #expect(target.holds("/p/Sources/A/Sketch.swift"))
        #expect(target.holds("/p/Sources/A/Deep/Helper.swift"))
        #expect(!target.holds("/p/Sources/AB/Sketch.swift"))
        #expect(!target.holds("/p/Sources/A/Old/Retired.swift"))
        // Excluding `Old` leaves a file whose name merely starts that way.
        #expect(target.holds("/p/Sources/A/Older.swift"))
    }

    // MARK: The bundle

    @Test func resourcesAreLaidOutAsTheBundleLaysThemOut() throws {
        let root = scratch()
        let folder = path(root, "Sources/T")
        for file in ["Images/photo.png", "Images/Nested/deeper.png", "Images/.DS_Store",
                     "Images/es.lproj/Greeting.strings", "Fonts/Display.otf", "ripple.metal",
                     "Shared/photo.png", "data.bin"] {
            write("x", path(folder, file))
        }
        let target = SketchTarget(
            packageRoot: root, name: "T", directory: folder, excluded: [], declaredSources: nil,
            resources: [
                .init(rule: .process, path: path(folder, "Images")),
                .init(rule: .copy, path: path(folder, "Fonts")),
                .init(rule: .process, path: path(folder, "ripple.metal")),
                .init(rule: .process, path: path(folder, "Shared")),
                .init(rule: .embedInCode, path: path(folder, "data.bin")),
                .init(rule: .copy, path: path(folder, "Missing")),
            ],
            settings: [], packageLanguageMode: "6", dependencies: [])
        #expect(target.declaresBundledResources)

        let bundle = path(scratch(), "Resources")
        try target.linkResources(into: bundle)
        let laidOut = try FileManager.default.contentsOfDirectory(atPath: bundle).sorted()
        // Flattened, the localization kept whole, the copied folder kept
        // whole, the second photo.png losing to the first, nothing hidden,
        // nothing embedded, nothing for a resource that is not there.
        #expect(laidOut == ["Fonts", "deeper.png", "es.lproj", "photo.png", "ripple.metal"])
        let photo = try FileManager.default.destinationOfSymbolicLink(atPath: path(bundle, "photo.png"))
        #expect(photo == path(folder, "Images/photo.png"))
        // The bundle finds a flattened file by name, as the package's does.
        #expect(Bundle(path: bundle)?.url(forResource: "deeper", withExtension: "png") != nil)
    }

    @Test func onlyEmbeddedResourcesDeclareNothingForTheBundle() {
        let target = SketchTarget(
            packageRoot: "/p", name: "T", directory: "/p/Sources/T", excluded: [], declaredSources: nil,
            resources: [.init(rule: .embedInCode, path: "/p/Sources/T/data.bin")],
            settings: [], packageLanguageMode: "6", dependencies: [])
        #expect(!target.declaresBundledResources)
    }

    // MARK: Paths

    @Test func twoSpellingsOfOneFileResolveTheSame() {
        let root = scratch()
        write("x", path(root, "Sketch.swift"))
        let viaTmp = root.replacingOccurrences(of: "/private/var/", with: "/var/")
        #expect(SketchTarget.resolved(path(viaTmp, "Sketch.swift")) == path(root, "Sketch.swift"))
        #expect(SketchTarget.resolved(path(root, "Shapes/../Sketch.swift")) == path(root, "Sketch.swift"))
        // A path that is not there keeps its tail on the resolved part.
        #expect(SketchTarget.resolved(path(viaTmp, "Old/Gone.swift")) == path(root, "Old/Gone.swift"))
    }

    // MARK: A real package

    /// A package with two sketch targets and a library, a sketch kept loose
    /// in a folder no target owns, written for SwiftPM to read.
    private func writePackage(_ root: String) {
        write("""
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Garden", targets: [
            .executableTarget(name: "Garden"),
            .executableTarget(name: "Pond", path: "Sketches/Pond"),
            .target(name: "Shared"),
        ])
        """, path(root, "Package.swift"))
        write("import Ollin\n@main\nfinal class Garden: Sketch {}\n", path(root, "Sources/Garden/Sketch.swift"))
        write("func petals() -> Int { 5 }\n", path(root, "Sources/Garden/Petals.swift"))
        write("import Ollin\nfinal class Pond: Sketch {}\n", path(root, "Sketches/Pond/Pond.swift"))
        write("public func shared() {}\n", path(root, "Sources/Shared/Shared.swift"))
        write("import Ollin\n@main\nfinal class Loose: Sketch {}\n", path(root, "Loose/Loose.swift"))
    }

    @Test func aFileInATargetFindsItAndAFileOutsideOneDoesNot() throws {
        let root = scratch()
        writePackage(root)
        let garden = try #require(try SketchTarget.containing(file: path(root, "Sources/Garden/Petals.swift")))
        #expect(garden.name == "Garden")
        #expect(garden.swiftSources().count == 2)
        #expect(garden.packageLanguageMode == "6")
        #expect(try SketchTarget.containing(file: path(root, "Sketches/Pond/Pond.swift"))?.name == "Pond")
        // A sketch kept loose inside a package compiles alone, as before.
        #expect(try SketchTarget.containing(file: path(root, "Loose/Loose.swift")) == nil)
        // And a file in no package at all.
        let loose = path(scratch(), "Dots.swift")
        write("import Ollin\n", loose)
        #expect(try SketchTarget.containing(file: loose) == nil)
    }

    @Test func aBrokenManifestSaysWhatSwiftPMSaid() {
        let root = scratch()
        write("// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(\n",
              path(root, "Package.swift"))
        write("import Ollin\n", path(root, "Sources/T/Sketch.swift"))
        do {
            _ = try SketchTarget.containing(file: path(root, "Sources/T/Sketch.swift"))
            Issue.record("a manifest that does not parse was read")
        } catch {
            #expect(error.packageRoot == root)
            #expect(error.description.contains("Package.swift could not be read"))
            #expect(!error.message.isEmpty)
        }
    }

    @Test func anEditedManifestIsReadAgain() throws {
        let root = scratch()
        writePackage(root)
        let file = path(root, "Loose/Loose.swift")
        #expect(try SketchTarget.containing(file: file) == nil)
        let manifestPath = path(root, "Package.swift")
        let text = try String(contentsOfFile: manifestPath, encoding: .utf8)
        write(text.replacingOccurrences(
            of: ".target(name: \"Shared\"),",
            with: ".target(name: \"Shared\"),\n    .executableTarget(name: \"Loose\", path: \"Loose\"),"),
              manifestPath)
        #expect(try SketchTarget.containing(file: file)?.name == "Loose")
    }

    // MARK: Choosing what to run

    @Test func theCommandLineNamesThePathAndTheTarget() {
        #expect(SketchChoice.arguments(["Garden", "--export", "f.png"]) == ("Garden", nil))
        #expect(SketchChoice.arguments(["--target", "Pond", "Garden"]) == ("Garden", "Pond"))
        #expect(SketchChoice.arguments(["Garden", "--target", "Pond", "--keep-clock"]) == ("Garden", "Pond"))
        #expect(SketchChoice.arguments(["--keep-clock"]) == (nil, nil))
        #expect(SketchChoice.arguments(["--target"]) == (nil, nil))
    }

    @Test func aFolderRunsItsOneSketchTargetAndAsksAmongSeveral() throws {
        let root = scratch()
        writePackage(root)
        #expect(throws: LaunchError.several(root, names: ["Garden", "Pond"])) {
            try SketchChoice.resolve(root, target: nil)
        }
        #expect(try SketchChoice.resolve(root, target: "Pond").sketchPath == path(root, "Sketches/Pond/Pond.swift"))
        #expect(throws: LaunchError.unknownTarget("Shared", among: ["Garden", "Pond"])) {
            try SketchChoice.resolve(root, target: "Shared")
        }
        // A folder inside the package narrows to the targets there.
        let garden = try SketchChoice.resolve(path(root, "Sources"), target: nil)
        #expect(garden == SketchChoice(sketchPath: path(root, "Sources/Garden/Sketch.swift"), note: nil))
        #expect(try SketchChoice.resolve(path(root, "Sources/Garden"), target: nil).sketchPath
                == path(root, "Sources/Garden/Sketch.swift"))
        #expect(throws: LaunchError.noSketch(path(root, "Sources/Shared"), packageRoot: root)) {
            try SketchChoice.resolve(path(root, "Sources/Shared"), target: nil)
        }
    }

    @Test func aHelperFileRunsItsTargetsSketchAndSaysSo() throws {
        let root = scratch()
        writePackage(root)
        let choice = try SketchChoice.resolve(path(root, "Sources/Garden/Petals.swift"), target: nil)
        #expect(choice.sketchPath == path(root, "Sources/Garden/Sketch.swift"))
        #expect(choice.note?.contains("Petals.swift declares no sketch") == true)
        // A sketch file runs as it is, and a target beside it is refused.
        let sketch = path(root, "Sources/Garden/Sketch.swift")
        #expect(try SketchChoice.resolve(sketch, target: nil) == SketchChoice(sketchPath: sketch, note: nil))
        #expect(throws: LaunchError.targetBesideAFile) {
            try SketchChoice.resolve(sketch, target: "Garden")
        }
    }

    @Test func aFolderWithNoPackageAndAPathWithNothingAreRefused() {
        let folder = scratch()
        #expect(throws: LaunchError.noPackage(folder)) {
            try SketchChoice.resolve(folder, target: nil)
        }
        #expect(throws: LaunchError.notFound(path(folder, "Gone.swift"))) {
            try SketchChoice.resolve(path(folder, "Gone.swift"), target: nil)
        }
    }

    /// A variation kept beside the sketch declares a `Sketch` subclass too; the
    /// one marked `@main` is the one the package runs, and so is the live one.
    @Test func theSketchMarkedMainWinsOverAVariationBesideIt() {
        let root = scratch()
        let folder = path(root, "Sources/T")
        write("import Ollin\nfinal class Draft: Sketch {}\n", path(folder, "A-Draft.swift"))
        write("import Ollin\n@main\nfinal class Final: Sketch {}\n", path(folder, "B-Final.swift"))
        let target = SketchTarget(
            packageRoot: root, name: "T", directory: folder, excluded: [], declaredSources: nil,
            resources: [], settings: [], packageLanguageMode: "6", dependencies: [])
        #expect(target.sketch()?.className == "Final")
    }

    // MARK: What a file declares

    @Test func aClassNamedInACommentOrAStringIsNotTheFilesOwn() {
        let source = #"""
        import Ollin
        /// Replaces the old `class Draft: Sketch` that lived here.
        let template = "final class Template: Sketch {}"
        /* class Block: Sketch { } */
        let raw = #"class Raw: Sketch {"#
        final class Real: Sketch {}
        """#
        #expect(SketchLoader.sketchClassName(in: source) == "Real")
        #expect(SketchLoader.sketchClassName(in: "// class Draft: Sketch {}\nstruct Nothing {}\n") == nil)
    }

    @Test func blankingKeepsEveryLineAndOffset() {
        let source = "let a = \"x\ny\" // note\nclass B: Sketch {}\n"
        let code = SourceRegions.code(in: source)
        #expect(code.utf16.count == source.utf16.count)
        #expect(code.split(separator: "\n", omittingEmptySubsequences: false).count
                == source.split(separator: "\n", omittingEmptySubsequences: false).count)
        #expect(code.hasSuffix("class B: Sketch {}\n"))
        #expect(!code.contains("note"))
    }

    @Test func mainIsFoundAmongTheAttributesInFrontOfTheClass() {
        let marked = SketchDeclarations("@MainActor @main\nfinal class A: Sketch {}\nfinal class B: Sketch {}\n")
        #expect(marked.classes == [.init(name: "A", isMain: true), .init(name: "B", isMain: false)])
        #expect(marked.mainCount == 1)
    }

    /// A host with sketches for its own tests, or an app with a sketch inside
    /// it, has an entry point of its own; a folder does not offer it as a
    /// sketch, and naming one of its files is how to run that sketch live.
    @Test func aTargetWhoseEntryPointIsSomethingElseIsNotASketchs() {
        let root = scratch()
        let folder = path(root, "Sources/Host")
        write("import SwiftUI\n@main\nstruct Host: App { var body: some Scene { WindowGroup {} } }\n",
              path(folder, "Host.swift"))
        write("import Ollin\nfinal class Probe: Sketch {}\n", path(folder, "Probe.swift"))
        let host = SketchTarget(
            packageRoot: root, name: "Host", directory: folder, excluded: [], declaredSources: nil,
            resources: [], settings: [], packageLanguageMode: "6", dependencies: [])
        #expect(host.sketch() == nil)

        // The same sketch in a library target, or one a main.swift starts, is.
        write("import Ollin\nProbe.main()\n", path(folder, "main.swift"))
        try? FileManager.default.removeItem(atPath: path(folder, "Host.swift"))
        #expect(host.sketch()?.className == "Probe")
    }

    // MARK: What the live route does not reach

    @Test func aMissingModuleTheTargetDependsOnIsNamedForWhatItIs() {
        let target = SketchTarget(
            packageRoot: "/p", name: "Garden", directory: "/p/Sources/Garden", excluded: [],
            declaredSources: nil, resources: [], settings: [], packageLanguageMode: "6",
            dependencies: ["Shared", "Ollin"])
        let log = "Sketch.swift:2:8: error: no such module 'Shared'\n2 | import Shared"
        let note = SketchLoader.unreachableDependencyNote(in: log, target: target)
        #expect(note?.contains("Shared is a dependency of the target Garden") == true)
        #expect(note?.contains("swift run Garden") == true)
        // A module the manifest never names is a typo, not the live route's limit.
        #expect(SketchLoader.unreachableDependencyNote(
            in: "error: no such module 'Sharde'", target: target) == nil)
        #expect(SketchLoader.unreachableDependencyNote(
            in: "error: cannot find 'petals' in scope", target: target) == nil)
    }
}
