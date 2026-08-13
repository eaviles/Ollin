import Foundation

/// A kind of color vision, and how far it departs from the average one.
///
/// About one man in twelve and one woman in two hundred sees color differently
/// from the palette most work is designed against. `ColorVision` names one such
/// way of seeing, so a sketch can ask what its colors look like to somebody else.
///
/// ```swift
/// let seen = Color.red.simulated(.deuteranopia)
/// ```
///
/// `severity` runs from 0, which changes nothing, to 1, which is dichromacy: one
/// of the three cone types is missing rather than shifted. Values between the two
/// are anomalous trichromacy, the far commoner case.
///
/// The simulation is the published physiologically based model. A color is
/// linearized, multiplied by a 3x3 matrix chosen by kind and severity, and
/// encoded back. The matrices weight the power of the display primaries, so they
/// belong in linear light. Applying them to display values instead is a common
/// mistake and gives a visibly different answer.
public struct ColorVision: Equatable, Hashable, Sendable {

    /// Which cone response is shifted.
    public enum Kind: String, CaseIterable, Sendable {
        /// The long wavelength cone, the one that peaks nearest red.
        case protanomaly
        /// The middle wavelength cone. This is the commonest kind.
        case deuteranomaly
        /// The short wavelength cone, the one that peaks nearest blue. Rare.
        case tritanomaly
    }

    /// Which cone response is shifted.
    public var kind: Kind

    /// How far it is shifted, from 0 (no change) to 1 (dichromacy).
    public var severity: Double

    /// A kind of color vision at a severity, clamped to `0...1`.
    public init(_ kind: Kind, severity: Double = 1) {
        self.kind = kind
        self.severity = min(max(severity, 0), 1)
    }

    /// Average color vision. Simulating it changes nothing.
    public static let normal = ColorVision(.deuteranomaly, severity: 0)

    /// No long wavelength cone.
    public static let protanopia = ColorVision(.protanomaly, severity: 1)
    /// No middle wavelength cone.
    public static let deuteranopia = ColorVision(.deuteranomaly, severity: 1)
    /// No short wavelength cone.
    public static let tritanopia = ColorVision(.tritanomaly, severity: 1)

    /// A shifted long wavelength cone at the given severity.
    public static func protanomaly(_ severity: Double) -> ColorVision {
        ColorVision(.protanomaly, severity: severity)
    }
    /// A shifted middle wavelength cone at the given severity.
    public static func deuteranomaly(_ severity: Double) -> ColorVision {
        ColorVision(.deuteranomaly, severity: severity)
    }
    /// A shifted short wavelength cone at the given severity.
    public static func tritanomaly(_ severity: Double) -> ColorVision {
        ColorVision(.tritanomaly, severity: severity)
    }

    /// The 3x3 transform for this kind and severity, in row-major order, to be
    /// applied to linear RGB.
    ///
    /// The published table gives a matrix every 0.1 of severity. A severity in
    /// between interpolates the two nearest, which is what the model's authors
    /// suggest for a value they did not tabulate.
    public var matrix: [Double] {
        let table = ColorVision.table(for: kind)
        let step = severity * 10
        let low = min(Int(step.rounded(.down)), 10)
        let high = min(low + 1, 10)
        let mix = step - Double(low)
        if low == high || mix == 0 {
            return Array(table[(low * 9)..<(low * 9 + 9)])
        }
        return (0..<9).map { i in
            table[low * 9 + i] * (1 - mix) + table[high * 9 + i] * mix
        }
    }

    /// Apply the transform to one linear RGB triple.
    ///
    /// Kept separate from ``Color/simulated(_:)`` so that a caller already
    /// working in linear light does not encode and decode for nothing.
    public func applied(toLinear r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let m = matrix
        return (m[0] * r + m[1] * g + m[2] * b,
                m[3] * r + m[4] * g + m[5] * b,
                m[6] * r + m[7] * g + m[8] * b)
    }

    private static func table(for kind: Kind) -> [Double] {
        switch kind {
        case .protanomaly: return protanomalyTable
        case .deuteranomaly: return deuteranomalyTable
        case .tritanomaly: return tritanomalyTable
        }
    }

