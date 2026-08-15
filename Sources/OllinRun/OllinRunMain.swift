import AppKit
import Foundation
import Ollin
import OllinRuntime

// OllinRun: the host that gives one loose `.swift` file its own window.
//
//   swift run OllinRun <path/to/Sketch.swift> [flags]
//   ollin <path/to/Sketch.swift> --installation
//
// The live host owns its window, and the sketch is a guest in it: chrome
// around the canvas, a sidebar, a saved frame, a recompile on every save. That
// is what iterating wants and the opposite of what a wall wants. Everything a
// sketch declares in its `Installation` (the filled screen, the hidden
// pointer, the held-off screen saver, the checkpoint, the watch, the hours,
// the corners it is lined up by) is read on the path where the sketch owns the
// window, so a loose file could not go up at all.
//
// This host is that path for a loose file. It compiles the file once, exactly
// as the live host does, and hands the sketch to `OllinApp.run`, which is the
// same call a packaged `@main` sketch makes. From there nothing knows the
// sketch came from a loose file: the window, the installation, the supervisor,
// and the checkpoint are the shipped ones.
//
// It reloads nothing. A piece on a wall must run the code it was started with,
// and an edit halfway through a save is not something to pick up at three in
// the morning. Use the live host to work on the piece, and this one to put it
// up.
@main
enum OllinRunHost {

    @MainActor
    static func main() {
        // AppKit reads a bare path argument as a request to open a file, which
        // is what suppresses a bundleless host's first window. Registered
        // before AppKit parses the arguments, so the sketch path stays an
        // argument (the live host and the gallery carry the same line).
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
        setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: a piped log keeps every line

        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--selftest") { RunSelfTest.run() }   // headless; exits

        guard let pathArgument = arguments.first(where: { !$0.hasPrefix("-") }) else {
            fail("usage: swift run OllinRun <path/to/Sketch.swift> [--installation]", code: 2)
        }
        let sketchPath = (pathArgument as NSString).isAbsolutePath
            ? pathArgument
            : (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent(pathArgument)
        guard FileManager.default.fileExists(atPath: sketchPath) else {
            fail("OllinRun: file not found: \(sketchPath)", code: 2)
        }

        // The export flags work here for the same reason they work in the live
        // host: the shared handler recognizes one before anything is compiled,
        // so the windowed path pays nothing and a loose file keeps one export
        // surface wherever it is run from.
        if OllinApp.handleCommandLine(arguments, makeSketch: { load(sketchPath) }) { exit(0) }

        // Compiled here rather than inside the run, which also makes a broken
        // file fail once, out loud, with the compiler's own message. A piece
        // that asks to be started again after a crash becomes its own
        // supervisor inside `run`, and a file that cannot compile would
        // otherwise fail in each child in turn until the watch gave up.
        OllinApp.run(load(sketchPath))
    }

    /// Compile the file and build the sketch out of it, or say why not and
    /// stop. The loader is the live host's: the sketch is compiled into a fresh
    /// dylib whose Ollin symbols bind to this process, so the loaded object
    /// really is an `Ollin.Sketch`.
    @MainActor
    private static func load(_ sketchPath: String) -> Sketch {
        switch SketchLoader(sketchPath: sketchPath).load() {
        case .success(let sketch):
            return sketch
        case .failure(let error):
            fail("OllinRun: \(error)", code: 1)
        }
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}
