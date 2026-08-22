@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// Render checks on `.distanceField`, the field a sketch measures back out of a layer.
///
/// Two things are worth pinning. The first is where the field's zero is: it must be the
/// layer's own edge and nowhere else, which is checked against the drawn shape rather
/// than against the radius it was asked for (a drawn circle's half-covered contour sits
/// a fraction of a pixel outside its nominal radius, because thin-mark coverage is
/// remapped to perceptual alpha, and a test written against the nominal radius measures
/// that convention instead of this filter). The second is the scale: cutting the field
/// at a distance draws the shape grown by exactly that much, at any distance.
///
/// Both are measured by area rather than by walking a scanline, and the area is summed
/// from an antialiased cut in linear light rather than counted from a hard one. A hard
/// count of a disc wobbles about a tenth of a pixel of radius as the grid falls where it
/// falls, which is the same size as the effects being measured.
@Suite
@MainActor
struct DistanceFieldTests {

    /// sRGB byte to linear light, so summed coverage means area.
    private static let toLinear: [Double] = (0 ..< 256).map { i in
        let c = Double(i) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

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

    /// The radius of a soft-edged white disc, from its summed coverage. The ramp the
    /// probe cuts with is a color ramp, so the sum sits a fixed fraction of a pixel off
    /// the true area; every comparison below is between two of these, where that cancels.
    private func softRadius(_ image: CGImage) throws -> Double {
        let data = pixels(of: image)
        var sum = 0.0
        for i in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            sum += DistanceFieldTests.toLinear[Int(data[i])]
        }
        return (sum / .pi).squareRoot()
    }

    /// How many pixels are at least half covered: the shape's own edge, as the picture
    /// itself draws it. Linear 0.5 encodes to sRGB 187.5.
    private func halfCoveredCount(_ image: CGImage) -> Int {
        let data = pixels(of: image)
        var n = 0
        for i in stride(from: 0, to: image.width * image.height * 4, by: 4) where data[i] > 187 {
            n += 1
        }
        return n
    }

    private func render(_ subject: FieldProbe.Subject) throws -> CGImage {
        try #require(OllinApp.image(of: FieldProbe.make(subject), frame: 1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theZeroContourIsTheShapesOwnEdge() throws {
        // The field calls a pixel inside when the layer is at least half covered there,
        // so cutting it at zero must reproduce that set exactly: same pixels, not merely
        // the same size. Anything else means the seed pass is measuring from the wrong
        // place, which every distance in the field is then built on.
        let drawn = halfCoveredCount(try render(.bare))
        let cut = halfCoveredCount(try render(.inside))
        #expect(abs(drawn - cut) <= 20,
                "the shape covers \(drawn) pixels, the field's inside is \(cut)")
        #expect(drawn > 30_000, "expected a shape worth measuring, got \(drawn) pixels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func cuttingTheFieldGrowsTheShapeByThatMuch() throws {
        // The scale of the measurement, over three orders of it. A field that measured in
        // some other unit, or from the pixel grid instead of the edge, would still pass
        // the zero test above and fail here.
        let base = try softRadius(try render(.grown(by: 0)))
        for offset in [10.0, 40.0, 100.0] {
            let grown = try softRadius(try render(.grown(by: offset)))
            #expect(abs(grown - base - offset) < 0.1,
                    "cut at \(offset) grew the radius by \(grown - base)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theEdgeIsFoundBetweenPixelsRatherThanAtTheirCenters() throws {
        // Half a pixel is the whole difference between seeding the crossing itself and
        // seeding the pixel that holds it, and it is a difference a picture hides. Two
        // cuts half a pixel apart have to move the edge half a pixel; seeding the pixel
        // centers instead would move it a whole one or not at all.
        let low = try softRadius(try render(.grown(by: 20)))
        let high = try softRadius(try render(.grown(by: 20.5)))
        #expect(abs(high - low - 0.5) < 0.06,
                "expected the edge to move half a pixel, it moved \(high - low)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func askingForLessDistanceMeasuresTheSameFieldNearTheEdge() throws {
        // A short `maxDistance` shortens the flood, so this is the one that would catch a
        // ladder whose first rung is too small to carry a seed as far as it promised.
        let whole = try softRadius(try render(.grown(by: 40)))
        let capped = try softRadius(try render(.grown(by: 40, within: 48)))
        #expect(abs(whole - capped) < 0.05, "capped measured \(capped) against \(whole)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerWithNoEdgeInItReadsAsNothingWithinReach() throws {
        // Nothing was drawn, so there is no edge to be near. Every pixel must read far
        // away rather than at distance zero, which is what an empty seed pass would give.
        let image = try render(.empty)
        let data = pixels(of: image)
        for (x, y) in [(8, 8), (256, 256), (500, 300)] {
            #expect(rgb(data, image, x, y).0 < 40, "expected the far end of the ramp at \(x), \(y)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theDirectionPointsAtTheNearestEdge() throws {
        // The direction channel read the way a sketch reads it: every pixel steps to its
        // nearest edge and takes the color of whatever was drawn there. Three dots of
        // three colors then paint their own Voronoi cells, so a pixel wearing the wrong
        // color is a direction pointing at the wrong dot.
        let image = try render(.nearestDot)
        let data = pixels(of: image)
        var wrong = 0, checked = 0
        for y in stride(from: 8, to: 512, by: 8) {
            for x in stride(from: 8, to: 512, by: 8) {
                let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                let byDistance = FieldProbe.dots
                    .map { ($0, ($0.center - p).length) }
                    .sorted { $0.1 < $1.1 }
                // Skip the pixels a cell boundary runs through: which side they fall on
                // is a fair question at half a pixel, and not what is being measured.
                guard byDistance[1].1 - byDistance[0].1 > 4 else { continue }
                checked += 1
                let (r, g, b) = rgb(data, image, x, y)
                let brightest = (r >= g && r >= b) ? 0 : (g >= b ? 1 : 2)
                if brightest != byDistance[0].0.channel { wrong += 1 }
            }
        }
        #expect(checked > 2000, "expected a decent sample, checked \(checked)")
        #expect(wrong == 0, "\(wrong) of \(checked) pixels took the wrong dot's color")
    }

    @Test func theKnobsAreHeldToTheirRange() {
        // A negative threshold would make every pixel of a layer inside the shape, and a
        // maxDistance under a pixel would ask for a ladder with no rungs in it.
        let filter = Filter.distanceField(from: .luminance, threshold: -2, maxDistance: 0.1)
        guard case let .distanceField(source, threshold, maxDistance) = filter.kind else {
            Issue.record("expected a distance field filter"); return
        }
        #expect(source.rawIndex == 1)
        #expect(threshold == 0)
        #expect(maxDistance == 1)
        guard case let .distanceField(_, _, unbounded) = Filter.distanceField().kind else { return }
        #expect(unbounded == nil, "no maxDistance means measure the whole layer")
    }
}

/// A shape drawn into a layer, measured, and the measurement drawn back at native size.
private final class FieldProbe: Sketch {
    struct Dot { let center: Vector2; let color: Color; let channel: Int }
    static let dots = [Dot(center: Vector2(140, 150), color: Color(hex: 0xFF0000), channel: 0),
                       Dot(center: Vector2(370, 120), color: Color(hex: 0x00FF00), channel: 1),
                       Dot(center: Vector2(250, 400), color: Color(hex: 0x0000FF), channel: 2)]