    // Table 1 of the published model: row-major 3x3 matrices for severities 0.0
    // to 1.0 in steps of 0.1. Transcribed from the authors' own published table.
    private static let protanomalyTable: [Double] = [
        1.000000, 0.000000, -0.000000, 0.000000, 1.000000, 0.000000, -0.000000, -0.000000, 1.000000,
        0.856167, 0.182038, -0.038205, 0.029342, 0.955115, 0.015544, -0.002880, -0.001563, 1.004443,
        0.734766, 0.334872, -0.069637, 0.051840, 0.919198, 0.028963, -0.004928, -0.004209, 1.009137,
        0.630323, 0.465641, -0.095964, 0.069181, 0.890046, 0.040773, -0.006308, -0.007724, 1.014032,
        0.539009, 0.579343, -0.118352, 0.082546, 0.866121, 0.051332, -0.007136, -0.011959, 1.019095,
        0.458064, 0.679578, -0.137642, 0.092785, 0.846313, 0.060902, -0.007494, -0.016807, 1.024301,
        0.385450, 0.769005, -0.154455, 0.100526, 0.829802, 0.069673, -0.007442, -0.022190, 1.029632,
        0.319627, 0.849633, -0.169261, 0.106241, 0.815969, 0.077790, -0.007025, -0.028051, 1.035076,
        0.259411, 0.923008, -0.182420, 0.110296, 0.804340, 0.085364, -0.006276, -0.034346, 1.040622,
        0.203876, 0.990338, -0.194214, 0.112975, 0.794542, 0.092483, -0.005222, -0.041043, 1.046265,
        0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998,
    ]

    private static let deuteranomalyTable: [Double] = [
        1.000000, 0.000000, -0.000000, 0.000000, 1.000000, 0.000000, -0.000000, -0.000000, 1.000000,
        0.866435, 0.177704, -0.044139, 0.049567, 0.939063, 0.011370, -0.003453, 0.007233, 0.996220,
        0.760729, 0.319078, -0.079807, 0.090568, 0.889315, 0.020117, -0.006027, 0.013325, 0.992702,
        0.675425, 0.433850, -0.109275, 0.125303, 0.847755, 0.026942, -0.007950, 0.018572, 0.989378,
        0.605511, 0.528560, -0.134071, 0.155318, 0.812366, 0.032316, -0.009376, 0.023176, 0.986200,
        0.547494, 0.607765, -0.155259, 0.181692, 0.781742, 0.036566, -0.010410, 0.027275, 0.983136,
        0.498864, 0.674741, -0.173604, 0.205199, 0.754872, 0.039929, -0.011131, 0.030969, 0.980162,
        0.457771, 0.731899, -0.189670, 0.226409, 0.731012, 0.042579, -0.011595, 0.034333, 0.977261,
        0.422823, 0.781057, -0.203881, 0.245752, 0.709602, 0.044646, -0.011843, 0.037423, 0.974421,
        0.392952, 0.823610, -0.216562, 0.263559, 0.690210, 0.046232, -0.011910, 0.040281, 0.971630,
        0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881,
    ]

    private static let tritanomalyTable: [Double] = [
        1.000000, 0.000000, -0.000000, 0.000000, 1.000000, 0.000000, -0.000000, -0.000000, 1.000000,
        0.926670, 0.092514, -0.019184, 0.021191, 0.964503, 0.014306, 0.008437, 0.054813, 0.936750,
        0.895720, 0.133330, -0.029050, 0.029997, 0.945400, 0.024603, 0.013027, 0.104707, 0.882266,
        0.905871, 0.127791, -0.033662, 0.026856, 0.941251, 0.031893, 0.013410, 0.148296, 0.838294,
        0.948035, 0.089490, -0.037526, 0.014364, 0.946792, 0.038844, 0.010853, 0.193991, 0.795156,
        1.017277, 0.027029, -0.044306, -0.006113, 0.958479, 0.047634, 0.006379, 0.248708, 0.744913,
        1.104996, -0.046633, -0.058363, -0.032137, 0.971635, 0.060503, 0.001336, 0.317922, 0.680742,
        1.193214, -0.109812, -0.083402, -0.058496, 0.979410, 0.079086, -0.002346, 0.403492, 0.598854,
        1.257728, -0.139648, -0.118081, -0.078003, 0.975409, 0.102594, -0.003316, 0.501214, 0.502102,
        1.278864, -0.125333, -0.153531, -0.084748, 0.957674, 0.127074, -0.000989, 0.601151, 0.399838,
        1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900,
    ]
}

extension ColorVision.Kind: ParamOption {}

