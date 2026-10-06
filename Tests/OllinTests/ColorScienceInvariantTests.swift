@testable import Ollin
import Testing

/// Invariants of the color science that hold whatever the implementation: a proof is a
/// projection onto what the press can print (so a second proof changes nothing and
/// nothing proofed is out of gamut), it keeps a gray neutral, and a simulation of a
/// dichromat's sight is one too (what the simulated viewer cannot tell apart, the
/// simulation maps to one color, so simulating twice is simulating once).
@Suite
struct ColorScienceInvariantTests {

    private let cmyk = SoftProof(.genericCMYK)

    private static let swatches: [Color] = [
        Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0), Color(red: 0, green: 0, blue: 1),
        Color(red: 0, green: 1, blue: 1), Color(red: 1, green: 0, blue: 1), Color(red: 1, green: 1, blue: 0),
        Color(red: 1, green: 0.5, blue: 0), Color(red: 0.5, green: 0, blue: 1), Color(red: 0.1, green: 0.6, blue: 0.3),
        Color(white: 0.5),
    ]

    /// An image of one flat color, opaque.
    private func flat(_ color: Color, size: Int = 8) -> Image {
        Image(width: size, height: size, color: color)
    }

    /// The mean color of an image, read back through its pixels, in 0...255.
    private func mean(_ image: Image) -> (r: Double, g: Double, b: Double) {
        guard let bytes = image.premultipliedPixels() else { return (-1, -1, -1) }
        var r = 0.0, g = 0.0, b = 0.0
        let count = image.width * image.height
        for p in 0 ..< count {
            let i = p * 4
            r += Double(bytes[i]); g += Double(bytes[i + 1]); b += Double(bytes[i + 2])
        }
        let n = Double(count)
        return (r / n, g / n, b / n)
    }

    private func color(_ m: (r: Double, g: Double, b: Double)) -> Color {
        Color(red: m.r / 255, green: m.g / 255, blue: m.b / 255)
    }

    // MARK: Print

    /// A proof is a projection: proofing what a proof produced changes nothing.
    ///
    /// Measured 2026-10-06 and filed: the system's generic CMYK profile does not
    /// round-trip, so a second proof moves a saturated swatch by 4 to 11 levels
    /// (yellow the worst). The proof is the system's own transform, so the gap is the
    /// profile's; the known issue keeps the statement and fails the day it holds.
    @Test(.enabled(if: SoftProof(.genericCMYK).destination.isUsable))
    func aProofIsIdempotent() {
        var worst = 0.0
        var at = Color.black
        for swatch in Self.swatches {
            let once = mean(flat(swatch).softProofed(cmyk))
            let twice = mean(flat(color(once)).softProofed(cmyk))
            let moved = max(abs(once.r - twice.r), abs(once.g - twice.g), abs(once.b - twice.b))
            if moved > worst { worst = moved; at = swatch }
        }
        withKnownIssue("the generic CMYK profile does not round-trip (4 to 11 levels, measured 2026-10-06)") {
            #expect(worst <= 3, "proofing \(at) twice moved it by \(worst) levels")
        }
    }

    /// Nothing a proof produced is out of the press's gamut.
    @Test(.enabled(if: SoftProof(.genericCMYK).destination.isUsable))
    func aProofNeverWidensTheGamut() {
        for swatch in Self.swatches {
            let proofed = color(mean(flat(swatch).softProofed(cmyk)))
            let outside = flat(proofed).outOfGamutFraction(cmyk)
            #expect(outside == 0, "the proof of \(swatch) is \(proofed) and reads \(outside) out of gamut")
        }
    }

    /// A proof keeps a gray neutral: the press's gray axis is gray.
    @Test(.enabled(if: SoftProof(.genericCMYK).destination.isUsable), arguments: [0.25, 0.5, 0.75])
    func aProofKeepsAGrayNeutral(gray: Double) {
        let proofed = mean(flat(Color(white: gray)).softProofed(cmyk))
        let cast = max(abs(proofed.r - proofed.g), abs(proofed.g - proofed.b), abs(proofed.r - proofed.b))
        #expect(cast <= 3, "gray \(gray) proofed with a cast of \(cast) levels: \(proofed)")
    }

    // MARK: Color vision

    private func distance(_ a: Color, _ b: Color) -> Double {
        let x = OKLab(a), y = OKLab(b)
        let dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// A dichromat sees a two-dimensional color world, so a simulation of that sight
    /// maps every color onto a surface of colors they see as themselves: simulating
    /// an already simulated color must leave it where it is.
    ///
    /// Measured 2026-10-06 and filed: the published severity-1 matrices are not
    /// projections. The red-green pair are rank two but their square differs from
    /// them by up to 0.06, which moves a blue by 0.064 (protan) and 0.031 (deutan)
    /// in OKLab on a second pass; the tritan matrix is not even rank two (a third
    /// singular value of 0.16, its square off by 0.33) and moves a purple by 0.072.
    /// The known issue keeps the statement and fails the day a projection model
    /// stands at severity 1.
    @Test(arguments: [ColorVision.Kind.protanomaly, .deuteranomaly, .tritanomaly])
    func aDichromatSimulationIsIdempotent(kind: ColorVision.Kind) {
        let vision = ColorVision(kind, severity: 1)
        var worst = 0.0
        var worstColor = Color.black
        let steps = 6
        for ri in 0...steps {
            for gi in 0...steps {
                for bi in 0...steps {
                    let c = Color(red: Double(ri) / Double(steps), green: Double(gi) / Double(steps),
                                  blue: Double(bi) / Double(steps))
                    let once = c.simulated(vision)
                    let twice = once.simulated(vision)
                    let d = distance(once, twice)
                    if d > worst { worst = d; worstColor = c }
                }
            }
        }
        withKnownIssue("the published matrices are not projections (0.03 to 0.07 OKLab on a second pass, measured 2026-10-06)") {
            #expect(worst < 0.02, "\(kind) moved \(worstColor) by \(worst) on a second pass")
        }
    }

    /// Severity is a dial from the viewer's own sight to the dichromat's: at any step
    /// a color lies between where it started and where severity 1 puts it, never
    /// beyond either.
    ///
    /// Holds for the red-green kinds. Measured 2026-10-06 and filed for the tritan
    /// kind: its published intermediate matrices wander (the red row passes 1.1 at
    /// severity 0.6 with a negative green term), so at severity 0.2 a red and a cyan
    /// are moved by 0.023 where severity 1 moves them by under 0.004. The known
    /// issue is scoped to that kind and fails the day its path is monotone.
    @Test(arguments: [ColorVision.Kind.protanomaly, .deuteranomaly, .tritanomaly])
    func aPartialSeverityNeverOvershootsTheEnds(kind: ColorVision.Kind) {
        let full = ColorVision(kind, severity: 1)
        var overshoot = 0.0
        var at = Color.black
        for swatch in Self.swatches {
            let end = swatch.simulated(full)
            let span = distance(swatch, end)
            for severity in [0.2, 0.45, 0.7, 0.9] {
                let part = swatch.simulated(ColorVision(kind, severity: severity))
                let past = max(distance(swatch, part), distance(part, end)) - span
                if past > overshoot { overshoot = past; at = swatch }
            }
        }
        withKnownIssue("the tritan path is not monotone in severity (measured 2026-10-06)", {
            #expect(overshoot <= 0.01, "\(kind) took \(at) \(overshoot) past the reach of severity 1")
        }, when: { kind == .tritanomaly })
    }
}
