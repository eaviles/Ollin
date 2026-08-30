@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// sRGB byte to linear light, so a reading means light rather than encoded light.
private let lightToLinear: [Double] = (0 ..< 256).map { i in
    let c = Double(i) / 255
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

/// One rendered frame, read back in linear light and in canvas coordinates, so a probe
/// placed under a shape reads what the sketch drew under it.
private struct Frame {
    let width: Int, height: Int, data: [UInt8]

    private func index(_ x: Int, _ y: Int) -> Int {
        let px = min(max(x, 0), width - 1), py = min(max(y, 0), height - 1)
        return (py * width + px) * 4
    }

    /// Linear luminance at one pixel.
    func lum(_ x: Int, _ y: Int) -> Double {
        let i = index(x, y)
        return 0.2126 * lightToLinear[Int(data[i])] + 0.7152 * lightToLinear[Int(data[i + 1])]
             + 0.0722 * lightToLinear[Int(data[i + 2])]
    }

    /// Linear luminance averaged over a band of rows, which is what makes a reading
    /// steadier than the dither the present pass adds.
    func band(_ x: Int, _ y: Int, rows: Int = 13) -> Double {
        var sum = 0.0
        let half = rows / 2
        for dy in -half ... half { sum += lum(x, y + dy) }
        return sum / Double(half * 2 + 1)
    }

    /// The three channels at one pixel, in linear light.
    func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        let i = index(x, y)
        return (lightToLinear[Int(data[i])], lightToLinear[Int(data[i + 1])],
                lightToLinear[Int(data[i + 2])])
    }
}

/// Render checks on `Combine.light`, the light a flat scene works out for itself.
///
/// The claims worth pinning are the ones a sketch is being promised, and none of them
/// is drawn by hand: a shape stops light, a small lamp falls off with distance, a
/// shadow is sharp where it meets the shape and soft further away, a lit surface gives
/// its own color back, and a wide lamp's falloff matches the exact answer the geometry
/// gives. That last one is the net under the published "bilinear fix", since a ladder
/// whose rungs do not meet counts a stretch of every ray twice and hands back more light
/// than was ever emitted.
///
/// Every measurement is in linear light and averaged across a band of rows, because the
/// present pass dithers and one row of an 8-bit picture wobbles by more than the effects
/// being measured.
@Suite
@MainActor
struct LightTests {

