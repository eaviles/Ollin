import Testing
import Foundation
import CoreGraphics
import ImageIO
import OllinWebGate
@testable import Ollin

/// The asset door of the web page: a picture drawn with `drawImage` travels
/// once as its file or a PNG of its pixels, text through the glyph atlas
/// travels as its quads over the font's page read at the end of the
/// recording, and a gradient on an analytic shape travels as its row of the
/// page's strip. The recorder is checked on its own (what an item holds, that
/// a picture drawn every frame is one asset, that an edit makes a second, that
/// a file crosses as its own bytes), then the page against the Mac in the
/// shared browser gate.
@Suite @MainActor struct WebAssetTests {

    // MARK: Fixtures

    /// A picture painted in memory: a checkered ramp with a translucent corner.
    static func paint() -> Image {
        let picture = Image(width: 96, height: 64, color: .white)
        for y in 0 ..< 64 {
            for x in 0 ..< 96 {
                let checker = (x / 8 + y / 8) % 2 == 0
                picture[x, y] = Color(red: Double(x) / 95, green: Double(y) / 63, blue: checker ? 0.9 : 0.2, alpha: 1)
            }
        }
        for y in 0 ..< 16 { for x in 0 ..< 16 { picture[x, y] = Color(red: 1, green: 0, blue: 0, alpha: 0.5) } }
        return picture
    }

