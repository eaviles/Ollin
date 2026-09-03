import Testing
import Foundation
import CoreGraphics
import ImageIO
import OllinWebGate
@testable import Ollin

/// The recorded web page. The recorder is checked on its own (what a frame
/// holds, what folds, what refuses), the two forms against each other, and
/// the page against the Mac: a headless browser plays the page to a chosen
/// frame and hands its pixels back, which are diffed against the same frame
/// from `OllinApp.image(of:frame:)` under the snapshot tolerance. The browser
/// checks skip, with the reason in the log, where no browser gives WebGL2.
@Suite @MainActor struct WebExportTests {

    // MARK: Fixtures

    /// The hello-world: a black circle outline breathing on white (the Basic
    /// example, at a smaller canvas).
    final class Hello: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.white)
            noFill()
            stroke(.black)
            strokeWeight(3.75 * scale)
            drawCircle(width / 2, height / 2, (150 + sin(time) * 40) * scale)
        }
    }

    /// The ring the site opens on (the Web example, at a smaller canvas): every
    /// motion a sine of one shared phase over a sixty-second loop.
    final class Ring: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override var loopDuration: Double? { 60 }
        private let count = 28
        override func draw() {
            background(.white)
            noFill()
            strokeWeight(2.5 * scale)
            let phase = time / 60 * .tau
            let ring = shortSide * 0.3
            for i in 0 ..< count {
                let n = Double(i)
                let angle = n / Double(count) * .tau + phase
                let drift = sin(phase * 7 + n * 1.31) * ring * 0.08
                let radius = ring * 0.19 + sin(phase * 10 + n * 0.83) * ring * 0.07
                let fade = 0.28 + 0.22 * sin(phase * 9 + n * 0.5)
                stroke(Color(red: 0, green: 0, blue: 0, alpha: fade))
                drawCircle(center: center + Vector2(cos(angle), sin(angle)) * (ring + drift), radius: radius)
            }
        }
    }

    /// A picture that never moves.
    final class Still: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(Color(hex: 0x203040))
            noStroke()
            fill(Color(hex: 0xE0C060))
            drawRect(center: center, width: 60, height: 40, cornerRadius: 8)
            fill(.white)
            drawStar(center: Vector2(30, 30), outerRadius: 18, innerRadius: 8, points: 5)
        }
    }

    /// A shape count that changes from frame to frame (`frameCount` is 1 on the
    /// first drawn frame, so the first recorded frame holds two).
    final class Growing: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.black)
            noStroke()
            fill(.white)
            for i in 0 ... frameCount { drawCircle(10 + Double(i) * 12, 60, 5) }
        }
    }

    /// A filled disc crossing the canvas: the area-conserving disk coverage, and
    /// a picture that changes a lot from one frame to another.
    final class Moving: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            noStroke()
            fill(Color(hex: 0x102030))
            drawCircle(20 + Double(frameCount) * 3, 60, 30)
        }
    }

    /// A circle whose radius a formula drives: the motion the page works out
    /// live from the formula rather than reading back.
    final class Driven: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        @Param(0 ... 300) var radius: Double = 100
        override func setup() {
            drive($radius, "150 + sin(time * tau / 6) * 40")
        }
        override func draw() {
            background(.white)
            noFill()
            stroke(.black)
            strokeWeight(3.75 * scale)
            drawCircle(width / 2, height / 2, radius * scale)
        }
    }

    final class Clipped: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            drawCircle(60, 60, 20)
            if frameCount == 2 {   // the second recorded frame
                withClip(Rectangle(x: 0, y: 0, width: 60, height: 60)) { drawCircle(30, 30, 40) }
            }
        }
    }

    final class Graded: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            fill(Gradient.linear(from: Vector2(0, 0), to: Vector2(120, 0), [.red, .blue]))
            drawRect(0, 0, 120, 120)
        }
    }

    final class Written: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            fill(.black)
            textMode(.atlas)
            drawText("hi", 20, 60)
        }
    }

    // MARK: Support

    /// The page's pixels at `frame`, read back through the browser: the inline
    /// fragment inside a bare page, or the standalone file, with a probe that
    /// shows the frame and writes the canvas as a PNG data URL into the DOM.
    static func probe(_ page: String, frame: Int) -> String {
        let probe = """
        <pre id="r0">PENDING</pre>
        <script>
        (function () {
          var out = document.getElementById('r0');
          try {
            var player = window.ollin;
            if (!player) { out.textContent = 'FAIL no player'; return; }
            player.pause();
            player.showFrame(\(frame));
            out.textContent = player.canvas.toDataURL('image/png');
          } catch (e) { out.textContent = 'FAIL ' + e; }
        })();
        </script>
        """
        if let end = page.range(of: "</body>") {
            return page.replacingCharacters(in: end, with: probe + "\n</body>")
        }
        return "<!doctype html><html><body>\n" + page + "\n" + probe + "\n</body></html>"
    }

    static func image(fromDataURL report: String) throws -> CGImage {
        let prefix = "data:image/png;base64,"
        try #require(report.hasPrefix(prefix), "\(report.prefix(300))")
        let data = try #require(Data(base64Encoded: String(report.dropFirst(prefix.count))))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func rgba(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return bytes
    }

    /// Mean absolute difference per byte, 0...255, of two same-sized images.
    static func meanDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        try #require(a.width == b.width && a.height == b.height, "\(a.width)x\(a.height) against \(b.width)x\(b.height)")
        let x = rgba(of: a), y = rgba(of: b)
        var sum = 0
        for i in x.indices { sum += abs(Int(x[i]) - Int(y[i])) }
        return Double(sum) / Double(x.count)
    }

    static func pagePixels(_ page: String, frame: Int) async throws -> CGImage {
        let dom = try await HeadlessBrowser.dom(of: probe(page, frame: frame))
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        return try image(fromDataURL: report)
    }

    // MARK: The recorder

    @Test func recordsWhatTheRendererReceived() throws {
        let recording = try OllinApp.recordWebFrames(of: Hello(), frames: 12, fps: 30)
        #expect(recording.frames.count == 12)
        #expect(recording.width == 240 && recording.height == 240)
        #expect(recording.rate == 30)
        #expect(!recording.loops)
        let frame = recording.frames[3]
        #expect(frame.instances.count == WebInstance.floats)
        #expect(frame.clear == SIMD3<Float>(1, 1, 1))
        #expect(frame.toneMapMode == 0 && frame.exposure == 1)
        // The circle: an ellipse tag, its radius breathing with the clock.
        #expect(frame.instances[WebInstance.shapeColumn] == 0)
        let radius = Double(frame.instances[8])
        #expect(abs(radius - (150 + sin(3.0 / 30) * 40) * 0.24) < 1e-3)
        // No fill, a black stroke 3.75 * scale wide.
        #expect(frame.instances[13] == 0)
        #expect(frame.instances[17] == 1)
        #expect(abs(Double(frame.instances[24]) - 3.75 * 0.24) < 1e-5)
        // The transform is the identity: the two axes and no translation.
        #expect(Array(frame.instances[0 ..< 6]) == [1, 0, 0, 1, 0, 0])
    }

    @Test func aLapOfTheLoopWraps() throws {
        let recording = try OllinApp.recordWebFrames(of: Ring(), frames: 600, fps: 10)
        #expect(recording.loops)
        #expect(recording.frames.allSatisfy { $0.instances.count == 28 * WebInstance.floats })
        let track = WebTrack(recording)
        #expect(track.stable)
        #expect(track.uniqueFrames == 600)
        #expect(track.meta.contains("\"loops\":true"))
        // Every moving column (center, radius, and the stroke's alpha of each
        // of the 28 circles) is a sum of a few sines with whole cycle counts per
        // lap, so all of them fit and nothing streams as samples.
        #expect(track.fittedColumns == 28 * 5)
        #expect(track.sampledColumns == 0)
        #expect(track.stream.isEmpty)
        #expect(track.fitTerms > 0 && track.fitTerms <= 28 * 9, "\(track.fitTerms) terms")
        #expect(!track.fit.isEmpty)
    }

    @Test func aFitRebuildsItsSamplesAndRefusesWhatItCannotShorten() {
        let n = 600
        let sines = (0 ..< n).map { k -> Double in
            let w = 2 * Double.pi * Double(k) / Double(n)
            return 3 + 2 * sin(7 * w) + 0.5 * cos(10 * w)
        }
        let fit = FourierFit.fit(sines, tolerance: 1e-6, maxTerms: n / 8)
        #expect(fit?.terms.count == 2)
        #expect(fit?.terms.map(\.frequency) == [7, 10])
        #expect(abs((fit?.mean ?? 0) - 3) < 1e-9)
        if let fit {
            var worst = 0.0
            for k in 0 ..< n { worst = max(worst, abs(fit.value(at: Double(k), period: n) - sines[k])) }
            #expect(worst < 1e-9)
            // Between the samples the fit is the signal itself, not a straight line.
            let between = fit.value(at: 100.5, period: n)
            let w = 2 * Double.pi * 100.5 / Double(n)
            #expect(abs(between - (3 + 2 * sin(7 * w) + 0.5 * cos(10 * w))) < 1e-9)
        }
        // A ramp over the lap has a jump at the wrap, which no short fit crosses.
        let ramp = (0 ..< n).map { Double($0) / Double(n) }
        #expect(FourierFit.fit(ramp, tolerance: 1e-4, maxTerms: n / 8) == nil)
    }

    @Test func theTransformAgreesWithTheDirectSum() {
        for n in [60, 61, 64, 90, 1800 / 30] {
            var seed: UInt64 = 12345
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53) * 2 - 1
            }
            let re = (0 ..< n).map { _ in next() }
            let im = (0 ..< n).map { _ in next() }
            let fast = DiscreteFourier.transform(re: re, im: im)
            let plain = DiscreteFourier.direct(re: re, im: im)
            var worst = 0.0
            for k in 0 ..< n {
                worst = max(worst, abs(fast.re[k] - plain.re[k]), abs(fast.im[k] - plain.im[k]))
            }
            #expect(worst < 1e-9, "length \(n): \(worst)")
        }
    }

    @Test func aDrivenParameterCrossesAsItsFormula() throws {
        let recording = try OllinApp.recordWebFrames(of: Driven(), frames: 30, fps: 30)
        #expect(recording.formulas.count == 1)
        let formula = try #require(recording.formulas.first)
        #expect(formula.name == "radius")
        #expect(formula.source == "150 + sin(time * tau / 6) * 40")
        #expect(formula.javaScript.contains("Math.sin("))
        #expect(formula.javaScript.contains("v[\"time\"]"))
        #expect(formula.lowerBound == 0 && formula.upperBound == 300)
        #expect(recording.series.first?.count == 30)
        // The radius column (size.x and size.y) reads as radius times the
        // canvas scale, so both are wired to the formula and nothing samples.
        let track = WebTrack(recording)
        #expect(track.stable)
        #expect(track.drivenColumns == 2)
        #expect(track.sampledColumns == 0 && track.fittedColumns == 0)
        #expect(track.stream.isEmpty)
        let meta = try #require(try JSONSerialization.jsonObject(with: Data(track.meta.utf8)) as? [String: Any])
        let drives = try #require(meta["drive"] as? [[Double]])
        #expect(drives.count == 2)
        for (i, drive) in drives.enumerated() {
            #expect(drive[0] == Double(8 + i) && drive[1] == 0, "\(drive)")
            #expect(abs(drive[2] - 0.24) < 1e-5 && abs(drive[3]) < 1e-3, "\(drive)")
        }
        #expect(track.meta.contains("\"formulas\":[{"))
        #expect(track.meta.contains("\"hi\":300"))
        #expect(track.meta.contains("\"clock\":{"))
        // A sketch without formulas carries none.
        let plain = WebTrack(try OllinApp.recordWebFrames(of: Hello(), frames: 3, fps: 30))
        #expect(plain.drivenColumns == 0)
        #expect(plain.meta.contains("\"formulas\":[]"))
    }

    @Test func aStillCostsOneFrame() throws {
        let recording = try OllinApp.recordWebFrames(of: Still(), frames: 40, fps: 30)
        let track = WebTrack(recording)
        #expect(track.uniqueFrames == 1)
        #expect(track.stable)
        #expect(track.meta.contains("\"refs\":[0,0,0"))
        #expect(track.meta.contains("\"clear\":[") && !track.meta.contains("\"clears\""))
        #expect(track.meta.contains("\"tone\":0") && track.meta.contains("\"exposure\":1"))
        // Nothing moves, so nothing streams: the base holds the two shapes.
        #expect(track.stream.isEmpty)
        #expect(!track.base.isEmpty)
        #expect(track.meta.contains("\"varying\":[]"))
        #expect(track.meta.contains("\"count\":2"))
    }

    @Test func aStableCastStreamsOnlyWhatMoves() throws {
        let recording = try OllinApp.recordWebFrames(of: Hello(), frames: 30, fps: 30)
        let track = WebTrack(recording)
        #expect(track.stable)
        // Only the radius (size.x and size.y) changes from frame to frame.
        #expect(track.meta.contains("\"varying\":[8,9]"))
        #expect(track.meta.contains("\"stable\":true"))
        // Every frame is its own record, so the frame map is not written.
        #expect(!track.meta.contains("\"refs\""))
    }

    @Test func aChangingCastIsStoredWhole() throws {
        let recording = try OllinApp.recordWebFrames(of: Growing(), frames: 4, fps: 30)
        let track = WebTrack(recording)
        #expect(!track.stable)
        #expect(track.meta.contains("\"lengths\":[56,84,112,140]"))
        #expect(track.meta.contains("\"offsets\":[0,56,140,252]"))
        #expect(track.meta.contains("\"graphOf\":[0,1,2,3]"))
        #expect(track.base.isEmpty)
        // 14 instances of 28 fields, two bytes each, base64.
        #expect(track.stream.count == (14 * 28 * 2 + 2) / 3 * 4)
        #expect(track.meta.contains("\"ranges\":["))
    }

    @Test func aSampledColumnStaysWithinItsRange() throws {
        // Not a lap, so the breathing radius travels as 16-bit samples inside
        // its own range: both ends exact, the middle within half a step.
        let recording = try OllinApp.recordWebFrames(of: Hello(), frames: 30, fps: 30)
        let track = WebTrack(recording)
        #expect(track.sampledColumns == 2)
        let values = recording.frames.map { Double($0.instances[8]) }
        let lo = values.min()!, hi = values.max()!
        let meta = try #require(try JSONSerialization.jsonObject(with: Data(track.meta.utf8)) as? [String: Any])
        let ranges = try #require(meta["ranges"] as? [Double])
        #expect(ranges.count == 4)
        #expect(abs(ranges[0] - lo) < 1e-5 && abs(ranges[1] - hi) < 1e-5, "\(ranges)")
        let step = (hi - lo) / 65535
        for v in values {
            let q = WebTrack.quantize(Float(v), in: (Float(lo), Float(hi)))
            let back = lo + Double(q) * step
            #expect(abs(back - v) <= step / 2 + 1e-9)
        }
    }

    @Test func refusesWhatCannotCrossAndNamesTheCall() throws {
        func refusal(_ sketch: Sketch, frames: Int = 4) -> WebExportRefusal? {
            do {
                _ = try OllinApp.recordWebFrames(of: sketch, frames: frames, fps: 30)
                return nil
            } catch let refusal as WebExportRefusal {
                return refusal
            } catch {
                return nil
            }
        }
        let clipped = try #require(refusal(Clipped()))
        #expect(clipped.call == "withClip")
        #expect(clipped.frame == 1)
        #expect(clipped.description.contains("--export-video"))
        let graded = try #require(refusal(Graded()))
        #expect(graded.call == "a gradient fill or stroke")
        #expect(graded.frame == 0)
        // Outline text crosses as its fills; the glyph atlas does not yet.
        let written = try #require(refusal(Written()))
        #expect(written.call.contains("drawText"))
        #expect(written.call.contains("glyph atlas"))
        #expect(refusal(Hello()) == nil)
    }

    // MARK: The page

    @Test func theStandaloneWrapsTheInlineFragment() throws {
        let recording = try OllinApp.recordWebFrames(of: Hello(), frames: 3, fps: 30)
        let inline = try OllinApp.webPage(of: recording, form: .inline)
        let standalone = try OllinApp.webPage(of: recording, form: .standalone)
        #expect(inline.hasPrefix("<canvas class=\"ollin-sketch\" width=\"240\" height=\"240\""))
        #expect(inline.contains("aria-label=\"Hello, a sketch made with Ollin\""))
        #expect(inline.contains("<script>") && inline.hasSuffix("</script>"))
        #expect(!inline.contains("<html"))
        #expect(standalone.hasPrefix("<!DOCTYPE html>"))
        #expect(standalone.contains("<title>Hello</title>"))
        #expect(standalone.contains(inline))
        // The paper is the first frame's background.
        #expect(standalone.contains("background: #ffffff;"))
        // Nothing of the sketch's source is on the page.
        #expect(!standalone.contains("drawCircle"))
        #expect(!standalone.contains("override func draw"))
    }

    @Test func thePagesShadersAreTheFrameworksOwn() throws {
        let shaders = try WebShaders.make()
        #expect(shaders.sdfFragment.hasPrefix("#version 300 es\n"))
        #expect(shaders.sdfFragment.contains("void ollin_sdf_coverage(uint shape, uint align, vec2 p, vec2 size,"))
        #expect(shaders.sdfFragment.contains("float sdStar("))
        #expect(shaders.sdfFragment.contains("float perceptualCoverage(float c)"))
        #expect(!shaders.sdfFragment.contains("float2"))
        #expect(!shaders.sdfFragment.contains("thread "))
        #expect(shaders.presentFragment.contains("float ditherTriangle(vec2 fragCoord)"))
        #expect(shaders.presentFragment.contains("vec3 toneMapACES(vec3 x)"))
        #expect(shaders.presentFragment.contains("float hash12(vec2 p)"))
    }

    // MARK: The browser

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePagePlaysWhatTheMacDrew() async throws {
        let cases: [(name: String, make: () -> Sketch, frames: Int, fps: Double, probe: Int)] = [
            ("HelloCircle", { Hello() }, 12, 30, 0),
            ("HelloCircle", { Hello() }, 12, 30, 7),
            ("BreathingRing", { Ring() }, 60, 30, 0),
            ("BreathingRing", { Ring() }, 60, 30, 41),
            ("BreathingRing lap, fitted", { Ring() }, 600, 10, 41),
            ("Still", { Still() }, 2, 30, 1),
            ("Moving", { Moving() }, 20, 30, 12),
            ("Driven, live", { Driven() }, 30, 30, 17),
        ]
        for c in cases {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: c.fps)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await Self.pagePixels(page, frame: c.probe)
            let reference = try #require(OllinApp.image(of: c.make(), frame: c.probe, fps: c.fps))
            let difference = try Self.meanDifference(played, reference)
            // Printed on every run, so a drift shows before it crosses the line.
            print("web page against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference))")
            #expect(difference < Snapshot.tolerance, "\(c.name) frame \(c.probe): mean difference \(difference)")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theFormulaJavaScriptComputesWhatSwiftComputes() async throws {
        let sources = [
            "150 + sin(time * tau / 6) * 40",
            "mod(-1, 3) + fract(-0.25) + round(-2.5) + round(2.5) + trunc(-1.7)",
            "if(time > 1 && !(frame < 0), map(time, 0, 2, 10, 20), step(0.5, time))",
            "clamp(2^3^2 / 512, 0, 1) + smoothstep(0, 1, 0.3) + min(3, 1, 2) + max(1, 4)",
            "-2^2 + lerp(0, 10, 0.25) + hypot(3, 4) + saturate(1.5) + sign(-3) + degrees(pi) + radians(90)",
            "(time >= 1.5 || frame == 3) * 7 + (time != 1.5) + atan2(1, 2) + pow(2, 0.5) + log2(8) + e",
            "width / 2 + mouseX * 0.5 + abs(-3) + floor(2.7) + ceil(2.1) + sqrt(16) + exp(0) + log(1) + log10(100)",
        ]
        let names = ["time": 1.5, "frame": 3.0, "width": 240.0, "height": 240.0, "mouseX": 10.0, "mouseY": 20.0]
        var expected: [Double] = []
        var expressions: [String] = []
        for source in sources {
            let formula = try Formula(source)
            expected.append(formula.value(names))
            expressions.append(try #require(FormulaJS.compile(formula)))
        }
        let namesJSON = String(decoding: try JSONSerialization.data(withJSONObject: names, options: [.sortedKeys]), as: UTF8.self)
        let pushes = expressions.map { "out.push(" + $0 + ");" }.joined(separator: "\n  ")
        let page = """
        <!doctype html><html><body><pre id="r0">PENDING</pre>
        <script>
        \(FormulaJS.helpers)
        (function () {
          var v = \(namesJSON);
          var out = [];
          \(pushes)
          document.getElementById('r0').textContent = out.map(function (x) { return x.toPrecision(17); }).join(';');
        })();
        </script></body></html>
        """
        let dom = try await HeadlessBrowser.dom(of: page)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        let values = report.split(separator: ";").map { Double($0) ?? .nan }
        try #require(values.count == sources.count, "\(report.prefix(300))")
        for (i, source) in sources.enumerated() {
            #expect(abs(values[i] - expected[i]) <= 1e-9 * max(1, abs(expected[i])),
                    "\(source): the page says \(values[i]), Swift says \(expected[i])")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theTwoFormsDrawTheSamePixels() async throws {
        let recording = try OllinApp.recordWebFrames(of: Ring(), frames: 30, fps: 30)
        let inline = try await Self.pagePixels(try OllinApp.webPage(of: recording, form: .inline), frame: 17)
        let standalone = try await Self.pagePixels(try OllinApp.webPage(of: recording, form: .standalone), frame: 17)
        #expect(Self.rgba(of: inline) == Self.rgba(of: standalone))
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theGateSeesAWrongPicture() async throws {
        // A gate that cannot fail proves nothing: the page at one frame against
        // the Mac at another must read as different.
        let recording = try OllinApp.recordWebFrames(of: Moving(), frames: 20, fps: 30)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await Self.pagePixels(page, frame: 0)
        let elsewhere = try #require(OllinApp.image(of: Moving(), frame: 19, fps: 30))
        let difference = try Self.meanDifference(played, elsewhere)
        #expect(difference > Snapshot.tolerance, "mean difference \(difference)")
    }
}
