import Foundation
import Testing
@testable import OllinProjects

/// An app for the phone is installed, never run, so the generator writes an
/// Xcode project spec rather than a package, and the quiet failures live in
/// that spec: a `.metal` under a source group is compiled into a library the
/// framework never reads, a satellite an example imports has to be linked as
/// a product, and a capability that wraps a Mac service would fail somewhere
/// inside the build rather than here. The sketch itself splits the same way
/// the wallpaper does: no entry point, since the host owns it.
@Suite("iPhone and iPad app projects")
struct IOSAppProjectTests {

    // MARK: - The plan

    @Test("The kind is offered, and asks for no more than a team")
    func theKindIsOpen() {
        #expect(ProjectKind.iOSApp.isAvailable)
        #expect(!ProjectKind.iOSApp.carriesEntryPoint)
        #expect(ProjectKind.iOSApp.fillsTheDisplay)
        #expect(ProjectKind.available.contains(.iOSApp))
    }

    @Test("The project carries the sketch, the host, the spec, and the app's name tag")
    func theLayoutIsWhatAnAppNeeds() throws {
        let project = try plan(named: "Rings")
        let paths = project.files.map(\.path)

        #expect(paths.contains("Sources/Rings/Sketch.swift"))
        #expect(paths.contains("Sources/Rings/RingsApp.swift"))
        #expect(paths.contains("project.yml"))
        #expect(paths.contains("Info.plist"))
        #expect(paths.contains("README.md"))
        #expect(paths.contains(".gitignore"))
        // No manifest and no script: the spec is the whole project.
        #expect(!paths.contains("Package.swift"))
        #expect(!paths.contains("build.sh"))
    }

    @Test("The sketch loses its entry point and takes the whole screen")
    func theSketchSuitsAPhone() throws {
        let project = try plan(named: "Rings")
        let sketch = try #require(project.files.first { $0.path == "Sources/Rings/Sketch.swift" }).contents

        // The host owns `@main`; a second one refuses to build.
        #expect(!sketch.contains("@main"))
        // The screen is the canvas, so `width` and `height` are its.
        #expect(sketch.contains("override var windowMode: WindowMode { .resizable }"))
        #expect(sketch.contains("final class Rings: Sketch"))
    }

    @Test("The host owns the entry point, spells out the SwiftUI scene, and makes the app the module")
    func theHostIsTheReferenceShape() throws {
        let project = try plan(named: "Rings")
        let host = try #require(project.files.first { $0.path == "Sources/Rings/RingsApp.swift" }).contents

        #expect(host.contains("@main"))
        #expect(host.contains("struct RingsApp: App"))
        // The framework has a 3D `Scene`, so the bare name is two types.
        #expect(host.contains("some SwiftUI.Scene"))
        #expect(host.contains("SketchView(Rings())"))
        // A resource beside the sketch is found through `in: .module`, which
        // an Xcode target never synthesizes, so the host says what it is.
        #expect(host.contains("static var module: Bundle { .main }"))
        #expect(host.contains(".ignoresSafeArea()"))
    }

    // MARK: - The spec

    @Test("The spec names the framework by path, the phone floor, and both device families")
    func theSpecTiesTheAppToTheFramework() throws {
        let project = try plan(named: "Rings")
        let spec = try #require(project.files.first { $0.path == "project.yml" }).contents

        #expect(spec.contains("name: Rings"))
        #expect(spec.contains("path: \"/tmp/ollin-framework\""))
        #expect(spec.contains("iOS: \"26.0\""))
        #expect(spec.contains("platform: iOS"))
        #expect(spec.contains("TARGETED_DEVICE_FAMILY: \"1,2\""))
        #expect(spec.contains("PRODUCT_BUNDLE_IDENTIFIER: com.example.rings"))
        #expect(spec.contains("INFOPLIST_FILE: Info.plist"))
        #expect(spec.contains("- path: Sources/Rings\n"))
        #expect(spec.contains("product: Ollin\n"))
    }

    @Test("The team is written when given, and its place is marked when not")
    func theTeamIsTheOneQuestion() throws {
        let without = try #require(try plan(named: "Rings").files.first { $0.path == "project.yml" }).contents
        #expect(!without.contains("DEVELOPMENT_TEAM: \""))
        // Marked, so someone opening the spec sees where the team goes and
        // why Xcode's own answer does not stick.
        #expect(without.contains("# DEVELOPMENT_TEAM: ABCDE12345"))
        #expect(without.contains("Signing & Capabilities"))

        var wanted = request(named: "Rings")
        wanted.team = "ZYX987WVU6"
        let with = try #require(try ProjectGenerator.plan(wanted).files.first { $0.path == "project.yml" }).contents
        #expect(with.contains("DEVELOPMENT_TEAM: \"ZYX987WVU6\""))
        #expect(!with.contains("# DEVELOPMENT_TEAM"))
    }

