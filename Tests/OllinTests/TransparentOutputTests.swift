import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// A see-through canvas (`background(.clear)`) leaves the file see-through: a
/// still carries the frame's coverage as its alpha beside the color as drawn,
/// the form a PNG stores, and a clip through a codec that keeps an alpha
/// channel (ProRes 4444, HEVC with alpha) composites over whatever it is laid
/// on. An opaque canvas is untouched, tag and bytes.
@Suite
@MainActor
struct TransparentOutputTests {

    /// One disk on a canvas whose background the test picks.
    private final class Disk: Sketch {
        var ground: Color = .clear
        var ink: Color = Color(red: 1, green: 0, blue: 0)
        var map: ToneMap? = nil
        var exposure: Double = 1
        var blur: Double = 0
        /// Moves the disk sideways, so its edge can fall across a pixel.
        var shift: Double = 0
        override var canvasSize: CanvasSize { .square(128) }
        override func draw() {
            background(ground)
            if map != nil || exposure != 1 { toneMap(map ?? .clamp, exposure: exposure) }
            if blur > 0 { postProcess(.gaussianBlur(radius: blur)) }
            noStroke()
            fill(ink)
            drawCircle(width / 2 + shift, height / 2, 40)
        }
    }

    /// Bytes as stored, BGRA, without going through Core Graphics (which would
    /// resolve the alpha away).
    private func storedBytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data as Data? else { return [] }
        return Array(data)
    }

    /// The stored BGRA at a pixel of a still.
    private func stored(_ image: CGImage, x: Int, y: Int) -> (b: Int, g: Int, r: Int, a: Int) {
        let bytes = storedBytes(image)
        let i = (y * image.bytesPerRow) + x * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
    }

    private func render(ground: Color, ink: Color = Color(red: 1, green: 0, blue: 0),
                       map: ToneMap? = nil) -> CGImage? {
        let sketch = Disk()
        sketch.ground = ground
        sketch.ink = ink
        sketch.map = map
        return try? OllinApp.image(of: sketch)
    }

    // MARK: Stills

    @Test func aClearCanvasExportsItsCoverageAsAlpha() throws {
        let image = try #require(render(ground: .clear))
        #expect(image.alphaInfo == .first)
        let corner = stored(image, x: 4, y: 4)
        #expect(corner.a == 0)
        #expect(corner.r == 0 && corner.g == 0 && corner.b == 0)
        let center = stored(image, x: 64, y: 64)
        #expect(center.a == 255)
        #expect(center.r >= 254 && center.g <= 1 && center.b <= 1)
    }

    @Test func anOpaqueCanvasKeepsItsTagAndBytes() throws {
        let image = try #require(render(ground: .white))
        #expect(image.alphaInfo == .noneSkipFirst)
        let corner = stored(image, x: 4, y: 4)
        #expect(corner.r == 255 && corner.g == 255 && corner.b == 255)
    }

    /// A half-covered pixel stores the color that was drawn beside its
    /// coverage: the red byte is full red, not the sRGB encode of half of
    /// linear red, and not the coverage's share of it.
    @Test func halfCoverStoresTheColorAsDrawn() throws {
        let image = try #require(render(ground: .clear, ink: Color(red: 1, green: 0, blue: 0, alpha: 0.5)))
        let center = stored(image, x: 64, y: 64)
        #expect(abs(center.a - 128) <= 1)
        #expect(center.r >= 254 && center.g <= 1 && center.b <= 1, "stored \(center)")
    }

    /// The tone map sees the straight color, so a half-covered mid gray maps to
    /// the same gray an opaque one does, at half the alpha.
    @Test func theToneMapSeesTheStraightColor() throws {
        let gray = Color(white: 0.5)
        let opaque = try #require(render(ground: .black, ink: gray, map: .reinhard))
        let seeThrough = try #require(render(ground: .clear, ink: Color(white: 0.5, alpha: 0.5), map: .reinhard))
        let solid = stored(opaque, x: 64, y: 64)
        let half = stored(seeThrough, x: 64, y: 64)
        #expect(abs(half.a - 128) <= 1)
        // Stored straight: the byte is the opaque byte, within the dither.
        #expect(abs(half.r - solid.r) <= 2, "stored \(half.r) against opaque \(solid.r)")
    }

    /// A background with any alpha under 1 counts; the rest of the color is the
    /// ground the canvas composites over, stored as it was drawn.
    @Test func aTranslucentGroundIsSeeThroughToo() throws {
        let image = try #require(render(ground: Color(red: 0, green: 0, blue: 1, alpha: 0.25)))
        #expect(image.alphaInfo == .first)
        let corner = stored(image, x: 4, y: 4)
        #expect(abs(corner.a - 64) <= 1)
        #expect(corner.b >= 254 && corner.r <= 1, "stored \(corner)")
    }

    /// Lights added over a canvas whose background the test picks: ten faint
    /// white discs piled on one spot, six orange ones beside and across them.
    private final class Lights: Sketch {
        var ground: Color = .clear
        var map: ToneMap = .clamp
        override var canvasSize: CanvasSize { .square(128) }
        override func draw() {
            background(ground)
            toneMap(map)
            noStroke()
            blendMode(.add)
            fill(Color(white: 1, alpha: 0.1))
            for _ in 0 ..< 10 { drawCircle(48, 64, 30) }
            fill(Color(red: 1, green: 0.4, blue: 0.1, alpha: 0.25))
            for _ in 0 ..< 6 { drawCircle(84, 64, 30) }
        }
    }

    /// A see-through frame laid over black is the picture the window shows.
    /// Marks added over a clear canvas pile up more light than coverage (ten
    /// whites at a tenth are full white at 65% cover), and a stored color
    /// cannot pass white, so the file's alpha rises to hold the light. It
    /// rises before the tone curve, so wherever the light fills the pixel the
    /// curve sees what the window's curve sees; under the plain clamp the two
    /// agree along a soft edge as well.
    @Test(arguments: [ToneMap.clamp, .reinhard, .aces, .neutral])
    func addedLightOverBlackIsTheWindowsPicture(map: ToneMap) throws {
        let clear = Lights(), black = Lights()
        clear.map = map
        black.map = map
        black.ground = .black
        let seeThrough = try OllinApp.image(of: clear), window = try OllinApp.image(of: black)
        #expect(seeThrough.alphaInfo == .first)
        // Inside the white pile, where the piles cross, inside the orange one,
        // near each pile's rim, and bare canvas; then, under the clamp, the
        // white pile's own anti-aliased edge.
        var places = [(40, 64), (66, 64), (92, 64), (48, 38), (104, 80), (4, 4)]
        if map == .clamp { places += [(48, 34), (18, 64), (114, 64)] }
        for (x, y) in places {
            let s = stored(seeThrough, x: x, y: y), w = stored(window, x: x, y: y)
            func over(_ byte: Int) -> Double {
                Color.linearToSrgb(Color.srgbToLinear(Double(byte) / 255) * Double(s.a) / 255) * 255
            }
            let shown = (r: over(s.r), g: over(s.g), b: over(s.b))
            #expect(abs(shown.r - Double(w.r)) <= 2 && abs(shown.g - Double(w.g)) <= 2 && abs(shown.b - Double(w.b)) <= 2,
                    "\(map) at (\(x), \(y)): the file stores \(s), which over black shows \(shown) where the window shows \(w)")
        }
        // The pile's middle is not left see-through: its light fills the pixel
        // (ten half-float sums of a tenth land a hair under 1).
        let middle = stored(seeThrough, x: 40, y: 64).a
        #expect(middle >= 252 && stored(seeThrough, x: 4, y: 4).a == 0, "\(map): the pile's middle stores an alpha of \(middle)")
    }

    /// The row through a disk's middle, from inside it to bare canvas across
    /// its anti-aliased edge. The disk is 40 in radius about x 64 and is moved
    /// half a pixel, so the pixel at x 104 is about half covered.
    private static let edgeRow = Array(98 ... 110)

    private func disk(ground: Color, ink: Color, exposure: Double = 1) throws -> CGImage {
        let sketch = Disk()
        sketch.ground = ground
        sketch.ink = ink
        sketch.exposure = exposure
        sketch.shift = 0.5
        return try OllinApp.image(of: sketch)
    }

    /// A stored pixel laid over an opaque backdrop byte, in linear light.
    private func laid(_ byte: Int, alpha: Int, over backdrop: Int) -> Double {
        let a = Double(alpha) / 255
        return Color.linearToSrgb(Color.srgbToLinear(Double(byte) / 255) * a
            + Color.srgbToLinear(Double(backdrop) / 255) * (1 - a)) * 255
    }

    /// The raise is not only for added light: any pixel holding more light
    /// than its coverage can show takes it, so the soft edge of a shape
    /// brighter than white, or of an ordinary shape under an exposure above 1,
    /// stores more alpha than it covers. Over black that is the window's
    /// picture, pixel for pixel along the edge. Over another backdrop the edge
    /// shows less of the backdrop than the window drawing over that backdrop
    /// does, never more: a stored color has four numbers and cannot hold a
    /// light and a coverage both.
    @Test(arguments: [0, 1])
    func aBrightEdgeOverBlackIsTheWindowsPicture(exposed: Int) throws {
        let ink = exposed == 1 ? Color(red: 0.9, green: 0.6, blue: 0.2) : Color(linear: 3.0, green: 1.2, blue: 0.3)
        let exposure = exposed == 1 ? 2.0 : 1.0
        let file = try disk(ground: .clear, ink: ink, exposure: exposure)
        let overBlack = try disk(ground: .black, ink: ink, exposure: exposure)
        let gray = Color(white: 0.5)
        let overGray = try disk(ground: gray, ink: ink, exposure: exposure)
        let plain = try disk(ground: .clear, ink: Color(red: 0.9, green: 0.6, blue: 0.2))
        var raised = 0, shortfall = 0.0
        for x in Self.edgeRow {
            let s = stored(file, x: x, y: 64), b = stored(overBlack, x: x, y: 64), g = stored(overGray, x: x, y: 64)
            for (channel, stored, black, grayed) in [("red", s.r, b.r, g.r), ("green", s.g, b.g, g.g), ("blue", s.b, b.b, g.b)] {
                let shown = laid(stored, alpha: s.a, over: 0)
                #expect(abs(shown - Double(black)) <= 2,
                        "x \(x), \(channel): the file \(s) shows \(shown) over black where the window shows \(black)")
                // The backdrop byte under the window's gray ground is its own corner.
                let backdrop = self.stored(overGray, x: 4, y: 4).r
                let onGray = laid(stored, alpha: s.a, over: backdrop)
                #expect(onGray <= Double(grayed) + 2,
                        "x \(x), \(channel): the file over gray shows \(onGray), brighter than the window's \(grayed)")
                shortfall = max(shortfall, Double(grayed) - onGray)
            }
            if s.a > stored(plain, x: x, y: 64).a + 1 { raised += 1 }
        }
        // The edge is where the alpha is raised: at least one pixel of the row
        // stores more than an ordinary color's coverage there.
        #expect(raised >= 1, "no pixel of the edge stores more alpha than its coverage")
        // Measured 2026-11-10 at the half-covered pixel: 11 levels for a color
        // three times white, 42 for an ordinary color under an exposure of 2.
        #expect(shortfall <= 48, "over mid gray the edge falls \(shortfall) levels short of the window")
        print("transparent edge, \(exposed == 1 ? "an exposure of 2" : "a color three times white"): over mid gray the file falls short of the window by at most \(String(format: "%.1f", shortfall)) levels along the edge")
    }

    /// A color within its coverage is never touched: an ordinary shape's edge
    /// stores the same alpha whatever its color.
    @Test func anOrdinaryEdgeKeepsItsCoverage() throws {
        let bright = try disk(ground: .clear, ink: Color(red: 1, green: 1, blue: 1))
        let dim = try disk(ground: .clear, ink: Color(white: 0.3))
        var partial = 0
        for x in Self.edgeRow {
            let a = stored(bright, x: x, y: 64).a, b = stored(dim, x: x, y: 64).a
            #expect(abs(a - b) <= 1, "x \(x): white stores an alpha of \(a), a dark gray \(b)")
            if a > 8, a < 247 { partial += 1 }
        }
        #expect(partial >= 1, "the row crosses no partly covered pixel")
    }

    /// The PNG on disk reads back with the alpha intact.
    @Test func thePNGCarriesTheAlpha() throws {
        let path = NSTemporaryDirectory() + "ollin-transparent-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let sketch = Disk()
        try OllinApp.export(sketch, to: path)
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let read = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = pixels(of: read)
        let at = { (x: Int, y: Int) -> (r: Int, a: Int) in
            let i = (y * read.width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 3]))
        }
        #expect(at(4, 4).a == 0)
        #expect(at(64, 64).a == 255 && at(64, 64).r >= 250)
    }

    /// A GIF holds one transparent index, so the see-through ground survives
    /// as a hard cut: fully clear where nothing was drawn, opaque on the disk.
    @Test func theGIFKeepsAHardTransparency() throws {
        let path = NSTemporaryDirectory() + "ollin-transparent-\(UUID().uuidString).gif"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try OllinApp.exportGIF(Disk(), to: path, frames: 2, fps: 10)
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let read = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = pixels(of: read)
        let alpha = { (x: Int, y: Int) -> Int in Int(bytes[(y * read.width + x) * 4 + 3]) }
        #expect(alpha(4, 4) == 0)
        #expect(alpha(64, 64) == 255)
    }

    /// A frame filter runs before the present, on the premultiplied frame, so
    /// a blur spreads the coverage with the color: the disk's edge fades in
    /// alpha and the far corner stays clear.
    @Test func aBlurredFrameKeepsItsCoverage() throws {
        let sketch = Disk()
        sketch.blur = 6
        let image = try OllinApp.image(of: sketch)
        #expect(image.alphaInfo == .first)
        #expect(stored(image, x: 4, y: 4).a == 0)
        #expect(stored(image, x: 64, y: 64).a == 255)
        let edge = stored(image, x: 64 + 40, y: 64)
        #expect(edge.a > 20 && edge.a < 235, "edge alpha \(edge.a)")
    }

    // MARK: Clips

    /// The first frame of a clip, as BGRA bytes and its row stride.
    private func firstFrame(of path: String) throws -> (bytes: [UInt8], bytesPerRow: Int, width: Int) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let reader = try AVAssetReader(asset: asset)
        let track = try #require(reader.asset.tracks(withMediaType: .video).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        reader.startReading()
        let sample = try #require(output.copyNextSampleBuffer())
        let pixels = try #require(CMSampleBufferGetImageBuffer(sample))
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        let base = try #require(CVPixelBufferGetBaseAddress(pixels))
        let count = stride * CVPixelBufferGetHeight(pixels)
        return (Array(UnsafeRawBufferPointer(start: base, count: count)), stride, CVPixelBufferGetWidth(pixels))
    }

    private func clip(codec: VideoCodec, ext: String) throws -> (corner: (r: Int, a: Int), center: (r: Int, a: Int)) {
        let path = NSTemporaryDirectory() + "ollin-transparent-\(UUID().uuidString).\(ext)"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try OllinApp.exportVideo(Disk(), to: path, frames: 3, fps: 30, codec: codec)
        let frame = try firstFrame(of: path)
        let at = { (x: Int, y: Int) -> (r: Int, a: Int) in
            let i = y * frame.bytesPerRow + x * 4
            return (Int(frame.bytes[i + 2]), Int(frame.bytes[i + 3]))
        }
        return (at(4, 4), at(64, 64))
    }

    @Test func proRes4444KeepsTheAlpha() throws {
        let read = try clip(codec: .proRes4444, ext: "mov")
        #expect(read.corner.a <= 2)
        #expect(read.center.a >= 253 && read.center.r >= 240)
    }

    @Test func hevcWithAlphaKeepsTheAlpha() throws {
        let read = try clip(codec: .hevcWithAlpha, ext: "mov")
        #expect(read.corner.a <= 2)
        #expect(read.center.a >= 253 && read.center.r >= 230)
    }

    /// A codec with no alpha channel shows the canvas over black, as the window
    /// does, and never over the last frame a pooled buffer held.
    @Test func aCodecWithoutAlphaCompositesOverBlack() throws {
        let read = try clip(codec: .h264, ext: "mp4")
        #expect(read.corner.a == 255 && read.corner.r <= 8)
        #expect(read.center.r >= 230)
    }

    @Test func theCodecFlagSpellsIt() {
        #expect(VideoCodec(flag: "hevcwithalpha") == .hevcWithAlpha)
        #expect(VideoCodec.hevcWithAlpha.carriesAlpha && VideoCodec.proRes4444.carriesAlpha)
        #expect(!VideoCodec.h264.carriesAlpha && !VideoCodec.hevc.carriesAlpha && !VideoCodec.proRes422.carriesAlpha)
        #expect(!VideoCodec.hevcWithAlpha.requiresQuickTime)
    }
}
