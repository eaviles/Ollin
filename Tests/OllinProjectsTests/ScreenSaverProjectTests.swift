import Foundation
import Testing
@testable import OllinProjects

/// A screen saver is a plug-in rather than a program, and three things follow
/// from that: the sketch loses its entry point, the manifest builds a bundle
/// instead of an executable, and a property list has to name the class the
/// system will ask for. The last one is the quiet failure: get the name wrong
/// and the saver installs, appears in the list, and shows nothing at all.
@Suite("Screen saver projects")
struct ScreenSaverProjectTests {

    // MARK: - The plan

    @Test("The project carries the sketch, the class the system asks for, and the script that wraps them")
    func theLayoutIsWhatAPlugInNeeds() throws {
        let project = try plan(named: "Ripple")
        let paths = project.files.map(\.path)

        #expect(paths.contains("Sources/Ripple/Sketch.swift"))
        #expect(paths.contains("Sources/Ripple/SaverView.swift"))
        #expect(paths.contains("Package.swift"))
        #expect(paths.contains("Info.plist"))
        #expect(paths.contains("build.sh"))
        #expect(paths.contains("README.md"))
    }

    @Test("The build script is written so it can be run, and does the three things a saver needs")
    func theScriptDoesWhatAPlugInNeeds() throws {
        let project = try plan(named: "Ripple")
        let script = try #require(project.files.first { $0.path == "build.sh" })
        #expect(script.isExecutable)

        // Asked for, never assumed: the two build systems the toolchain ships
        // put the binary in different places, and a hard-coded path finds
        // nothing under the other one.
        #expect(script.contents.contains("--show-bin-path"))
        // The framework's own files travel inside the saver, because they are
        // looked for beside the running program and that program is the
        // system's.
        #expect(script.contents.contains("\"$BIN\"/*.bundle"))
        // Unsigned, the system refuses to load it.
        #expect(script.contents.contains("codesign"))
    }

    // MARK: - The name the system asks for

    @Test("The class in the property list is the class the sketch file declares")
    func thePrincipalClassMatchesTheSource() throws {
        let project = try plan(named: "Ripple")
        let plist = try #require(project.files.first { $0.path == "Info.plist" }).contents
        let source = try #require(project.files.first { $0.path == "Sources/Ripple/SaverView.swift" }).contents

        #expect(plist.contains("<key>NSPrincipalClass</key>"))
        #expect(plist.contains("<string>RippleSaverView</string>"))
        // `@objc` pins the runtime name. Without it Swift decorates the name and
        // the property list points at nothing.
        #expect(source.contains("@objc(RippleSaverView)"))
        #expect(source.contains("final class RippleSaverView: SketchSaverView"))
        // The attribute needs Foundation in scope, which is easy to leave out
        // when the file only mentions Ollin.
        #expect(source.contains("import Foundation"))
    }

    @Test("The property list says it is a plug-in and names its own binary")
    func thePropertyListDescribesABundle() throws {
        let project = try plan(named: "Ripple")
        let plist = try #require(project.files.first { $0.path == "Info.plist" }).contents

        // BNDL, not APPL. An app's package type here loads nothing.
        #expect(plist.contains("<string>BNDL</string>"))
        #expect(plist.contains("<key>CFBundleExecutable</key>"))
        #expect(plist.contains("<string>Ripple</string>"))
    }

    // MARK: - The manifest

    @Test("The manifest builds a loadable bundle rather than a program")
    func theManifestBuildsAPlugIn() throws {
        let project = try plan(named: "Ripple")
        let manifest = try #require(project.files.first { $0.path == "Package.swift" }).contents

        #expect(manifest.contains("type: .dynamic"))
        // The flag that turns the dynamic library into the Mach-O kind the
        // system loads. Without it the file is a dylib and the saver never
        // appears.
        #expect(manifest.contains("\"-Xlinker\", \"-bundle\""))
        #expect(!manifest.contains(".executableTarget"))
    }

    // MARK: - The sketch itself

    @Test("The sketch has no entry point of its own")
    func aPlugInSketchHasNoMain() throws {
        let project = try plan(named: "Ripple")
        let sketch = try #require(project.files.first { $0.path == "Sources/Ripple/Sketch.swift" }).contents
        #expect(!sketch.contains("@main"))
        #expect(sketch.contains("final class Ripple: Sketch"))
    }

    @Test("A sketch copied from an example loses the entry point it came with")
    func anExampleLosesItsMainToo() {
        // Every maintained example is a program in its own right, so the one it
        // carries has to come off on the way in.
        let source = """
        import Ollin

        /// A sketch that mentions `@main` in its own notes.
        @main
        final class Ripple: Sketch {
        }
        """
        let stripped = ProjectGenerator.withoutEntryPoint(source)
        #expect(!stripped.split(separator: "\n").contains("@main"))
        // A line that only talks about it is left alone.
        #expect(stripped.contains("mentions `@main` in its own notes"))
    }

    @Test("The sketch is drawn onto the whole display")
    func theSketchFillsTheScreen() throws {
        let project = try plan(named: "Ripple")
        let sketch = try #require(project.files.first { $0.path == "Sources/Ripple/Sketch.swift" }).contents
        #expect(sketch.contains("override var windowMode: WindowMode { .resizable }"))
    }

    @Test("A canvas that was asked for keeps its own proportions")
    func anAskedForCanvasWins() throws {
        // Asking for a shape and being given the display's shape instead would
        // be the generator overruling the request.
        let project = try plan(named: "Ripple", canvas: .fhd1080)
        let sketch = try #require(project.files.first { $0.path == "Sources/Ripple/Sketch.swift" }).contents
        #expect(!sketch.contains("override var windowMode"))
        #expect(sketch.contains("override var canvasSize"))
    }

    // MARK: - Support

    private func plan(named name: String,
                      canvas: CanvasChoice = .default) throws -> GeneratedProject {
        try ProjectGenerator.plan(ProjectRequest(
            name: name,
            kind: .screenSaver,
            template: .motion,
            canvas: canvas,
            destination: URL(fileURLWithPath: "/tmp/ollin-screensaver-tests"),
            framework: .localPath(URL(fileURLWithPath: "/tmp/ollin"))
        ))
    }
}
