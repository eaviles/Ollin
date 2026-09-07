@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// Render checks on `.brushwork`, the anisotropic Kuwahara filter.
///
/// Each one is a law the technique promises rather than a picture, because a sector
/// filter can look painterly while being wrong in ways a snapshot's mean hides: a
/// brush that never stretches still flattens, a weighting that ignores the spread is
/// only a blur, and a tensor read off the wrong axis still turns something. The laws:
///
/// - a flat tone comes back as itself;
/// - a hard edge stays hard, with each side keeping its own tone, and with the
///   spread ignored (sharpness 0) the same edge blurs, which is the counterfactual for
///   the sector weighting;
/// - speckle on a flat tone is flattened away;
/// - fine stripes survive a brush drawn out along them and fade under a round one, so
///   the stretch follows the tensor's direction rather than any fixed axis;
/// - empty space on a transparent layer stays transparent and a shape keeps its tone;
/// - the same layer renders the same twice.
@Suite
@MainActor
struct BrushworkTests {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// One channel of every pixel as a display byte.
    private func channel(_ image: CGImage, _ c: Int) -> [Int] {
        let data = pixels(of: image)
        return (0 ..< image.width * image.height).map { Int(data[$0 * 4 + c]) }
    }

    private func render(_ subject: BrushworkProbe.Subject, _ filter: Filter?,
                        size: Int = 96) throws -> CGImage {
        try #require(OllinApp.image(of: BrushworkProbe.make(subject, filter: filter, size: size),
                                    frame: 1))
    }

    /// The byte a `Color(white:)` value shows as: the components are already the
    /// display's own encoding.
    private static func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }

    private func mean(_ v: [Int]) -> Double { Double(v.reduce(0, +)) / Double(max(v.count, 1)) }

    private func stddev(_ v: [Int]) -> Double {
        let m = mean(v)
        return (v.reduce(0.0) { $0 + (Double($1) - m) * (Double($1) - m) } / Double(max(v.count, 1))).squareRoot()
    }

    /// The mean of one channel down each column, the middle rows only, so the edge
    /// of the canvas never enters a measurement.
    private func columnMeans(_ image: CGImage, _ c: Int) -> [Double] {
        let w = image.width, h = image.height
        let v = channel(image, c)
        return (0 ..< w).map { x in
            mean((h / 4 ..< 3 * h / 4).map { v[$0 * w + x] })
        }
    }

    @Test func aFlatToneComesBackAsItself() throws {
        let tone = channel(try render(.flat(gray: 0.5), .brushwork()), 1)
        let expected = BrushworkTests.byte(0.5)
        #expect(tone.allSatisfy { abs($0 - expected) <= 1 },
                "a flat tone is its own average (\(tone.min()!)...\(tone.max()!) against \(expected))")
    }

    @Test func aHardEdgeStaysHardAndBlursOnlyWhenTheSpreadIsIgnored() throws {
        let dark = BrushworkTests.byte(0.25), light = BrushworkTests.byte(0.75)
        func transition(_ image: CGImage) -> (width: Int, left: Double, right: Double) {
            let cols = columnMeans(image, 1)
            let w = cols.count
            let between = cols.filter { $0 > Double(dark) + 4 && $0 < Double(light) - 4 }.count
            return (between, mean(cols[8 ..< w / 2 - 8].map { Int($0.rounded()) }),
                    mean(cols[w / 2 + 8 ..< w - 8].map { Int($0.rounded()) }))
        }
        let kept = transition(try render(.edge, .brushwork()))
        #expect(kept.width <= 2, "the edge stays within two columns (\(kept.width))")
        #expect(abs(kept.left - Double(dark)) <= 1.5 && abs(kept.right - Double(light)) <= 1.5,
                "each side keeps its tone (\(kept.left), \(kept.right))")
        // With every sector weighted alike the brush is only a Gaussian, and the edge
        // spreads across it: the counterfactual for the spread-based weighting.
        let blurred = transition(try render(.edge, .brushwork(sharpness: 0)))
        #expect(blurred.width >= 4 && blurred.width > kept.width + 2,
                "with the spread ignored the edge blurs (\(blurred.width) against \(kept.width))")
    }

    @Test func speckleIsFlattenedAway() throws {
        let raw = stddev(channel(try render(.noisy, nil), 1))
        let painted = stddev(channel(try render(.noisy, .brushwork()), 1))
        #expect(raw > 12, "the probe carries real speckle (\(raw))")
        #expect(painted < raw / 2.5, "the speckle is flattened (\(painted) against \(raw))")
    }

    @Test func stripesSurviveABrushDrawnOutAlongThem() throws {
        // Vertical stripes three texels wide under speckle: a brush drawn out along
        // them reads each stripe as its own flat sector, a round one straddles them.
        func contrast(_ image: CGImage) -> Double {
            let cols = columnMeans(image, 1)
            let lit = stride(from: 8, to: cols.count - 8, by: 1).filter { ($0 / 3) % 2 == 1 }.map { cols[$0] }
            let dim = stride(from: 8, to: cols.count - 8, by: 1).filter { ($0 / 3) % 2 == 0 }.map { cols[$0] }
            return lit.reduce(0, +) / Double(lit.count) - dim.reduce(0, +) / Double(dim.count)
        }
        let raw = contrast(try render(.stripes, nil))
        let stretched = contrast(try render(.stripes, .brushwork(stretch: 4)))
        let round = contrast(try render(.stripes, .brushwork(stretch: 1)))
        #expect(raw > 40, "the probe carries real stripes (\(raw))")
        #expect(stretched > 0.6 * raw, "stripes survive the stretched brush (\(stretched) of \(raw))")
        #expect(stretched > 1.3 * round, "and fade under the round one (\(round) against \(stretched))")
    }

    @Test func emptySpaceStaysEmptyAndAShapeKeepsItsTone() throws {
        let image = try render(.disc, .brushwork())
        let data = pixels(of: image)
        let w = image.width
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
        // The corner is far from the disc: the magenta ground shows through untouched.
        let corner = rgb(2, 2)
        #expect(corner.0 >= 254 && corner.1 <= 1 && corner.2 >= 254,
                "empty space stays transparent (\(corner))")
        let middle = rgb(w / 2, w / 2)
        let gray = BrushworkTests.byte(0.5)
        #expect(abs(middle.0 - gray) <= 1 && abs(middle.1 - gray) <= 1 && abs(middle.2 - gray) <= 1,
                "the disc keeps its tone (\(middle) against \(gray))")
    }

    @Test func theSameLayerRendersTheSameTwice() throws {
        let a = pixels(of: try render(.stripes, .brushwork()))
        let b = pixels(of: try render(.stripes, .brushwork()))
        #expect(a == b)
    }
}

