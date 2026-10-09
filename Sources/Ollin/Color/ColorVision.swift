import Foundation
import simd

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
/// At severity 1 the simulation is a projection. A dichromat has two cone
/// responses where most people have three, so every color they can tell apart is
/// a point on a surface, and colors that differ only along the missing cone's
/// response land on the same point. A color is linearized, moved along the
/// missing cone's axis onto that surface, and encoded back; simulating a
/// simulated color leaves it where it is. A severity below 1 moves a color part
/// of the way, in a straight line in linear light from where it starts to where
/// the dichromat sees it.
///
/// The surface reaches past the colors a display can show, and a result outside
/// the range is clamped channel by channel. The clamp moves a color mostly along
/// the missing cone's response, which the simulated viewer cannot see, so over
/// the display's colors it keeps what they see several times closer than the
/// nearest color on the surface that fits would.
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

    /// Apply the simulation to one linear RGB triple.
    ///
    /// Kept separate from ``Color/simulated(_:)`` so that a caller already
    /// working in linear light does not encode and decode for nothing. The
    /// result is the model's own and can fall outside the display range: a
    /// dichromat's surface reaches past the cube of colors a display shows.
    /// ``Color/simulated(_:)`` clamps it back in.
    public func applied(toLinear r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let source = SIMD3(r, g, b)
        let seen = source + (DichromatProjection.of(kind).projected(source) - source) * severity
        return (seen.x, seen.y, seen.z)
    }

    /// The two linear transforms the GPU filter applies at this severity, with
    /// the separator that picks one per color.
    ///
    /// Each is the dichromat's half-plane projection blended with the identity
    /// by severity, which is the same straight line ``applied(toLinear:_:_:)``
    /// takes, since a color's side of the separator does not depend on severity.
    var transforms: (first: simd_double3x3, second: simd_double3x3, separator: SIMD3<Double>) {
        let projection = DichromatProjection.of(kind)
        let identity = matrix_identity_double3x3
        let s = severity
        return (identity * (1 - s) + projection.first * s,
                identity * (1 - s) + projection.second * s,
                projection.separator)
    }
}

/// A dichromat's sight as a projection of linear RGB onto the surface of colors
/// they can tell apart, along the axis of the missing cone.
///
/// Built once per kind from published measurements rather than stored as
/// numbers: the display's primaries, the cone sensitivities, and the two
/// wavelengths each kind of dichromat is known to see the same as everybody
/// else. The surface is two half-planes meeting along the gray axis; a color's
/// side of the separator says which half it lands on, and the projection never
/// moves a color across it.
struct DichromatProjection: Sendable {
    /// The transform for colors on the separator's positive side.
    let first: simd_double3x3
    /// The transform for colors on its negative side.
    let second: simd_double3x3
    /// The separating plane's normal in linear RGB.
    let separator: SIMD3<Double>

    func projected(_ color: SIMD3<Double>) -> SIMD3<Double> {
        simd_dot(separator, color) >= 0 ? first * color : second * color
    }

    static func of(_ kind: ColorVision.Kind) -> DichromatProjection {
        switch kind {
        case .protanomaly: return protan
        case .deuteranomaly: return deutan
        case .tritanomaly: return tritan
        }
    }

    // Brettel, Viénot and Mollon (1997): each half-plane holds the gray axis and
    // one light the dichromat sees as everybody else does, measured on viewers
    // with one normal eye and one dichromat eye. The red-green kinds anchor on
    // 475 nm and 575 nm, the blue-yellow kind on 485 nm and 660 nm.
    static let protan = halfPlanes(missing: 0, anchors: (Cones.blue475, Cones.yellow575))
    static let deutan = halfPlanes(missing: 1, anchors: (Cones.blue475, Cones.yellow575))
    static let tritan = halfPlanes(missing: 2, anchors: (Cones.cyan485, Cones.red660))

