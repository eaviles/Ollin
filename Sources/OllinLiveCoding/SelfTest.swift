import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinLiveCoding --selftest`: a headless smoke test for the
/// evaluate pipeline, exercising the *buffer* path (`SketchLoader.Input.source`)
/// end to end with no window: compile an in-memory source as a sketch that was
/// never written to disk, render it off-screen, "edit" the buffer, render
/// again, and assert the two frames differ. Then break the buffer and assert
/// the failure parses into a line-accurate diagnostic carrying the sketch's
/// own file name (what the editor keys on), plus a canned multi-diagnostic
/// parse check.
enum SelfTest {
    @MainActor
    static func run() -> Never {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinLiveCoding-selftest")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        // The buffer's stand-in path, never written: the point of the buffer
        // path is that the file on disk isn't touched.
        let sketchFile = (dir as NSString).appendingPathComponent("Sketch.swift")
        let loader = SketchLoader(sketchPath: sketchFile)

        func source(radius: Double) -> String {
            """
            import Ollin
            final class BufferSketch: Sketch {
                override func draw() {
                    background(.white)
                    fill(.black)
                    drawCircle(width / 2, height / 2, \(radius))
                }
            }
            """
        }

        func compileLoadRender(_ text: String, to path: String) -> Bool {
            switch loader.compile(.source(text)) {
            case .success(let dylibPath):
                switch loader.instantiate(dylibPath: dylibPath) {
                case .success(let sketch):
                    OllinApp.export(sketch, to: path)   // off-screen render, no window
                    return FileManager.default.fileExists(atPath: path)
                case .failure(let error):
                    print("  \(error)")
                    return false
                }
            case .failure(let error):
                print("  \(error)")
                return false
            }
        }

        let pngA = (dir as NSString).appendingPathComponent("a.png")
        let pngB = (dir as NSString).appendingPathComponent("b.png")

        print("OllinLiveCoding selftest: compile buffer v1 (radius 40) + render …")
        guard compileLoadRender(source(radius: 40), to: pngA) else {
            fail("buffer v1 failed to compile/load/render")
        }
        guard !FileManager.default.fileExists(atPath: sketchFile) else {
            fail("the buffer compile wrote the sketch file; evaluate must never save")
        }

        print("OllinLiveCoding selftest: compile buffer v2 (radius 240) + render …")
        guard compileLoadRender(source(radius: 240), to: pngB) else {
            fail("buffer v2 failed to compile/load/render")
        }

        let a = (try? Data(contentsOf: URL(fileURLWithPath: pngA))) ?? Data()
        let b = (try? Data(contentsOf: URL(fileURLWithPath: pngB))) ?? Data()
        guard !a.isEmpty, !b.isEmpty else { fail("a render produced no output") }
        guard a != b else { fail("v1 and v2 rendered identically; the swap had no effect") }

        // A broken buffer: `let x: Int = "no"` on a known line (1-indexed; the
        // source builder puts it right after `draw() {`, line 4).
        print("OllinLiveCoding selftest: compile a broken buffer, expect a parsed diagnostic …")
        let broken = """
        import Ollin
        final class BufferSketch: Sketch {
            override func draw() {
                let x: Int = "no"
                _ = x
            }
        }
        """
        guard case .failure(.compileFailed(let log)) = loader.compile(.source(broken)) else {
            fail("the broken buffer compiled")
        }
        let parsed = CompileDiagnostic.parse(log)
        guard let diagnostic = parsed.first(where: { $0.severity == .error }) else {
            fail("no error parsed out of the compiler log:\n\(log)")
        }
        guard diagnostic.fileName == "Sketch.swift" else {
            fail("diagnostic names \(diagnostic.fileName), expected Sketch.swift")
        }
        guard diagnostic.line == 4 else {
            fail("diagnostic at line \(diagnostic.line), expected 4")
        }

        // The parser against a canned log: severities kept, context lines dropped.
        let canned = """
        /tmp/x/Sketch.swift:3:5: error: cannot find 'wat' in scope
            wat()
            ^
        /tmp/x/Sketch.swift:7:9: warning: variable 'v' was never used
        /tmp/x/Sketch.swift:7:9: note: consider removing it
        ld: some unrelated linker chatter
        """
        let cannedParsed = CompileDiagnostic.parse(canned)
        guard cannedParsed.count == 3,
              cannedParsed[0].severity == .error, cannedParsed[0].line == 3,
              cannedParsed[0].column == 5,
              cannedParsed[1].severity == .warning, cannedParsed[1].line == 7,
              cannedParsed[2].severity == .note
        else {
            fail("canned log parsed as \(cannedParsed)")
        }

        print("OllinLiveCoding selftest passed: buffer compile, swap render "
            + "(\(a.count) vs \(b.count) bytes), and diagnostics all check out.")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLiveCoding selftest FAILED: \(message)\n".utf8))
        exit(1)
    }
}
