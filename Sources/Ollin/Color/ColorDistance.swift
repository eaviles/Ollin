import Foundation

// How far apart two colors look, and the palette entry nearest a color.
//
// Two measures: straight-line distance in OKLab, the space the rest of the
// color tier works in, and CIEDE2000, the CIE's color-difference formula,
// implemented from the published definition and checked against its
// published test pairs (credited in ATTRIBUTION.md).

/// A way to measure how different two colors look.
///
/// The two read on different scales, so a tolerance written for one does not
/// carry to the other.
public enum ColorDistance: Sendable, Hashable, CaseIterable {
    /// Straight-line distance in OKLab, where black to white is 1. About 0.02
    /// is a difference most people just see side by side; the palette checks
    /// (`Palette.confusions(tolerance:)`) measure on this scale. The default:
    /// cheap, and even across hues.
    case oklab
    /// The CIE's 2000 color-difference formula (ΔE00), measured in CIELAB
    /// (D50). About 1 is a just-visible difference and 2.3 a commonly quoted
    /// threshold; the print and textile trades write their tolerances in it.
    /// It corrects CIELAB's unevenness in the blues and among near-grays, and
    /// costs a few dozen operations more than `.oklab`.
    case ciede2000
}

public extension Color {
    /// How different this color looks from `other`: 0 for the same color, and
    /// more the further apart they look. Alpha is not compared.
    ///
    /// ```swift
    /// if ink.distance(to: paper) < 0.05 { stroke(.black) }          // too close to read
    /// let delta = ink.distance(to: proof, measure: .ciede2000)    // a press tolerance
    /// ```
    func distance(to other: Color, measure: ColorDistance = .oklab) -> Double {
        switch measure {
        case .oklab:
            return OKLab(self).distance(to: OKLab(other))
        case .ciede2000:
            return CIELab(self).ciede2000(to: CIELab(other))
        }
    }
}

extension OKLab {
    /// Straight-line distance to another OKLab value.
    func distance(to other: OKLab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}

extension CIELab {
    /// The CIEDE2000 difference to another value, with the reference
    /// conditions' weights (kL = kC = kH = 1). Symmetric in its two colors.
    ///
    /// Follows the formula as published, including the place implementations
    /// most often slip: the mean hue of two colors whose hues lie more than half
    /// a turn apart, which has to be taken across the wrap. A color with no
    /// chroma has its hue taken as zero, which the result never reads, since
    /// its hue difference is zero too.
    func ciede2000(to other: CIELab) -> Double {
        let pow25To7 = 6_103_515_625.0                           // 25^7
        let c1 = (a * a + b * b).squareRoot()
        let c2 = (other.a * other.a + other.b * other.b).squareRoot()
        let cMean = (c1 + c2) / 2
        let cMean7 = Foundation.pow(cMean, 7)
        let g = 0.5 * (1 - (cMean7 / (cMean7 + pow25To7)).squareRoot())
        let a1 = (1 + g) * a, a2 = (1 + g) * other.a
        let c1p = (a1 * a1 + b * b).squareRoot()
        let c2p = (a2 * a2 + other.b * other.b).squareRoot()
        func hue(_ b: Double, _ a: Double) -> Double {
            guard a != 0 || b != 0 else { return 0 }
            let degrees = atan2(b, a) * 180 / .pi
            return degrees < 0 ? degrees + 360 : degrees
        }
        let h1p = hue(b, a1), h2p = hue(other.b, a2)

        let dL = other.l - l
        let dC = c2p - c1p
        var dh = 0.0
        if c1p * c2p != 0 {
            dh = h2p - h1p
            if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        }
        let dH = 2 * (c1p * c2p).squareRoot() * sin(dh * .pi / 360)

        let lMean = (l + other.l) / 2
        let cMeanP = (c1p + c2p) / 2
        let hMean: Double
        if c1p * c2p == 0 {
            hMean = h1p + h2p
        } else if abs(h1p - h2p) <= 180 {
            hMean = (h1p + h2p) / 2
        } else if h1p + h2p < 360 {
            hMean = (h1p + h2p + 360) / 2
        } else {
            hMean = (h1p + h2p - 360) / 2
        }
        func cosd(_ x: Double) -> Double { cos(x * .pi / 180) }
        let t = 1 - 0.17 * cosd(hMean - 30) + 0.24 * cosd(2 * hMean)
            + 0.32 * cosd(3 * hMean + 6) - 0.20 * cosd(4 * hMean - 63)
        let rotation = 30 * exp(-((hMean - 275) / 25) * ((hMean - 275) / 25))
        let cMeanP7 = Foundation.pow(cMeanP, 7)
        let rC = 2 * (cMeanP7 / (cMeanP7 + pow25To7)).squareRoot()
        let lOffset = (lMean - 50) * (lMean - 50)
        let sL = 1 + 0.015 * lOffset / (20 + lOffset).squareRoot()
        let sC = 1 + 0.045 * cMeanP
        let sH = 1 + 0.015 * cMeanP * t
        let rT = -sin(2 * rotation * .pi / 180) * rC
        let l = dL / sL, c = dC / sC, h = dH / sH
        return (l * l + c * c + h * h + rT * c * h).squareRoot()
    }
}

// MARK: - The nearest entry

public extension Palette {
    /// The entry that looks most like `color`, or `nil` for an empty palette.
    /// When two entries are equally near, the earlier one wins.
    ///
    /// ```swift
    /// let sampled = photo.averageColor(in: cell)
    /// fill(palette.nearest(to: sampled) ?? sampled)
    /// ```
    func nearest(to color: Color, measure: ColorDistance = .oklab) -> Color? {
        nearestIndex(to: color, measure: measure).map { colors[$0] }
    }

    /// The position of the entry that looks most like `color`, or `nil` for an
    /// empty palette: the form to use when the entries stand for something (a
    /// plate to print with, a thread to stitch). Ties go to the earlier entry.
    func nearestIndex(to color: Color, measure: ColorDistance = .oklab) -> Int? {
        guard !colors.isEmpty else { return nil }
        var best = 0
        var bestDistance = Double.infinity
        switch measure {
        case .oklab:
            let target = OKLab(color)
            for (i, entry) in colors.enumerated() {
                let d = OKLab(entry).distance(to: target)
                if d < bestDistance { best = i; bestDistance = d }
            }
        case .ciede2000:
            let target = CIELab(color)
            for (i, entry) in colors.enumerated() {
                let d = CIELab(entry).ciede2000(to: target)
                if d < bestDistance { best = i; bestDistance = d }
            }
        }
        return best
    }
}
