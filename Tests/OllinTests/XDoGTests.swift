@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// Render checks on `.xdog`, the flow-based difference of Gaussians.
///
/// Each one is a law the technique promises rather than a picture, because the filter
/// can look convincing while being wrong in ways a snapshot's mean hides: a cut that
/// lands on the wrong scale still draws lines, a walk that crosses the edge instead of
/// following it still draws lines, and empty space read as ink looks like a design
/// choice. The laws:
///
/// - a flat tone is paper or ink by the threshold alone, and the soft cut is the
///   published tanh ramp to the level;
/// - an edge draws a line on its dark side and nothing far from it, and with no
///   sharpening there is no line at all (the counterfactual for the edge term);
/// - along a straight edge the response is constant, so gathering it along the flow
///   changes nothing, which is only true if the walk follows the edge;
/// - on a noisy edge the flow straightens the ragged line and mends its breaks;
/// - the ink and the paper are the colors given;
/// - empty space on a transparent layer reads as paper, and a transparent paper stays
///   transparent in the result.
@Suite
@MainActor
struct XDoGTests {

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
    private func channel(_ image: CGImage, _ c: Int) -> [UInt8] {
        let data = pixels(of: image)
        return (0 ..< image.width * image.height).map { data[$0 * 4 + c] }
    }

    private func render(_ subject: XDoGProbe.Subject, size: Int = 128) throws -> CGImage {
        try #require(OllinApp.image(of: XDoGProbe.make(subject, size: size), frame: 1))
    }

    /// A linear-light value as the byte a display shows it at.
    private static func srgbByte(_ v: Double) -> Int {
        let c = min(max(v, 0), 1)
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return Int((s * 255).rounded())
    }

    /// The pixels within `band` of the circle of radius `r` about the middle.
    private func ring(_ values: [UInt8], size: Int, radius r: Double, band: Double) -> [UInt8] {
        var out: [UInt8] = []
        let mid = Double(size) / 2
        for y in 0 ..< size {
            for x in 0 ..< size {
                let d = (Vector2(Double(x) + 0.5, Double(y) + 0.5) - Vector2(mid, mid)).length
                if abs(d - r) <= band { out.append(values[y * size + x]) }
            }
        }
        return out
    }

    @Test func aFlatToneIsCutByTheThresholdAlone() throws {
        let paper = channel(try render(.flat(gray: 0.6, softness: 0)), 1)
        #expect(paper.allSatisfy { $0 >= 250 }, "a tone above the threshold is paper everywhere")
        let ink = channel(try render(.flat(gray: 0.1, softness: 0)), 1)
        #expect(ink.allSatisfy { $0 <= 3 }, "a tone below it, under a hard cut, is ink everywhere")
    }

