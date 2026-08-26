import Foundation
import Testing
@testable import OllinProjects

/// A wallpaper project is the app's shape with the entry point moved: the
/// sketch loses its `@main` to a wrapper file that hands it to the wallpaper
/// host, and the property list keeps the app out of the Dock. The quiet
/// failures are a second entry point (refuses to build), a Dock icon for a
/// program with no window (reads as a hang, since clicking it shows nothing),
/// and a sketch left at its windowed proportions (letterboxed wallpaper nobody
/// asked for).
@Suite("Wallpaper projects")
struct WallpaperProjectTests {

    @Test("The project carries the sketch, the wrapper program, and the app files")
    func theLayoutIsWhatAWallpaperNeeds() throws {
        let project = try plan(named: "Drift")
        let paths = project.files.map(\.path)

        #expect(paths.contains("Sources/Drift/Sketch.swift"))
        #expect(paths.contains("Sources/Drift/Main.swift"))
        #expect(paths.contains("Package.swift"))
        #expect(paths.contains("Info.plist"))
        #expect(paths.contains("build.sh"))
        #expect(paths.contains("README.md"))
        #expect(paths.contains(".gitignore"))
    }

    @Test("The entry point lives in the wrapper, not the sketch")
    func theWrapperCarriesTheEntryPoint() throws {
        let project = try plan(named: "Drift")
        let sketch = try #require(project.files.first { $0.path == "Sources/Drift/Sketch.swift" }).contents
        let main = try #require(project.files.first { $0.path == "Sources/Drift/Main.swift" }).contents

        // Two entry points refuse to build, so the sketch's has to come off.
        #expect(!sketch.split(separator: "\n").contains("@main"))
        #expect(main.contains("@main"))
        #expect(main.contains("OllinApp.runAsWallpaper { Drift() }"))
        // The shared command-line surface stays, which is also how build.sh
        // renders the icon from a frame of the piece.
        #expect(main.contains("OllinApp.handleCommandLine"))
    }

    @Test("The app stays out of the Dock")
    func theAppIsAnAccessory() throws {
        let project = try plan(named: "Drift")
        let plist = try #require(project.files.first { $0.path == "Info.plist" }).contents
        // A Dock icon for a program with no window reads as a hang: clicking
        // it would show nothing at all.
        #expect(plist.contains("<key>LSUIElement</key>"))
        // Still a program, with the app's own icon in Finder.
        #expect(plist.contains("<string>APPL</string>"))
        #expect(plist.contains("<key>CFBundleIconFile</key>"))
    }

    @Test("The manifest is an ordinary executable target with the app's script")
    func theManifestAndScriptAreTheAppsOwn() throws {
        let project = try plan(named: "Drift")
        let manifest = try #require(project.files.first { $0.path == "Package.swift" }).contents
        #expect(manifest.contains(".executableTarget"))
        #expect(!manifest.contains("-bundle"))

        let script = try #require(project.files.first { $0.path == "build.sh" })
        #expect(script.isExecutable)
        #expect(script.contents.contains("--show-bin-path"))
        #expect(script.contents.contains("\"$BIN\"/*.bundle"))
        #expect(project.runCommand.hasSuffix("build.sh"))
    }

    @Test("The sketch is drawn across the whole display")
    func theSketchFillsTheDisplay() throws {
        let project = try plan(named: "Drift")
        let sketch = try #require(project.files.first { $0.path == "Sources/Drift/Sketch.swift" }).contents
        #expect(sketch.contains("override var windowMode: WindowMode { .resizable }"))
    }

    @Test("A canvas that was asked for keeps its own proportions")
    func anAskedForCanvasWins() throws {
        let project = try plan(named: "Drift", canvas: .fhd1080)
        let sketch = try #require(project.files.first { $0.path == "Sources/Drift/Sketch.swift" }).contents
        #expect(!sketch.contains("override var windowMode"))
        #expect(sketch.contains("override var canvasSize"))
    }

    // MARK: - Support

    private func plan(named name: String,
                      canvas: CanvasChoice = .default) throws -> GeneratedProject {
        try ProjectGenerator.plan(ProjectRequest(
            name: name,
            kind: .wallpaper,
            template: .motion,
            canvas: canvas,
            destination: URL(fileURLWithPath: "/tmp/ollin-wallpaper-tests"),
            framework: .localPath(URL(fileURLWithPath: "/tmp/ollin"))
        ))
    }
}

/// A menu-bar project is the wallpaper's shape pointed at the other host. The
/// one claim of its own is the wrapper's call, so the checks here stay with
/// what differs; everything shared is pinned by the wallpaper suite above.
@Suite("Menu bar projects")
struct MenuBarProjectTests {

    @Test("The wrapper hands the sketch to the menu-bar host")
    func theWrapperCallsTheMenuBarHost() throws {
        let project = try plan(named: "Pulse")
        let sketch = try #require(project.files.first { $0.path == "Sources/Pulse/Sketch.swift" }).contents
        let main = try #require(project.files.first { $0.path == "Sources/Pulse/Main.swift" }).contents

        #expect(!sketch.split(separator: "\n").contains("@main"))
        #expect(main.contains("@main"))
        #expect(main.contains("OllinApp.runInMenuBar { Pulse() }"))
        #expect(main.contains("OllinApp.handleCommandLine"))
    }

    @Test("The app stays out of the Dock and the sketch follows the strip")
    func theAppIsAnAccessoryAndTheSketchFollows() throws {
        let project = try plan(named: "Pulse")
        let plist = try #require(project.files.first { $0.path == "Info.plist" }).contents
        #expect(plist.contains("<key>LSUIElement</key>"))
        #expect(plist.contains("<string>APPL</string>"))

        // The strip is a few points; a sketch that followed a fixed canvas
        // would be fitted into it as a sliver.
        let sketchFile = try #require(project.files.first { $0.path == "Sources/Pulse/Sketch.swift" }).contents
        #expect(sketchFile.contains("override var windowMode: WindowMode { .resizable }"))
    }

    @Test("The README says how to change the strip's width")
    func theWidthIsSaidWhereItIsChanged() throws {
        // The width is an argument of the wrapper's call, which is not where
        // anybody would think to look without being told.
        let project = try plan(named: "Pulse")
        let readme = try #require(project.files.first { $0.path == "README.md" }).contents
        #expect(readme.contains("runInMenuBar(width:"))
    }

    // MARK: - Support

    private func plan(named name: String) throws -> GeneratedProject {
        try ProjectGenerator.plan(ProjectRequest(
            name: name,
            kind: .menuBar,
            template: .motion,
            destination: URL(fileURLWithPath: "/tmp/ollin-menubar-tests"),
            framework: .localPath(URL(fileURLWithPath: "/tmp/ollin"))
        ))
    }
}