    private func frame(_ subject: LightProbe.Subject) throws -> Frame {
        let image = try #require(OllinApp.image(of: LightProbe.make(subject), frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Frame(width: w, height: h, data: data)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aShapeStopsLight() throws {
        // The bar sits between the lamp and the pixel below it. The pixel beside it, the
        // same distance from the lamp, has nothing in the way, so the two readings are a
        // shadow test with the falloff taken out of it.
        let f = try frame(.room)
        let shaded = f.band(LightProbe.underBar, LightProbe.readingRow)
        let open = f.band(LightProbe.beside, LightProbe.readingRow)
        #expect(shaded < open * 0.25,
                "behind the bar reads \(shaded), beside it \(open)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSmallLampFallsOffWithDistance() throws {
        // A lamp covers less of the circle of directions the further away it is, so in a
        // flat world the light halves as the distance doubles. Nothing in the code says
        // so: it falls out of counting the directions that reach it.
        let f = try frame(.lamp(reach: nil))
        let near = f.band(LightProbe.lampX + 80, LightProbe.lampY)
        let far = f.band(LightProbe.lampX + 160, LightProbe.lampY)
        let ratio = near / max(far, 1e-9)
        #expect(ratio > 1.6 && ratio < 2.6,
                "doubling the distance divided the light by \(ratio) (near \(near), far \(far))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theShadowSoftensFurtherFromTheShape() throws {
        // The penumbra. Beside the shape a pixel sees the lamp cut off sharply; further
        // down, the same edge is spread over many pixels. This is the behavior the
        // ladder exists for, and a single-resolution light field cannot produce it.
        let f = try frame(.room)
        let near = edgeWidth(f, row: LightProbe.nearRow)
        let far = edgeWidth(f, row: LightProbe.farRow)
        #expect(far > near * 1.8,
                "the shadow edge is \(near) px wide beside the bar and \(far) px far from it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theLightMatchesWhatTheGeometryAllows() throws {
        // A disc of radius R seen from r away covers `2·asin(R/r)` of the circle of
        // directions, so the average light arriving is `asin(R/r) / π` of the disc's
        // own. That is an exact answer, and measuring against it over a range of
        // distances pins two things at once: the scale of the whole field, and that the
        // rungs of the ladder meet.
        //
        // The reading runs a few per cent under the exact answer all the way out, which
        // is the disc's antialiased rim and the point being read one pixel inside it.
        // What it must never do is run *over*: light that was never emitted means a
        // stretch of a ray counted twice, which is what happens when each rung's rays
        // end where this probe's ray would rather than where the rung above it starts.
        // Measured with that one line changed: 0.900…1.108 of the exact answer, against
        // 0.902…0.952 as it stands.
        let f = try frame(.disc)
        for y in stride(from: 200, through: 490, by: 10) {
            let r = Double(y - LightProbe.lampY)
            let exact = asin(min(LightProbe.discRadius / r, 1)) / .pi
            var sum = 0.0
            for dx in -4 ... 4 { sum += f.lum(LightProbe.lampX + dx, y) }
            let ratio = (sum / 9) / exact
            #expect(ratio > 0.85 && ratio < 1.02,
                    "at \(Int(r)) px the light is \(ratio) of what the geometry allows")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLitWallGivesItsColorBack() throws {
        // With no bounce a surface is black and the room is the color of its lamp. With
        // one, the red wall lights what stands beside it in its own color.
        let plain = try frame(.wall(bounces: 0))
        let bounced = try frame(.wall(bounces: 1))
        let (r0, g0, _) = plain.rgb(LightProbe.nearWall, LightProbe.wallY)
        let (r1, g1, _) = bounced.rgb(LightProbe.nearWall, LightProbe.wallY)
        #expect(r1 / max(g1, 1e-9) > r0 / max(g0, 1e-9) * 1.3,
                "beside the wall the red/green ratio went from \(r0 / max(g0, 1e-9)) to \(r1 / max(g1, 1e-9))")
        let wallPlain = plain.lum(LightProbe.wallX, LightProbe.wallY)
        let wallBounced = bounced.lum(LightProbe.wallX, LightProbe.wallY)
        #expect(wallPlain < 0.01, "with no bounce the wall itself must stay dark, it read \(wallPlain)")
        #expect(wallBounced > wallPlain * 3, "with a bounce the wall lights up, it read \(wallBounced)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func askingForLessReachStopsTheLightSooner() throws {
        // `reach` takes rungs off the ladder, so it is the speed knob. It has to be an
        // honest one: the near field must be unchanged and only the far field go dark.
        let whole = try frame(.lamp(reach: nil))
        let short = try frame(.lamp(reach: 90))
        let near = (whole.band(LightProbe.lampX + 40, LightProbe.lampY),
                    short.band(LightProbe.lampX + 40, LightProbe.lampY))
        let far = (whole.band(LightProbe.lampX + 200, LightProbe.lampY),
                   short.band(LightProbe.lampX + 200, LightProbe.lampY))
        #expect(abs(near.0 - near.1) < near.0 * 0.25,
                "the near field moved from \(near.0) to \(near.1)")
        #expect(far.1 < far.0 * 0.5, "the far field read \(far.1) against \(far.0)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSkyLightsWhatNoLampReaches() throws {
        // A ray that meets nothing within reach takes the sky, so a scene with one set
        // brightens where no lamp shines rather than only near the lamps.
        let dark = try frame(.lamp(reach: nil))
        let lit = try frame(.lamp(reach: nil, sky: Color(white: 0.25)))
        let corner = (dark.band(40, 40), lit.band(40, 40))
        #expect(corner.1 > corner.0 + 0.01,
                "the far corner read \(corner.0) with no sky and \(corner.1) with one")
    }

    @Test func theKnobsAreHeldToTheirRange() {
        // A negative brightness would subtract light, and a reach under a pixel asks for
        // a ladder with no rungs in it.
        let op = Combine.light(reach: 0.1, brightness: -3, bounces: 99)
        guard case let .light(reach, brightness, bounces, _, _) = op.kind else {
            Issue.record("expected a light combine"); return
        }
        #expect(reach == 1)
        #expect(brightness == 0)
        #expect(bounces == 4)
        guard case let .light(unbounded, _, _, _, _) = Combine.light().kind else { return }
        #expect(unbounded == nil, "no reach means light travels the whole layer")
    }

    /// How many pixels the shadow's edge takes to open up along one row: the distance
    /// between where the light passes a quarter of that row's brightest reading and where
    /// it passes three quarters of it.
    private func edgeWidth(_ f: Frame, row: Int) -> Double {
        var peak = 0.0
        for x in stride(from: 20, to: f.width - 20, by: 2) { peak = max(peak, f.band(x, row)) }
        var low = -1, high = -1
        for x in stride(from: 20, to: f.width - 20, by: 1) {
            let v = f.band(x, row)
            if low < 0 && v > peak * 0.25 { low = x }
            if low >= 0 && high < 0 && v > peak * 0.75 { high = x; break }
        }
        return (low >= 0 && high >= 0) ? Double(high - low) : 0
    }
}

