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

    final class Lined: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            drawCircle(60, 60, 20)
            if frameCount == 2 { drawLine(0, 0, 120, 120) }   // the second recorded frame
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
    }

    @Test func aStillCostsOneFrame() throws {
        let recording = try OllinApp.recordWebFrames(of: Still(), frames: 40, fps: 30)
        let track = WebTrack(recording)
        #expect(track.uniqueFrames == 1)
        #expect(track.stable)
        #expect(track.meta.contains("\"refs\":[0,0,0"))
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
    }

    @Test func aChangingCastIsStoredWhole() throws {
        let recording = try OllinApp.recordWebFrames(of: Growing(), frames: 4, fps: 30)
        let track = WebTrack(recording)
        #expect(!track.stable)
        #expect(track.meta.contains("\"counts\":[2,3,4,5]"))
        #expect(track.meta.contains("\"offsets\":[0,56,140,252]"))
        #expect(track.base.isEmpty)
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
        let lined = try #require(refusal(Lined()))
        #expect(lined.call.contains("drawLine"))
        #expect(lined.frame == 1)
        #expect(lined.description.contains("--export-video"))
        let graded = try #require(refusal(Graded()))
        #expect(graded.call == "a gradient fill or stroke")
        #expect(graded.frame == 0)
        // Outline text fills through the triangle path, so that is what it names.
        let written = try #require(refusal(Written()))
        #expect(written.call.contains("drawText"))
        #expect(written.call.contains("triangle path"))
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
        let cases: [(name: String, make: () -> Sketch, frames: Int, probe: Int)] = [
            ("HelloCircle", { Hello() }, 12, 0),
            ("HelloCircle", { Hello() }, 12, 7),
            ("BreathingRing", { Ring() }, 60, 0),
            ("BreathingRing", { Ring() }, 60, 41),
            ("Still", { Still() }, 2, 1),
            ("Moving", { Moving() }, 20, 12),
        ]
        for c in cases {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: 30)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await Self.pagePixels(page, frame: c.probe)
            let reference = try #require(OllinApp.image(of: c.make(), frame: c.probe, fps: 30))
            let difference = try Self.meanDifference(played, reference)
            // Printed on every run, so a drift shows before it crosses the line.
            print("web page against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference))")
            #expect(difference < Snapshot.tolerance, "\(c.name) frame \(c.probe): mean difference \(difference)")
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
