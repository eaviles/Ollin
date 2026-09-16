import Foundation
import Testing
@testable import OllinProjects

/// A widget project is the one kind that is two programs. The system finds a
/// widget through the app it is packed inside, so the sketch has to be
/// reachable from both, and the quiet failures all live in that split: a
/// sketch made public (which would make every override in it public too), a
/// second entry point, an extension the system cannot recognize, and a
/// signature that seals the app before the thing inside it is signed.
@Suite("Widget projects")
struct WidgetProjectTests {

    @Test("The project carries the sketch, its door, and two programs")
    func theLayoutIsWhatAWidgetNeeds() throws {
        let project = try plan(named: "Ripple")
        let paths = project.files.map(\.path)

        #expect(paths.contains("Sources/Ripple/Sketch.swift"))
        #expect(paths.contains("Sources/Ripple/Piece.swift"))
        #expect(paths.contains("Sources/RippleApp/Main.swift"))
        #expect(paths.contains("Sources/RippleWidget/Widget.swift"))
        #expect(paths.contains("Package.swift"))
        #expect(paths.contains("Info.plist"))
        #expect(paths.contains("Widget-Info.plist"))
        #expect(paths.contains("Widget.entitlements"))
        #expect(paths.contains("build.sh"))
        #expect(paths.contains("README.md"))
    }

    @Test("The sketch stays an ordinary sketch, reached through one public door")
    func theSketchStaysOrdinary() throws {
        let project = try plan(named: "Ripple")
        let sketch = try #require(project.files.first { $0.path == "Sources/Ripple/Sketch.swift" }).contents
        let door = try #require(project.files.first { $0.path == "Sources/Ripple/Piece.swift" }).contents

        // A public class would force `public override func draw()` on every
        // override in it, which is a sketch written differently from every
        // other kind's. One public line instead.
        #expect(sketch.contains("final class Ripple: Sketch {"))
        #expect(!sketch.contains("public final class"))
        #expect(!sketch.contains("public override"))
        // Two entry points refuse to build, and neither program here is the
        // sketch.
        #expect(!sketch.split(separator: "\n").contains("@main"))
        #expect(door.contains("public enum RipplePiece"))
        #expect(door.contains("@MainActor public static func make() -> Sketch { Ripple() }"))
    }

    @Test("The sketch says how far apart its pictures sit")
    func theSketchDeclaresItsRun() throws {
        let project = try plan(named: "Ripple")
        let sketch = try #require(project.files.first { $0.path == "Sources/Ripple/Sketch.swift" }).contents

        #expect(sketch.contains("override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }"))
        // A widget is drawn at whatever size the system asks for, so a fixed
        // canvas would be fitted into it rather than filling it.
        #expect(sketch.contains("override var windowMode: WindowMode { .resizable }"))
    }

    @Test("Each program has one entry point, and only one")
    func eachProgramHasItsOwnEntryPoint() throws {
        let project = try plan(named: "Ripple")
        let main = try #require(project.files.first { $0.path == "Sources/RippleApp/Main.swift" }).contents
        let widget = try #require(project.files.first { $0.path == "Sources/RippleWidget/Widget.swift" }).contents

        #expect(main.contains("@main"))
        #expect(main.contains("OllinApp.run(RipplePiece.make())"))
        // The export flags keep working, which is how build.sh renders the
        // icon and how `--export-widget` shows the run without waiting for it.
        #expect(main.contains("OllinApp.handleCommandLine"))

        #expect(widget.contains("@main"))
        #expect(widget.contains("struct SketchWidget: Widget"))
        #expect(widget.contains("OllinApp.widgetFrames"))
    }

    @Test("Names that mean two things in this file are spelled out")
    func theAmbiguousNamesAreQualified() throws {
        let project = try plan(named: "Ripple")
        let widget = try #require(project.files.first { $0.path == "Sources/RippleWidget/Widget.swift" }).contents

        // Ollin and WidgetKit both have a `Timeline`, and Ollin and SwiftUI
        // both have a `Color`. All four are in scope in this one file, so a
        // bare name is a build failure in generated code.
        #expect(widget.contains("WidgetKit.Timeline<Moment>"))
        #expect(widget.contains("SwiftUI.Color.black"))
        #expect(!widget.contains(" Timeline<Moment>("))
    }

