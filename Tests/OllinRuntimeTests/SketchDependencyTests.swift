import Foundation
@testable import OllinRuntime
import Testing

/// What a sketch's target imports besides the framework, read the way the
/// live hosts read it: the order its dependencies build in, the modules each
/// one's compile imports, which dependencies are the host's own and never
/// built, where a fetched package is found, what is refused and in what
/// words, and the compile line a dependency is built with.
///
/// The compile and the load themselves need a host that carries the
/// framework, so they are proven by the OllinLive `--selftest` dependency
/// phase. Here the graph is read from manifests handed over as values, with
/// one check under *A real package* that lets SwiftPM describe two packages.
@Suite
struct SketchDependencyTests {

    // MARK: Fixtures

    private func scratch() -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("SketchDependencyTests-\(UUID().uuidString)")
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

    /// A target of the package at `root`, with one Swift file on disk unless
    /// `files` says otherwise.
    private func target(_ name: String, in root: String, needs links: [SketchTarget.Link] = [],
                        files: [String] = ["Code.swift"]) -> SketchTarget {
        let folder = path(root, "Sources/\(name)")
        try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for file in files { write("// \(file)\n", path(folder, file)) }
        return SketchTarget(
            packageRoot: root, name: name, directory: folder, excluded: [], declaredSources: nil,
            resources: [], settings: [], packageLanguageMode: "6",
            dependencies: links.map(\.name), links: links)
    }

    private func local(_ name: String) -> SketchTarget.Link { .init(name: name, kind: .target) }

    /// The order for `sketch`, over manifests kept by their root. A module
    /// whose name starts with `Ollin` stands for one the host carries.
    private func order(
        of sketch: SketchTarget, in manifests: [SketchTarget.Manifest],
        read: ((String) -> Void)? = nil
    ) throws(DependencyError) -> [SketchTarget.Dependency] {
        let byRoot = Dictionary(uniqueKeysWithValues: manifests.map { ($0.root, $0) })
        return try sketch.dependencyOrder(
            carried: { $0.hasPrefix("Ollin") },
            workspace: PackageWorkspace(root: sketch.packageRoot, mayResolve: false),
            reading: { root throws(ManifestError) in
                read?(root)
                guard let found = byRoot[root] else {
                    throw ManifestError(packageRoot: root, message: "no manifest in the fixture")
                }
                return found
            })
    }

    private func refusal(
        of sketch: SketchTarget, in manifests: [SketchTarget.Manifest]
    ) -> DependencyError? {
        do {
            _ = try order(of: sketch, in: manifests)
            return nil
        } catch {
            return error
        }
    }

    // MARK: The order

    @Test func eachTargetBuildsAfterEverythingItNeeds() throws {
        let root = scratch()
        let leaf = target("Leaf", in: root)
        let petals = target("Petals", in: root, needs: [local("Leaf")])
        let stems = target("Stems", in: root, needs: [.init(name: "Leaf", kind: .byName)])
        let bloom = target("Bloom", in: root, needs: [local("Petals"), local("Stems")])
        let garden = target("Garden", in: root, needs: [
            .init(name: "Ollin", kind: .product(package: "Ollin")), local("Bloom"), local("Stems"),
        ])
        let manifest = SketchTarget.Manifest(root: root, targets: [garden, bloom, stems, petals, leaf])
        let built = try order(of: garden, in: [manifest])
        // A shared dependency is built once, and before both that need it.
        #expect(built.map(\.target.name) == ["Leaf", "Petals", "Stems", "Bloom"])
        // What each one's compile imports: everything below it, nearest last.
        #expect(built.map(\.needs) == [[], ["Leaf"], ["Leaf"], ["Leaf", "Petals", "Stems"]])
        // The sketch's own target is what asked; it is not in its own list.
        #expect(!built.contains { $0.target.name == "Garden" })
    }

    /// The framework and its libraries are in the host. A sketch binds to
    /// those copies, and a second build of one would be a second `Sketch`.
    @Test func aModuleTheHostCarriesIsNeverBuiltAndItsPackageNeverRead() throws {
        let root = scratch()
        let garden = target("Garden", in: root, needs: [
            .init(name: "Ollin", kind: .product(package: "Ollin")),
            .init(name: "OllinAudio", kind: .product(package: "Ollin")),
            .init(name: "OllinPhysics", kind: .byName),
        ])
        let manifest = SketchTarget.Manifest(
            root: root, targets: [garden],
            packages: [.init(identity: "ollin", path: "/somewhere/Ollin")])
        var roots: [String] = []
        let built = try order(of: garden, in: [manifest], read: { roots.append($0) })
        #expect(built.isEmpty)
        #expect(roots == [root])
    }

