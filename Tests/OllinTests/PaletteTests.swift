import Ollin
import Testing

/// Pure CPU checks on `Ramp`, the discrete `Palette`, and the harmony
/// builders. No Metal, so these run everywhere including CI.
@Suite
struct PaletteTests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool {
        abs(a - b) <= eps
    }

    private func close(_ a: Color, _ b: Color, _ eps: Double = 1e-6) -> Bool {
        close(a.red, b.red, eps) && close(a.green, b.green, eps)
            && close(a.blue, b.blue, eps) && close(a.alpha, b.alpha, eps)
    }

    // MARK: Ramp

    @Test func rampEvenSpacingMatchesMix() {
        let ramp = Ramp([.red, .blue])
        #expect(close(ramp.color(at: 0), .red))
        #expect(close(ramp.color(at: 1), .blue))
        #expect(close(ramp.color(at: 0.5), Color.mix(.red, .blue, t: 0.5)))
        let three = Ramp([.red, .white, .blue], in: .rgb)
        #expect(close(three.color(at: 0.5), .white))
        #expect(close(three.color(at: 0.25), Color.mix(.red, .white, t: 0.5, in: .rgb)))
    }

    @Test func rampClampsOutsideStops() {
        let ramp = Ramp(stops: [(0.2, Color.red), (0.8, Color.blue)])
        #expect(close(ramp.color(at: 0), .red))
        #expect(close(ramp.color(at: -5), .red))
        #expect(close(ramp.color(at: 0.1), .red))
        #expect(close(ramp.color(at: 0.9), .blue))
        #expect(close(ramp.color(at: 7), .blue))
    }

    @Test func rampSortsStopsAndHonorsHardEdges() {
        let sorted = Ramp(stops: [(0.8, Color.blue), (0.2, Color.red)])
        #expect(close(sorted.color(at: 0.2), .red))
        #expect(close(sorted.color(at: 0.8), .blue))
        let edge = Ramp(stops: [(0, Color.red), (0.5, Color.red), (0.5, Color.blue), (1, Color.blue)])
        #expect(close(edge.color(at: 0.49), .red, 0.05))
        #expect(close(edge.color(at: 0.51), .blue, 0.05))
    }

    @Test func rampDegenerateInputs() {
        #expect(close(Ramp([]).color(at: 0.5), .clear))
        #expect(close(Ramp([.green]).color(at: 0.0), .green))
        #expect(close(Ramp([.green]).color(at: 0.7), .green))
    }

    // MARK: Palette

    @Test func paletteSubscriptWraps() {
        let p = Palette(.red, .green, .blue)
        #expect(p[0] == .red)
        #expect(p[3] == .red)
        #expect(p[7] == .green)
        #expect(p[-1] == .blue)
        #expect(Palette([])[5] == .clear)
    }

    @Test func paletteColorAtQuantizes() {
        let p = Palette(.red, .green, .blue)
        #expect(p.color(at: 0) == .red)
        #expect(p.color(at: 0.32) == .red)
        #expect(p.color(at: 0.34) == .green)
        #expect(p.color(at: 0.67) == .blue)
        #expect(p.color(at: 1) == .blue)
        #expect(p.color(at: -2) == .red)
        #expect(p.color(at: 9) == .blue)
    }

    @Test func paletteRampBridges() {
        let p = Palette(.red, .blue)
        #expect(close(p.ramp().color(at: 0.5), Color.mix(.red, .blue, t: 0.5)))
        #expect(close(p.ramp(in: .rgb).color(at: 0.5), Color.mix(.red, .blue, t: 0.5, in: .rgb)))
    }

    // MARK: Harmonies

    @Test func complementaryRotatesHalfTurn() {
        let base = Color(OKHSL(h: 0.1, s: 0.8, l: 0.6))
        let p = Palette.complementary(of: base)
        #expect(p.count == 2)
        #expect(p[0] == base)
        let baseLCH = OKLCH(base)
        let otherLCH = OKLCH(p[1])
        let delta = abs(otherLCH.h - baseLCH.h)
        #expect(close(min(delta, 1 - delta), 0.5, 1e-3))
        #expect(close(otherLCH.l, baseLCH.l, 1e-3))
    }

    @Test func triadicSplitsTheWheel() {
        let base = Color(OKHSL(h: 0.65, s: 0.7, l: 0.5))
        let p = Palette.triadic(of: base)
        #expect(p.count == 3)
        let h0 = OKLCH(p[0]).h
        for (i, expected) in [(1, 1.0 / 3), (2, 2.0 / 3)] {
            let d = (OKLCH(p[i]).h - h0).truncatingRemainder(dividingBy: 1)
            let wrapped = d < 0 ? d + 1 : d
            #expect(close(wrapped, expected, 1e-3), "color \(i)")
        }
    }

    @Test func splitComplementaryFlanksTheOpposite() {
        let base = Color(OKHSL(h: 0.2, s: 0.8, l: 0.55))
        let p = Palette.splitComplementary(of: base)
        #expect(p.count == 3)
        let h0 = OKLCH(p[0]).h
        let offsets = [1, 2].map { i -> Double in
            let d = (OKLCH(p[i]).h - h0).truncatingRemainder(dividingBy: 1)
            return d < 0 ? d + 1 : d
        }
        #expect(close(offsets[0], 0.5 - 1.0 / 12, 1e-3))
        #expect(close(offsets[1], 0.5 + 1.0 / 12, 1e-3))
    }

    @Test func analogousCentersOnBase() {
        let base = Color(OKHSL(h: 0.5, s: 0.8, l: 0.6))
        let p = Palette.analogous(of: base, count: 5)
        #expect(p.count == 5)
        #expect(p[2] == base)
        let hs = p.colors.map { OKLCH($0).h }
        for i in 1..<5 {
            let d = (hs[i] - hs[i - 1]).truncatingRemainder(dividingBy: 1)
            let wrapped = d < 0 ? d + 1 : d
            #expect(close(wrapped, 1.0 / 12, 1e-3), "gap \(i)")
        }
    }

    @Test func harmoniesHoldLightness() {
        let base = Color(OKHSL(h: 0.85, s: 0.9, l: 0.6))
        let baseL = OKLCH(base).l
        for c in Palette.triadic(of: base).colors {
            #expect(close(OKLCH(c).l, baseL, 1e-3))
        }
    }

    // MARK: Built-in sets

    @Test func builtInSetsCarryTheCanonicalData() {
        #expect(Palette.set1.count == 9)
        #expect(Palette.set2.count == 8)
        #expect(Palette.set3.count == 12)
        #expect(Palette.paired.count == 12)
        #expect(Palette.pastel1.count == 9)
        #expect(Palette.pastel2.count == 8)
        #expect(Palette.dark2.count == 8)
        #expect(Palette.accent.count == 8)
        // Spot-check against the published RGB values.
        #expect(Palette.set1[0] == Color(hex: 0xE41A1C))
        #expect(Palette.set2[0] == Color(red: 102.0 / 255, green: 194.0 / 255, blue: 165.0 / 255))
        #expect(Palette.dark2[3] == Color(red: 231.0 / 255, green: 41.0 / 255, blue: 138.0 / 255))
        #expect(Palette.paired[11] == Color(red: 177.0 / 255, green: 89.0 / 255, blue: 40.0 / 255))
    }
}
