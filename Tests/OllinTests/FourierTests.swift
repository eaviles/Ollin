import CoreGraphics
import Foundation
import Ollin
import Testing

/// Probes for the GPU Fourier transform: `Filter.fourier`, `.inverseFourier`, and
/// the `.spectrum` view over them.
///
/// The transform is arithmetic, so these check arithmetic rather than looks: a
/// round trip has to hand the picture back, a single wave has to land at the one
/// place in the spectrum that wave belongs, and a flat field has to put all of
/// its energy in the middle. Metal-gated.
@Suite
@MainActor
struct FourierTests {

    // MARK: The round trip

    /// The headline claim. A transform followed by its opposite is the picture
    /// that went in. The probe draws a gray pattern (so the layer's luminance is
    /// the pattern itself) and compares the round trip against it pixel for
    /// pixel; float32 through 16 butterfly rungs leaves it inside one 8-bit
    /// level.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRoundTripReturnsThePicture() throws {
        let plain = try #require(OllinApp.image(of: PatternProbe.make(.none), frame: 1))
        let back = try #require(OllinApp.image(of: PatternProbe.make(.roundTrip), frame: 1))
        #expect(maxDifference(plain, back) <= 2,
                "the round trip strayed by \(maxDifference(plain, back)) levels")
    }

    /// A layer the ladder cannot climb comes back untouched rather than empty: a
    /// side that is not a power of two has no radix-2 ladder, and a sketch that
    /// asks for one gets its picture and a note, not a black rectangle.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerThatIsNotAPowerOfTwoComesBackUntouched() throws {
        let plain = try #require(OllinApp.image(of: OddSizeProbe.make(.none), frame: 1))
        let back = try #require(OllinApp.image(of: OddSizeProbe.make(.roundTrip), frame: 1))
        #expect(maxDifference(plain, back) == 0)
    }

    // MARK: Where a wave lands

    /// One wave, one place. A grating of eight cycles across the layer puts its
    /// energy at eight steps either side of the middle, and nowhere else. This is
    /// the test that pins the frequency mapping *and* the centering: get either
    /// wrong and the peaks move.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aGratingLandsAtItsOwnFrequency() throws {
        let image = try #require(OllinApp.image(of: PatternProbe.make(.spectrum, cycles: 8),
                                                frame: 1))
        let px = pixels(of: image)
        let center = px.width / 2
        let peaks = brightestOffCenter(px, count: 2, center: center)
        for peak in peaks {
            #expect(peak.y == center, "a horizontal grating should stay on the middle row, got y = \(peak.y)")
            #expect(abs(abs(peak.x - center) - 8) <= 1,
                    "the peak sits \(abs(peak.x - center)) steps from the middle, not 8")
        }
        #expect(peaks.count == 2 && peaks[0].x != peaks[1].x,
                "a real wave shows twice, once each side of the middle")
    }

    /// The same wave turned a quarter lands on the other axis, which is what says
    /// the column ladder runs as well as the row one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTurnedGratingLandsOnTheOtherAxis() throws {
        let image = try #require(OllinApp.image(
            of: PatternProbe.make(.spectrum, cycles: 8, vertical: true), frame: 1))
        let px = pixels(of: image)
        let center = px.width / 2
        for peak in brightestOffCenter(px, count: 2, center: center) {
            #expect(peak.x == center, "a vertical grating should stay on the middle column, got x = \(peak.x)")
            #expect(abs(abs(peak.y - center) - 8) <= 1,
                    "the peak sits \(abs(peak.y - center)) steps from the middle, not 8")
        }
    }

    /// A field with nothing in it but one value is one wave of no frequency at
    /// all, so the whole of it lands in the middle and the rest of the spectrum
    /// is empty.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatFieldIsOneSpotInTheMiddle() throws {
        let image = try #require(OllinApp.image(of: PatternProbe.make(.spectrum, cycles: 0),
                                                frame: 1))
        let px = pixels(of: image)
        let center = px.width / 2
        let middle = gray(px, x: center, y: center)
        #expect(middle > 200, "the flat part of the picture should light the middle (\(middle))")
        var worst = 0
        for y in stride(from: 4, to: px.height - 4, by: 7) {
            for x in stride(from: 4, to: px.width - 4, by: 7) {
                if abs(x - center) < 3 && abs(y - center) < 3 { continue }
                worst = max(worst, gray(px, x: x, y: y))
            }
        }
        #expect(worst < 20, "a flat field should leave the rest of the spectrum dark (\(worst))")
    }

    // MARK: Helpers

    private func pixels(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }

    private func gray(_ px: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int) -> Int {
        Int(px.bytes[(y * px.width + x) * 4 + 1])
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }

    /// The `count` brightest pixels that are not the middle one, each from its own
    /// neighborhood, so one broad peak is reported once rather than nine times.
    private func brightestOffCenter(_ px: (bytes: [UInt8], width: Int, height: Int),
                                    count: Int, center: Int) -> [(x: Int, y: Int, v: Int)] {
        var found: [(x: Int, y: Int, v: Int)] = []
        for y in 0 ..< px.height {
            for x in 0 ..< px.width {
                if abs(x - center) < 3 && abs(y - center) < 3 { continue }
                found.append((x, y, gray(px, x: x, y: y)))
            }
        }
        found.sort { $0.v > $1.v }
        var picked: [(x: Int, y: Int, v: Int)] = []
        for spot in found {
            if picked.contains(where: { abs($0.x - spot.x) < 4 && abs($0.y - spot.y) < 4 }) { continue }
            picked.append(spot)
            if picked.count == count { break }
        }
        return picked
    }
}

/// What the probe should show: the pattern itself, the pattern taken through the
/// transform and back, or the spectrum of it.
private enum FourierView { case none, roundTrip, spectrum }

/// A gray pattern on a square power-of-two canvas. Gray on purpose: the transform
/// reads the layer's luminance, and a gray layer's luminance is the layer, so a
/// round trip can be compared against the original pixel for pixel.
private final class PatternProbe: Sketch {
    var view: FourierView = .none
    var cycles = 8.0
    var vertical = false

    static func make(_ view: FourierView, cycles: Double = 8, vertical: Bool = false) -> PatternProbe {
        let s = PatternProbe()
        s.view = view; s.cycles = cycles; s.vertical = vertical
        return s
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        let axis = vertical ? "uv.y" : "uv.x"
        let layer = generate(Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float v = 0.5 + 0.35 * cos(6.28318530718 * \(cycles) * \(axis));
            return float4(v, v, v, 1.0);
        }
        """))
        switch view {
        case .none:
            drawImage(layer.image, 0, 0)
        case .roundTrip:
            drawImage(layer.filtered(.fourier()).filtered(.inverseFourier()).image, 0, 0)
        case .spectrum:
            drawImage(layer.filtered(.fourier()).filtered(.spectrum()).image, 0, 0)
        }
    }
}

/// The same pattern on a canvas the ladder cannot climb.
private final class OddSizeProbe: Sketch {
    var view: FourierView = .none

    static func make(_ view: FourierView) -> OddSizeProbe {
        let s = OddSizeProbe()
        s.view = view
        return s
    }

    override var canvasSize: CanvasSize { .square(300) }

    override func draw() {
        let layer = generate(Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float v = 0.5 + 0.35 * cos(6.28318530718 * 8.0 * uv.x);
            return float4(v, v, v, 1.0);
        }
        """))
        switch view {
        case .roundTrip:
            drawImage(layer.filtered(.fourier()).filtered(.inverseFourier()).image, 0, 0)
        default:
            drawImage(layer.image, 0, 0)
        }
    }
}
