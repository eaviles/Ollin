@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// Render checks on `.shock`, the coherence-enhancing filter.
///
/// Each one is a law the technique promises rather than a picture, because the filter
/// can look convincing while being wrong: a smoothing that runs across the flow
/// instead of along it still flattens, a shock with its sign turned still sharpens,
/// and a filter that invents colors still looks painterly. The laws:
///
/// - a flat tone is left alone, to the level;
/// - a soft edge gets narrower, and more rounds make it narrower still (the
///   counterfactual for the shock);
/// - a hard straight edge stays where it was, straight, in every row;
/// - the smoothing runs along the flow: noise along a line is averaged away while
///   the contrast between the line and the gap beside it is kept, which is only
///   true if the walk follows the line;
/// - a noisy edge straightens, and the noise on either side of it is calmed;
/// - no color is invented: a two-color picture keeps its two colors and loses the
///   blend between them;
/// - empty space on a transparent layer reads as paper and stays transparent.
@Suite
@MainActor
struct ShockFilterTests {

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

    private func render(_ subject: ShockProbe.Subject, filter: Filter?, size: Int = 128) throws -> CGImage {
        try #require(OllinApp.image(of: ShockProbe.make(subject, filter: filter, size: size), frame: 1))
    }

    /// The width, in columns, of the 10%…90% transition on one row of a picture that
    /// runs from `high` on the left to `low` on the right.
    private func transitionWidth(_ g: [UInt8], size: Int, row: Int, high: Int, low: Int) -> Int {
        let span = Double(high - low)
        let upper = Double(low) + 0.9 * span, lower = Double(low) + 0.1 * span
        var first: Int? = nil, last: Int? = nil
        for x in 0 ..< size {
            let v = Double(g[row * size + x])
            if first == nil && v < upper { first = x }
            if v > lower { last = x }
        }
        guard let first, let last else { return 0 }
        return max(last - first + 1, 0)
    }

