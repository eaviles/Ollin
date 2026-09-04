import Foundation
import ImageIO
import Ollin
import OllinRuntime

/// `swift run OllinLive --selftest` — a headless smoke test for the reload
/// pipeline that needs no window. It writes a sketch, compiles + loads it via
/// `SketchLoader`, renders a frame off-screen, then *edits* the sketch and does
/// it again, asserting the two renders differ. That proves the risky part —
/// recompile → `dlopen` → instantiate → render — end to end (Metal required).
/// Two further phases cover the directly-executable hashbang form: a
/// `#!/usr/bin/env ollin` sketch must compile and render, and a broken one
/// must still report diagnostics at the original line numbers.
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
                    drawCircle(width / 2, height / 2, \(radius))
                }
            }
            """
            try! source.write(toFile: sketchFile, atomically: true, encoding: .utf8)
        }

        func compileLoadRender(to path: String,
                               optimization: SketchLoader.Optimization = .speed) -> Bool {
            switch SketchLoader(sketchPath: sketchFile, optimization: optimization).load() {
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

        // The sketch compiles optimized by default (`-O`); `--no-optimize`
        // compiles it plain. Both must load, and the picture is the same
        // either way, since the drawing happens in the host.
        print("OllinLive selftest: v2 compiled without optimization renders the same bytes …")
        let pngD = (dir as NSString).appendingPathComponent("d.png")
        guard compileLoadRender(to: pngD, optimization: .none) else {
            fail("v2 failed to compile/load/render without optimization")
        }
        // Decoded pixels, not file bytes: the PNG carries the export's
        // metadata, and its timestamp differs between two exports.
        guard let pixelsB = pixels(pngB), let pixelsD = pixels(pngD) else {
            fail("could not decode the v2 renders")
        }
        guard pixelsD == pixelsB else {
            fail("the unoptimized compile rendered different pixels")
        }

        // A hashbang first line (the directly-executable single-file form) must
        // compile: the loader neutralizes it before handing the source to swiftc,
        // which otherwise rejects a hashbang outside a main file.
        print("OllinLive selftest: hashbang sketch compiles + renders …")
        let shebangSketch = """
        #!/usr/bin/env ollin
        import Ollin
        final class SelfTestSketch: Sketch {
            override func draw() {
                background(.white)
                fill(.black)
                drawCircle(width / 2, height / 2, 140)
            }
        }
        """
        try! shebangSketch.write(toFile: sketchFile, atomically: true, encoding: .utf8)
        let pngC = (dir as NSString).appendingPathComponent("c.png")
        guard compileLoadRender(to: pngC) else {
            fail("hashbang sketch failed to compile/load/render")
        }

        // The neutralization swaps `#!` for `//` in place, so a diagnostic in a
        // hashbang file must still carry the original line number.
        print("OllinLive selftest: hashbang diagnostics keep exact line numbers …")
        let brokenSketch = """
        #!/usr/bin/env ollin
        import Ollin
        final class SelfTestSketch: Sketch {
            override func draw() {
                let mistyped: Int = "not an Int"
                _ = mistyped
            }
        }
        """
        try! brokenSketch.write(toFile: sketchFile, atomically: true, encoding: .utf8)
        switch SketchLoader(sketchPath: sketchFile).compile() {
        case .success:
            fail("broken hashbang sketch compiled unexpectedly")
        case .failure(let error):
            guard "\(error)".contains("Sketch.swift:5:") else {
                fail("hashbang diagnostic lost its line number: \(error)")
            }
        }

        print("OllinLive selftest: PASS: the edited sketch recompiled, loaded, and "
            + "rendered differently (\(a.count) vs \(b.count) bytes), the unoptimized "
            + "compile rendered the same bytes, and the hashbang form compiled with "
            + "exact diagnostic lines.")
        exit(0)
    }

    /// The decoded pixels of a PNG, for comparing two exports whose bytes
    /// differ only in their metadata.
    private static func pixels(_ path: String) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let data = image.dataProvider?.data else { return nil }
        return data as Data
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive selftest: FAIL — \(message)\n".utf8))
        exit(1)
    }
}
