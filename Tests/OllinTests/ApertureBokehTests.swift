import CoreGraphics
import Ollin
import Testing

/// Probes for the shape an out-of-focus highlight takes: the opening the light came
/// through, rather than a circle. A blurred step edge is what these read, because the
/// blur of a step edge runs exactly as far as the opening reaches that way, so the
/// ramp's width measures the opening along one line without any of the dilution a
/// single bright dot would suffer. Metal-gated.
@Suite
@MainActor
struct ApertureBokehTests {

    /// A round opening reaches the same distance every way, so the ramp across a
    /// vertical edge is as wide as `maxBlur`.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRoundOpeningReachesTheSameDistanceEveryWay() throws {
        let round = try rampWidth(EdgeProbe.make(blades: 0))
        #expect(abs(round - 60) <= 8)
    }

    /// Six blades put a flat side across the direction of the edge, so the blur reaches
    /// less far that way than a round opening does. Turning the iris by half a blade
    /// brings a corner around instead, and the blur reaches further than round.
    @Test(.enabled(if: Snapshot.hasMetal))
    func bladesReachFurtherAtACornerThanAlongAFlatSide() throws {
        let round = try rampWidth(EdgeProbe.make(blades: 0))
        let flat = try rampWidth(EdgeProbe.make(blades: 6))
        let corner = try rampWidth(EdgeProbe.make(blades: 6, irisAngle: .pi / 6))
        #expect(flat < round)
        #expect(corner > round)
        // A hexagon of the same area as the round opening: 0.952 across a flat side,
        // 1.0996 at a corner.
        #expect(abs(flat / round - 0.952) <= 0.09)
        #expect(abs(corner / round - 1.0996) <= 0.09)
    }

    /// Away from the middle of the frame the barrel clips the opening along the line to
    /// the middle, and hardly at all across it. So a highlight out near the right edge
    /// reaches much less far sideways than it does up and down: the lemon lying the long
    /// way around the frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBarrelLaysAHighlightDownTowardTheCorner() throws {
        let acrossTheRadius = try rampWidth(EdgeProbe.make(catsEye: 1, edgeAt: 560), y: 300)
        let alongTheRadius = try rampWidth(EdgeProbe.make(catsEye: 1, horizontal: true),
                                           column: 560)
        #expect(acrossTheRadius < alongTheRadius * 0.7)
    }

    /// With no clipping asked for, the same two readings agree: the shape stays round
    /// wherever it sits in the frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutClippingAHighlightStaysRoundAnywhereInTheFrame() throws {
        let acrossTheRadius = try rampWidth(EdgeProbe.make(edgeAt: 560), y: 300)
        let alongTheRadius = try rampWidth(EdgeProbe.make(horizontal: true), column: 560)
        #expect(abs(acrossTheRadius - alongTheRadius) <= 8)
    }

    /// A scene defocused by its own depth takes the blade count from the camera that
    /// drew it, so the live blur, the flare ghosts, and the path-traced export cannot
    /// disagree about what lens this is. Naming no blade count at the call is what
    /// leaves the camera in charge.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSceneTakesItsBladesFromItsOwnCamera() throws {
        let round = try #require(OllinApp.image(of: SceneProbe.make(blades: 0), frame: 1))
        let six = try #require(OllinApp.image(of: SceneProbe.make(blades: 6), frame: 1))
        let again = try #require(OllinApp.image(of: SceneProbe.make(blades: 6), frame: 1))
        #expect(difference(round, six) > 12)
        // Two runs of the same lens differ only by the present pass's own dither.
        #expect(difference(six, again) <= 2)
    }

    /// A depth map drawn by hand carries no camera, so it stays round on its own and
    /// only the call itself can shape it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDrawnDepthMapStaysRoundUntilTheCallSaysOtherwise() throws {
        let round = try rampWidth(EdgeProbe.make())
        let stated = try rampWidth(EdgeProbe.make(blades: 6, irisAngle: .pi / 6))
        #expect(abs(round - 60) <= 8)
        #expect(stated > round)
    }

    // MARK: Readback helpers

    /// The largest difference between two images at any one channel, in 0...255. A mean
    /// is the wrong reading here: the shape of a highlight moves a few thousand pixels
    /// on a mostly black frame, which any average buries.
    private func difference(_ a: CGImage, _ b: CGImage) -> Double {
        let pa = pixels(of: a), pb = pixels(of: b)
        guard pa.bytes.count == pb.bytes.count else { return .infinity }
        var worst = 0.0
        for i in 0 ..< pa.bytes.count {
            worst = max(worst, abs(Double(pa.bytes[i]) - Double(pb.bytes[i])))
        }
        return worst
    }

    /// Half the width of the blurred ramp across the probe's edge, in pixels: the
    /// distance from the edge out to where the blur has run out of reach. Read on the
    /// bright side, from the edge outward, as the first sample that is essentially white.
    private func rampWidth(_ probe: EdgeProbe, y: Int = 300, column: Int? = nil) throws -> Double {
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        let px = pixels(of: image)
        let edge = Int(probe.edgeAt)
        // Walk away from the edge into the dark side. The blur runs out exactly where
        // the opening stops reaching back over the bright side, so the first sample
        // that is properly black (and stays black) is the reach. The present pass
        // dithers, so a single sample is not enough to call it.
        func sample(_ step: Int) -> Int {
            if let column { return Int(px.bytes[((edge - step) * px.width + column) * 4]) }
            return Int(px.bytes[(y * px.width + edge - step) * 4])
        }
        for step in 1 ..< 200 where (0 ... 3).allSatisfy({ sample(step + $0) <= 2 }) {
            return Double(step)
        }
        return 200
    }

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
}

