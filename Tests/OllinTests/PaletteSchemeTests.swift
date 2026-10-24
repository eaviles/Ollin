import Testing
import Foundation
@testable import Ollin

/// Palette schemes (`Palette.scheme(_:key:count:jitter:seed:)`) and a hue's most
/// vivid color (`Color.mostVivid(hue:)`), read against the sRGB gamut found
/// by search rather than by the framework's own boundary.
struct PaletteSchemeTests {

    // MARK: The oracle

    /// Whether OKLab `(l, a, b)` is a color the screen shows: the published
    /// OKLab to linear sRGB transform, every channel inside `0...1`.
    static func inGamut(_ l: Double, _ a: Double, _ b: Double) -> Bool {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bl = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        let e = 1e-7
        return r >= -e && r <= 1 + e && g >= -e && g <= 1 + e && bl >= -e && bl <= 1 + e
    }

    /// The largest chroma the screen shows at lightness `l` and hue `h` (a
    /// turn), by bisection.
    static func searchedChroma(_ l: Double, _ h: Double) -> Double {
        let a = cos(h * 2 * .pi), b = sin(h * 2 * .pi)
        var lo = 0.0, hi = 0.5
        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            if inGamut(l, mid * a, mid * b) { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// The hue's peak chroma over every lightness, and where it peaks.
    static func searchedPeak(_ h: Double) -> (l: Double, c: Double) {
        var best = (l: 0.0, c: 0.0)
        var l = 0.002
        while l < 1 {
            let c = searchedChroma(l, h)
            if c > best.c { best = (l, c) }
            l += 0.002
        }
        return best
    }

    /// How far apart two hues sit around the wheel, in degrees.
    static func degrees(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b).truncatingRemainder(dividingBy: 1)
        if d > 0.5 { d = 1 - d }
        return d * 360
    }

    // MARK: The most vivid point

    @Test func theMostVividColorSitsWhereItsHuesChromaPeaks() {
        for i in 0..<24 {
            let h = Double(i) / 24
            let peak = Self.searchedPeak(h)
            let lch = OKLCH(Color.mostVivid(hue: h))
            #expect(Self.degrees(lch.h, h) < 1, "hue \(h) comes back at \(lch.h)")
            #expect(abs(lch.c - peak.c) < 0.004, "hue \(h): chroma \(lch.c) against the searched \(peak.c)")
            #expect(abs(lch.l - peak.l) < 0.02, "hue \(h): lightness \(lch.l) against the searched \(peak.l)")
        }
        // A hue wraps.
        #expect(Color.mostVivid(hue: 1.25) == Color.mostVivid(hue: 0.25))
    }

    // MARK: Schemes

    static let keys: [Color] = [Color(hex: 0xC8553D), Color(hex: 0x2E86AB), Color(hex: 0xF4D35E),
                                Color(hex: 0x6A994E), Color(hex: 0x7B2CBF), Color(hex: 0xE5989B)]

    @Test func monochromeKeepsOneHueWithItsMostVividPointFirst() {
        for key in Self.keys {
            let hue = OKLCH(key).h
            let palette = Palette.scheme(.monochrome, key: key, count: 6)
            #expect(palette.count == 6)
            let lch = palette.map(OKLCH.init)
            for c in lch {
                #expect(Self.degrees(c.h, hue) < 1, "a color drifted to hue \(c.h) from \(hue)")
            }
            let peak = Self.searchedPeak(hue)
            #expect(abs(lch[0].c - peak.c) < 0.004, "the first color's chroma \(lch[0].c) against the peak \(peak.c)")
            // The rest divide the lightness range from deep to light, the
            // vivid point standing in for the step nearest it (yellow's is
            // the lightest step).
            let rest = lch.dropFirst().map(\.l)
            #expect(rest == rest.sorted(), "\(rest)")
            let all = lch.map(\.l)
            #expect(all.min()! < 0.3 && all.max()! > 0.85, "\(all)")
        }
    }

    @Test func vividAndDarkSplitsItsWheelAtALightness() {
        for key in Self.keys {
            for jitter in [0.0, 1.0] {
                let palette = Palette.scheme(.vividAndDark, key: key, count: 6, jitter: jitter, seed: 9)
                let lch = palette.map(OKLCH.init)
                for (i, c) in lch.enumerated() {
                    // Turns from the key around the wheel: 0, 1/6, 2/6, 3/6, ...
                    let around = Double(min(i, 6 - i)) / 6
                    if around <= 0.25 {
                        #expect(c.l > 0.4, "color \(i), near the key, is at lightness \(c.l)")
                    } else {
                        #expect(c.l < 0.4, "color \(i), across the wheel, is at lightness \(c.l)")
                    }
                }
                #expect(Self.degrees(lch[0].h, OKLCH(key).h) < 1 + jitter * 11)
            }
        }
    }

    @Test func theVividWheelTakesEachHueAtItsFullChroma() {
        for key in Self.keys {
            let lch = Palette.scheme(.vivid, key: key, count: 8).map(OKLCH.init)
            for (i, c) in lch.enumerated() {
                let h = OKLCH(key).h + Double(i) / 8
                #expect(Self.degrees(c.h, h) < 1, "color \(i) at hue \(c.h), not \(h)")
                #expect(abs(c.c - Self.searchedChroma(c.l, c.h)) < 0.004,
                        "color \(i): chroma \(c.c) against the searched \(Self.searchedChroma(c.l, c.h))")
            }
        }
        // The lightness follows the hue's color word: yellow light, blue deep.
        let yellow = OKLCH(Palette.scheme(.vivid, key: .mostVivid(hue: 105.0 / 360), count: 1)[0])
        let blue = OKLCH(Palette.scheme(.vivid, key: .mostVivid(hue: 255.0 / 360), count: 1)[0])
        #expect(yellow.l > 0.85 && blue.l < 0.55, "yellow at \(yellow.l), blue at \(blue.l)")
    }

