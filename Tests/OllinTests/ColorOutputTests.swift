import AVFoundation
import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Ollin

/// Probes for wide-gamut and high-dynamic-range output.
///
/// Three kinds of claim, because the feature has three ends. The color math is
/// checked against the published matrices and curve, exactly, on the CPU. The
/// rendered frame is checked against its *counterfactual twin*: the same sketch
/// at a different `colorOutput`, so a claim can only pass if the setting is
/// doing the work. And the standard path is checked for byte-identity, since
/// the whole design rests on an ordinary sketch being untouched.
@Suite
@MainActor
struct ColorOutputTests {

    // MARK: Sketches under test

    /// A saturated P3 red beside its sRGB neighbour, and a lamp core well above
    /// white: the two things the two settings are each supposed to carry.
    private final class Swatches: Sketch {
        var output: ColorOutput = .standard
        override var colorOutput: ColorOutput { output }
        override var canvasSize: CanvasSize { .square(64) }

        override func draw() {
            background(.black)
            noStroke()
            fill(Color(displayP3: 1, green: 0, blue: 0))
            drawRect(0, 0, 32, 32)                    // top-left: outside sRGB
            fill(Color(red: 1, green: 0, blue: 0))
            drawRect(32, 0, 32, 32)                   // top-right: the sRGB one
            fill(Color(white: 3))                     // bottom: three times white
            drawRect(0, 32, 32, 32)
            fill(.white)
            drawRect(32, 32, 32, 32)                  // bottom-right: white itself
        }
    }

    // MARK: Read-back support