    private func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }
    private func std(_ values: [Double]) -> Double {
        let m = mean(values)
        return (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(max(values.count, 1))).squareRoot()
    }

    @Test func aFlatToneIsLeftAlone() throws {
        let before = channel(try render(.flat(gray: 0.45), filter: nil), 1)
        let after = channel(try render(.flat(gray: 0.45), filter: .shock()), 1)
        let level = Int(before[before.count / 2])
        #expect(after.allSatisfy { abs(Int($0) - level) <= 2 },
                "a flat tone stays at its level: \(after.min()!)…\(after.max()!) against \(level)")
    }

    @Test func aSoftEdgeGetsNarrowerAndMoreRoundsNarrowIt() throws {
        let size = 128
        let plain = channel(try render(.ramp, filter: nil, size: size), 1)
        let once = channel(try render(.ramp, filter: .shock(iterations: 1), size: size), 1)
        let thrice = channel(try render(.ramp, filter: .shock(iterations: 3), size: size), 1)
        let high = Int(plain[size / 2 * size + 4]), low = Int(plain[size / 2 * size + size - 5])
        #expect(high - low > 100, "the probe's two tones are far apart: \(high) and \(low)")

        let rows = [20, 48, 64, 80, 108]
        let before = mean(rows.map { Double(transitionWidth(plain, size: size, row: $0, high: high, low: low)) })
        let after1 = mean(rows.map { Double(transitionWidth(once, size: size, row: $0, high: high, low: low)) })
        let after3 = mean(rows.map { Double(transitionWidth(thrice, size: size, row: $0, high: high, low: low)) })
        #expect(before >= 14, "the ramp is soft to begin with: \(before) columns")
        #expect(after1 < before - 2, "one round narrows it: \(before) -> \(after1)")
        #expect(after3 < after1 - 2, "three rounds narrow it further: \(after1) -> \(after3)")
        #expect(after3 <= before * 0.6, "three rounds take it well under the original: \(before) -> \(after3)")

        // Far from the edge the tones are untouched.
        for x in [4, 12, size - 12, size - 5] {
            let column = (0 ..< size).map { Int(thrice[$0 * size + x]) }
            let expected = x < size / 2 ? high : low
            #expect(column.allSatisfy { abs($0 - expected) <= 2 }, "column \(x) keeps its tone")
        }
    }

    @Test func aHardStraightEdgeStaysWhereItWas() throws {
        let size = 128
        let plain = channel(try render(.step, filter: nil, size: size), 1)
        let after = channel(try render(.step, filter: .shock(), size: size), 1)
        let high = Int(plain[size / 2 * size + 4]), low = Int(plain[size / 2 * size + size - 5])
        let mid = (high + low) / 2
        func edge(_ g: [UInt8], row: Int) -> Int? { (0 ..< size).first { Int(g[row * size + $0]) < mid } }
        let before = edge(plain, row: size / 2)!
        for row in stride(from: 2, to: size - 2, by: 3) {
            let x = edge(after, row: row)
            #expect(x != nil && abs(x! - before) <= 1, "row \(row): the edge is at \(String(describing: x)), was \(before)")
        }
    }

    @Test func theSmoothingRunsAlongTheFlow() throws {
        let size = 128
        let plain = channel(try render(.noisyLines, filter: nil, size: size), 1)
        let after = channel(try render(.noisyLines, filter: .shock(), size: size), 1)
        // The lines are 3 columns wide every 12, starting at column 4; read the middle
        // column of each line and the middle of each gap, over the inner rows.
        let rows = Array(16 ..< size - 16)
        func alongLineStd(_ g: [UInt8]) -> Double {
            mean(stride(from: 5, to: size - 6, by: 12).map { x in
                std(rows.map { Double(g[$0 * size + x]) })
            })
        }
        func contrast(_ g: [UInt8]) -> Double {
            let line = mean(stride(from: 5, to: size - 6, by: 12).flatMap { x in rows.map { Double(g[$0 * size + x]) } })
            let gap = mean(stride(from: 11, to: size - 6, by: 12).flatMap { x in rows.map { Double(g[$0 * size + x]) } })
            return gap - line
        }
        let noiseBefore = alongLineStd(plain), noiseAfter = alongLineStd(after)
        #expect(noiseBefore > 8, "the lines have to be noisy for the law to mean anything: \(noiseBefore)")
        #expect(noiseAfter < noiseBefore * 0.5, "the noise along a line is averaged away: \(noiseBefore) -> \(noiseAfter)")
        let contrastBefore = contrast(plain), contrastAfter = contrast(after)
        #expect(contrastAfter > contrastBefore * 0.8,
                "the line keeps its contrast against the gap, so nothing was smoothed across: \(contrastBefore) -> \(contrastAfter)")
    }

    @Test func aNoisyEdgeStraightensAndItsSidesCalmDown() throws {
        let size = 128
        let plain = channel(try render(.noisyEdge, filter: nil, size: size), 1)
        let after = channel(try render(.noisyEdge, filter: .shock(), size: size), 1)
        let band = (size / 2 - 12) ... (size / 2 + 12)
        let high = mean((8 ..< size - 8).flatMap { y in (8 ..< 40).map { x in Double(plain[y * size + x]) } })
        let low = mean((8 ..< size - 8).flatMap { y in (size - 40 ..< size - 8).map { x in Double(plain[y * size + x]) } })
        let midpoint = UInt8((high + low) / 2)

        /// Where the tone first drops under the midpoint on each row, within the band.
        func starts(_ g: [UInt8]) -> [Int?] {
            (0 ..< size).map { y in band.first { x in g[y * size + x] < midpoint } }
        }
        func jitter(_ s: [Int?]) -> Double {
            var total = 0.0, pairs = 0.0
            for y in 1 ..< s.count {
                if let a = s[y - 1], let b = s[y] { total += Double(abs(a - b)); pairs += 1 }
            }
            return total / max(pairs, 1)
        }
        let a = starts(plain), b = starts(after)
        #expect(jitter(a) > 1, "the noisy edge is ragged to begin with: \(jitter(a))")
        #expect(jitter(b) < jitter(a) / 2, "the edge straightens: \(jitter(a)) -> \(jitter(b))")

        // The noise on the light side, well away from the edge, is calmed.
        func sideStd(_ g: [UInt8]) -> Double {
            std((8 ..< size - 8).flatMap { y in (8 ..< 40).map { x in Double(g[y * size + x]) } })
        }
        #expect(sideStd(after) < sideStd(plain) * 0.6, "the flat side calms: \(sideStd(plain)) -> \(sideStd(after))")
    }

    @Test func noColorIsInvented() throws {
        let size = 128
        // The probe's two colors as display bytes: pure red, and a blue dark enough
        // that the brightness steps by half the scale between them.
        let blueByte = 64
        func counts(_ image: CGImage) -> (reds: Int, blues: Int, mixed: Int, maxGreen: Int) {
            let data = pixels(of: image)
            var reds = 0, blues = 0, mixed = 0, maxGreen = 0
            for i in 0 ..< size * size {
                let r = Int(data[i * 4]), g = Int(data[i * 4 + 1]), b = Int(data[i * 4 + 2])
                maxGreen = max(maxGreen, g)
                if r > 235 && b < 20 { reds += 1 }
                else if r < 20 && abs(b - blueByte) <= 20 { blues += 1 }
                else { mixed += 1 }
            }
            return (reds, blues, mixed, maxGreen)
        }
        let before = counts(try render(.twoColors, filter: nil, size: size))
        let after = counts(try render(.twoColors, filter: .shock(), size: size))
        #expect(before.mixed > size * 6, "the probe has a wide blend to begin with: \(before.mixed) mixed pixels")
        #expect(before.maxGreen <= 8, "the probe's own blend holds no green: \(before.maxGreen)")
        #expect(after.mixed < before.mixed / 2, "the blend narrows: \(before.mixed) -> \(after.mixed)")
        #expect(after.reds > 0 && after.blues > 0, "both colors survive")
        #expect(after.maxGreen <= 8, "red and blue never make green: \(after.maxGreen)")
    }

    @Test func emptySpaceReadsAsPaperAndStaysTransparent() throws {
        let size = 128
        let image = try render(.disc, filter: .shock(), size: size)
        let data = pixels(of: image)
        for (x, y) in [(3, 3), (size - 4, 3), (3, size - 4), (size - 4, size - 4)] {
            let i = (y * size + x) * 4
            #expect(data[i] >= 240 && data[i + 1] <= 8 && data[i + 2] >= 240,
                    "the corner at \(x), \(y) shows the ground through the layer")
        }
        // The disc keeps its footprint: the gray count within the disc barely moves.
        let plain = channel(try render(.disc, filter: nil, size: size), 1)
        let after = channel(image, 1)
        let mid = size / 2
        func grayRun(_ g: [UInt8]) -> Int { (0 ..< size).filter { g[mid * size + $0] < 200 }.count }
        #expect(abs(grayRun(after) - grayRun(plain)) <= 3, "the disc's width holds: \(grayRun(plain)) -> \(grayRun(after))")
    }
}