    @Test func aDependencyHeldForAnotherPlatformIsLeftOut() throws {
        let root = scratch()
        let mac = target("MacOnly", in: root)
        let linux = target("LinuxOnly", in: root, files: ["shim.c"])
        let garden = target("Garden", in: root, needs: [
            .init(name: "MacOnly", kind: .target, platforms: ["macos", "ios"]),
            .init(name: "LinuxOnly", kind: .target, platforms: ["linux"]),
        ])
        let manifest = SketchTarget.Manifest(root: root, targets: [garden, mac, linux])
        // The Linux one holds C, and is never looked at.
        #expect(try order(of: garden, in: [manifest]).map(\.target.name) == ["MacOnly"])
    }

    // MARK: Other packages

    @Test func aProductOfAPackageByPathBuildsTheTargetsItIsMadeOf() throws {
        let root = scratch()
        let other = scratch()
        let core = target("Core", in: other)
        let extras = target("Extras", in: other, needs: [local("Core")])
        let unused = target("Unused", in: other)
        let kit = SketchTarget.Manifest(
            root: other, targets: [core, extras, unused],
            products: ["Kit": ["Extras", "Core"], "Spare": ["Unused"]])
        let petals = target("Petals", in: root, needs: [.init(name: "Kit", kind: .product(package: "Kit"))])
        let garden = target("Garden", in: root, needs: [local("Petals")])
        let manifest = SketchTarget.Manifest(
            root: root, targets: [garden, petals],
            packages: [.init(identity: "kit", path: other)])
        let built = try order(of: garden, in: [manifest, kit])
        #expect(built.map(\.target.name) == ["Core", "Extras", "Petals"])
        #expect(built.map(\.target.packageRoot) == [other, other, root])
        #expect(built.last?.needs == ["Core", "Extras"])
    }

    /// A bare name that is no target of the package is the product of that
    /// name in a package it depends on, looked for first in the package the
    /// name suggests.
    @Test func aBareNameFindsTheProductInAPackage() throws {
        let root = scratch()
        let far = scratch()
        let near = scratch()
        let leaf = SketchTarget.Manifest(
            root: near, targets: [target("Leaf", in: near)], products: ["Leaf": ["Leaf"]])
        let unrelated = SketchTarget.Manifest(
            root: far, targets: [target("Bark", in: far)], products: ["Bark": ["Bark"]])
        let garden = target("Garden", in: root, needs: [.init(name: "Leaf", kind: .byName)])
        let manifest = SketchTarget.Manifest(
            root: root, targets: [garden],
            packages: [.init(identity: "bark", path: far), .init(identity: "leaf", path: near)])
        var roots: [String] = []
        let built = try order(of: garden, in: [manifest, leaf, unrelated], read: { roots.append($0) })
        #expect(built.map(\.target.name) == ["Leaf"])
        // The package named like the product was read, and the other was not.
        #expect(roots == [root, near])
    }

