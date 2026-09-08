@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// Render checks on `.hatching`, the pen filter whose strokes follow the picture.
///
/// Each one is a law the technique promises rather than a picture, because hatching
/// can look like hatching and be wrong: strokes laid at a fixed angle still read as
/// pen work, and a screen that ignores the tone still covers the page. The laws:
///
/// - the ink covers as much of the paper as the picture is dark, tone by tone;
/// - white paper is left bare and black is filled;
/// - the strokes run along the picture's flow: on a picture whose edges run one way
///   the marks run that way too, and turning the picture turns them (the
///   counterfactual for the walk);
/// - the spacing sets how fine the pen is: half the spacing, twice the strokes;
/// - a second direction crosses the first rather than thickening it;
/// - nothing but the two colors is on the page;
/// - empty space on a transparent layer counts as paper and can stay empty.
@Suite
@MainActor
struct HatchingFilterTests {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func channel(_ image: CGImage, _ c: Int) -> [UInt8] {
        let data = pixels(of: image)
        return (0 ..< image.width * image.height).map { data[$0 * 4 + c] }
    }

    private func render(_ subject: HatchProbe.Subject, filter: Filter?, size: Int = 160) throws -> CGImage {
        try #require(OllinApp.image(of: HatchProbe.make(subject, filter: filter, size: size), frame: 1))
    }

    private func linear(_ byte: UInt8) -> Double {
        let v = Double(byte) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// The share of the light a black ink took out of white paper, which is the
    /// share of the paper it covers however the edges of a mark are blended.
    private func coverage(_ image: CGImage, inset: Int = 8) -> Double {
        let g = channel(image, 1)
        let size = image.width
        var sum = 0.0, count = 0.0
        for y in inset ..< size - inset {
            for x in inset ..< size - inset {
                sum += linear(g[y * size + x])
                count += 1
            }
        }
        return 1 - sum / count
    }

    /// The mean step between neighbors one row apart and one column apart, over a
    /// band of the picture: a mark that runs down the page makes the first small
    /// and the second large.
    private func steps(_ image: CGImage, rows: Range<Int>, columns: Range<Int>) -> (down: Double, across: Double) {
        let g = channel(image, 1)
        let size = image.width
        var down = 0.0, across = 0.0, count = 0.0
        for y in rows {
            for x in columns {
                down += abs(Double(g[y * size + x]) - Double(g[(y + 1) * size + x]))
                across += abs(Double(g[y * size + x]) - Double(g[y * size + x + 1]))
                count += 1
            }
        }
        return (down / count, across / count)
    }

    /// How many separate runs of ink a scanline crosses.
    private func runs(_ image: CGImage, row: Int, inset: Int = 8) -> Int {
        let g = channel(image, 1)
        let size = image.width
        var count = 0
        var wasInk = false
        for x in inset ..< size - inset {
            let isInk = g[row * size + x] < 128
            if isInk && !wasInk { count += 1 }
            wasInk = isInk
        }
        return count
    }

    @Test func theInkCoversAsMuchAsThePictureIsDark() throws {
        for darkness in [0.25, 0.5, 0.75] {
            let image = try render(.flat(gray: 1 - darkness), filter: .hatching())
            let covered = coverage(image)
            #expect(abs(covered - darkness) < 0.05,
                    "a tone \(darkness) dark is covered \(covered)")
        }
    }

    @Test func paperStaysBareAndBlackFillsIn() throws {
        let white = coverage(try render(.flat(gray: 1), filter: .hatching()))
        let black = coverage(try render(.flat(gray: 0), filter: .hatching()))
        #expect(white < 0.03, "white paper keeps its light: \(white) covered")
        #expect(black > 0.9, "black fills in: \(black) covered")
    }

    @Test func theStrokesRunAlongTheFlow() throws {
        // A ramp across the page: its edges run down it, so the flow does too, and
        // the marks with it. Turned a quarter, everything turns with it. One
        // direction only, since a second would lay marks the other way on purpose.
        let down = try render(.ramp(vertical: false), filter: .hatching(directions: 1))
        let (a, b) = steps(down, rows: 20 ..< 140, columns: 20 ..< 140)
        #expect(a < b * 0.6, "marks run down the page: \(a) down against \(b) across")

        let across = try render(.ramp(vertical: true), filter: .hatching(directions: 1))
        let (c, d) = steps(across, rows: 20 ..< 140, columns: 20 ..< 140)
        #expect(d < c * 0.6, "turning the picture turns the marks: \(c) down against \(d) across")
    }