private final class BrushworkProbe: Sketch {
    enum Subject {
        /// One flat tone.
        case flat(gray: Double)
        /// A 0.25 gray on the left, 0.75 on the right.
        case edge
        /// A 0.5 gray under per-pixel speckle, pinned by a seed.
        case noisy
        /// Vertical stripes three texels wide (0.3 and 0.7) under lighter speckle.
        case stripes
        /// A 0.5 gray disc on an otherwise empty layer.
        case disc
    }

    var subject: Subject = .flat(gray: 0.5)
    var filter: Filter?
    var size = 96

    static func make(_ subject: Subject, filter: Filter?, size: Int) -> BrushworkProbe {
        let probe = BrushworkProbe()
        probe.subject = subject
        probe.filter = filter
        probe.size = size
        return probe
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        // Magenta, so transparency shows as something no gray could be.
        background(Color(red: 1, green: 0, blue: 1))
        let layer = makeRenderTarget()
        withTarget(layer) { paint() }
        if let filter {
            drawImage(layer.filtered(filter).image, 0, 0)
        } else {
            drawImage(layer.image, 0, 0)
        }
    }

    private func paint() {
        let s = Double(size)
        noStroke()
        switch subject {
        case .flat(let gray):
            background(Color(white: gray))
        case .edge:
            background(Color(white: 0.25))
            fill(Color(white: 0.75))
            drawRect(s / 2, 0, s / 2, s)
        case .noisy:
            seed(11)
            for y in 0 ..< size {
                for x in 0 ..< size {
                    fill(Color(white: 0.5 + random(-0.15, 0.15)))
                    drawRect(Double(x), Double(y), 1, 1)
                }
            }
        case .stripes:
            seed(23)
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let base = (x / 3) % 2 == 1 ? 0.7 : 0.3
                    fill(Color(white: base + random(-0.06, 0.06)))
                    drawRect(Double(x), Double(y), 1, 1)
                }
            }
        case .disc:
            fill(Color(white: 0.5))
            drawCircle(s / 2, s / 2, s * 0.32)
        }
    }
}
