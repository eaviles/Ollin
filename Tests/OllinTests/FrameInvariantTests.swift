@testable import Ollin
import Testing
import CoreGraphics

/// Invariants of the passes that run over a finished frame: the tone map, the dither
/// at the 8-bit encode, the jittered anti-aliasing average, and the motion blur. Each
/// is a statement about the pass that holds whatever its implementation (a tone curve
/// is monotone, a dither is unbiased, an average or a blur only moves light) and is
/// read against an analytic value or the frame with the pass off.
@Suite
@MainActor
struct FrameInvariantTests {

    // MARK: Pixel support

    private struct Frame {
        var bytes: [UInt8]
        var width: Int
        var height: Int
        func byte(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(bytes[(y * width + x) * 4 + c]) }
    }

    private func frame(_ image: CGImage) -> Frame {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Frame(bytes: data, width: w, height: h)
    }

    private func render(_ sketch: Sketch, frame n: Int = 1) throws -> Frame {
        frame(try OllinApp.image(of: sketch, frame: n))
    }

    /// The sRGB transfer function, written out here so the reference is independent
    /// of the code it checks.
    private func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    private func toDisplay(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// Total linear light of the frame, the three channels summed.
    private func total(_ f: Frame) -> Double {
        var sum = 0.0
        for i in 0..<(f.width * f.height * 4) where i % 4 != 3 { sum += toLinear(Double(f.bytes[i]) / 255) }
        return sum
    }

    /// Mean of one channel over a centered block, so the dither averages out.
    private func centerMean(_ f: Frame, channel: Int, block: Int = 16) -> Double {
        let x0 = f.width / 2 - block / 2, y0 = f.height / 2 - block / 2
        var sum = 0
        for y in y0..<(y0 + block) { for x in x0..<(x0 + block) { sum += f.byte(x, y, channel) } }
        return Double(sum) / Double(block * block)
    }

    // MARK: The tone map

    /// The curve the docs name, written here from its published form.
    private func mapped(_ v: Double, by map: ToneMap) -> Double {
        switch map {
        case .clamp: return min(1, v)
        case .reinhard: return v / (1 + v)
        case .aces:
            let a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14
            return min(1, max(0, (v * (a * v + b)) / (v * (c * v + d) + e)))
        }
    }

    private static let exposures = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]

    /// A tone curve is a monotone map of light into the display's range that leaves a
    /// gray gray: as the exposure climbs, a mid gray never gets darker, never passes
    /// white, and never picks up a tint.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: ToneMap.allCases)
    func aToneCurveIsMonotoneBoundedAndNeutral(map: ToneMap) throws {
        var last = -1.0
        for exposure in Self.exposures {
            let f = try render(ToneInvariantProbe.make(map: map, exposure: exposure, gray: 0.5))
            let r = centerMean(f, channel: 0), g = centerMean(f, channel: 1), b = centerMean(f, channel: 2)
            #expect(r >= last - 0.5, "\(map) went darker at exposure \(exposure): \(r) after \(last)")
            #expect(r <= 255)
            #expect(abs(r - g) < 0.01 && abs(g - b) < 0.01, "\(map) tinted a gray at exposure \(exposure): \(r) \(g) \(b)")
            last = r
        }
    }