private final class ShockProbe: Sketch {
    enum Subject {
        /// One flat tone.
        case flat(gray: Double)
        /// White on the left and a dark gray on the right, joined by a 24-column ramp.
        case ramp
        /// The same two tones meeting at a hard edge.
        case step
        /// Dark vertical lines on light paper, every pixel of each line jittered.
        case noisyLines
        /// A light and a mid gray meeting at the middle, under per-pixel noise.
        case noisyEdge
        /// Red on the left, a dark blue on the right, a 16-column blend between.
        case twoColors
        /// A gray disc on an otherwise empty layer.
        case disc
    }

    var subject: Subject = .flat(gray: 0.5)
    var filter: Filter? = nil
    var size = 128

    static func make(_ subject: Subject, filter: Filter?, size: Int) -> ShockProbe {
        let probe = ShockProbe()
        probe.subject = subject
        probe.filter = filter
        probe.size = size
        return probe
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        // Magenta, so a transparent layer shows as something no gray could be.
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
        let mid = s / 2
        noStroke()
        switch subject {
        case let .flat(gray):
            background(Color(white: gray))
        case .ramp:
            // A smoothstep from white to the dark gray over 24 columns, mixed in
            // linear light column by column, so the profile bends everywhere and a
            // shock has curvature to read (a straight ramp only clips at its ends).
            background(.white)
            fill(Color(white: 0.15))
            drawRect(mid + 12, 0, mid - 12, s)
            for i in 0 ..< 24 {
                let u = (Double(i) + 0.5) / 24
                let t = u * u * (3 - 2 * u)
                fill(Color(white: 1 + (0.15 - 1) * t))
                drawRect(mid - 12 + Double(i), 0, 1, s)
            }
        case .step:
            background(.white)
            fill(Color(white: 0.15))
            drawRect(mid, 0, mid, s)
        case .noisyLines:
            background(Color(white: 0.85))
            seed(7)
            for x in stride(from: 4, to: size - 6, by: 12) {
                for y in 0 ..< size {
                    for dx in 0 ..< 3 {
                        fill(Color(white: 0.25 + random(-0.2, 0.2)))
                        drawRect(Double(x + dx), Double(y), 1, 1)
                    }
                }
            }
        case .noisyEdge:
            seed(11)
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let base = x < size / 2 ? 0.7 : 0.4
                    fill(Color(white: base + random(-0.2, 0.2)))
                    drawRect(Double(x), Double(y), 1, 1)
                }
            }
        case .twoColors:
            // Red to blue over 32 columns as a smoothstep mixed in linear light, so
            // the blend itself holds no green.
            let blue = Color(red: 0, green: 0, blue: 0.25)
            background(.red)
            fill(blue)
            drawRect(mid + 8, 0, mid - 8, s)
            for i in 0 ..< 16 {
                let u = (Double(i) + 0.5) / 16
                let t = u * u * (3 - 2 * u)
                fill(Color(red: 1 - t, green: 0, blue: 0.25 * t))
                drawRect(mid - 8 + Double(i), 0, 1, s)
            }
        case .disc:
            fill(Color(white: 0.5))
            drawCircle(mid, mid, s * 0.3)
        }
    }
}