/// A scene, a lamp, and the light between them, drawn at native size.
private final class LightProbe: Sketch {
    enum Subject {
        /// One small lamp in an empty scene: falloff, rings, reach, and sky.
        case lamp(reach: Double?, sky: Color = .clear)
        /// A lamp above a bar: shadows and the penumbra.
        case room
        /// A lamp beside a red wall, with nothing between them: the bounce.
        case wall(bounces: Int)
        /// One wide disc of light in an empty scene, whose falloff has an exact answer.
        case disc
    }

    static let lampX = 280, lampY = 120
    static let readingRow = 300
    static let underBar = 150          // in the bar's shadow
    static let beside = 410            // the same distance from the lamp, nothing in the way
    static let nearRow = 230           // just under the bar
    static let farRow = 420            // well under it

    static let discRadius = 60.0
    static let wallLampX = 300, wallLampY = 256
    static let nearWall = 52           // the open floor just beside the red wall
    static let wallX = 40, wallY = 256 // inside the wall, near the face the lamp shines on

    var subject: Subject = .lamp(reach: nil)

    static func make(_ subject: Subject) -> LightProbe {
        let probe = LightProbe()
        probe.subject = subject
        return probe
    }

    override var canvasSize: CanvasSize { .square(512) }

    override func draw() {
        background(.black)
        let scene = makeRenderTarget()
        let lamps = makeRenderTarget()

        switch subject {
        case let .lamp(reach, sky):
            // Even an empty scene is drawn into: a layer nobody draws into is never
            // recorded, and the combine then has no base to read at all.
            withTarget(scene) {}
            withTarget(lamps) { lamp(at: Vector2(Double(LightProbe.lampX),
                                                 Double(LightProbe.lampY))) }
            let lit = scene.combined(with: lamps,
                                     .light(reach: reach, brightness: 6, bounces: 0, sky: sky,
                                            quality: .performance))
            drawImage(lit.image, 0, 0)
        case .room:
            withTarget(scene) {
                noStroke()
                // The bar reaches the left edge, so each row below it holds exactly one
                // shadow edge and its width is a fair reading.
                fill(Color(hex: 0x808080))
                drawRect(0, 190, 256, 16)
            }
            withTarget(lamps) { lamp(at: Vector2(Double(LightProbe.lampX),
                                                 Double(LightProbe.lampY))) }
            let lit = scene.combined(with: lamps,
                                     .light(brightness: 6, bounces: 0, quality: .performance))
            drawImage(lit.image, 0, 0)
        case .disc:
            withTarget(scene) {}
            withTarget(lamps) {
                noStroke()
                fill(.white)
                drawCircle(Double(LightProbe.lampX), Double(LightProbe.lampY),
                           LightProbe.discRadius)
            }
            let lit = scene.combined(with: lamps,
                                     .light(brightness: 1, bounces: 0, quality: .performance))
            drawImage(lit.image, 0, 0)
        case let .wall(bounces):
            // A red wall with clear air between it and the lamp, so what reaches it is
            // only the lamp and what leaves it is only the bounce.
            withTarget(scene) {
                noStroke()
                fill(Color(hex: 0xFF2000))
                drawRect(16, 120, 28, 280)
            }
            withTarget(lamps) { lamp(at: Vector2(Double(LightProbe.wallLampX),
                                                 Double(LightProbe.wallLampY))) }
            let lit = scene.combined(with: lamps,
                                     .light(brightness: 6, bounces: bounces, quality: .performance))
            drawImage(lit.image, 0, 0)
        }
    }

    private func lamp(at p: Vector2) {
        noStroke()
        fill(.white)
        drawCircle(p.x, p.y, 10)
    }
}