    @Test func pastelIsLightAndSoftAndDarkIsDeepBothNearTheKey() {
        for key in Self.keys {
            let hue = OKLCH(key).h
            for c in Palette.scheme(.pastel, key: key, count: 5).map(OKLCH.init) {
                #expect(c.l >= 0.8 && c.c <= 0.08, "a pastel at lightness \(c.l), chroma \(c.c)")
                #expect(Self.degrees(c.h, hue) < 30)
            }
            for c in Palette.scheme(.dark, key: key, count: 5).map(OKLCH.init) {
                #expect(c.l <= 0.4, "a dark color at lightness \(c.l)")
                #expect(Self.degrees(c.h, hue) < 30)
            }
        }
    }

    @Test func theSeedPicksTheJitter() {
        let key = Color(hex: 0x2E86AB)
        let a = Palette.scheme(.vivid, key: key, count: 6, jitter: 0.6, seed: 1)
        #expect(a == Palette.scheme(.vivid, key: key, count: 6, jitter: 0.6, seed: 1))
        #expect(a != Palette.scheme(.vivid, key: key, count: 6, jitter: 0.6, seed: 2))
        // No jitter, no seed to read.
        #expect(Palette.scheme(.vivid, key: key, count: 6, seed: 1) == Palette.scheme(.vivid, key: key, count: 6, seed: 2))
        // A jittered monochrome palette keeps its one hue.
        for c in Palette.scheme(.monochrome, key: key, count: 6, jitter: 1, seed: 4).map(OKLCH.init) {
            #expect(Self.degrees(c.h, OKLCH(key).h) < 1)
        }
        #expect(Palette.scheme(.pastel, key: key, count: 0).isEmpty)
        #expect(Palette.scheme(.monochrome, key: key, count: 1).count == 1)
    }
}
