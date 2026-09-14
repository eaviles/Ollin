import CoreGraphics
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
/// parse check. Then the two-speed evaluation through the shared engine: the
/// plain build lands first and the optimized one replaces it, both timed
/// against the single optimized build, and the two builds render the same
/// bytes, so the second swap can never be seen.
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

        // Completion at the caret, against the toolchain's own service: a word
        // typed after the canvas calls finds the framework's drawing methods,
        // narrowing the same session keeps only what still matches, and a
        // member dot on a value type lists its members with their types.
        print("OllinLiveCoding selftest: complete a name in the buffer …")
        guard let completer = CodeCompleter.load() else {
            fail("the toolchain's completion service could not be loaded; looked at \(CodeCompleter.frameworkPaths)")
        }
        let partial = """
        import Ollin
        final class BufferSketch: Sketch {
            override func draw() {
                background(.white)
                fill(Color.)
                draw
            }
        }
        """
        let drawCaret = (partial as NSString).range(of: "draw\n").location + 4
        let wordStart = CompletionText.wordStart(in: partial, caret: drawCaret)
        guard wordStart == drawCaret - 4, CompletionText.prefix(in: partial, caret: drawCaret) == "draw" else {
            fail("the word under the caret was read as starting at \(wordStart), expected \(drawCaret - 4)")
        }
        let arguments = loader.completionArguments(sourceFile: sketchFile)
        let word = CodeCompleter.Session(
            name: sketchFile, offset: CompletionText.utf8Offset(of: wordStart, in: partial))
        do {
            let started = Date()
            let rows = try completer.open(word, source: partial, arguments: arguments, filter: "drawCi")
            let seconds = Date().timeIntervalSince(started)
            guard let circle = rows.first(where: { $0.label == "drawCircle(x: Double, y: Double, radius: Double)" }) else {
                fail("`drawCi` did not offer drawCircle(x:y:radius:); the rows were \(rows.map(\.name))")
            }
            guard circle.insertion == "drawCircle(<#x: Double#>, <#y: Double#>, <#radius: Double#>)",
                  circle.kind == .function, circle.typeName == "Void", circle.bytesToErase == 0 else {
                fail("drawCircle came back as \(circle)")
            }
            guard rows.contains(where: { $0.name == "drawCircle(center:radius:)" }) else {
                fail("the labeled overload drawCircle(center:radius:) was not offered")
            }
            let narrowed = try completer.update(word, filter: "drawCircles")
            guard narrowed.contains(where: { $0.name == "drawCircles(:)" }),
                  !narrowed.contains(where: { $0.name == "drawCircle(:::)" }) else {
                fail("narrowing the session to `drawCircles` gave \(narrowed.map(\.name))")
            }
            completer.close(word)
            print("  the first request took \(String(format: "%.2f", seconds)) s, "
                + "\(rows.count) rows for `drawCi`, \(narrowed.count) for `drawCircles`")

            let dotCaret = (partial as NSString).range(of: "Color.").location + 6
            guard CompletionText.isMemberAccess(in: partial, caret: dotCaret) else {
                fail("the caret after `Color.` was not read as a member access")
            }
            let member = CodeCompleter.Session(
                name: sketchFile, offset: CompletionText.utf8Offset(of: dotCaret, in: partial))
            let colors = try completer.open(member, source: partial, arguments: arguments, filter: "re")
            guard let red = colors.first(where: { $0.name == "red" }) else {
                fail("`Color.` filtered by `re` did not offer red; the rows were \(colors.map(\.name))")
            }
            guard red.typeName == "Color", red.kind == .property, red.insertion == "red" else {
                fail("red came back as \(red)")
            }
            completer.close(member)
        } catch {
            fail("the completion service refused a request: \(error)")
        }

        Task { @MainActor in
            await checkTwoSpeed(loader: loader, dir: dir)
            print("OllinLiveCoding selftest passed: buffer compile, swap render "
                + "(\(a.count) vs \(b.count) bytes), diagnostics, completion, "
                + "and the two-speed evaluation all check out.")
            exit(0)
        }
        RunLoop.main.run()   // pumped until the check above exits
        exit(1)
    }

    /// Two-speed evaluation, headless through `SketchSession` with no runner
    /// (each build then lands as `sketch`): the plain build lands first and
    /// reports the optimized one on its way, the optimized build replaces it
    /// and is a different program (the sketch reads its own build level), the
    /// two render byte-identical frames, and a single-build session lands its
    /// one optimized build with nothing behind it. The three waits are
    /// printed, since what the mode buys is the gap between them.
    @MainActor
    private static func checkTwoSpeed(loader: SketchLoader, dir: String) async {
        // Drawing with arithmetic of its own, so the optimizer has something
        // to work on and the byte-identity means what it says.
        let source = """
        import Ollin
        final class TwoSpeedSketch: Sketch {
            @Param(0...2) var build = 0.0
            override func setup() {
                build = _isDebugAssertConfiguration() ? 1 : 2   // plain 1, optimized 2
            }
            override func draw() {
                background(.white)
                fill(.black)
                noStroke()
                for i in 0..<1500 {
                    let t = Double(i) * 0.0173
                    let r = 120 + 300 * (0.5 + 0.5 * sin(t * 3.1 + cos(t * 7.5)))
                    let x = width / 2 + cos(t * 41) * r
                    let y = height / 2 + sin(t * 29) * r
                    drawCircle(x, y, 3 + 5 * (0.5 + 0.5 * cos(t * 13)))
                }
            }
        }
        """
        func build(of sketch: Sketch) -> Double {
            guard let handle = sketch.parameters().first(where: { $0.name == "build" }),
                  case .number(let v) = handle.param.stored else { return .nan }
            return v
        }
        // Decoded pixels, never a file's bytes: an exported PNG carries the
        // recipe with the parameter values, and `build` reads differently on
        // purpose, so the two files would differ while the pictures do not.
        func render(_ sketch: Sketch) -> [UInt8] {
            guard let image = OllinApp.image(of: sketch) else { return [] }
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: &pixels, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return [] }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return pixels
        }
        func wait(_ what: String, until done: @MainActor () -> Bool) async {
            for _ in 0..<6000 {   // a compile is a second or two; cap at a minute
                if done() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
            fail("\(what) never happened")
        }

        print("OllinLiveCoding selftest: two-speed evaluation, the plain build first …")
        let session = SketchSession(keepClock: true, landsPlainBuildFirst: true)
        let started = Date()
        // The host hears about the first landing through `onSuccess`, once;
        // reading there is the only sure way to catch the plain build, since
        // on a sketch this small the optimized one lands a few tens of
        // milliseconds behind it, inside any poll.
        var landings = 0
        var plainSeconds = 0.0
        var plain: Sketch?
        var optimizingAtLanding = false
        session.evaluate(loader, input: .source(source)) { sketch in
            landings += 1
            plainSeconds = Date().timeIntervalSince(started)
            plain = sketch
            optimizingAtLanding = session.isOptimizing
        }
        await wait("the evaluation settling") { session.phase != .compiling && !session.isOptimizing }
        let optimizedSeconds = Date().timeIntervalSince(started)
        guard case .idle = session.phase, let plain else {
            fail("the two-speed evaluation failed: \(session.phase)")
        }
        guard landings == 1 else { fail("the host was told about \(landings) landings, expected one") }
        guard optimizingAtLanding else {
            fail("the plain build landed without an optimized build reported behind it")
        }
        let plainFrame = render(plain)
        guard build(of: plain) == 1 else {
            fail("the first build to land reads as build \(build(of: plain)), expected the plain one (1)")
        }
        guard let optimized = session.sketch, optimized !== plain else {
            fail("the optimized build did not replace the plain one")
        }
        let optimizedFrame = render(optimized)
        guard build(of: optimized) == 2 else {
            fail("the second build to land reads as build \(build(of: optimized)), expected the optimized one (2)")
        }
        guard !plainFrame.isEmpty, plainFrame == optimizedFrame else {
            fail("the plain and optimized builds rendered different pixels; the second swap would show")
        }

        print("OllinLiveCoding selftest: the single optimized build, for the comparison …")
        let single = SketchSession(keepClock: true)
        let singleStarted = Date()
        single.evaluate(loader, input: .source(source))
        await wait("the single build landing") { single.phase != .compiling }
        let singleSeconds = Date().timeIntervalSince(singleStarted)
        guard case .idle = single.phase, let only = single.sketch else {
            fail("the single-build evaluation failed: \(single.phase)")
        }
        let singleFrame = render(only)   // runs its setup(), which reads the build level
        guard !single.isOptimizing, build(of: only) == 2 else {
            fail("the single-build session did not land one optimized build (optimizing \(single.isOptimizing), build \(build(of: only)))")
        }
        guard singleFrame == optimizedFrame else {
            fail("the single optimized build rendered different pixels from the two-speed one")
        }
        print("  plain build on stage at \(String(format: "%.2f", plainSeconds)) s, "
            + "optimized build in at \(String(format: "%.2f", optimizedSeconds)) s; "
            + "the single optimized build alone took \(String(format: "%.2f", singleSeconds)) s")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLiveCoding selftest FAILED: \(message)\n".utf8))
        exit(1)
    }
}