    /// The picture drawn whole, at half size (a smaller level), tinted, under
    /// multiply, covering a box of another shape, and turning with the clock.
    final class Pictured: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        let picture = WebAssetTests.paint()
        override func draw() {
            background(Color(hex: 0xF0EEE8))
            drawImage(picture, 10, 10, 96, 64)
            drawImage(picture, 120, 10, 48, 32)
            tint(Color(red: 0.5, green: 1, blue: 0.5, alpha: 0.8))
            drawImage(picture, 10, 90, 96, 64)
            noTint()
            blendMode(.multiply)
            drawImage(picture, 120, 60, 96, 64)
            blendMode(.normal)
            drawImage(picture, in: Rectangle(x: 10, y: 170, width: 60, height: 60), fit: .cover)
            withState {
                translate(150, 190)
                rotate(time * 0.5)
                drawImage(picture, -48, -32, 96, 64)
            }
        }
    }

    /// Two images with the same pixels, one of them edited on the third frame.
    final class Repainted: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        let a = Image(width: 8, height: 8, color: .red)
        let b = Image(width: 8, height: 8, color: .red)
        override func draw() {
            background(.white)
            drawImage(a, 0, 0, 60, 60)
            drawImage(b, 60, 0, 60, 60)
            if frameCount == 3 { a[0, 0] = .blue }
        }
    }

    /// A picture loaded from a file (`Loaded.url`, set before the sketch is made).
    final class Loaded: Sketch {
        static var url: URL?
        let picture: Image
        required init() { picture = Image(contentsOf: Loaded.url!)!; super.init() }
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(.white)
            drawImage(picture, 20, 30, 120, 80)
        }
    }

    /// Text through the glyph atlas at three sizes, one moving, one under a
    /// gradient, one turned.
    final class AtlasText: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.white)
            textMode(.atlas)
            fill(.black)
            textSize(40)
            drawText("Atlas", 16, 60)
            textSize(18)
            fill(Color(hex: 0x2040A0))
            drawText("body text on the page", 16, 100 + sin(time) * 4)
            fill(Gradient.linear(from: Vector2(16, 0), to: Vector2(220, 0), [.red, .blue]))
            textSize(32)
            drawText("gradient", 16, 160)
            withState {
                translate(120, 200)
                rotate(0.3)
                fill(.black)
                textSize(24)
                drawText("turned", -50, 0)
            }
        }
    }

    /// Gradients on analytic shapes: a linear fill, a radial fill, a stroke
    /// along the path, a linear stroke, and a ramp that moves with the clock.
    final class Graded: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.white)
            noStroke()
            fill(Gradient.linear(from: Vector2(10, 10), to: Vector2(110, 110), [.red, .blue]))
            drawRect(10, 10, 100, 100)
            fill(Gradient.radial(center: Vector2(170, 60), radius: 50, [.yellow, .black]))
            drawCircle(170, 60, 50)
            noFill()
            strokeWeight(10)
            stroke(Gradient.alongPath([.red, .green, .blue]))
            drawCircle(60, 170, 40)
            strokeWeight(6)
            stroke(Gradient.linear(from: Vector2(120, 130), to: Vector2(220, 230), [.black, .white]))
            drawRect(120, 130, 100, 100)
            noStroke()
            fill(Gradient.linear(from: Vector2(0, 0), to: Vector2(40, 0), [Color(hex: 0x208040), .white]))
            drawCircle(200 + sin(time) * 10, 200, 20)
        }
    }

    /// Atlas text and a picture inside a recording, replayed turning.
    final class Batched: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        let picture = WebAssetTests.paint()
        var batch: Batch?
        override func setup() {
            batch = makeBatch {
                textMode(.atlas)
                fill(.black)
                textSize(28)
                drawText("Ollin", -40, -10)
                drawImage(picture, -48, 0, 96, 64)
                noStroke()
                fill(Color(hex: 0xC03060))
                drawCircle(60, -40, 10)
            }
        }
        override func draw() {
            background(.white)
            guard let batch else { return }
            withState {
                translate(100, 100)
                rotate(Double(frameCount) * 0.15)
                drawBatch(batch)
            }
        }
    }

    /// The paper alone, for the sabotage.
    final class Paper: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() { background(Color(hex: 0xF0EEE8)) }
    }

    /// Writes `image` to `path` as a PNG.
    static func dump(_ image: CGImage, to path: String) {
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// Writes `image` to a temporary file as `type` (`public.png`,
    /// `public.jpeg`) and returns the URL.
    static func write(_ image: Image, as type: String, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ollin-web-asset-\(UUID().uuidString)-\(name)")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image.currentCGImage(), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    // MARK: The recorder

    @Test func aPictureCrossesOnceHoweverOftenItIsDrawn() throws {
        let sketch = Pictured()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 4, fps: 30)
        // One asset, a PNG of the painted pixels.
        #expect(recording.pictures.count == 1)
        let picture = try #require(recording.pictures.first)
        #expect(picture.mime == "image/png" && picture.width == 96 && picture.height == 64)
        #expect(WebAssetEncoder.browserFormat(of: picture.data) == "image/png")
        // Six draws, each its own quad sampling picture 0, the multiply one
        // under its blend, in call order.
        let g = recording.frames[0].graph
        #expect(g.quadCount == 6 && g.instanceCount == 0 && g.vertexCount == 0)
        var blends: [Int] = []
        for (i, item) in g.canvas.enumerated() {
            guard case let .image(source, quad, count, blend) = item else { Issue.record("\(item)"); continue }
            #expect(source == .picture(0) && quad == i && count == 1)
            blends.append(blend)
        }
        #expect(blends == [0, 0, 0, WebBlend.index(of: .multiply), 0, 0])
        // A quad on the wire is the drawer's six vertices, position, uv, and tint.
        let v = sketch.drawer.imageVertices[0]
        let onWire = Array(recording.frames[3].vector[g.quadOffset ..< g.quadOffset + 8])
        #expect(onWire == [v.position.x, v.position.y, v.uv.x, v.uv.y, v.tint.x, v.tint.y, v.tint.z, v.tint.w])
        // The tinted quad carries its tint; the turning one moves the frames.
        #expect(recording.frames[0].vector[g.quadOffset + 2 * WebQuad.floats + 4] == 0.5)
        #expect(recording.frames[0].vector != recording.frames[3].vector)
        #expect(recording.frames[0].graph == recording.frames[3].graph)
        #expect(WebTrack(recording).stable)
    }

    @Test func anEditedPictureIsASecondAssetAndEqualPixelsAreOne() throws {
        let recording = try OllinApp.recordWebFrames(of: Repainted(), frames: 5, fps: 30)
        // Two images with the same pixels are one asset; the edit on the third
        // frame makes a second, and the graph changes with it.
        #expect(recording.pictures.count == 2)
        func sources(_ k: Int) -> [WebImageSource] {
            recording.frames[k].graph.canvas.compactMap { if case let .image(s, _, _, _) = $0 { return s } else { return nil } }
        }
        #expect(sources(0) == [.picture(0), .picture(0)])
        #expect(sources(1) == [.picture(0), .picture(0)])
        #expect(sources(2) == [.picture(1), .picture(0)])
        #expect(sources(4) == [.picture(1), .picture(0)])
        #expect(recording.frames[0].graph != recording.frames[2].graph)
        #expect(!WebTrack(recording).stable)
    }

    @Test func aLoadedFileTravelsAsItsOwnBytes() throws {
        let painted = Self.paint()
        for (type, mime) in [("public.png", "image/png"), ("public.jpeg", "image/jpeg")] {
            let url = try Self.write(painted, as: type, name: mime.replacingOccurrences(of: "/", with: "."))
            defer { try? FileManager.default.removeItem(at: url) }
            Loaded.url = url
            let recording = try OllinApp.recordWebFrames(of: Loaded(), frames: 2, fps: 30)
            let picture = try #require(recording.pictures.first)
            #expect(picture.mime == mime)
            #expect(picture.data == (try Data(contentsOf: url)))
            #expect(picture.width == 96 && picture.height == 64)
        }
        // A file in a format a browser does not open crosses as a PNG of its pixels.
        let tiff = try Self.write(painted, as: "public.tiff", name: "tiff")
        defer { try? FileManager.default.removeItem(at: tiff) }
        Loaded.url = tiff
        let recording = try OllinApp.recordWebFrames(of: Loaded(), frames: 1, fps: 30)
        #expect(recording.pictures.first?.mime == "image/png")
        #expect(WebAssetEncoder.browserFormat(of: try Data(contentsOf: tiff)) == nil)
    }

    @Test func atlasTextCrossesAsGlyphQuadsOverThePage() throws {
        let sketch = AtlasText()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 3, fps: 30)
        // One atlas, a gray PNG of the rows the glyphs were packed into, at the
        // top of a page-sized texture.
        #expect(recording.atlases.count == 1)
        let atlas = try #require(recording.atlases.first)
        #expect(atlas.size == GlyphAtlas.webPageSize)
        #expect(atlas.rows > 0 && atlas.rows <= atlas.size)
        #expect(WebAssetEncoder.browserFormat(of: atlas.png) == "image/png")
        let source = try #require(CGImageSourceCreateWithData(atlas.png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == atlas.size && decoded.height == atlas.rows)
        #expect(decoded.bitsPerPixel == 8)
        // Four runs of glyph quads, one per drawText, in call order, sampling
        // atlas 0; the quads together are the drawer's glyph vertices.
        let g = recording.frames[2].graph
        var counts: [Int] = []
        for item in g.canvas {
            guard case let .glyphs(atlasIndex, _, count, blend) = item else { Issue.record("\(item)"); continue }
            #expect(atlasIndex == 0 && blend == 0)
            counts.append(count)
        }
        #expect(counts.count == 4)
        #expect(counts.reduce(0, +) == sketch.drawer.glyphVertices.count / WebQuad.vertices)
        #expect(counts[0] == 5)   // "Atlas"
        #expect(g.quadCount == counts.reduce(0, +))
        // Every glyph's uv lies inside the rows the page carries.
        let uvMaxV = stride(from: g.quadOffset, to: g.vertexOffset, by: 8).map { recording.frames[2].vector[$0 + 3] }.max() ?? 0
        #expect(uvMaxV <= Float(atlas.rows) / Float(atlas.size) + 1e-6, "\(uvMaxV) against \(atlas.rows) rows")
        // The moving line moves the frames; the cast is stable.
        #expect(recording.frames[0].vector != recording.frames[2].vector)
        #expect(WebTrack(recording).stable)
    }

    @Test func aGradientOnAShapeCrossesWithItsRow() throws {
        let recording = try OllinApp.recordWebFrames(of: Graded(), frames: 3, fps: 30)
        // Five ramps, each baked once into the recording's strip.
        #expect(recording.gradientRows.count == 5)
        #expect(recording.gradientRows.allSatisfy { $0.count == BakedGradient.width * 4 })
        let frame = recording.frames[0]
        #expect(frame.graph.instanceCount == 5)
        let n = WebInstance.floats
        func instance(_ i: Int) -> [Float] { Array(frame.vector[i * n ..< (i + 1) * n]) }
        // The rect's fill is linear (kind 1) on row 0; the circle's radial
        // (kind 2) on row 1; the ring's stroke along the path (kind 3) on row
        // 2; the second rect's stroke linear on row 3; the moving disc on row 4.
        func fillKind(_ i: Int) -> Int { (Int(instance(i)[WebInstance.shapeColumn]) >> 10) & 3 }
        func strokeKind(_ i: Int) -> Int { (Int(instance(i)[WebInstance.shapeColumn]) >> 12) & 3 }
        #expect(fillKind(0) == 1 && instance(0)[28] == 0)
        #expect(fillKind(1) == 2 && instance(1)[28] == 1)
        #expect(strokeKind(2) == 3 && instance(2)[29] == 2)
        #expect(strokeKind(3) == 1 && instance(3)[29] == 3)
        #expect(fillKind(4) == 1 && instance(4)[28] == 4)
        // A row a frame did not bake reads 0 on the wire.
        #expect(instance(0)[29] == 0 && instance(2)[28] == 0)
        // The rows are the same table on every frame, whatever order the frame
        // baked them in.
        for f in recording.frames { #expect(Array(f.vector[28 ..< 30]) == [0, 0]) }
        #expect(WebTrack(recording).stable)
    }

    @Test func aRecordingOfTextAndAPictureReplaysUnderItsTransform() throws {
        let sketch = Batched()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 2, fps: 30)
        let batch = try #require(sketch.batch)
        let frame = recording.frames[1]
        let g = frame.graph
        // The runs in the recording's order: the glyphs, the picture, the circle.
        var order: [String] = []
        for item in g.canvas {
            switch item {
            case .glyphs: order.append("glyphs")
            case .image(.picture(0), _, 1, _): order.append("picture")
            case .shapes: order.append("shape")
            default: order.append("?")
            }
        }
        #expect(order == ["glyphs", "picture", "shape"])
        #expect(g.quadCount == batch.glyphVertices.count / 6 + 1)
        #expect(recording.pictures.count == 1 && recording.atlases.count == 1)
        // A recorded glyph vertex lands where the draw-time transform puts it.
        let angle = Float(2 * 0.15)
        let v = batch.glyphVertices[0].position
        let expected = SIMD2<Float>(100 + v.x * cos(angle) - v.y * sin(angle), 100 + v.x * sin(angle) + v.y * cos(angle))
        let qo = g.quadOffset
        #expect(abs(frame.vector[qo] - expected.x) < 1e-3 && abs(frame.vector[qo + 1] - expected.y) < 1e-3,
                "\(frame.vector[qo]), \(frame.vector[qo + 1]) against \(expected)")
    }

    @Test func thePageCarriesTheAssetsAndTheStrip() throws {
        let recording = try OllinApp.recordWebFrames(of: Graded(), frames: 2, fps: 30)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        #expect(page.contains("var STRIP = [5, \(BakedGradient.width), \""))
        #expect(page.contains("var PICTURES = []"))
        #expect(page.contains("var ATLASES = []"))
        #expect(page.contains("uniform sampler2D gradients;"))
        #expect(page.contains("layout(location = 9) in vec2 aRows;"))
        let pictured = try OllinApp.recordWebFrames(of: Pictured(), frames: 1, fps: 30)
        let picturePage = try OllinApp.webPage(of: pictured, form: .inline)
        #expect(picturePage.contains("var PICTURES = [[\"image/png\", \""))
        #expect(picturePage.contains("img.src = 'data:' + mime"))
        let written = try OllinApp.recordWebFrames(of: AtlasText(), frames: 1, fps: 30)
        let textPage = try OllinApp.webPage(of: written, form: .inline)
        #expect(textPage.contains("var ATLASES = [[\""))
        #expect(textPage.contains(", \(GlyphAtlas.webPageSize), \(written.atlases[0].rows)]]"))
        let shaders = try WebShaders.make()
        #expect(shaders.glyphFragment.contains("float perceptualCoverage(float c)"))
        #expect(shaders.glyphFragment.contains("float aa = fwidth(d);"))
        #expect(shaders.sdfFragment.contains("vec4 resolvePaint(vec4 slot, uint kind, float row, vec2 p, float pathT)"))
    }

    // MARK: The browser

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePageDrawsThePicturesTextAndGradientsTheMacDrew() async throws {
        let png = try Self.write(Self.paint(), as: "public.png", name: "png")
        let jpeg = try Self.write(Self.paint(), as: "public.jpeg", name: "jpeg")
        defer { try? FileManager.default.removeItem(at: png); try? FileManager.default.removeItem(at: jpeg) }
        let cases: [(name: String, make: () -> Sketch, frames: Int, probe: Int)] = [
            ("Pictured (a painted picture whole, small, tinted, multiplied, covering, turning)", { Pictured() }, 6, 0),
            ("Pictured, turning", { Pictured() }, 6, 4),
            ("Repainted (an edited picture, two assets)", { Repainted() }, 5, 3),
            ("Loaded (a PNG file as its own bytes)", { Loaded.url = png; return Loaded() }, 1, 0),
            ("Loaded (a JPEG file as its own bytes)", { Loaded.url = jpeg; return Loaded() }, 1, 0),
            ("AtlasText (three sizes, a gradient fill, a turned line)", { AtlasText() }, 6, 0),
            ("AtlasText, moving", { AtlasText() }, 6, 4),
            ("Graded (linear, radial, along the path, a gradient stroke, a moving ramp)", { Graded() }, 6, 3),
            ("Batched (text and a picture in a recording, turning)", { Batched() }, 4, 2),
        ]
        for (k, c) in cases.enumerated() {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: 30)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await WebExportTests.pagePixels(page, frame: c.probe)
            let reference = try #require(OllinApp.image(of: c.make(), frame: c.probe, fps: 30))
            if let dump = ProcessInfo.processInfo.environment["OLLIN_WEB_DUMP"] {
                // The two pictures on disk, for a look at a difference.
                Self.dump(played, to: "\(dump)/case\(k)-page.png")
                Self.dump(reference, to: "\(dump)/case\(k)-mac.png")
                try page.write(toFile: "\(dump)/case\(k).html", atomically: true, encoding: .utf8)
            }
            let difference = try WebExportTests.meanDifference(played, reference)
            let far = WebTriangleTests.farFraction(played, reference)
            print("web page against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
            #expect(difference < Snapshot.tolerance, "\(c.name) frame \(c.probe): mean difference \(difference)")
            // A JPEG is decoded by the browser, and two decoders disagree by a
            // few levels along a sharp chroma edge (the checker's cells), which
            // the far count reads and the mean does not; the file crosses as it
            // is, since a photo re-encoded as PNG would weigh several times more.
            if !c.name.contains("JPEG") {
                #expect(far < WebTriangleTests.farTolerance, "\(c.name) frame \(c.probe): \(far * 100)% of the pixels past 32 levels")
            }
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theGateSeesAMissingPicture() async throws {
        // The page with the pictures against the Mac's paper alone must read as
        // different, or the parity above proves nothing.
        let recording = try OllinApp.recordWebFrames(of: Pictured(), frames: 1, fps: 30)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 0)
        let paper = try #require(OllinApp.image(of: Paper(), frame: 0, fps: 30))
        let difference = try WebExportTests.meanDifference(played, paper)
        #expect(difference > Snapshot.tolerance, "mean difference \(difference)")
        #expect(WebTriangleTests.farFraction(played, paper) > WebTriangleTests.farTolerance)
    }
}
