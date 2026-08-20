import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// Probes for the export supersample (`--render-scale`, `OllinApp.exportRenderScale`).
/// Three things must hold, and each has its own counterfactual: the exported
/// picture keeps its canvas size at every scale; a hard tessellated edge moves
/// *toward* the converged answer as the scale goes up (a sharper edge alone
/// proves nothing, a closer one does); and the picture-side chain still measures
/// in canvas pixels, so a blur the sketch asked for keeps its width.
@Suite
@MainActor
struct RenderScaleTests {

    // MARK: Pixel support

    private func pixels(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    private func ink(_ p: (data: [UInt8], w: Int, h: Int), _ x: Int, _ y: Int) -> Int {
        Int(p.data[(y * p.w + x) * 4])
    }

    /// Render one frame of `sketch` at `scale`, leaving the dial where it was.
    private func frame(_ make: () -> Sketch, scale: Int) throws -> (data: [UInt8], w: Int, h: Int) {
        let previous = OllinApp.exportRenderScale
        defer { OllinApp.exportRenderScale = previous }
        OllinApp.exportRenderScale = scale
        return pixels(try #require(OllinApp.image(of: make())))
    }

    /// The mean difference between two frames over the whole canvas, in bytes.
    private func meanDifference(_ a: (data: [UInt8], w: Int, h: Int),
                                _ b: (data: [UInt8], w: Int, h: Int)) -> Double {
        var total = 0
        for y in 0..<a.h {
            for x in 0..<a.w { total += abs(ink(a, x, y) - ink(b, x, y)) }
        }
        return Double(total) / Double(a.w * a.h)
    }

    // MARK: The claims

    /// The dial is a sampling rate, not a size: the exported picture is the
    /// canvas at every scale. (A frame that came back at 2x here would mean the
    /// resolve never ran and every downstream size claim is off.)
    @Test(.enabled(if: Snapshot.hasMetal))
    func theExportKeepsItsCanvasSize() throws {
        for scale in [1, 2, 4] {
            let f = try frame({ RSEdgeProbe() }, scale: scale)
            #expect(f.w == 256 && f.h == 256, "scale \(scale) exported \(f.w)x\(f.h)")
        }
    }

    /// A hard tessellated edge converges: measured against the 4x render, the 2x
    /// frame sits closer than the 1x one. This is the whole point of the dial,
    /// and it is the claim a "looks sharper" eye test cannot make.
    @Test(.enabled(if: Snapshot.hasMetal))
    func moreSamplesMoveTheEdgeTowardTheConvergedAnswer() throws {
        let one = try frame({ RSEdgeProbe() }, scale: 1)
        let two = try frame({ RSEdgeProbe() }, scale: 2)
        let four = try frame({ RSEdgeProbe() }, scale: 4)
        let coarse = meanDifference(one, four)
        let fine = meanDifference(two, four)
        #expect(coarse > 0.05, "1x and 4x must actually disagree somewhere: \(coarse)")
        #expect(fine < coarse * 0.7,
                "2x must sit closer to 4x than 1x does: 2x-4x \(fine), 1x-4x \(coarse)")
    }

    /// The counterfactual for the split: everything that treats the frame as a
    /// picture runs at canvas size, so a blur keeps the width the sketch asked
    /// for. Move the resolve behind the frame filters and this reads red: the
    /// blur would cover half as much of a 2x frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBlurKeepsItsWidthUnderTheDial() throws {
        let one = try frame({ RSBlurProbe() }, scale: 1)
        let two = try frame({ RSBlurProbe() }, scale: 2)
        // The band's edge sits at x = 128; walk out from it and find where the
        // blur has fallen to about half. A blur measured in render pixels would
        // halve that distance at 2x.
        func halfWidth(_ p: (data: [UInt8], w: Int, h: Int)) -> Int {
            let peak = ink(p, 100, 128)
            for x in 128..<220 where ink(p, x, 128) < peak / 2 { return x - 128 }
            return 0
        }
        let a = halfWidth(one), b = halfWidth(two)
        #expect(a > 4, "the probe must actually be blurred: \(a) px")
        #expect(abs(a - b) <= 2, "the blur must keep its width: \(a) px at 1x, \(b) px at 2x")
    }

    /// Asking for more than the renderer takes renders anyway, at the ceiling,
    /// rather than failing or silently producing something else.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anImpossibleAskIsClampedRatherThanRefused() throws {
        let capped = try frame({ RSEdgeProbe() }, scale: 64)
        let ceiling = try frame({ RSEdgeProbe() }, scale: MetalRenderer.maxRenderScale)
        #expect(capped.w == 256)
        #expect(meanDifference(capped, ceiling) < 0.01,
                "an over-large ask must render at the ceiling")
    }
}

/// A rotated square filled through the tessellated triangle path: four straight
/// edges at an angle no pixel grid likes, which is exactly what the supersample
/// is for. Nothing here is analytic, so the SDF path's own coverage cannot mask
/// the measurement.
private final class RSEdgeProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        noStroke()
        fill(.white)
        let center = Vector2(128, 128)
        let angle = 0.35, radius = 90.0
        let corners = (0..<4).map { k -> Vector2 in
            let a = angle + Double(k) * .pi / 2
            return center + Vector2(cos(a), sin(a)) * radius
        }
        drawShape(Shape(corners))
    }
}

/// A hard-edged band under a whole-frame blur: the profile out from its edge is
/// the width the sketch asked for, measured in canvas pixels.
private final class RSBlurProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        noStroke()
        fill(.white)
        drawRect(0, 0, 128, 256)
        postProcess(.gaussianBlur(radius: 12))
    }
}