    /// SwiftPM's record of what it fetched, in the shape it writes.
    @Test func aFetchedPackageIsFoundThroughSwiftPMsRecord() throws {
        let root = scratch()
        let edited = scratch()
        write(#"""
        {"object": {"artifacts": [], "dependencies": [
          {"basedOn": null,
           "packageRef": {"identity": "stem", "kind": "remoteSourceControl",
                          "location": "https://example.com/stem.git", "name": "Stem"},
           "state": {"checkoutState": {"revision": "abc", "version": "1.0.0"},
                     "name": "sourceControlCheckout"},
           "subpath": "Stem"},
          {"basedOn": null,
           "packageRef": {"identity": "ollin", "kind": "fileSystem",
                          "location": "\#(edited)", "name": "Ollin"},
           "state": {"name": "fileSystem", "path": "\#(edited)"}, "subpath": "ollin"},
          {"basedOn": null,
           "packageRef": {"identity": "ghost", "kind": "remoteSourceControl",
                          "location": "https://example.com/ghost.git", "name": "Ghost"},
           "state": {"name": "sourceControlCheckout"}, "subpath": "ghost"}
        ], "prebuilts": []}, "version": 7}
        """#, path(root, ".build/workspace-state.json"))
        write("// swift-tools-version: 6.0\n", path(root, ".build/checkouts/Stem/Package.swift"))
        write("// swift-tools-version: 6.0\n", path(edited, "Package.swift"))

        let workspace = PackageWorkspace(root: root, mayResolve: false)
        #expect(workspace.recorded("stem") == path(root, ".build/checkouts/Stem"))
        #expect(workspace.recorded("ollin") == edited)
        // Listed, with nothing checked out where the record says.
        #expect(workspace.recorded("ghost") == nil)
        #expect(workspace.recorded("never-heard-of") == nil)
        // A read that may not fetch says the package is missing; it does not
        // start SwiftPM.
        #expect(throws: DependencyError.unresolved(package: "ghost", detail: "")) {
            try workspace.folder(of: "ghost")
        }
        #expect(try workspace.folder(of: "stem") == path(root, ".build/checkouts/Stem"))
    }

    // MARK: What is refused

    @Test func aTargetThatIsNotSwiftIsRefusedByItsNameAndItsFile() {
        let root = scratch()
        let shim = target("Shim", in: root, files: ["shim.c", "include/shim.h"])
        let mixed = target("Mixed", in: root, files: ["Code.swift", "glue.mm"])
        let empty = target("Headers", in: root, files: ["include/only.h"])
        for (dependency, file) in [(shim, "shim.c"), (mixed, "glue.mm"), (empty, nil as String?)] {
            let garden = target("Garden", in: root, needs: [local(dependency.name)])
            let manifest = SketchTarget.Manifest(root: root, targets: [garden, dependency])
            let error = refusal(of: garden, in: [manifest])
            #expect(error == .notSwift(
                target: dependency.name, file: file.map { path(dependency.directory, $0) }))
            let sentence = error?.description ?? ""
            #expect(sentence.contains("The target \(dependency.name) holds"))
            #expect(sentence.contains(file ?? "no Swift source"))
            #expect(sentence.contains("`swift run`"))
        }
    }

    @Test func aTargetThatIsNoSourceAtAllIsRefusedByItsKind() {
        let root = scratch()
        let words = ["system": "a system library", "binary": "a prebuilt binary",
                     "macro": "a macro", "plugin": "a plugin"]
        for (kind, word) in words {
            let garden = target("Garden", in: root, needs: [.init(name: "Other", kind: .byName)])
            let manifest = SketchTarget.Manifest(root: root, targets: [garden], otherTargets: ["Other": kind])
            let error = refusal(of: garden, in: [manifest])
            #expect(error == .unbuildable(target: "Other", kind: kind))
            #expect(error?.description.contains("The target Other is \(word).") == true)
        }
        // And one inside a product of another package.
        let other = scratch()
        let kit = SketchTarget.Manifest(
            root: other, targets: [target("Core", in: other)], otherTargets: ["Blob": "binary"],
            products: ["Kit": ["Core", "Blob"]])
        let garden = target("Garden", in: root, needs: [.init(name: "Kit", kind: .product(package: "kit"))])
        let manifest = SketchTarget.Manifest(
            root: root, targets: [garden], packages: [.init(identity: "kit", path: other)])
        #expect(refusal(of: garden, in: [manifest, kit]) == .unbuildable(target: "Blob", kind: "binary"))
    }

    @Test func whatTheManifestNamesAndNothingProvidesIsSaidSo() {
        let root = scratch()
        let other = scratch()
        let kit = SketchTarget.Manifest(root: other, targets: [target("Core", in: other)],
                                        products: ["Kit": ["Core"]])
        let packages = [SketchTarget.PackageReference(identity: "kit", path: other)]
        for link: SketchTarget.Link in [
            local("Nowhere"),
            .init(name: "Nowhere", kind: .byName),
            .init(name: "Nowhere", kind: .product(package: "kit")),
            .init(name: "Kit", kind: .product(package: "another")),
        ] {
            let garden = target("Garden", in: root, needs: [link])
            let manifest = SketchTarget.Manifest(root: root, targets: [garden], packages: packages)
            guard case .unknown(_, let from) = refusal(of: garden, in: [manifest, kit]) else {
                Issue.record("\(link) was not refused as unknown")
                continue
            }
            #expect(from == "Garden")
        }
    }

    @Test func aProductWhoseModulesAreRenamedIsRefused() {
        let root = scratch()
        let garden = target("Garden", in: root, needs: [
            .init(name: "Kit", kind: .product(package: "kit"), renamesModules: true),
        ])
        let manifest = SketchTarget.Manifest(
            root: root, targets: [garden], packages: [.init(identity: "kit", path: "/nowhere")])
        #expect(refusal(of: garden, in: [manifest]) == .renamed(product: "Kit", from: "Garden"))
    }

    @Test func aTargetThatDependsBackOnItselfIsRefused() {
        let root = scratch()
        let one = target("One", in: root, needs: [local("Two")])
        let two = target("Two", in: root, needs: [local("Three")])
        let three = target("Three", in: root, needs: [local("One")])
        let garden = target("Garden", in: root, needs: [local("One")])
        let manifest = SketchTarget.Manifest(root: root, targets: [garden, one, two, three])
        #expect(refusal(of: garden, in: [manifest]) == .cycle(target: "One", from: "Three"))
    }

    @Test func twoTargetsThatWouldBeOneModuleAreRefused() {
        let root = scratch()
        let other = scratch()
        let kit = SketchTarget.Manifest(root: other, targets: [target("Utils", in: other)],
                                        products: ["Kit": ["Utils"]])
        let garden = target("Garden", in: root, needs: [
            local("Utils"), .init(name: "Kit", kind: .product(package: "kit")),
        ])
        let manifest = SketchTarget.Manifest(
            root: root, targets: [garden, target("Utils", in: root)],
            packages: [.init(identity: "kit", path: other)])
        #expect(refusal(of: garden, in: [manifest, kit]) == .twoModules(named: "Utils"))
    }

    @Test func aDependencysBrokenManifestIsTheRefusal() {
        let root = scratch()
        let garden = target("Garden", in: root, needs: [.init(name: "Kit", kind: .product(package: "kit"))])
        let manifest = SketchTarget.Manifest(
            root: root, targets: [garden], packages: [.init(identity: "kit", path: "/nowhere/Kit")])
        guard case .manifest(let error) = refusal(of: garden, in: [manifest]) else {
            Issue.record("a package with no readable manifest was not refused as one")
            return
        }
        #expect(error.packageRoot == "/nowhere/Kit")
    }

    // MARK: The walk's depth

    /// How deep a package graph goes is the manifests' to say, so the walk
    /// keeps its open targets on a list. Run on a thread with a small stack,
    /// where a walk that called itself once a level would not come back.
    @Test func aChainThousandsDeepIsWalkedOnASmallStack() async throws {
        let root = scratch()
        let depth = 2_000
        // Every target shares one folder; the walk asks only that it hold Swift.
        let folder = path(root, "Sources/Chain")
        write("// one file\n", path(folder, "Code.swift"))
        let targets = (0...depth).map { index in
            SketchTarget(
                packageRoot: root, name: "T\(index)", directory: folder, excluded: [],
                declaredSources: nil, resources: [], settings: [], packageLanguageMode: "6",
                dependencies: [], links: index < depth ? [.init(name: "T\(index + 1)", kind: .target)] : [])
        }
        let manifest = SketchTarget.Manifest(root: root, targets: targets)
        let first = targets[0]
        let names: [String] = try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                do {
                    let built = try first.dependencyOrder(
                        carried: { _ in false },
                        workspace: PackageWorkspace(root: root, mayResolve: false),
                        reading: { _ throws(ManifestError) in manifest })
                    continuation.resume(returning: built.map(\.target.name))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
        #expect(names.count == depth)
        #expect(names.first == "T\(depth)")
        #expect(names.last == "T1")
    }

    // MARK: The build

    private func built(_ name: String, _ stamp: String) -> BuiltDependency {
        BuiltDependency(
            realName: name, moduleName: "\(name)_\(stamp)", directory: "/work/\(name)_\(stamp)",
            library: "/work/\(name)_\(stamp)/lib\(name)_\(stamp).dylib", frameworkModules: [])
    }

    /// The fingerprint is the build's name, so it has to move with anything
    /// that changes what the compile produces, and with nothing else.
    @Test func theFingerprintMovesWithEverythingThatDecidesTheBuild() throws {
        let root = scratch()
        let petals = target("Petals", in: root, files: ["A.swift", "B.swift"])
        let sources = petals.swiftSources()
        func stamp(of target: SketchTarget = petals, flags: [String] = ["-DX"],
                   optimization: SketchLoader.Optimization = .speed,
                   needs: [BuiltDependency] = []) -> String? {
            SketchLoader.fingerprint(of: target, sources: sources, flags: flags,
                                     optimization: optimization, needs: needs)
        }
        let base = try #require(stamp())
        #expect(base.count == 12)
        #expect(stamp() == base)
        #expect(stamp(flags: ["-DY"]) != base)
        #expect(stamp(optimization: .none) != base)
        #expect(stamp(needs: [built("Leaf", "aaaaaaaaaaaa")]) != base)
        #expect(stamp(needs: [built("Leaf", "aaaaaaaaaaaa")]) != stamp(needs: [built("Leaf", "bbbbbbbbbbbb")]))
        #expect(stamp(of: target("Petals", in: scratch(), files: ["A.swift", "B.swift"])) != base)

        // One character of one source.
        write("// B.swift!\n", sources[1])
        let edited = try #require(stamp())
        #expect(edited != base)
        // Put back, the text is the text a build was already made from.
        write("// B.swift\n", sources[1])
        #expect(stamp() == base)

        try FileManager.default.removeItem(atPath: sources[0])
        #expect(stamp() == nil)
    }

    @Test func aDependencyCompilesToAModuleAndALibraryThatLeaveTheFrameworkToTheHost() {
        let leaf = built("Leaf", "0123456789ab")
        let args = SketchLoader.dependencyCompileArguments(
            library: "/work/Petals_ffff/libPetals_ffff.dylib", moduleName: "Petals_ffff",
            directory: "/work/Petals_ffff", sources: ["/p/Sources/Petals/Petals.swift"],
            optimization: .speed, flags: ["-package-name", "garden", "-swift-version", "6"],
            needs: [leaf])
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).map { args[$0 + 1] }
        }
        #expect(args.first == "swiftc")
        #expect(args.contains("-emit-library"))
        #expect(value(after: "-o") == "/work/Petals_ffff/libPetals_ffff.dylib")
        // The next compile imports the module, so it is emitted beside the library.
        #expect(args.contains("-emit-module"))
        #expect(value(after: "-emit-module-path") == "/work/Petals_ffff/Petals_ffff.swiftmodule")
        #expect(value(after: "-module-name") == "Petals_ffff")
        // A target of one file would otherwise be read as a script.
        #expect(args.contains("-parse-as-library"))
        #expect(args.filter { $0 == "-O" }.count == 1)
        #expect(args.filter { $0 == "-wmo" }.count == 1)
        // The framework's symbols stay unresolved, as in the sketch's own
        // library, so the process holds one copy of the framework.
        #expect(args.contains("dynamic_lookup"))
        #expect(!args.contains { $0.hasPrefix("-lOllin") })
        // The library is named by its own path, which is what the library
        // that links it records.
        #expect(value(after: "-install_name") == "-Xlinker")
        #expect(args.last == "/work/Petals_ffff/libPetals_ffff.dylib")
        // What it imports in turn: found, renamed, linked.
        #expect(value(after: "-I") == leaf.directory)
        #expect(value(after: "-module-alias") == "Leaf=Leaf_0123456789ab")
        #expect(args.contains(leaf.library))
        // Flags before the sources, the linker's after.
        let source = args.firstIndex(of: "/p/Sources/Petals/Petals.swift")!
        #expect(args.firstIndex(of: "-package-name")! < source)
        #expect(args.firstIndex(of: "-Xlinker")! > source)

        let plain = SketchLoader.dependencyCompileArguments(
            library: "/l.dylib", moduleName: "M", directory: "/d", sources: [], optimization: .none,
            flags: [], needs: [])
        #expect(plain.contains("-Onone") && !plain.contains("-O"))
        #expect(!plain.contains("-module-alias"))
    }

    @Test func theSketchsCompileIsHandedEachDependencyInOrder() {
        let args = SketchLoader.importArguments([built("Leaf", "aaaa"), built("Petals", "bbbb")])
        #expect(args == [
            "-I", "/work/Leaf_aaaa", "-module-alias", "Leaf=Leaf_aaaa", "/work/Leaf_aaaa/libLeaf_aaaa.dylib",
            "-I", "/work/Petals_bbbb", "-module-alias", "Petals=Petals_bbbb",
            "/work/Petals_bbbb/libPetals_bbbb.dylib",
        ])
        #expect(SketchLoader.importArguments([]).isEmpty)
        // The sketch's line carries them among its flags, ahead of the sources.
        let line = SketchLoader.compileArguments(
            dylibPath: "/w/sketch.dylib", moduleName: "S", sources: ["/w/Sketch.swift"],
            optimization: .speed, flags: args)
        #expect(line.firstIndex(of: "-module-alias")! < line.firstIndex(of: "/w/Sketch.swift")!)
    }

    /// A diagnostic that qualifies a type would otherwise show the name the
    /// library was built under.
    @Test func aDiagnosticReadsTheNameTheSourcesUse() {
        let log = "Sketch.swift:9:5: error: 'Ring' is ambiguous: Petals_3fa9c1d2e4b7.Ring, Leaf_0a0a0a0a0a0a.Ring"
        let named = SketchLoader.naming(
            [built("Petals", "3fa9c1d2e4b7"), built("Leaf", "0a0a0a0a0a0a")], in: log)
        #expect(named == "Sketch.swift:9:5: error: 'Ring' is ambiguous: Petals.Ring, Leaf.Ring")
    }

    @Test func aTargetsNameBecomesAnIdentifier() {
        #expect(SketchTarget.identifier("Petals") == "Petals")
        #expect(SketchTarget.identifier("my-lib") == "my_lib")
        #expect(SketchTarget.identifier("2d shapes") == "_2d_shapes")
        #expect(SketchTarget.identifier("café") == "caf_")
    }

    // MARK: A real package

    /// SwiftPM describes two packages, and the order is read from what it
    /// wrote: the proof that the dependency, product, and package shapes are
    /// still the ones `dump-package` writes.
    @Test func swiftPMsOwnDescriptionGivesTheOrder() throws {
        let root = scratch()
        let garden = path(root, "Garden")
        let leaf = path(root, "Leaf")
        write("""
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "Leaf",
            products: [.library(name: "Leaf", targets: ["Leaf", "Vein"])],
            targets: [.target(name: "Leaf", dependencies: ["Vein"]), .target(name: "Vein")])
        """, path(leaf, "Package.swift"))
        write("public func leaf() {}\n", path(leaf, "Sources/Leaf/Leaf.swift"))
        write("public func vein() {}\n", path(leaf, "Sources/Vein/Vein.swift"))
        write("""
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "Garden",
            dependencies: [
                .package(path: "../Leaf"),
                .package(url: "https://example.com/never/fetched.git", from: "1.0.0"),
            ],
            targets: [
                .target(name: "Petals", dependencies: [.product(name: "Leaf", package: "Leaf")]),
                .target(name: "Frost", dependencies: []),
                .systemLibrary(name: "CZip"),
                .executableTarget(name: "Garden", dependencies: [
                    "Petals",
                    .target(name: "Frost", condition: .when(platforms: [.linux])),
                    .product(name: "OllinAudio", package: "fetched"),
                ]),
            ])
        """, path(garden, "Package.swift"))
        write("import Ollin\n@main\nfinal class Garden: Sketch {}\n", path(garden, "Sources/Garden/Sketch.swift"))
        write("public func petals() {}\n", path(garden, "Sources/Petals/Petals.swift"))
        write("public func frost() {}\n", path(garden, "Sources/Frost/Frost.swift"))
        write("module CZip [system] { link \"z\" }\n", path(garden, "Sources/CZip/module.modulemap"))

        let manifest = try SketchTarget.Manifest.read(root: garden)
        #expect(manifest.otherTargets == ["CZip": "system"])
        #expect(manifest.packages == [
            .init(identity: "leaf", path: leaf), .init(identity: "fetched", path: nil),
        ])
        #expect(try SketchTarget.Manifest.read(root: leaf).products == ["Leaf": ["Leaf", "Vein"]])

        let sketch = try #require(try SketchTarget.containing(file: path(garden, "Sources/Garden/Sketch.swift")))
        #expect(sketch.links.map(\.platforms) == [[], ["linux"], []])
        // The fetched package is never asked for: what the sketch wants from
        // it, the host carries.
        let built = try sketch.dependencyOrder(
            carried: { $0.hasPrefix("Ollin") },
            workspace: PackageWorkspace(root: garden, mayResolve: false))
        #expect(built.map(\.target.name) == ["Vein", "Leaf", "Petals"])
        #expect(built.map(\.needs) == [[], ["Vein"], ["Vein", "Leaf"]])
    }
}