    @Test func theSoftCutIsThePublishedRampToTheLevel() throws {
        // A gray of 0.1 sits 0.2 under the default threshold of 0.3, so with the default
        // softness of 0.2 the cut is 1 + tanh(-1) in linear light, everywhere.
        let expected = XDoGTests.srgbByte(1 + tanh((0.1 - 0.3) / 0.2))
        let tone = channel(try render(.flat(gray: 0.1, softness: 0.2)), 1)
        let lo = Int(tone.min()!), hi = Int(tone.max()!)
        #expect(abs(lo - expected) <= 3 && abs(hi - expected) <= 3,
                "expected \(expected) everywhere, got \(lo)…\(hi)")
    }

    @Test func anEdgeDrawsALineOnItsDarkSideAndNothingFarFromIt() throws {
        let size = 128
        let g = channel(try render(.edge(sharpening: 20, flow: 3), size: size), 1)
        func column(_ x: Int) -> [UInt8] { (0 ..< size).map { g[$0 * size + x] } }

        for x in [4, 20, 40, 88, 108, 124] {
            #expect(column(x).allSatisfy { $0 >= 240 }, "column \(x), far from the edge, is paper")
        }
        // The brighter side keeps its paper right up to the edge: the line is on the dark side.
        for x in 50 ... 60 {
            #expect(column(x).allSatisfy { $0 >= 240 }, "column \(x), on the bright side, is paper")
        }
        let inkRows = (62 ... 74).map { x in column(x).filter { $0 < 128 }.count }
        #expect(inkRows.max()! >= size - 2, "some column on the dark side is ink in every row")

        // With no sharpening the edge term is gone, and both tones sit above the
        // threshold, so nothing is drawn.
        let plain = channel(try render(.edge(sharpening: 0, flow: 3), size: size), 1)
        #expect(plain.allSatisfy { $0 >= 240 })
    }

    @Test func aStraightEdgeGathersNothingAlongTheFlow() throws {
        let still = channel(try render(.edge(sharpening: 20, flow: 0)), 1)
        let flowing = channel(try render(.edge(sharpening: 20, flow: 6)), 1)
        let diff = zip(still, flowing).map { abs(Int($0) - Int($1)) }
        let mean = Double(diff.reduce(0, +)) / Double(diff.count)
        #expect(mean < 0.5, "mean difference \(mean)")
        #expect(diff.max()! <= 8, "largest difference \(diff.max()!)")
    }

    @Test func theFlowMendsAndStraightensANoisyLine() throws {
        let size = 128
        let still = channel(try render(.noisy(flow: 0), size: size), 1)
        let flowing = channel(try render(.noisy(flow: 6), size: size), 1)
        let band = (size / 2 - 4) ... (size / 2 + 10)

        /// Where the line starts on each row (the first pixel visibly darker than the
        /// paper), or nil where the row has no ink in the band. Under noise the line
        /// thins to a gray hair in places, so the cut is "visibly inked", not "black".
        func starts(_ g: [UInt8]) -> [Int?] {
            (0 ..< size).map { y in band.first { x in g[y * size + x] < 200 } }
        }
        func breaks(_ s: [Int?]) -> Int { s.filter { $0 == nil }.count }
        /// How far the line's edge moves from one inked row to the next, on average.
        func jitter(_ s: [Int?]) -> Double {
            var total = 0.0, pairs = 0.0
            for y in 1 ..< s.count {
                if let a = s[y - 1], let b = s[y] { total += Double(abs(a - b)); pairs += 1 }
            }
            return total / max(pairs, 1)
        }

        let a = starts(still), b = starts(flowing)
        #expect(jitter(a) > 0.3,
                "the still line has to be ragged for the law to mean anything: \(jitter(a))")
        #expect(jitter(b) < jitter(a) / 2, "the flow straightens it: \(jitter(a)) -> \(jitter(b))")
        #expect(breaks(b) <= 2 && breaks(b) <= breaks(a),
                "under the flow the line runs the whole height: \(breaks(a)) -> \(breaks(b)) rows without ink")
    }

    @Test func inkAndPaperAreTheColorsGiven() throws {
        let image = try render(.colors)
        let data = pixels(of: image)
        var maxGreen: UInt8 = 0, reds = 0, blues = 0
        for i in 0 ..< image.width * image.height {
            let r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2]
            maxGreen = max(maxGreen, g)
            if r > 200 && b < 60 { reds += 1 }
            if b > 200 && r < 60 { blues += 1 }
        }
        #expect(maxGreen <= 6, "red ink on blue paper has no green anywhere")
        #expect(reds > 0 && blues > 0, "both the ink and the paper appear")
    }

    @Test func emptySpaceReadsAsPaperNotInk() throws {
        let size = 128
        let corners = [(3, 3), (size - 4, 3), (3, size - 4), (size - 4, size - 4)]
        let r = Double(size) * 0.3

        let onWhite = channel(try render(.disc(paper: .white), size: size), 1)
        for (x, y) in corners {
            #expect(onWhite[y * size + x] >= 250, "the empty corner at \(x), \(y) is paper")
        }
        let rimInk = ring(onWhite, size: size, radius: r, band: 6).filter { $0 < 128 }.count
        #expect(rimInk > 100, "the disc's rim is drawn (\(rimInk) ink pixels)")

        // A transparent paper reads as white for the cut and stays transparent in the
        // result, so the sketch's magenta ground shows through the empty corners.
        let image = try render(.disc(paper: .clear), size: size)
        let data = pixels(of: image)
        for (x, y) in corners {
            let i = (y * size + x) * 4
            #expect(data[i] >= 240 && data[i + 1] <= 8 && data[i + 2] >= 240,
                    "the corner at \(x), \(y) shows the ground through a transparent paper")
        }
        let red = channel(image, 0)
        let rimInkOnClear = ring(red, size: size, radius: r, band: 6).filter { $0 < 60 }.count
        #expect(rimInkOnClear > 100, "the rim still inks over a transparent paper (\(rimInkOnClear))")
    }
}

private final class XDoGProbe: Sketch {
    enum Subject {
        /// One flat tone, cut with the given softness.
        case flat(gray: Double, softness: Double)
        /// White on the left, a 0.6 gray on the right, both above the threshold.
        case edge(sharpening: Double, flow: Double)
        /// The same edge under per-pixel noise, pinned by a seed.
        case noisy(flow: Double)
        /// The edge in red ink on blue paper.
        case colors
        /// A gray disc on an otherwise empty layer, over the given paper.
        case disc(paper: Color)
    }

    var subject: Subject = .colors
    var size = 128

    static func make(_ subject: Subject, size: Int) -> XDoGProbe {
        let probe = XDoGProbe()
        probe.subject = subject
        probe.size = size
        return probe
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        // Magenta, so a transparent paper shows as something no ink or paper could be.
        background(Color(red: 1, green: 0, blue: 1))
        let layer = makeRenderTarget()
        withTarget(layer) { paint() }

        let filter: Filter
        switch subject {
        case let .flat(_, softness):
            filter = .xdog(softness: softness)
        case let .edge(sharpening, flow):
            filter = .xdog(sharpening: sharpening, flow: flow)
        case .noisy(let flow):
            filter = .xdog(flow: flow)
        case .colors:
            filter = .xdog(foreground: .red, background: .blue)
        case .disc(let paper):
            filter = .xdog(background: paper)
        }
        drawImage(layer.filtered(filter).image, 0, 0)
    }

    private func paint() {
        let s = Double(size)
        noStroke()
        switch subject {
        case let .flat(gray, _):
            background(Color(white: gray))
        case .edge, .colors:
            background(.white)
            fill(Color(white: 0.6))
            drawRect(s / 2, 0, s / 2, s)
        case .noisy:
            seed(11)
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let base = x < size / 2 ? 0.8 : 0.5
                    fill(Color(white: base + random(-0.15, 0.15)))
                    drawRect(Double(x), Double(y), 1, 1)
                }
            }
        case .disc:
            fill(Color(white: 0.5))
            drawCircle(s / 2, s / 2, s * 0.3)
        }
    }
}
