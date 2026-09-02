@testable import Ollin
import Testing
import CoreGraphics

/// Render checks on the `.lineIntegralConvolution` combine. Each is a claim the
/// technique makes by construction rather than a taste: a mark averaged along a
/// field that runs straight across it smears across and not along; a field that
/// runs along a mark leaves the mark whole, because every sample on the walk is
/// the mark itself; a still field gives back the base, because the walk never
/// leaves its own pixel; and the contour reading of a radial gradient runs around
/// the center, so a dot beside the center smears around it and never outward.
/// One probe, three encodings, so all three readings of the field are exercised.
@Suite
@MainActor
struct LineIntegralConvolutionTests {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func gray(_ data: [UInt8], _ x: Int, _ y: Int, width: Int = 256) -> Int {
        Int(data[(y * width + x) * 4])
    }

    /// The largest per-channel difference between two renders. The present pass
    /// dithers by pixel position, so the same value lands on the same byte in both
    /// and a difference of 1 is float rounding, not a discrepancy.
    private func worst(_ a: CGImage, _ b: CGImage) -> Int {
        let (da, db) = (pixels(of: a), pixels(of: b))
        var worst = 0
        for i in stride(from: 0, to: da.count, by: 4) {
            for c in 0 ..< 3 { worst = max(worst, abs(Int(da[i + c]) - Int(db[i + c]))) }
        }
        return worst
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldAcrossAStripeSmearsItSideways() throws {
        // A vector field pointing right, over a vertical stripe: the stripe leaks
        // into the black on both sides and loses brightness, and nothing changes
        // from row to row.
        let image = try #require(OllinApp.image(of: StreakProbe.make(.acrossTheStripe), frame: 0))
        let data = pixels(of: image)
        #expect(gray(data, 100, 128) > 40, "the stripe did not leak to its left")
        #expect(gray(data, 156, 128) > 40, "the stripe did not leak to its right")
        #expect(gray(data, 128, 128) < 250, "the stripe's own center kept full brightness")
        #expect(gray(data, 20, 128) == 0, "the smear reached further than the streak length")
        // Two positions dither differently, so one value can land two bytes apart.
        #expect(abs(gray(data, 128, 20) - gray(data, 128, 128)) <= 2,
                "a field with no vertical part changed the picture from row to row")
        #expect(abs(gray(data, 100, 236) - gray(data, 100, 128)) <= 2)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldAlongAStripeLeavesItWhole() throws {
        // The angle reading, a quarter turn: every walk runs up and down its own
        // column, where the base is one value throughout, so the average is that
        // value and the stripe keeps its edges.
        let streaked = try #require(OllinApp.image(of: StreakProbe.make(.alongTheStripe), frame: 0))
        let plain = try #require(OllinApp.image(of: StreakProbe.make(.plain), frame: 0))
        let w = worst(streaked, plain)
        #expect(w <= 1, "a field along the stripe moved it by \(w)/255")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillFieldGivesTheBaseBack() throws {
        // The contour reading of a flat field has no gradient anywhere, so the
        // walk stops at once and the pixel is its own only sample.
        let streaked = try #require(OllinApp.image(of: StreakProbe.make(.still), frame: 0))
        let plain = try #require(OllinApp.image(of: StreakProbe.make(.plain), frame: 0))
        let w = worst(streaked, plain)
        #expect(w <= 1, "a still field changed the base by \(w)/255")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func contoursRunAroundTheCenterOfARadialField() throws {
        // A dot at (188, 128) beside a gradient centered at (128, 128): the
        // contours are circles about the center, so the dot smears up and down
        // along its circle and not outward along the radius.
        let image = try #require(OllinApp.image(of: StreakProbe.make(.aroundTheCenter), frame: 0))
        let data = pixels(of: image)
        #expect(gray(data, 188, 140) > 40, "the dot did not smear along its contour")
        #expect(gray(data, 188, 116) > 40, "the dot did not smear the other way along its contour")
        #expect(gray(data, 200, 128) == 0, "the dot smeared outward, across the contours")
        #expect(gray(data, 176, 128) == 0, "the dot smeared inward, across the contours")
        #expect(gray(data, 188, 128) < 250, "the dot's own center kept full brightness")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldThatTurnsBackIsWalkedThrough() throws {
        // An angle field that flips sign at x = 144: pointing right on the left,
        // left on the right. A walk from the right side heads left, crosses the
        // seam, and must keep going to reach the stripe. Without the heading rule
        // the walk bounces between the two sides of the seam and never arrives.
        // The seam is cut hard, since a half-covered edge texel reads as a quarter
        // turn in an angle field, a wall along the seam that no walk can cross.
        let image = try #require(OllinApp.image(of: StreakProbe.make(.acrossASeam), frame: 0))
        let data = pixels(of: image)
        #expect(gray(data, 160, 128) > 40, "the walk turned back at the seam and never reached the stripe")
        #expect(gray(data, 100, 128) > 40, "the stripe did not leak to its left")
    }