    @Test func theSpacingSetsHowFineThePenIs() throws {
        let fine = try render(.flat(gray: 0.55), filter: .hatching(spacing: 4, directions: 1))
        let broad = try render(.flat(gray: 0.55), filter: .hatching(spacing: 12, directions: 1))
        let rows = [40, 60, 80, 100, 120]
        let fineRuns = rows.map { runs(fine, row: $0) }.reduce(0, +)
        let broadRuns = rows.map { runs(broad, row: $0) }.reduce(0, +)
        #expect(fineRuns > broadRuns * 2,
                "a finer pen lays more strokes: \(fineRuns) against \(broadRuns)")
    }

    @Test func aSecondDirectionCrossesTheFirst() throws {
        // A tone dark enough that one direction has laid all it may. With one, the
        // marks still run down the page and a column of one is all alike; with two,
        // the layer over them runs across, which is a step from one row to the next
        // where there was none.
        let dark = 0.25
        let one = try render(.flat(gray: dark), filter: .hatching(directions: 1))
        let two = try render(.flat(gray: dark), filter: .hatching(directions: 2))
        let single = steps(one, rows: 20 ..< 140, columns: 20 ..< 140).down
        let crossed = steps(two, rows: 20 ..< 140, columns: 20 ..< 140).down
        #expect(crossed > single * 1.5,
                "the second direction crosses the first: \(single) down against \(crossed)")
        // And the tone is kept either way, since each layer takes on what the one
        // before it left.
        #expect(abs(coverage(one) - coverage(two)) < 0.06,
                "both reach the same tone: \(coverage(one)) against \(coverage(two))")
    }

    @Test func nothingButTheTwoColorsIsOnThePage() throws {
        let image = try render(.flat(gray: 0.5),
                               filter: .hatching(foreground: .red, background: .white))
        let data = pixels(of: image)
        let size = image.width
        var worst = 0
        for y in 8 ..< size - 8 {
            for x in 8 ..< size - 8 {
                let i = (y * size + x) * 4
                worst = max(worst, abs(Int(data[i + 1]) - Int(data[i + 2])))
                #expect(data[i] >= data[i + 1], "red ink never darkens the red channel")
            }
        }
        #expect(worst <= 2, "every pixel is red ink on white paper: green and blue differ by \(worst)")
    }

    @Test func emptySpaceCountsAsPaperAndCanStayEmpty() throws {
        // A dark disc on an otherwise empty layer, hatched onto no paper at all: the
        // strokes land on the disc and the rest of the layer stays transparent, which
        // the magenta the probe draws under it shows.
        let image = try render(.disc, filter: .hatching(background: .clear))
        let data = pixels(of: image)
        let size = image.width
        let corner = (4 * size + 4) * 4
        #expect(data[corner] > 200 && data[corner + 1] < 60 && data[corner + 2] > 200,
                "the corner is the magenta under the layer")
        let covered = coverage(image, inset: size / 2 - 12)
        #expect(covered > 0.3, "the disc itself is hatched: \(covered) covered at the middle")
    }
}

/// A small sketch that paints one subject into a layer, filters it, and draws the
/// result over magenta, so anything the filter leaves transparent shows as a color
/// no gray could be.
private final class HatchProbe: Sketch {
    enum Subject {
        /// One flat tone.
        case flat(gray: Double)
        /// A smooth ramp from light to dark across the page, or down it.
        case ramp(vertical: Bool)
        /// A dark disc on an otherwise empty layer.
        case disc
    }

    var subject: Subject = .flat(gray: 0.5)
    var filter: Filter? = nil
    var size = 160

    static func make(_ subject: Subject, filter: Filter?, size: Int) -> HatchProbe {
        let probe = HatchProbe()
        probe.subject = subject
        probe.filter = filter
        probe.size = size
        return probe
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
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
        case let .flat(gray):
            background(Color(white: gray))
        case let .ramp(vertical):
            background(.white)
            for i in 0 ..< size {
                let u = (Double(i) + 0.5) / s
                fill(Color(white: 0.85 - 0.55 * u))
                if vertical {
                    drawRect(0, Double(i), s, 1)
                } else {
                    drawRect(Double(i), 0, 1, s)
                }
            }
        case .disc:
            fill(Color(white: 0.35))
            drawCircle(s / 2, s / 2, s * 0.35)
        }
    }
}
