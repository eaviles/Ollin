import Foundation
@testable import OllinRuntime
import Testing

/// The project `ollin phone` writes around a sketch, read as text.
///
/// Every check here is pure: hand the planner a sketch's source and the names
/// of the files beside it, and read the plan and the three files it emits. The
/// proof that the host it writes still compiles for the phone is
/// `PhoneProjectBuildTests`, which drives the real compiler.
@Suite
struct PhoneProjectTests {

    private let sketchPath = "/Users/someone/Sketches/Waves/Sketch.swift"
    private let framework = "/Users/someone/Developer/Ollin"

    private func plan(_ source: String, siblings: [String] = [], path: String? = nil) throws -> PhoneProject {
        try PhoneProject.plan(source: source, sketchPath: path ?? sketchPath, siblings: siblings,
                              frameworkPath: framework, team: "TEAM123456")
    }

    // MARK: Reading the sketch

    @Test func thePlanReadsTheType() throws {
        let plan = try plan("import Ollin\n\nfinal class Waves: Sketch {\n}\n")
        #expect(plan.typeName == "Waves")
        #expect(plan.satellites == ["OllinRemote"])
        #expect(plan.untried.isEmpty)
        #expect(plan.assets.isEmpty)
    }

    @Test func aFileWithNoSketchIsRefused() {
        #expect(throws: PhoneProject.PlanError.noSketch(sketchPath)) {
            try plan("import Ollin\nstruct Nothing {}\n")
        }
    }

    @Test func importsBecomeProductsAndTheRemoteIsAlwaysAmongThem() throws {
        let plan = try plan("import Ollin\nimport OllinPhysics\nimport OllinAudio\nimport OllinAudio\n\nclass Waves: Sketch {}\n")
        #expect(plan.satellites == ["OllinAudio", "OllinPhysics", "OllinRemote"])
        #expect(plan.untried.isEmpty)
    }

    @Test func anUntriedSatelliteIsNamedRatherThanRefused() throws {
        let plan = try plan("import Ollin\nimport OllinLink\n\nclass Waves: Sketch {}\n")
        #expect(plan.satellites.contains("OllinLink"))
        #expect(plan.untried == ["OllinLink"])
    }

    @Test func aDeskOnlySatelliteIsRefusedWithItsReason() {
        let source = "import Ollin\nimport OllinSyphon\n\nclass Waves: Sketch {}\n"
        #expect(throws: PhoneProject.PlanError.deskOnly(["OllinSyphon"])) { try plan(source) }
        let message = "\(PhoneProject.PlanError.deskOnly(["OllinSyphon"]))"
        #expect(message.contains("OllinSyphon"))
        #expect(message.contains("Syphon shares frames"))
    }

    @Test func theImportScanIgnoresTheCoreAndCommentedLines() {
        let source = """
        import Ollin
        import OllinMIDI
        // import OllinAudio
        import Foundation
        """
        #expect(PhoneProject.importedSatellites(in: source) == ["OllinMIDI"])
    }

    // MARK: The files beside the sketch

    @Test func assetsRideAlongAndCodeAndHiddenFilesDoNot() throws {
        let folder = (sketchPath as NSString).deletingLastPathComponent
        let siblings = ["photo.JPG", "Other.swift", ".DS_Store", "notes.md", "loop.wav", "shade.metal"]
            .map { (folder as NSString).appendingPathComponent($0) } + [sketchPath]
        let plan = try plan("class Waves: Sketch {}", siblings: siblings)
        #expect(plan.assets.map { ($0 as NSString).lastPathComponent } == ["loop.wav", "photo.JPG", "shade.metal"])
    }

    // MARK: What gets written

    @Test func theSpecNamesEverythingThroughTheTwoLinks() throws {
        let folder = (sketchPath as NSString).deletingLastPathComponent
        let asset = (folder as NSString).appendingPathComponent("photo.png")
        let plan = try plan("import OllinPhysics\nclass Waves: Sketch {}", siblings: [asset])
        let spec = plan.projectSpec
        #expect(plan.sketchReference == "Sketch/Sketch.swift")
        #expect(spec.contains("- path: \"Sketch/Sketch.swift\""))
        #expect(spec.contains("- path: \"Sketch/photo.png\"\n        buildPhase: resources"))
        #expect(spec.contains("  Ollin:\n    path: Ollin"))
        #expect(!spec.contains(sketchPath), "an absolute path is what makes xcodegen loop")
        #expect(!spec.contains(framework))
        #expect(spec.contains("product: OllinPhysics"))
        #expect(spec.contains("product: OllinRemote"))
        #expect(spec.contains("DEVELOPMENT_TEAM: \"TEAM123456\""))
        #expect(spec.contains("PRODUCT_BUNDLE_IDENTIFIER: dev.ollin.OllinPhone"))
        // The sketch's own file is never also a resource.
        #expect(!spec.contains("\"Sketch/Sketch.swift\"\n        buildPhase"))
    }

    @Test func aNameWithASpaceAndAQuoteSurvivesTheSpec() throws {
        let odd = "/Users/someone/Sketches/my \"odd\" sketch.swift"
        let plan = try plan("class Waves: Sketch {}", path: odd)
        #expect(plan.projectSpec.contains(#"- path: "Sketch/my \"odd\" sketch.swift""#))
    }

    @Test func theHostMakesTheTypeAndCarriesItsState() throws {
        let host = try plan("class Waves: Sketch {}").hostSource
        #expect(host.contains("let sketch = Waves()"))
        #expect(host.contains("forgetCheckpoint()"))
        #expect(host.contains("RemoteInspector(port: 9330)"))
        #expect(host.contains(".every(seconds: 1.0)"))
        #expect(host.contains("beginInstallation"))
        #expect(host.contains("static var module: Bundle { .main }"))
        #expect(host.contains("some SwiftUI.Scene"))
    }

    @Test func thePlistShowsTheTypeAsTheAppsName() throws {
        let plist = try plan("class Waves: Sketch {}").infoPlist
        #expect(plist.contains("<key>CFBundleDisplayName</key>\n\t<string>Waves</string>"))
        #expect(plist.contains("UIInterfaceOrientationPortrait"))
    }

    @Test func writingPutsTheFilesAndLinksDownAndWritesOverThem() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-phone-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plan = try plan("class Waves: Sketch {}")
        try plan.write(to: folder)
        try plan.write(to: folder)   // a second run writes over its own files without complaint
        for name in ["project.yml", "Info.plist", "Sources/OllinPhoneHost.swift"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), "\(name)")
        }
        let written = try String(contentsOf: folder.appendingPathComponent("Sources/OllinPhoneHost.swift"), encoding: .utf8)
        #expect(written == plan.hostSource)
        // The two links point where the plan says, and are replaced rather
        // than stacked on a second write.
        let sketchLink = try FileManager.default.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("Sketch").path)
        #expect(sketchLink.hasSuffix("/Users/someone/Sketches/Waves"))
        let frameworkLink = try FileManager.default.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("Ollin").path)
        #expect(frameworkLink.hasSuffix(framework))
    }
}