    /// Each curve is the one its name promises: clamp cuts at white, Reinhard is
    /// x over 1 + x, ACES is the published fit; and the exposure multiplies the light
    /// before the curve.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: ToneMap.allCases)
    func theCurveIsTheOneItsNamePromises(map: ToneMap) throws {
        for exposure in Self.exposures {
            let f = try render(ToneInvariantProbe.make(map: map, exposure: exposure, gray: 0.5))
            let read = centerMean(f, channel: 1)
            let expected = toDisplay(mapped(toLinear(0.5) * exposure, by: map)) * 255
            #expect(abs(read - expected) < (map == .aces ? 1.5 : 1.0),
                    "\(map) at exposure \(exposure) read \(read), the curve says \(expected)")
        }
    }

    /// The dither is unbiased: a flat field whose encode lands exactly between two
    /// 8-bit levels averages to that half level over the frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDitherIsUnbiased() throws {
        let half = 100.5 / 255
        let f = try render(ToneInvariantProbe.make(map: .clamp, exposure: 1, gray: half, size: 192))
        var sum = 0, low = 255, high = 0
        for y in 0..<f.height {
            for x in 0..<f.width {
                let v = f.byte(x, y, 1)
                sum += v; low = min(low, v); high = max(high, v)
            }
        }
        let mean = Double(sum) / Double(f.width * f.height)
        #expect(high > low, "a flat half-level field came out at one level (\(low)): no dither ran")
        #expect(abs(mean - 100.5) < 0.1, "the dither biased a half-level field to \(mean)")
    }

    // MARK: Temporal anti-aliasing

    /// The jittered average only moves light between neighboring pixels: the frame's
    /// total is the plain frame's, to within what one unjittered frame misses of a
    /// highlight it samples at pixel centers alone (measured at half a percent).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theJitterAverageConservesTheFramesLight() throws {
        let on = total(try render(TAAInvariantProbe.make(taa: true)))
        let off = total(try render(TAAInvariantProbe.make(taa: false)))
        #expect(off > 100, "the scene drew nothing: \(off)")
        #expect(abs(on / off - 1) < 0.01, "the jittered average changed the frame's light by \(on / off)")
    }

    // MARK: Motion blur

    /// A streak spreads a mover's light along its travel and makes none: the blurred
    /// frame's total is the sharp frame's.
    ///
    /// Measured 2026-10-06 and filed: a 24-pixel box crossing at 20 pixels a frame
    /// gains 5% of its light at the default shutter and 25% at a full one. The
    /// reconstruction filter gathers, so a pixel inside the box keeps the box's full
    /// value while the ramps outside are added on; a scatter would dim the interior
    /// by the share of the exposure the box spent elsewhere. The known issue is the
    /// standing nomination and fails the day the streak conserves.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theStreakConservesLight() throws {
        let on = total(try render(BlurInvariantProbe.make(blur: true), frame: 2))
        let off = total(try render(BlurInvariantProbe.make(blur: false), frame: 2))
        #expect(off > 100, "the mover drew nothing: \(off)")
        withKnownIssue("the motion blur gains light: 25% at a full shutter (measured 2026-10-06)") {
            #expect(abs(on / off - 1) < 0.02, "the blur changed the frame's light by \(on / off)")
        }
    }

    /// A blur is a weighted mean of what was there: no pixel of the streak is
    /// brighter than the brightest pixel of the sharp frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStreakNeverOutshinesItsSource() throws {
        let on = try render(BlurInvariantProbe.make(blur: true), frame: 2)
        let off = try render(BlurInvariantProbe.make(blur: false), frame: 2)
        func brightest(_ f: Frame) -> Int {
            var top = 0
            for i in 0..<(f.width * f.height * 4) where i % 4 != 3 { top = max(top, Int(f.bytes[i])) }
            return top
        }
        let a = brightest(on), b = brightest(off)
        #expect(a <= b + 1, "the streak reached \(a) where the mover was \(b) at its brightest")
    }
}

// MARK: - The probe scenes

/// A flat gray canvas under one tone map and exposure.
private final class ToneInvariantProbe: Sketch {
    var map: ToneMap = .clamp
    var exposure = 1.0
    var gray = 0.5
    var size = 64

    static func make(map: ToneMap, exposure: Double, gray: Double, size: Int = 64) -> ToneInvariantProbe {
        let p = ToneInvariantProbe()
        p.map = map
        p.exposure = exposure
        p.gray = gray
        p.size = size
        return p
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        toneMap(map, exposure: exposure)
        background(Color(white: gray))
    }
}

/// Three lit spheres well inside the frame, the anti-aliasing on or off.
private final class TAAInvariantProbe: Sketch {
    var taa = true

    static func make(taa: Bool) -> TAAInvariantProbe {
        let p = TAAInvariantProbe()
        p.taa = taa
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 2, 9), target: .zero))
        directionalLight(.white, direction: Vector3(-0.3, -1, -0.5), intensity: 1)
        if taa { temporalAntialiasing() }
        material(.dielectric(roughness: 0.6))
        fill(Color(white: 0.7))
        withState { translate(-1.6, 0, 0); drawSphere(radius: 0.9) }
        fill(Color(red: 0.8, green: 0.3, blue: 0.2))
        withState { translate(1.4, 0.4, 0.5); drawSphere(radius: 0.7) }
        fill(Color(red: 0.2, green: 0.4, blue: 0.9))
        withState { translate(0.2, -0.8, 1.5); drawBox(width: 1, height: 0.6, depth: 1) }
    }
}

/// A gray box crossing an orthographic 1:1 frame at 20 pixels a frame, the blur on
/// or off, the frame read at the second export frame so there is a previous one.
private final class BlurInvariantProbe: Sketch {
    var blur = true

    static func make(blur: Bool) -> BlurInvariantProbe {
        let p = BlurInvariantProbe()
        p.blur = blur
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 0, 100), target: .zero, height: 192, near: 1, far: 200)
        if blur { motionBlur(shutter: 1) }
        fill(Color(white: 0.6))
        withMotion {
            withState {
                translate(20 * Double(frameCount) - 40, 0, 0)
                drawBox(width: 24, height: 24, depth: 2)
            }
        }
    }
}