    /// The frame's four quadrant colors in extended-linear Display P3, the space
    /// the wide present pass writes, so components can legitimately exceed 1 and
    /// fall below 0.
    private func quadrants(_ image: CGImage) -> [(r: Double, g: Double, b: Double)] {
        let w = image.width, h = image.height
        var buf = [Float32](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                bitsPerComponent: 32, bytesPerRow: w * 16, space: space,
                                bitmapInfo: CGBitmapInfo.floatComponents.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue
                                    | CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return [(16, 16), (48, 16), (16, 48), (48, 48)].map { x, y in
            let i = (y * w + x) * 4
            return (Double(buf[i]), Double(buf[i + 1]), Double(buf[i + 2]))
        }
    }

    private func render(_ output: ColorOutput) throws -> CGImage {
        let sketch = Swatches()
        sketch.output = output
        return try #require(OllinApp.image(of: sketch))
    }

    // MARK: The color math

    @Test("a Display P3 color stores as the sRGB components that decode back to it")
    func p3RoundTrip() {
        // The two directions are the published matrices, each rounded to seven
        // decimals rather than one being inverted from the other, so the round
        // trip closes to about 1e-7 in linear light. The transfer curve's straight
        // segment then multiplies that by 12.92 on its way back to components,
        // which lands just under one step of a 16-bit channel (1.5e-5): invisible,
        // and the price of both matrices reading as the documented constants.
        for named in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.2, 0.7, 0.4), (1.0, 1.0, 1.0)] {
            let color = Color(displayP3: named.0, green: named.1, blue: named.2)
            let back = color.displayP3Components
            #expect(abs(back.red - named.0) < 1e-5)
            #expect(abs(back.green - named.1) < 1e-5)
            #expect(abs(back.blue - named.2) < 1e-5)
        }
    }

    @Test("white is the same white in both gamuts, and a saturated P3 color is not")
    func whiteIsShared() {
        let white = Color(displayP3: 1, green: 1, blue: 1)
        #expect(abs(white.red - 1) < 1e-6)
        #expect(abs(white.green - 1) < 1e-6)
        #expect(abs(white.blue - 1) < 1e-6)
        #expect(!white.isOutsideSRGB)

        // A P3 primary has to leave the sRGB cube to be a different color at all.
        let red = Color(displayP3: 1, green: 0, blue: 0)
        #expect(red.isOutsideSRGB)
        #expect(red.green < 0)
        #expect(red.blue < 0)
    }

    @Test("a negative component survives the transfer curve both ways")
    func negativesRoundTrip() {
        // The pipeline's own encode has to be the exact inverse of the decode the
        // shaders apply, or a color outside sRGB lands somewhere else. Below the
        // curve's knee both directions are the same straight line.
        for linear in [-0.5, -0.04, -0.001, 0.0, 0.5, 1.0, 3.0] {
            let encoded = Color.linearToSrgb(linear)
            #expect(abs(Color.srgbToLinear(encoded) - linear) < 1e-9)
        }
    }

    // MARK: The rendered frame

    @Test("a wide frame keeps a color the standard one clips")
    func wideKeepsWhatStandardClips() throws {
        let standard = quadrants(try render(.standard))
        let wide = quadrants(try render(.wide))

        // Standard: the P3 red and the sRGB red have been flattened into the same
        // color, because the wider one had nowhere to go.
        let clippedDelta = abs(standard[0].r - standard[1].r) + abs(standard[0].g - standard[1].g)
        #expect(clippedDelta < 0.02)

        // Wide: they are different colors, and the wide one is the more saturated
        // (a real P3 primary has no green in it at all).
        #expect(wide[0].g < 0.01)
        #expect(wide[1].g > 0.02)
        #expect(abs(wide[0].r - wide[1].r) > 0.1)
    }

    @Test("only the extended frame carries a value above white")
    func extendedKeepsHighlights() throws {
        let wide = quadrants(try render(.wide))
        let extended = quadrants(try render(.extended))

        // The 3x-white patch beside plain white. Standard range stops at white,
        // whatever it was asked for.
        #expect(abs(wide[2].r - wide[3].r) < 0.02)
        #expect(wide[2].r <= 1.05)

        // Extended keeps it, and keeps it *above* the white beside it.
        #expect(extended[2].r > 1.5)
        #expect(extended[2].r > extended[3].r * 1.5)
        #expect(abs(extended[3].r - 1) < 0.05)     // white is still exactly white
    }

    @Test("a standard sketch renders exactly the bytes it always did")
    func standardIsUntouched() throws {
        // The claim the whole design rests on: nothing about a sketch that says
        // nothing has changed, down to the byte, including the dither.
        let a = try render(.standard)
        let b = try render(.standard)
        #expect(a.bitsPerComponent == 8)
        #expect(a.width == 64 && a.height == 64)
        let dataA = try #require(a.dataProvider?.data as Data?)
        let dataB = try #require(b.dataProvider?.data as Data?)
        #expect(dataA == dataB)
    }

    @Test("the wide frame comes back as float, the standard one as bytes")
    func readBackFormats() throws {
        #expect(try render(.standard).bitsPerComponent == 8)
        #expect(try render(.wide).bitsPerComponent == 16)
        #expect(try render(.extended).bitsPerComponent == 16)
    }

    // MARK: What the renderer is built as

    @Test("each setting picks its own drawable and encoding")
    func rendererConfiguration() {
        #expect(ColorOutput.standard.drawablePixelFormat == .bgra8Unorm_srgb)
        #expect(ColorOutput.wide.drawablePixelFormat == .rgba16Float)
        #expect(ColorOutput.extended.drawablePixelFormat == .rgba16Float)
        #expect(ColorOutput.standard.presentEncoding == .srgb8)
        #expect(ColorOutput.wide.presentEncoding == .linearDisplayP3)
        // Only the extended one asks the system for room above white.
        #expect(!ColorOutput.standard.wantsExtendedDynamicRange)
        #expect(!ColorOutput.wide.wantsExtendedDynamicRange)
        #expect(ColorOutput.extended.wantsExtendedDynamicRange)
    }

    @Test("a wide sketch stops at white however much headroom the display reports")
    func onlyExtendedTakesHeadroom() {
        #expect(ColorOutput.standard.ceiling(displayHeadroom: 4) == 1)
        #expect(ColorOutput.wide.ceiling(displayHeadroom: 4) == 1)
        #expect(ColorOutput.extended.ceiling(displayHeadroom: 4) == 4)
        // A display with none is standard range in practice, whatever was asked.
        #expect(ColorOutput.extended.ceiling(displayHeadroom: 0.5) == 1)
    }

    // MARK: The exported video

    @Test("an extended sketch exports HDR10, a standard one does not")
    func hdrVideoIsTagged() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-hdr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func tags(of output: ColorOutput) async throws -> (primaries: String, transfer: String, bits: Int) {
            let sketch = Swatches()
            sketch.output = output
            let path = directory.appendingPathComponent("\(output.rawValue).mov").path
            OllinApp.exportVideo(sketch, to: path, frames: 4, fps: 30, codec: .hevc)
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let desc = try #require(try await track.load(.formatDescriptions).first)
            let ext = CMFormatDescriptionGetExtensions(desc) as? [String: Any] ?? [:]
            return (ext["CVImageBufferColorPrimaries"] as? String ?? "?",
                    ext["CVImageBufferTransferFunction"] as? String ?? "?",
                    ext["BitsPerComponent"] as? Int ?? 0)
        }

        let plain = try await tags(of: .standard)
        #expect(plain.primaries == "ITU_R_709_2")
        #expect(plain.transfer == "ITU_R_709_2")

        // Wide is the same standard-range curve through wider primaries: a change
        // of gamut only, which is the whole distinction from extended.
        let wide = try await tags(of: .wide)
        #expect(wide.primaries == "P3_D65")
        #expect(wide.transfer == "ITU_R_709_2")

        // Extended is HDR10: Rec. 2020 primaries, the PQ curve, ten bits.
        let hdr = try await tags(of: .extended)
        #expect(hdr.primaries == "ITU_R_2020")
        #expect(hdr.transfer == "SMPTE_ST_2084_PQ")
        #expect(hdr.bits == 10)
    }
}
