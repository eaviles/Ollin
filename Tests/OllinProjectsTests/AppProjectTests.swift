import Foundation
import Testing
@testable import OllinProjects

/// An app is still a program, so unlike the screen saver the sketch keeps its
/// entry point and the manifest stays the mac sketch's. What the kind adds is
/// the wrapper, and the quiet failures live there: a bundle without the
/// framework's resource files runs and shows nothing, and an unsigned or
/// ad-hoc-signed app travels to another machine only to be refused at the
/// first double click. The script has to get both right, and say plainly
/// which signature it made.
@Suite("Mac app projects")
struct AppProjectTests {

    // MARK: - The plan

    @Test("The project carries the sketch, the wrapper script, and the app's name tag")
    func theLayoutIsWhatAnAppNeeds() throws {
        let project = try plan(named: "Orbit")
        let paths = project.files.map(\.path)

        #expect(paths.contains("Sources/Orbit/Sketch.swift"))
        #expect(paths.contains("Package.swift"))
        #expect(paths.contains("Info.plist"))
        #expect(paths.contains("build.sh"))
        #expect(paths.contains("README.md"))
        #expect(paths.contains(".gitignore"))
    }

    @Test("The build script can be run, and does the four things an app needs")
    func theScriptDoesWhatAnAppNeeds() throws {
        let project = try plan(named: "Orbit")
        let script = try #require(project.files.first { $0.path == "build.sh" })
        #expect(script.isExecutable)

        // Asked for, never assumed: the two build systems the toolchain ships
        // put the binary in different places.
        #expect(script.contents.contains("--show-bin-path"))
        // The framework's own files travel inside the app, because a binary
        // run from a bundle looks for them in the bundle's Resources folder.
        #expect(script.contents.contains("\"$BIN\"/*.bundle"))
        // The icon is a frame the sketch renders of itself, folded into an
        // .icns; an AppIcon.icns of the author's own wins.
        #expect(script.contents.contains("--export"))
        #expect(script.contents.contains("iconutil"))
        #expect(script.contents.contains("-f AppIcon.icns"))
        // Signed ad-hoc by default, and the identity path carries the two
        // things the notary checks for.
        #expect(script.contents.contains("codesign --force --sign - --timestamp=none"))
        #expect(script.contents.contains("--options runtime"))
    }

    @Test("Notarizing without an identity is refused before any work is done")
    func notarizeAloneIsRefused() throws {
        // An ad-hoc signature can never pass the notary, so sending one would
        // spend minutes to fail with Apple's error instead of this one.
        let project = try plan(named: "Orbit")
        let script = try #require(project.files.first { $0.path == "build.sh" }).contents
        #expect(script.contains("--notarize needs --sign"))
    }

    // MARK: - The name tag

    @Test("The property list says it is an app and names its own binary")
    func thePropertyListDescribesAnApp() throws {
        let project = try plan(named: "Orbit")
        let plist = try #require(project.files.first { $0.path == "Info.plist" }).contents

        // APPL, not BNDL: this one is a program.
        #expect(plist.contains("<string>APPL</string>"))
        #expect(plist.contains("<key>CFBundleExecutable</key>"))
        #expect(plist.contains("<string>Orbit</string>"))
        // Without this line the canvas renders scaled on a Retina display.
        #expect(plist.contains("<key>NSHighResolutionCapable</key>"))
        #expect(plist.contains("<key>CFBundleIconFile</key>"))
        // An app has no principal class to name; that is the plug-in's need.
        #expect(!plist.contains("NSPrincipalClass"))
    }

    @Test("Camera and microphone usage lines ride the wired capabilities")
    func usageLinesRideTheCapabilities() throws {
        // A bundled app that touches the camera or the microphone without the
        // matching line is killed on the first ask, so wiring the capability
        // has to bring the line, and not wiring it has to leave it out.
        let bare = try plan(named: "Orbit")
        let barePlist = try #require(bare.files.first { $0.path == "Info.plist" }).contents
        #expect(!barePlist.contains("NSCameraUsageDescription"))
        #expect(!barePlist.contains("NSMicrophoneUsageDescription"))

        let wired = try plan(named: "Orbit", capabilities: [.vision, .audio])
        let wiredPlist = try #require(wired.files.first { $0.path == "Info.plist" }).contents
        #expect(wiredPlist.contains("NSCameraUsageDescription"))
        #expect(wiredPlist.contains("NSMicrophoneUsageDescription"))
    }

    // MARK: - The manifest and the sketch

    @Test("The manifest is the mac sketch's: an ordinary executable target")
    func theManifestBuildsAProgram() throws {
        let project = try plan(named: "Orbit")
        let manifest = try #require(project.files.first { $0.path == "Package.swift" }).contents
        #expect(manifest.contains(".executableTarget"))
        #expect(!manifest.contains("-bundle"))
    }

    @Test("The sketch keeps its entry point and its own window")
    func theSketchStaysAProgram() throws {
        let project = try plan(named: "Orbit")
        let sketch = try #require(project.files.first { $0.path == "Sources/Orbit/Sketch.swift" }).contents
        #expect(sketch.contains("@main"))
        // An app is a windowed sketch, not a display-filling one.
        #expect(!sketch.contains("override var windowMode"))
    }

    @Test("What the script builds is not kept in the repository")
    func theBuiltAppIsIgnored() throws {
        let project = try plan(named: "Orbit")
        let ignored = try #require(project.files.first { $0.path == ".gitignore" }).contents
        #expect(ignored.contains("*.app"))
        // The notary zip is a build product too.
        #expect(ignored.contains("*.zip"))
    }

    // MARK: - Support

    private func plan(named name: String,
                      capabilities: [Capability] = []) throws -> GeneratedProject {
        try ProjectGenerator.plan(ProjectRequest(
            name: name,
            kind: .macApp,
            template: .motion,
            capabilities: capabilities,
            destination: URL(fileURLWithPath: "/tmp/ollin-app-tests"),
            framework: .localPath(URL(fileURLWithPath: "/tmp/ollin"))
        ))
    }
}
