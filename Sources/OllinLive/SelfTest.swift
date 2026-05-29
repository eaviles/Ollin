import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinLive --selftest` — a headless smoke test for the reload
/// pipeline that needs no window. It writes a sketch, compiles + loads it via
/// `SketchLoader`, renders a frame off-screen, then *edits* the sketch and does
/// it again, asserting the two renders differ. That proves the risky part —
/// recompile → `dlopen` → instantiate → render — end to end (Metal required).
enum SelfTest {
    @MainActor
    static func run() -> Never {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinLive-selftest")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let sketchFile = (dir as NSString).appendingPathComponent("Sketch.swift")

        func writeSketch(radius: Double) {
            let source = """
            import Ollin
            final class SelfTestSketch: Sketch {
                override func draw() {
                    background(.white)
                    fill(.black)
                    circle(width / 2, height / 2, \(radius))
                }
            }
            """
            try! source.write(toFile: sketchFile, atomically: true, encoding: .utf8)
        }

        func compileLoadRender(to path: String) -> Bool {
            switch SketchLoader(sketchPath: sketchFile).load() {
            case .success(let sketch):
                OllinApp.export(sketch, to: path)   // off-screen MSAA render, no window
                return FileManager.default.fileExists(atPath: path)
            case .failure(let error):
                print("  \(error)")
                return false
            }
        }

        let pngA = (dir as NSString).appendingPathComponent("a.png")
        let pngB = (dir as NSString).appendingPathComponent("b.png")

        print("OllinLive selftest: compile + load + render v1 (radius 40) …")
        writeSketch(radius: 40)
        guard compileLoadRender(to: pngA) else { fail("v1 failed to compile/load/render") }

        print("OllinLive selftest: edit, recompile + load + render v2 (radius 240) …")
        writeSketch(radius: 240)
        guard compileLoadRender(to: pngB) else { fail("v2 failed to compile/load/render") }

        let a = (try? Data(contentsOf: URL(fileURLWithPath: pngA))) ?? Data()
        let b = (try? Data(contentsOf: URL(fileURLWithPath: pngB))) ?? Data()
        guard !a.isEmpty, !b.isEmpty else { fail("a render produced no output") }
        guard a != b else { fail("v1 and v2 rendered identically — the reload had no effect") }

        print("OllinLive selftest: PASS — the edited sketch recompiled, loaded, and "
            + "rendered differently (\(a.count) vs \(b.count) bytes).")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive selftest: FAIL — \(message)\n".utf8))
        exit(1)
    }
}