    @Test("Three targets, because two programs cannot share a folder")
    func theManifestSplitsTheSketchOut() throws {
        let project = try plan(named: "Ripple")
        let manifest = try #require(project.files.first { $0.path == "Package.swift" }).contents

        #expect(manifest.contains(".target(\n            name: \"Ripple\""))
        #expect(manifest.contains(".executableTarget(\n            name: \"RippleApp\""))
        #expect(manifest.contains(".executableTarget(\n            name: \"RippleWidget\""))
        // Both programs reach the sketch, and both link the framework.
        let dependsOnTheSketch = manifest.components(separatedBy: "\n                \"Ripple\",").count - 1
        #expect(dependsOnTheSketch == 2)
    }

    @Test("The extension says what kind of extension it is, under the app's name")
    func theExtensionIsRecognizable() throws {
        let project = try plan(named: "Ripple")
        let plist = try #require(project.files.first { $0.path == "Widget-Info.plist" }).contents

        // Without this the system has no idea what it is holding and never
        // asks it for anything.
        #expect(plist.contains("<key>NSExtensionPointIdentifier</key>"))
        #expect(plist.contains("<string>com.apple.widgetkit-extension</string>"))
        // An identifier under the app's own is how the system knows which app
        // this extension belongs to.
        #expect(plist.contains("<string>com.example.ripple.widget</string>"))
        #expect(plist.contains("<string>XPC!</string>"))
        #expect(plist.contains("<string>RippleWidget</string>"))
    }

    @Test("The app names the program it actually holds")
    func theAppPlistNamesItsBinary() throws {
        let project = try plan(named: "Ripple")
        let plist = try #require(project.files.first { $0.path == "Info.plist" }).contents

        // The executable is the app target, not the library the sketch is in.
        #expect(plist.contains("<key>CFBundleExecutable</key>\n    <string>RippleApp</string>"))
        #expect(plist.contains("<string>com.example.ripple</string>"))
        // This app has a window, so unlike the wallpaper it belongs in the Dock.
        #expect(!plist.contains("<key>LSUIElement</key>"))
    }

    @Test("The extension is sandboxed and signed before the app is sealed")
    func theSigningOrderIsRight() throws {
        let project = try plan(named: "Ripple")
        let entitlements = try #require(project.files.first { $0.path == "Widget.entitlements" }).contents
        let script = try #require(project.files.first { $0.path == "build.sh" }).contents

        // An extension signed without saying it is sandboxed is refused rather
        // than sandboxed.
        #expect(entitlements.contains("com.apple.security.app-sandbox"))
        #expect(script.contains("--entitlements Widget.entitlements \"$APPEX\""))

        // Signing the app seals what is inside it, so the extension has to be
        // signed first or the seal breaks.
        let appex = try #require(script.range(of: "--entitlements Widget.entitlements \"$APPEX\""))
        let app = try #require(script.range(of: "--sign - --timestamp=none \"$APP\""))
        #expect(appex.lowerBound < app.lowerBound)
    }

    @Test("The framework's own files travel in both programs")
    func bothProgramsCarryTheResources() throws {
        let project = try plan(named: "Ripple")
        let script = try #require(project.files.first { $0.path == "build.sh" }).contents

        // They are looked for beside the running program, and there are two
        // running programs here.
        #expect(script.contains("cp -R \"$bundle\" \"$APP/Contents/Resources/\""))
        #expect(script.contains("cp -R \"$bundle\" \"$APPEX/Contents/Resources/\""))
        // Inside the app, where the system looks for an extension.
        #expect(script.contains("APPEX=\"$APP/Contents/PlugIns/$WIDGET_TARGET.appex\""))
    }

    @Test("The README says how to see the run without waiting for it")
    func theReadmeSaysHowToWorkOnIt() throws {
        let project = try plan(named: "Ripple")
        let readme = try #require(project.files.first { $0.path == "README.md" }).contents

        // A quarter of an hour between pictures is no way to work.
        #expect(readme.contains("--export-widget frames"))
        #expect(readme.contains("widgetTimeline"))
        #expect(readme.contains("Edit Widgets"))
    }

    // MARK: - Support

    private func plan(named name: String) throws -> GeneratedProject {
        try ProjectGenerator.plan(ProjectRequest(
            name: name,
            kind: .widget,
            template: .motion,
            destination: URL(fileURLWithPath: "/tmp/ollin-widget-tests"),
            framework: .localPath(URL(fileURLWithPath: "/tmp/ollin"))
        ))
    }
}
