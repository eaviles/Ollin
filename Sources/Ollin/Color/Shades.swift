import Foundation

// Shades of one color whose hue drifts with lightness: warmer in the light,
// cooler in the shadow, the way pixel artists build a ramp by hand rather
// than only darkening and lightening one hue (credited in ATTRIBUTION.md).
//
// The walk is in OKLCH. Lightness runs evenly from dark to light through the
// base; the hue turns toward yellow as the shades lighten and away from it as
// they darken, by `hueDrift` turns at each end, and the lights stop turning if
// they reach yellow first. Away from yellow is toward blue or purple for every
// hue but yellow itself, whose shadows turn toward orange. Chroma eases from
// the base's to half of it at the two ends, since a very dark or very light
// shade at full strength reads heavy or loud, and the gamut map takes what a
// shade still cannot show.

public extension Ramp {
    /// A gradient of shades of `base` from dark to light, its hue drifting:
    /// toward yellow in the light, toward blue or purple in the shadow. Its
    /// chroma eases to half the base's at the two ends, where full strength
    /// reads heavy in the dark and loud in the light.
    ///
    /// - Parameters:
    ///   - base: the color the ramp passes through, at the position its own
    ///     lightness gives it.
    ///   - lightness: the OKLab lightness at the two ends (0 is black, 1 is
    ///     white). A base outside the range widens it to reach the base.
    ///   - hueDrift: how far the hue turns at each end, in turns. Negative
    ///     reverses the drift, cooling the lights and warming the shadows. Zero
    ///     keeps one hue throughout.
    ///
    /// ```swift
    /// let sea = Ramp.shades(of: Color(hex: 0x2A7F8F))
    /// postProcess(.gradientMap(sea))     // the frame's tones, shaded the painter's way
    /// ```
    static func shades(of base: Color, lightness: ClosedRange<Double> = 0.2...0.95,
                       hueDrift: Double = 1.0 / 12) -> Ramp {
        let walk = ShadeWalk(base: base, lightness: lightness, hueDrift: hueDrift)
        var stops: [(position: Double, color: Color)] = []
        if walk.basePosition > 0 { stops.append((0, walk.dark)) }
        stops.append((walk.basePosition, base))
        if walk.basePosition < 1 { stops.append((1, walk.light)) }
        return Ramp(stops: stops, in: .oklch)
    }
}

public extension Palette {
    /// `count` shades of `base` from dark to light, their hue drifting the way
    /// `Ramp.shades(of:lightness:hueDrift:)` describes. `base` is always one of
    /// them, at the place its lightness gives it, and the others step evenly in
    /// lightness on either side.
    ///
    /// ```swift
    /// let skin = Palette.shades(of: Color(hex: 0xC8875E), count: 6)
    /// let leaf = Palette.shades(of: .green, count: 4, hueDrift: 0.15)
    /// ```
    static func shades(of base: Color, count: Int = 5,
                       lightness: ClosedRange<Double> = 0.2...0.95,
                       hueDrift: Double = 1.0 / 12) -> Palette {
        guard count > 1 else { return Palette(count == 1 ? [base] : []) }
        let ramp = Ramp.shades(of: base, lightness: lightness, hueDrift: hueDrift)
        let p = ShadeWalk(base: base, lightness: lightness, hueDrift: hueDrift).basePosition
        let last = count - 1
        let k = Swift.min(Swift.max(Int((p * Double(last)).rounded()), 0), last)
        return Palette((0...last).map { i in
            if i == k { return base }
            let t = i < k ? p * Double(i) / Double(k)
                          : p + (1 - p) * Double(i - k) / Double(last - k)
            return ramp.color(at: t)
        })
    }
}

/// The two ends of a shade walk and where the base sits between them.
struct ShadeWalk {
    let dark: Color
    let light: Color
    let basePosition: Double

    /// The hue the lights turn toward: sRGB yellow's, in turns.
    static let warmHue = OKLCH(Color(red: 1, green: 1, blue: 0)).h

    /// The share of the base's chroma the two ends keep.
    static let endChroma = 0.5

    init(base: Color, lightness: ClosedRange<Double>, hueDrift: Double) {
        let lch = OKLCH(base)
        let low = min(max(min(lightness.lowerBound, lch.l), 0), 1)
        let high = min(max(max(lightness.upperBound, lch.l), 0), 1)
        basePosition = high > low ? (lch.l - low) / (high - low) : 0

        // The signed shorter turn from the base's hue to yellow; at yellow
        // itself the sign is taken as positive, so its shadows turn toward
        // orange.
        var arc = (ShadeWalk.warmHue - lch.h).truncatingRemainder(dividingBy: 1)
        if arc > 0.5 { arc -= 1 } else if arc <= -0.5 { arc += 1 }
        let toward = arc >= 0 ? 1.0 : -1.0
        let drift = abs(hueDrift)
        let warming = toward * min(drift, abs(arc))    // stops at yellow
        let cooling = -toward * drift
        let lightTurn = hueDrift >= 0 ? warming : cooling
        let darkTurn = hueDrift >= 0 ? cooling : warming

        let endChroma = lch.c * ShadeWalk.endChroma
        dark = Color(OKLCH(l: low, c: endChroma, h: lch.h + darkTurn), alpha: base.alpha)
        light = Color(OKLCH(l: high, c: endChroma, h: lch.h + lightTurn), alpha: base.alpha)
    }
}