    private static func halfPlanes(missing axis: Int,
                                   anchors: (SIMD3<Double>, SIMD3<Double>)) -> DichromatProjection {
        // The display's white stands for the neutral axis rather than the
        // equal-energy one, so white simulates to itself and less of the cube
        // projects outside it.
        let neutral = Cones.fromLinearRGB * SIMD3(1, 1, 1)
        var one = Cones.fromXYZ * anchors.0
        var two = Cones.fromXYZ * anchors.1
        var missing = SIMD3<Double>.zero
        missing[axis] = 1
        let split = simd_cross(neutral, missing)
        if simd_dot(split, one) < 0 { swap(&one, &two) }
        let first = Cones.toLinearRGB * along(axis, onto: simd_cross(neutral, one)) * Cones.fromLinearRGB
        let second = Cones.toLinearRGB * along(axis, onto: simd_cross(neutral, two)) * Cones.fromLinearRGB
        return DichromatProjection(first: first, second: second,
                                   separator: Cones.fromLinearRGB.transpose * split)
    }

    /// Moves a cone response along one cone's axis onto the plane through the
    /// origin with the given normal: the other two responses are kept and the
    /// missing one becomes whatever puts the point on the plane.
    private static func along(_ axis: Int, onto normal: SIMD3<Double>) -> simd_double3x3 {
        var rows = [SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 0, 1)]
        var row = -normal / normal[axis]
        row[axis] = 0
        rows[axis] = row
        return simd_double3x3(rows: rows)
    }
}

/// The cone responses of linear sRGB.
private enum Cones {
    /// Smith and Pokorny's (1975) cone fundamentals as a transform from the
    /// Judd-Vos corrected tristimulus space, the one the dichromat model was
    /// measured in.
    static let fromXYZ = simd_double3x3(rows: [
        SIMD3(0.15514, 0.54312, -0.03286),
        SIMD3(-0.15514, 0.45684, 0.03286),
        SIMD3(0, 0, 0.01608),
    ])

    static let fromLinearRGB = fromXYZ * xyzFromLinearRGB
    static let toLinearRGB = fromLinearRGB.inverse

    /// The sRGB primaries and its D65 white, moved into the corrected space by
    /// Vos's (1978) chromaticity correction, then the usual construction of a
    /// display's tristimulus matrix from its primaries and white.
    static let xyzFromLinearRGB: simd_double3x3 = {
        func corrected(_ x: Double, _ y: Double) -> SIMD3<Double> {
            let d = 0.03845 * x + 0.01496 * y + 1
            let cx = (1.0271 * x - 0.00008 * y - 0.00009) / d
            let cy = (0.00376 * x + 1.0072 * y + 0.00764) / d
            return SIMD3(cx / cy, 1, (1 - cx - cy) / cy)
        }
        let primaries = simd_double3x3(columns: (corrected(0.64, 0.33),
                                                  corrected(0.30, 0.60),
                                                  corrected(0.15, 0.06)))
        let scale = primaries.inverse * corrected(0.3127, 0.3290)
        return simd_double3x3(columns: (primaries.columns.0 * scale.x,
                                        primaries.columns.1 * scale.y,
                                        primaries.columns.2 * scale.z))
    }()

    /// The Judd-Vos corrected color matching functions at the four anchor
    /// wavelengths, from the Colour & Vision Research Laboratory's table.
    static let blue475 = SIMD3(1.328700e-1, 1.128400e-1, 9.422000e-1)
    static let yellow575 = SIMD3(8.439400e-1, 9.155800e-1, 1.970600e-3)
    static let cyan485 = SIMD3(5.698500e-2, 1.698700e-1, 5.864000e-1)
    static let red660 = SIMD3(1.616100e-1, 6.100000e-2, 1.190600e-5)
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
    /// the whole judgment rather than half of it. Red and green look alike to a
    /// protanope in hue, but one is much darker than the other, so the pair is
    /// still usable. Two colors of the same lightness that differ only in hue
    /// are the ones that merge.
    ///
    /// The default tolerance is measured rather than guessed. The published
    /// eight-color safe set (``colorblindSafe``) has 0.078 between its closest
    /// pair under the worst kind, while a familiar six-color chart set falls to
    /// 0.013. A tolerance of 0.06 separates them with room on both sides.
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
    /// closest pair under the worst kind sits at 0.078, against 0.013 for a
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
