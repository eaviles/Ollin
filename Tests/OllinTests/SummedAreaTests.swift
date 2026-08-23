@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// Render checks on the two filters that ride on a summed-area table: `.boxBlur` and
/// `.adaptiveThreshold`.
///
/// Each one is checked against a law rather than against a picture, because both of them
/// can look completely convincing while being wrong. A box average that is off by a few
/// percent still reads as a blur, and a threshold that has quietly stopped adapting still
/// reads as lettering until the light moves. The three laws:
///
/// - the average a box lookup reports is the average of the texels it stands for, which
///   is checked against a table built independently on the CPU in `Double`;
/// - a flat field stays flat at every window size, which is where a table's precision
///   shows first, since the sums are largest and the answer is known exactly;
/// - turning the light down changes nothing the local cut decides, which is the whole
///   reason the technique exists and is a property a global cut provably does not have.
///   That last one carries its own counterfactual: the same test run against
///   `.threshold` has to fail, or it is not testing what it claims to.
@Suite
@MainActor
struct SummedAreaTests {

    private static let toLinear: [Double] = (0 ..< 256).map { i in
        let c = Double(i) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func toSRGB(_ v: Double) -> Double {
        let c = min(max(v, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
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

    /// The green channel of every pixel, in linear light. Green alone because the probes
    /// below are drawn in grays, and one channel is enough to compare fields with.
    private func linearGreen(_ image: CGImage) -> [Double] {
        let data = pixels(of: image)
        return (0 ..< image.width * image.height).map {
            SummedAreaTests.toLinear[Int(data[$0 * 4 + 1])]
        }
    }

    private func render(_ subject: SumProbe.Subject, size: Int = 256) throws -> CGImage {
        try #require(OllinApp.image(of: SumProbe.make(subject, size: size), frame: 1))
    }

    /// A summed-area table built on the CPU in `Double`, and the box average read off it.
    /// This is the reference the GPU table is measured against: the same algorithm with
    /// no precision question hanging over it.
    private func boxAverages(_ field: [Double], width w: Int, height h: Int,
                             radius r: Int) -> [Double] {
        var table = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0 ..< h {
            var row = 0.0
            for x in 0 ..< w {
                row += field[y * w + x]
                table[(y + 1) * (w + 1) + x + 1] = table[y * (w + 1) + x + 1] + row
            }
        }
        func sum(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Double {
            table[(y1 + 1) * (w + 1) + x1 + 1] - table[y0 * (w + 1) + x1 + 1]
                - table[(y1 + 1) * (w + 1) + x0] + table[y0 * (w + 1) + x0]
        }
        var out = [Double](repeating: 0, count: w * h)
        for y in 0 ..< h {
            for x in 0 ..< w {
                let x0 = max(0, x - r), y0 = max(0, y - r)
                let x1 = min(w - 1, x + r), y1 = min(h - 1, y + r)
                let area = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                out[y * w + x] = sum(x0, y0, x1, y1) / area
            }
        }
        return out
    }

    /// The average a box lookup reports must be the average of the texels it stands for.
    ///
    /// The marks are rendered once bare and once blurred, and the bare rendering is then
    /// blurred again on the CPU through a table built in `Double`. The two blurs are
    /// compared in 8-bit sRGB, which is the form both of them are read back in, so the
    /// error budget is the 8-bit round trip and the present pass's dither rather than
    /// anything the filter does.
    @Test func aBoxAverageIsTheAverageItStandsFor() throws {
        let radius = 12
        let bare = try render(.marks)
        let blurred = try render(.blurred(radius: Double(radius)))
        let w = bare.width, h = bare.height

        let reference = boxAverages(linearGreen(bare), width: w, height: h, radius: radius)
        let measured = linearGreen(blurred)

        var worst = 0.0, total = 0.0
        for i in 0 ..< w * h {
            let d = abs(SummedAreaTests.toSRGB(reference[i]) - SummedAreaTests.toSRGB(measured[i]))
            worst = max(worst, d)
            total += d
        }
        let mean = total / Double(w * h) * 255
        #expect(mean < 0.6, "mean box-average error \(mean)/255")
        #expect(worst * 255 < 4, "worst box-average error \(worst * 255)/255")
    }

    /// A flat field has to stay flat, at every working window size, everywhere including
    /// the border.
    ///
    /// The border is part of the claim rather than a detail. A window that hangs over the
    /// edge is clamped and divided by the area it really covered, so the edges keep their
    /// brightness; dividing by the area that was asked for instead would darken every
    /// border by the fraction that fell outside, which at a large radius is most of it.
    ///
    /// Both tones matter, and a mid-gray one would not. Elements go into the table biased
    /// by -0.5, so a tone whose linear value is near a half goes in as near zero, its sums
    /// stay tiny, and an error in the *area* they are divided by barely moves the answer.
    /// A probe at that tone is nearly blind to exactly the mistake this test is here to
    /// catch (sabotaged, it reported 3/255 where the tones below report 7). The two here
    /// sit at the ends instead, where the sums are largest.
    @Test(arguments: [37.0, 240.0], [0.25, 1.0])
    func aFlatFieldStaysFlat(radius: Double, gray: Double) throws {
        let image = try render(.flat(gray: gray, radius: radius), size: 1024)
        #expect(driftOffFlat(image, gray: gray) * 255 < 1.5,
                "gray \(gray) at radius \(radius) drifted off flat")
    }

    /// What the table costs, measured rather than asserted away.
    ///
    /// A running total spends about `log2(width * height)` bits of a mantissa on itself, so
    /// a box sum is a difference between large numbers and carries roughly four times their
    /// spacing as error. That error is *absolute*, so what a reader of the table sees is
    /// that error divided by the area asked for: it falls as the window grows. A 1024
    /// square canvas of a dark tone puts about 7/255 into a 3x3 window and under 1.5/255
    /// into anything from 37 pixels up, which is the whole of the range this filter exists
    /// for. This test pins the small end so a change that makes it worse is caught, and it
    /// is also the number quoted in the filter's own documentation.
    @Test func theTableSpendsItsPrecisionOnTheRunningTotal() throws {
        let tight = driftOffFlat(try render(.flat(gray: 0.25, radius: 1), size: 1024),
                                 gray: 0.25) * 255
        let wide = driftOffFlat(try render(.flat(gray: 0.25, radius: 240), size: 1024),
                                gray: 0.25) * 255
        #expect(tight < 10, "a 3x3 window drifted \(tight)/255, past the documented bound")
        #expect(wide < tight, "the error is meant to fall as the window grows")
    }

    /// How far the worst pixel of a rendering sits from the flat tone it should be, in
    /// sRGB, where the eye and the 8-bit readback both live.
    private func driftOffFlat(_ image: CGImage, gray: Double) -> Double {
        let target = SummedAreaTests.toSRGB(SummedAreaTests.toLinear[Int((gray * 255).rounded())])
        return linearGreen(image).reduce(0.0) {
            max($0, abs(SummedAreaTests.toSRGB($1) - target))
        }
    }

    /// Turning the light down must not change one pixel of what the local cut decides.
    ///
    /// Light falling on a page multiplies what comes back off it, so a cut that is a
    /// fraction of the local average is invariant under it and a cut at a fixed value is
    /// not. That is the entire reason the technique exists, and it is a theorem rather
    /// than a preference, so it is worth pinning as one. The comparison is made in linear
    /// light, where a change in illumination really is a plain scale.
    @Test func theLocalCutIgnoresHowBrightTheLightIs() throws {
        let bright = linearGreen(try render(.localCut(gain: 1.0)))
        let dim = linearGreen(try render(.localCut(gain: 0.4)))
        var differing = 0
        for i in 0 ..< bright.count where abs(bright[i] - dim[i]) > 0.05 { differing += 1 }
        let fraction = Double(differing) / Double(bright.count)
        #expect(fraction < 0.005, "the local cut moved on \(fraction * 100)% of the page")
    }

    /// The counterfactual for the test above: a global cut has to fail it. Without this
    /// the invariance test would pass just as happily against a filter that had stopped
    /// looking at the image at all.
    @Test func aGlobalCutDoesNotIgnoreIt() throws {
        let bright = linearGreen(try render(.globalCut(gain: 1.0)))
        let dim = linearGreen(try render(.globalCut(gain: 0.4)))
        var differing = 0
        for i in 0 ..< bright.count where abs(bright[i] - dim[i]) > 0.05 { differing += 1 }
        let fraction = Double(differing) / Double(bright.count)
        #expect(fraction > 0.2, "the global cut only moved on \(fraction * 100)% of the page")
    }
}

/// The layers the checks above are measured on. Everything is drawn in grays and with no
/// motion, so a rendering is a function of its subject alone.
private final class SumProbe: Sketch {
    enum Subject {
        /// The marks as drawn, with no filter in the way: the reference field.
        case marks
        case blurred(radius: Double)
        /// A single flat tone, filtered at `radius`. The answer is the tone itself.
        case flat(gray: Double, radius: Double)
        /// The marks under a light of the given strength, cut against their surroundings.
        case localCut(gain: Double)
        /// The same, cut against one number for the whole layer.
        case globalCut(gain: Double)
    }

    var subject: Subject = .marks
    var size = 256

    static func make(_ subject: Subject, size: Int) -> SumProbe {
        let probe = SumProbe()
        probe.subject = subject
        probe.size = size
        return probe
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        background(.black)
        let layer = renderTarget()
        withTarget(layer) { paint() }

        switch subject {
        case .marks:
            drawImage(layer.image, 0, 0)
        case .blurred(let radius):
            drawImage(layer.filtered(.boxBlur(radius: radius)).image, 0, 0)
        case .flat(_, let radius):
            drawImage(layer.filtered(.boxBlur(radius: radius)).image, 0, 0)
        case .localCut:
            drawImage(layer.filtered(.adaptiveThreshold(window: 64, bias: 0.15)).image, 0, 0)
        case .globalCut:
            drawImage(layer.filtered(.threshold(0.35)).image, 0, 0)
        }
    }

    /// Marks with detail at several sizes, so a box average has something to do, and then
    /// the light over them where the subject calls for it.
    private func paint() {
        if case let .flat(gray, _) = subject {
            background(Color(white: gray))
            return
        }
        background(Color(white: 0.86))
        noStroke()
        fill(Color(white: 0.08))
        for i in 0 ..< 7 {
            let x = Double(size) * (0.08 + Double(i) * 0.13)
            drawCircle(x, Double(size) * 0.3, Double(4 + i * 3))
            drawRect(x - 8, Double(size) * 0.55, 16, Double(10 + i * 6))
        }
        stroke(Color(white: 0.08))
        strokeWeight(3)
        drawLine(0, Double(size) * 0.82, Double(size), Double(size) * 0.86)
        noStroke()

        // A light that falls off across the page, at whatever strength the subject asked
        // for. Multiplying is what makes it an illumination rather than a wash.
        let gain: Double
        switch subject {
        case .localCut(let g), .globalCut(let g): gain = g
        default: return
        }
        blendMode(.multiply)
        fill(Gradient.linear(from: Vector2(0, 0), to: Vector2(Double(size), Double(size)),
                             Ramp([Color(white: gain), Color(white: gain * 0.35)])))
        drawRect(0, 0, Double(size), Double(size))
        blendMode(.normal)
    }
}