// MARK: Probe sketch

/// A hard black-to-white step edge over a depth map that is the same everywhere, so
/// every pixel blurs by exactly `maxBlur` and the ramp across the edge measures how far
/// the opening reaches in that direction and nothing else.
private final class EdgeProbe: Sketch {
    var blades: Int? = nil
    var irisAngle = 0.0
    var catsEye = 0.0
    var edgeAt = 300.0
    var horizontal = false

    static func make(blades: Int? = nil, irisAngle: Double = 0, catsEye: Double = 0,
                     edgeAt: Double = 300, horizontal: Bool = false) -> EdgeProbe {
        let probe = EdgeProbe()
        probe.blades = blades; probe.irisAngle = irisAngle; probe.catsEye = catsEye
        probe.edgeAt = edgeAt; probe.horizontal = horizontal
        return probe
    }

    override var canvasSize: CanvasSize { .square(600) }
    override func draw() {
        noLoop()
        compose {
            layer {
                background(.black)
                noStroke(); fill(.white)
                if horizontal {
                    drawRect(0, edgeAt, 600, 600 - edgeAt)
                } else {
                    drawRect(edgeAt, 0, 600 - edgeAt, 600)
                }
            }
            .defocused(by: aside { background(.white) },
                       focus: 0, range: 0.05, maxBlur: 60,
                       blades: blades, irisAngle: irisAngle, catsEye: catsEye)
        }
    }
}

/// A small 3D scene defocused by its own depth buffer, so the blade count reaches the
/// blur through the camera rather than through the call.
private final class SceneProbe: Sketch {
    var blades = 0

    static func make(blades: Int) -> SceneProbe {
        let probe = SceneProbe()
        probe.blades = blades
        return probe
    }

    override var canvasSize: CanvasSize { .square(480) }
    override func draw() {
        noLoop()
        background(.black)
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(Color(white: 0.02))
            var view = Camera3D(eye: Vector3(0, 1.4, 9), target: Vector3(0, 0, -2),
                                near: 4, far: 22,
                                projection: .perspective(fieldOfView: .pi / 4))
            view.apertureBlades = blades
            camera(view)
            // Small, very bright balls on black, so what the blur spreads is close to a
            // point of light and the shape of the opening is most of what is left.
            ambientLight(.white)
            for i in 0 ..< 4 {
                let t = Double(i) / 3
                withState {
                    translate(-2.6 + t * 5.2, 0, 3 - t * 12)
                    fill(.white)
                    drawSphere(radius: 0.34)
                }
            }
        }
        drawImage(scene.combined(with: scene.depth,
                                 .defocus(focus: 1, range: 0.05, maxBlur: 70)).image, 0, 0)
    }
}
