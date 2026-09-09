import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// A see-through canvas (`background(.clear)`) leaves the file see-through: a
/// still carries the frame's coverage as its alpha, premultiplied the way an
/// 8-bit image with alpha is read, and a clip through a codec that keeps an
/// alpha channel (ProRes 4444, HEVC with alpha) composites over whatever it is
/// laid on. An opaque canvas is untouched, tag and bytes.
@Suite
@MainActor
struct TransparentOutputTests {

    /// One disk on a canvas whose background the test picks.
    private final class Disk: Sketch {
        var ground: Color = .clear
        var ink: Color = Color(red: 1, green: 0, blue: 0)
        var map: ToneMap? = nil
        var blur: Double = 0
        override var canvasSize: CanvasSize { .square(128) }
        override func draw() {
            background(ground)
            if let map { toneMap(map) }
            if blur > 0 { postProcess(.gaussianBlur(radius: blur)) }
            noStroke()
            fill(ink)
            drawCircle(width / 2, height / 2, 40)
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
        return OllinApp.image(of: sketch)
    }

    // MARK: Stills

    @Test func aClearCanvasExportsItsCoverageAsAlpha() throws {
        let image = try #require(render(ground: .clear))
        #expect(image.alphaInfo == .premultipliedFirst)
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

    /// A half-covered pixel premultiplies the *encoded* color, the way a reader
    /// divides it back out: the red byte is the alpha byte, not the sRGB encode
    /// of half of linear red.
    @Test func halfCoverIsPremultipliedInTheEncodedDomain() throws {
        let image = try #require(render(ground: .clear, ink: Color(red: 1, green: 0, blue: 0, alpha: 0.5)))
        let center = stored(image, x: 64, y: 64)
        #expect(abs(center.a - 128) <= 1)
        #expect(abs(center.r - center.a) <= 1)
        // Divided back out, the color is the red that was drawn.
        #expect(center.r * 255 / center.a >= 250)
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
        // Premultiplied by the coverage in the encoded domain: the stored byte is
        // the opaque byte halved, within the dither and the rounding.
        #expect(abs(half.r * 2 - solid.r) <= 3, "stored \(half.r) against opaque \(solid.r)")
    }

    /// A background with any alpha under 1 counts; the rest of the color is the
    /// premultiplied ground the canvas composites over.
    @Test func aTranslucentGroundIsSeeThroughToo() throws {
        let image = try #require(render(ground: Color(red: 0, green: 0, blue: 1, alpha: 0.25)))
        #expect(image.alphaInfo == .premultipliedFirst)
        let corner = stored(image, x: 4, y: 4)
        #expect(abs(corner.a - 64) <= 1)
        #expect(abs(corner.b - 64) <= 1 && corner.r <= 1)
    }

    /// The PNG on disk reads back with the alpha intact.
    @Test func thePNGCarriesTheAlpha() throws {
        let path = NSTemporaryDirectory() + "ollin-transparent-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let sketch = Disk()
        OllinApp.export(sketch, to: path)
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let read = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try #require(FrameGrabTests.rgba(of: read))
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
        OllinApp.exportGIF(Disk(), to: path, frames: 2, fps: 10)
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let read = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try #require(FrameGrabTests.rgba(of: read))
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
        let image = try #require(OllinApp.image(of: sketch))
        #expect(image.alphaInfo == .premultipliedFirst)
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
        OllinApp.exportVideo(Disk(), to: path, frames: 3, fps: 30, codec: codec)
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