    enum Subject {
        /// The circle as drawn, with no field in the way: the reference edge.
        case bare
        /// White exactly where the field is negative, cut hard so the two sets can be
        /// counted against each other pixel for pixel.
        case inside
        /// White where the field reads at most `offset` pixels: the shape grown by that
        /// much, its edge left one pixel wide so its area can be summed rather than counted.
        case grown(by: Double, within: Double? = nil)
        case empty
        case nearestDot
    }
    var subject: Subject = .empty

    static func make(_ subject: Subject) -> FieldProbe {
        let probe = FieldProbe()
        probe.subject = subject
        return probe
    }

    override var canvasSize: CanvasSize { .square(512) }

    override func draw() {
        background(.black)
        let marks = renderTarget()
        withTarget(marks) {
            noStroke()
            switch subject {
            case .bare, .grown, .inside:
                fill(.white)
                drawCircle(256, 256, 100)
            case .empty:
                break
            case .nearestDot:
                for dot in FieldProbe.dots {
                    fill(dot.color)
                    drawCircle(dot.center.x, dot.center.y, 26)
                }
            }
        }
        switch subject {
        case .bare:
            drawImage(marks.image, 0, 0)
        case .inside:
            let field = marks.filtered(.distanceField())
            drawImage(field.filtered(.fieldMap(Ramp([.white, .black]),
                                               from: 0, to: 0.001)).image, 0, 0)
        case let .grown(offset, cap):
            let field = marks.filtered(.distanceField(maxDistance: cap))
            drawImage(field.filtered(.fieldMap(Ramp([.white, .black]),
                                               from: offset - 0.5, to: offset + 0.5)).image, 0, 0)
        case .empty:
            let field = marks.filtered(.distanceField())
            drawImage(field.filtered(.fieldMap(Ramp([.white, .black]), from: 0, to: 40)).image, 0, 0)
        case .nearestDot:
            let field = marks.filtered(.distanceField())
            drawImage(field.combined(with: marks, .shader(Shader(FieldProbe.nearest))).image, 0, 0)
        }
    }

    /// Walk to the nearest edge and keep going a little, so the lookup lands inside the
    /// shape rather than on its antialiased rim. Signing the overshoot is what makes one
    /// line serve both sides: from outside the direction already points inward.
    static let nearest = """
    float4 shade(float2 uv, ShaderInfo info) {
        float4 field = sampleRaw(info, uv);
        float2 here = uv * info.resolution;
        float2 inside = here + field.gb * (abs(field.r) + 3.0 * sign(field.r));
        return sampleAux(info, inside / info.resolution);
    }
    """
}
