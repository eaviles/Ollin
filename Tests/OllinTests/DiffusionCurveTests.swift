@testable import Ollin
import Testing
import CoreGraphics

/// Render checks on the `.diffuse` filter. The load-bearing one is the rule the
/// solve is defined by: away from the marks every pixel must end up the average
/// of its four neighbors. That is what a Laplace solve *is*, and it is what
/// makes the field look the way it does, so it is worth measuring rather than
/// trusting. Beside it sits the maximum principle, which says no color can
/// appear that was not put there.
@Suite
@MainActor
struct DiffusionCurveTests {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func rgb(_ data: [UInt8], _ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMarkKeepsItsOwnColorAndTheSpaceBetweenFillsIn() throws {
        let image = try #require(OllinApp.image(of: DiffusionProbe.make(.twoDots), frame: 1))
        let data = pixels(of: image)
        let left = rgb(data, image, 48, 128), right = rgb(data, image, 208, 128)
        #expect(left.0 > 200 && left.2 < 60, "the red mark stayed red: \(left)")
        #expect(right.2 > 200 && right.0 < 60, "the blue mark stayed blue: \(right)")
        // Halfway between them the two have met and neither wins.
        let middle = rgb(data, image, 128, 128)
        #expect(middle.0 > 40 && middle.2 > 40,
                "expected both colors present in the middle: \(middle)")
        #expect(abs(middle.0 - middle.2) < 90, "and neither to dominate: \(middle)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFieldIsTheAverageOfItsNeighborsAwayFromTheMarks() throws {
        // The rule the solve is defined by. Sampled well away from the marks,
        // where nothing is held, and in the green channel of a red/blue pair so
        // the measurement is not riding on either source.
        let image = try #require(OllinApp.image(of: DiffusionProbe.make(.twoDots), frame: 1))
        let data = pixels(of: image)
        var worst = 0
        for y in stride(from: 40, to: 216, by: 8) {
            for x in stride(from: 90, to: 166, by: 8) {
                let here = rgb(data, image, x, y)
                let around = [rgb(data, image, x - 4, y), rgb(data, image, x + 4, y),
                              rgb(data, image, x, y - 4), rgb(data, image, x, y + 4)]
                for channel in 0 ... 2 {
                    let mine = [here.0, here.1, here.2][channel]
                    let mean = around.map { [$0.0, $0.1, $0.2][channel] }.reduce(0, +) / 4
                    worst = max(worst, abs(mine - mean))
                }
            }
        }
        #expect(worst <= 6, "a pixel differed from its neighbors' average by \(worst)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func noColorAppearsThatWasNotPutThere() throws {
        // The maximum principle: the solve can only ever average what it was
        // given, so a red and a blue mark can never make green.
        let image = try #require(OllinApp.image(of: DiffusionProbe.make(.twoDots), frame: 1))
        let data = pixels(of: image)
        var greenest = 0
        for y in stride(from: 4, to: 252, by: 4) {
            for x in stride(from: 4, to: 252, by: 4) {
                greenest = max(greenest, rgb(data, image, x, y).1)
            }
        }
        #expect(greenest < 40, "green reached \(greenest) from two marks that had none")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRingFillsWithTheColorItIsDrawnIn() throws {
        // A closed mark holds its whole interior, since every path inward from
        // the boundary carries the same value. This is the harmonic maximum
        // principle again, seen from the inside.
        let image = try #require(OllinApp.image(of: DiffusionProbe.make(.ring), frame: 1))
        let data = pixels(of: image)
        let middle = rgb(data, image, 128, 128)
        #expect(middle.1 > 170 && middle.0 < 90,
                "expected the ring's own green inside it: \(middle)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aCurveCarriesADifferentColorOnEachSide() throws {
        // What the technique is named for: the field jumps across the curve and
        // is smooth everywhere else.
        let image = try #require(OllinApp.image(of: DiffusionProbe.make(.curve), frame: 1))
        let data = pixels(of: image)
        let above = rgb(data, image, 128, 96), below = rgb(data, image, 128, 160)
        #expect(above.0 > 150 && above.2 < 110, "above the curve is the warm side: \(above)")
        #expect(below.2 > 150 && below.0 < 110, "below it is the cool side: \(below)")
        // And the jump is at the curve, not spread over the picture: two samples
        // a few pixels apart across it must differ far more than two the same
        // distance apart on one side.
        let near = rgb(data, image, 128, 122), far = rgb(data, image, 128, 134)
        let across = abs(near.0 - far.0) + abs(near.2 - far.2)
        let along = abs(above.0 - rgb(data, image, 128, 84).0)
            + abs(above.2 - rgb(data, image, 128, 84).2)
        #expect(across > along * 3, "expected the jump at the curve: \(across) against \(along)")
    }

    @Test func theKnobsAreHeldToTheirRange() {
        // Nothing renders here: a threshold of zero would make every pixel of an
        // empty layer a source, and the sharpness feeds a pass count.
        let filter = Filter.diffuse(threshold: -4, sharpness: 9)
        guard case let .diffuse(threshold, sharpness) = filter.kind else {
            Issue.record("expected a diffuse filter"); return
        }
        #expect(threshold == 0.01)
        #expect(sharpness == 1)
    }
}

/// A few marks drawn into a layer, diffused, and drawn back at native size.
private final class DiffusionProbe: Sketch {
    enum Subject { case twoDots, ring, curve }
    var subject: Subject = .twoDots

    static func make(_ subject: Subject) -> DiffusionProbe {
        let probe = DiffusionProbe()
        probe.subject = subject
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        let marks = renderTarget()
        withTarget(marks) {
            noStroke()
            switch subject {
            case .twoDots:
                fill(Color(hex: 0xFF0000)); drawCircle(48, 128, 14)
                fill(Color(hex: 0x0000FF)); drawCircle(208, 128, 14)
            case .ring:
                noFill()
                stroke(Color(hex: 0x00CC44))
                strokeWeight(6)
                drawCircle(128, 128, 70)
            case .curve:
                drawDiffusionCurve([Vector2(10, 128), Vector2(128, 128), Vector2(246, 128)],
                                   left: Color(hex: 0xFF3300), right: Color(hex: 0x0033FF),
                                   width: 4)
            }
        }
        drawImage(marks.filtered(.diffuse(sharpness: 1)).image, 0, 0)
    }
}