    @Test("A shipped framework is pinned to its minor, the way the manifest pins it")
    func theRemoteFormPinsTheMinor() throws {
        var wanted = request(named: "Rings")
        wanted.framework = .remote(url: "https://github.com/eaviles/Ollin.git", version: "0.1.0")
        let spec = try #require(try ProjectGenerator.plan(wanted).files.first { $0.path == "project.yml" }).contents

        #expect(spec.contains("url: https://github.com/eaviles/Ollin.git"))
        #expect(spec.contains("minorVersion: \"0.1.0\""))
        #expect(!spec.contains("  Ollin:\n    path:"))
    }

    @Test("A shader rides as a resource by name, kept out of the source group")
    func aShaderStaysAFile() throws {
        var wanted = request(named: "Rings")
        wanted.capabilities = [.shaders]
        let project = try ProjectGenerator.plan(wanted)
        let spec = try #require(project.files.first { $0.path == "project.yml" }).contents

        #expect(project.files.contains { $0.path == "Sources/Rings/effect.metal" })
        // Under the source group, and in the resources phase too, Xcode would
        // compile it into a library; the framework reads a shader's source at
        // run time, and a copy-files phase only copies.
        #expect(spec.contains("excludes:\n          - \"effect.metal\""))
        #expect(spec.contains("- path: \"Sources/Rings/effect.metal\"\n        buildPhase:\n          copyFiles:\n            destination: resources"))
        #expect(!spec.contains("effect.metal\"\n        buildPhase: resources"))
    }

    @Test("An asset folder rides whole, so its files land flat in the bundle")
    func aFolderRidesAsResources() throws {
        var wanted = request(named: "Rings")
        wanted.capabilities = [.images]
        let project = try ProjectGenerator.plan(wanted)
        let spec = try #require(project.files.first { $0.path == "project.yml" }).contents

        #expect(project.files.contains { $0.path == "Sources/Rings/Images/Images.md" })
        #expect(spec.contains("- \"Images\""))
        #expect(spec.contains("- path: \"Sources/Rings/Images\"\n        buildPhase: resources"))
        // Named before the group: named after it, the folder adds nothing.
        let folder = try #require(spec.range(of: "- path: \"Sources/Rings/Images\""))
        let group = try #require(spec.range(of: "- path: Sources/Rings\n"))
        #expect(folder.lowerBound < group.lowerBound)
    }

    @Test("Every library the sketch links is a product, an example's untried one included")
    func satellitesAreLinkedAsProducts() throws {
        var wanted = request(named: "Rings")
        wanted.capabilities = [.audio, .physics]
        wanted.example = ExampleSource.Example(
            path: "Sound/Pulse", directory: URL(fileURLWithPath: "/tmp/example"),
            modules: ["OllinAudio", "OllinNewThing"], resources: []
        )
        let spec = try #require(try ProjectGenerator.plan(wanted).files.first { $0.path == "project.yml" }).contents

        for product in ["Ollin", "OllinAudio", "OllinPhysics", "OllinNewThing"] {
            #expect(spec.contains("product: \(product)\n"), "\(product) is not linked")
        }
        // Once each, whichever list named it.
        #expect(spec.components(separatedBy: "product: OllinAudio\n").count == 2)
    }

    @Test("A capability that wraps a Mac service is refused with its reason")
    func deskCapabilitiesAreRefused() throws {
        for capability in [Capability.syphon, .screen, .virtualCamera, .phone, .record3D] {
            var wanted = request(named: "Rings")
            wanted.capabilities = [capability]
            #expect(throws: ProjectGeneratorError.staysOnTheDesk(capability, .iOSApp)) {
                _ = try ProjectGenerator.plan(wanted)
            }
        }
        // The message names the reason, so the refusal reads as a fact about
        // the platform rather than a failure of the build.
        let error = ProjectGeneratorError.staysOnTheDesk(.syphon, .iOSApp)
        #expect(error.description.contains("Syphon shares frames between Mac apps"))
        #expect(error.description.contains("bound for a device (iPhone and iPad app)"))