    @Test func theLengthIsHeldToTheLayer() {
        guard case let .lineIntegralConvolution(length, field) =
                Combine.lineIntegralConvolution(length: 3, field: .contour).kind else {
            Issue.record("expected a lineIntegralConvolution"); return
        }
        #expect(length == 1)
        #expect(field == .contour)
        guard case let .lineIntegralConvolution(negative, _) =
                Combine.lineIntegralConvolution(length: -1).kind else {
            Issue.record("expected a lineIntegralConvolution"); return
        }
        #expect(negative == 0)
    }
}

/// A white mark on black, streaked along a field drawn as a second layer. The
/// mark is a vertical stripe for the straight fields and a dot for the radial
/// one; the field is a flat color for the two straight readings (a vector, then
/// an angle) and a radial gradient for the contour reading.
private final class StreakProbe: Sketch {
    enum Scene { case plain, acrossTheStripe, alongTheStripe, still, aroundTheCenter, acrossASeam }
    var scene: Scene = .plain

    static func make(_ scene: Scene) -> StreakProbe {
        let probe = StreakProbe()
        probe.scene = scene
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        let base = makeRenderTarget()
        withTarget(base) {
            background(.black)
            noStroke()
            fill(.white)
            if scene == .aroundTheCenter { drawCircle(188, 128, 4) } else { drawRect(120, 0, 16, 256) }
        }
        let field = makeRenderTarget()
        let op: Combine
        var hardSeam = false
        switch scene {
        case .plain:
            drawImage(base.image, 0, 0)
            return
        case .acrossTheStripe:
            // Red full, green at the mid-gray the vector reading is centered on
            // (a layer holds linear light, and 0.7354 in sRGB is linear 0.5).
            withTarget(field) { background(Color(red: 1, green: 0.7354, blue: 0)) }
            op = .lineIntegralConvolution(length: 0.25, field: .vector)
        case .alongTheStripe:
            withTarget(field) { background(.white) }
            op = .lineIntegralConvolution(length: 0.25, field: .angle(turns: 0.25))
        case .still:
            withTarget(field) { background(Color(white: 0.5)) }
            op = .lineIntegralConvolution(length: 0.25, field: .contour)
        case .acrossASeam:
            withTarget(field) {
                background(.black)
                noStroke()
                fill(.white)
                drawRect(144, 0, 112, 256)
            }
            hardSeam = true
            op = .lineIntegralConvolution(length: 0.25, field: .angle(turns: 0.5))
        case .aroundTheCenter:
            withTarget(field) {
                background(.black)
                noStroke()
                fill(.radial(center: Vector2(128, 128), radius: 128, [.white, .black]))
                drawRect(0, 0, 256, 256)
            }
            op = .lineIntegralConvolution(length: 0.25, field: .contour)
        }
        let steer = hardSeam ? field.filtered(.threshold(0.5)) : field
        drawImage(base.combined(with: steer, op).image, 0, 0)
    }
}