public extension Color {
    /// This color as somebody with the given color vision sees it.
    ///
    /// Alpha is carried through untouched. The result is clamped into the
    /// display range, since the transform can land outside it.
    func simulated(_ vision: ColorVision) -> Color {
        guard vision.severity > 0 else { return self }
        let (r, g, b) = vision.applied(toLinear: Color.srgbToLinear(red),
                                       Color.srgbToLinear(green),
                                       Color.srgbToLinear(blue))
        return Color(red: Color.linearToSrgb(min(max(r, 0), 1)),
                     green: Color.linearToSrgb(min(max(g, 0), 1)),
                     blue: Color.linearToSrgb(min(max(b, 0), 1)),
                     alpha: alpha)
    }
}

/// Two colors in a palette that land close enough together, for somebody with
/// one kind of color vision, to be hard to tell apart.
public struct ColorConfusion: Equatable, Sendable {
    /// Index of the first color in the palette.
    public var first: Int
    /// Index of the second.
    public var second: Int
    /// How far apart the two are once simulated, in the same perceptual units
    /// the tolerance is given in.
    public var distance: Double
    /// The color vision that brings them together.
    public var vision: ColorVision
}

public extension Palette {
    /// Every color in the palette as somebody with the given color vision sees it.
    func simulated(_ vision: ColorVision) -> Palette {
        Palette(colors.map { $0.simulated(vision) })
    }

    /// The pairs that collapse onto each other under the given color vision,
    /// worst pair first.
    ///
    /// Distance is measured in OKLab, across lightness as well as hue, which is
    /// the whole judgement rather than half of it. Red and green look alike to a
    /// protanope in hue, but one is much darker than the other, so the pair is
    /// still usable. Two colors of the same lightness that differ only in hue
    /// are the ones that merge.
    ///
    /// The default tolerance is measured rather than guessed. The published
    /// eight-color safe set (``colorblindSafe``) has 0.076 between its closest
    /// pair under the worst kind, while a familiar six-color chart set falls to
    /// 0.007. A tolerance of 0.06 separates them with room on both sides.
    func confusions(under vision: ColorVision, tolerance: Double = 0.06) -> [ColorConfusion] {
        guard colors.count > 1 else { return [] }
        let seen = colors.map { OKLab($0.simulated(vision)) }
        var found: [ColorConfusion] = []
        for i in 0..<seen.count {
            for j in (i + 1)..<seen.count {
                let a = seen[i], b = seen[j]
                let dl = a.l - b.l, da = a.a - b.a, db = a.b - b.b
                let d = (dl * dl + da * da + db * db).squareRoot()
                if d < tolerance {
                    found.append(ColorConfusion(first: i, second: j, distance: d, vision: vision))
                }
            }
        }
        return found.sorted { ($0.distance, $0.first, $0.second) < ($1.distance, $1.first, $1.second) }
    }

    /// The pairs that collapse under any of the three kinds at full severity,
    /// worst pair first.
    func confusions(tolerance: Double = 0.06) -> [ColorConfusion] {
        let all = ColorVision.Kind.allCases.flatMap {
            confusions(under: ColorVision($0), tolerance: tolerance)
        }
        return all.sorted {
            ($0.distance, $0.first, $0.second) < ($1.distance, $1.first, $1.second)
        }
    }

    /// Whether every pair of colors stays apart under all three kinds.
    ///
    /// A palette that fails says which pairs and by how much through
    /// ``confusions(tolerance:)``.
    func isColorblindSafe(tolerance: Double = 0.06) -> Bool {
        confusions(tolerance: tolerance).isEmpty
    }

    /// Eight colors chosen to stay apart under every kind of color vision.
    ///
    /// The set published for color universal design by Okabe and Ito, and the
    /// usual answer when a piece needs categories anybody can follow. Its
    /// closest pair under the worst kind sits at 0.076, against 0.007 for a
    /// familiar chart set.
    static var colorblindSafe: Palette {
        Palette([
            Color(hex: 0x000000),  // black
            Color(hex: 0xE69F00),  // orange
            Color(hex: 0x56B4E9),  // sky blue
            Color(hex: 0x009E73),  // bluish green
            Color(hex: 0xF0E442),  // yellow
            Color(hex: 0x0072B2),  // blue
            Color(hex: 0xD55E00),  // vermillion
            Color(hex: 0xCC79A7),  // reddish purple
        ])
    }
}

public extension Ramp {
    /// The ramp as somebody with the given color vision sees it, stop by stop.
    func simulated(_ vision: ColorVision) -> Ramp {
        Ramp(stops: stops.map { (position: $0.position, color: $0.color.simulated(vision)) },
             in: space)
    }
}