        // The ones that reach a phone still go through.
        for capability in [Capability.audio, .vision, .physics, .midi, .osc, .bluetooth, .controller] {
            var wanted = request(named: "Rings")
            wanted.capabilities = [capability]
            #expect(throws: Never.self) { _ = try ProjectGenerator.plan(wanted) }
        }
    }

    @Test("An example that imports a Mac-only library is refused the same way")
    func deskExamplesAreRefused() throws {
        var wanted = request(named: "Rings")
        wanted.example = ExampleSource.Example(
            path: "Integration/SyphonOut", directory: URL(fileURLWithPath: "/tmp/example"),
            modules: ["OllinSyphon"], resources: []
        )
        #expect(throws: ProjectGeneratorError.staysOnTheDesk(.syphon, .iOSApp)) {
            _ = try ProjectGenerator.plan(wanted)
        }
    }

    // MARK: - The property list

    @Test("The name tag fills the screen, allows the phone's orientations, and asks for Metal")
    func thePlistDescribesAPhoneApp() throws {
        let project = try plan(named: "Rings")
        let plist = try #require(project.files.first { $0.path == "Info.plist" }).contents

        #expect(plist.contains("<key>CFBundleDisplayName</key>\n\t<string>Rings</string>"))
        #expect(plist.contains("<key>UIRequiresFullScreen</key>\n\t<true/>"))
        #expect(plist.contains("UIInterfaceOrientationLandscapeLeft"))
        #expect(plist.contains("<key>UIRequiredDeviceCapabilities</key>"))
        #expect(plist.contains("<string>metal</string>"))
        #expect(!plist.contains("NSCameraUsageDescription"))
        #expect(!plist.contains("NSMicrophoneUsageDescription"))
    }

    @Test("Camera, microphone, and Bluetooth usage lines ride the wired capabilities")
    func usageLinesRideTheCapabilities() throws {
        var wanted = request(named: "Rings")
        wanted.capabilities = [.vision, .audio, .bluetooth]
        let plist = try #require(try ProjectGenerator.plan(wanted).files.first { $0.path == "Info.plist" }).contents

        #expect(plist.contains("NSCameraUsageDescription"))
        #expect(plist.contains("NSMicrophoneUsageDescription"))
        #expect(plist.contains("NSBluetoothAlwaysUsageDescription"))
    }

    // MARK: - What it says

    @Test("The next steps say how to write the project and where the team goes")
    func theNextStepsAreTheWholeLoop() throws {
        let project = try plan(named: "Rings")
        let steps = project.nextSteps.joined(separator: "\n")

        #expect(steps.contains("xcodegen generate"))
        #expect(steps.contains("Rings.xcodeproj"))
        #expect(steps.contains("Signing & Capabilities"))
        #expect(steps.contains("ollin phone"))
        #expect(project.runCommand.contains("xcodegen generate && open Rings.xcodeproj"))

        var wanted = request(named: "Rings")
        wanted.team = "ZYX987WVU6"
        let withTeam = try ProjectGenerator.plan(wanted).nextSteps.joined(separator: "\n")
        #expect(!withTeam.contains("Signing & Capabilities"))
    }

    @Test("The README says what the simulator cannot do and what to change before handing it out")
    func theReadmeCarriesTheTwoWarnings() throws {
        let project = try plan(named: "Rings")
        let readme = try #require(project.files.first { $0.path == "README.md" }).contents

        #expect(readme.contains("simulator"))
        #expect(readme.contains("PRODUCT_BUNDLE_IDENTIFIER"))
        #expect(readme.contains("ollin phone Sources/Rings/Sketch.swift"))
        #expect(readme.contains("copyFiles"))
    }

    @Test("Every template fits the phone")
    func everyTemplateFits() {
        for template in ProjectTemplate.all {
            #expect(template.fits(.iOSApp), "\(template.id) does not fit the phone")
        }
    }

    // MARK: - Helpers

    private func request(named name: String) -> ProjectRequest {
        ProjectRequest(
            name: name,
            kind: .iOSApp,
            template: .blank,
            destination: URL(fileURLWithPath: "/tmp/ollin-generated"),
            framework: .localPath(URL(fileURLWithPath: "/tmp/ollin-framework"))
        )
    }

    private func plan(named name: String) throws -> GeneratedProject {
        try ProjectGenerator.plan(request(named: name))
    }
}
