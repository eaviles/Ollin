import Foundation

// Perceptual color: the OKLab family, plus mixing in a chosen space.
//
// The conversions are implemented from the published OKLab reference math
// (credited in the README's Techniques list). Hue is a turn in `0...1`
// throughout, like the HSB initializer; alpha rides on `Color`, never on the
// component values.

// MARK: - sRGB transfer

extension Color {
    /// sRGB → linear for a single 0–1 component (the standard piecewise curve).
    static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear → sRGB for a single 0–1 component (the inverse curve).
    static func linearToSrgb(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

// MARK: - OKLab

/// A color in the OKLab perceptual space: lightness plus two opponent axes.
///
/// OKLab is the workhorse for color *math*: mixing two colors comes out
/// visually even, and changing one component doesn't drag the others around.
/// `l` is perceived lightness in `0...1`; `a` runs green → red and `b` runs
/// blue → yellow, each roughly `-0.4...0.4` for displayable colors.
public struct OKLab: Equatable, Sendable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// Convert a color to OKLab. Alpha stays on the `Color`.
    public init(_ color: Color) {
        let v = oklabFromLinear(Color.srgbToLinear(color.red),
                                Color.srgbToLinear(color.green),
                                Color.srgbToLinear(color.blue))
        self.init(l: v.l, a: v.a, b: v.b)
    }
}

/// OKLab in polar form: lightness, chroma, hue — the space for hue and
/// chroma *dials*, since turning `h` leaves lightness and colorfulness alone.
///
/// `l` is `0...1`, `h` is a turn in `0...1` (wraps), and `c` is chroma from 0
/// up — but the maximum displayable chroma depends on hue and lightness
/// (sRGB tops out around 0.37), so a dialed-up `c` can leave the screen's
/// gamut. `Color.init` maps such values back by reducing chroma at constant
/// lightness and hue.
public struct OKLCH: Equatable, Sendable {
    public var l: Double
    public var c: Double
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }

    /// Convert a color to OKLCH. An achromatic color (gray) has no hue of its
    /// own and reads back `h = 0`.
    public init(_ color: Color) {
        let lab = OKLab(color)
        let c = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        if c <= achromaticChroma {
            self.init(l: lab.l, c: 0, h: 0)
        } else {
            self.init(l: lab.l, c: c, h: wrapHue(atan2(lab.b, lab.a) / .tau))
        }
    }
}

/// The OKLab model squeezed into the sRGB gamut: hue, saturation, lightness,
/// every combination displayable.
///
/// Where OKLCH's chroma can ask for colors the screen can't show, OKHSL's
/// `s` and `l` run `0...1` and always land on a real sRGB color — the space
/// for *generated* color ("random hue, same perceived lightness"). `h` is a
/// turn in `0...1` (wraps); `s` and `l` clamp.
public struct OKHSL: Equatable, Sendable {
    public var h: Double
    public var s: Double
    public var l: Double

    public init(h: Double, s: Double, l: Double) {
        self.h = h
        self.s = s
        self.l = l
    }

    /// Convert a color to OKHSL. Black, white, and grays have no hue or
    /// saturation of their own and read back `h = 0, s = 0`.
    public init(_ color: Color) {
        let lab = OKLab(color)
        let c = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        guard c > achromaticChroma, lab.l > 1e-9, lab.l < 1 - 1e-9 else {
            self.init(h: 0, s: 0, l: toe(min(max(lab.l, 0), 1)))
            return
        }
        let cs = chromaLimits(l: lab.l, a: lab.a / c, b: lab.b / c)
        let s: Double
        if c < cs.mid {
            let k1 = okhslMid * cs.zero
            let k2 = 1 - k1 / cs.mid
            s = okhslMid * (c / (k1 + k2 * c))
        } else {
            let k0 = cs.mid
            let k1 = (1 - okhslMid) * cs.mid * cs.mid * okhslMidInv * okhslMidInv / cs.zero
            let k2 = 1 - k1 / (cs.max - cs.mid)
            s = okhslMid + (1 - okhslMid) * ((c - k0) / (k1 + k2 * (c - k0)))
        }
        self.init(h: wrapHue(atan2(lab.b, lab.a) / .tau), s: s, l: toe(lab.l))
    }
}

// MARK: - Color from the OKLab family

public extension Color {
    /// Create a color from OKLab. A value outside the sRGB gamut is mapped
    /// back by reducing chroma at constant lightness and hue, so the color
    /// stays *the same color*, just as vivid as the screen can show.
    init(_ lab: OKLab, alpha: Double = 1.0) {
        let rgb = srgbFromOKLab(l: lab.l, a: lab.a, b: lab.b)
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    /// Create a color from OKLCH. Hue wraps; an out-of-gamut chroma is
    /// reduced at constant lightness and hue.
    init(_ lch: OKLCH, alpha: Double = 1.0) {
        let angle = lch.h * Double.tau
        let c = max(lch.c, 0)
        self.init(OKLab(l: lch.l, a: c * cos(angle), b: c * sin(angle)), alpha: alpha)
    }

    /// Create a color from OKHSL. Always lands in the sRGB gamut; hue wraps,
    /// saturation and lightness clamp to `0...1`.
    init(_ hsl: OKHSL, alpha: Double = 1.0) {
        let s = min(max(hsl.s, 0), 1)
        let lightness = min(max(hsl.l, 0), 1)
        guard lightness > 0 else { self.init(white: 0, alpha: alpha); return }
        guard lightness < 1 else { self.init(white: 1, alpha: alpha); return }
        let l = toeInv(lightness)
        guard s > 1e-9 else {
            let gray = min(max(Color.linearToSrgb(l * l * l), 0), 1)
            self.init(white: gray, alpha: alpha)
            return
        }
        let angle = hsl.h * Double.tau
        let a_ = cos(angle)
        let b_ = sin(angle)
        let cs = chromaLimits(l: l, a: a_, b: b_)
        let c: Double
        if s < okhslMid {
            let t = okhslMidInv * s
            let k1 = okhslMid * cs.zero
            let k2 = 1 - k1 / cs.mid
            c = t * k1 / (1 - k2 * t)
        } else {
            let t = (s - okhslMid) / (1 - okhslMid)
            let k0 = cs.mid
            let k1 = (1 - okhslMid) * cs.mid * cs.mid * okhslMidInv * okhslMidInv / cs.zero
            let k2 = 1 - k1 / (cs.max - cs.mid)
            c = k0 + t * k1 / (1 - k2 * t)
        }
        let rgb = linearFromOKLab(l, c * a_, c * b_)
        self.init(red: min(max(Color.linearToSrgb(min(max(rgb.r, 0), 1)), 0), 1),
                  green: min(max(Color.linearToSrgb(min(max(rgb.g, 0), 1)), 0), 1),
                  blue: min(max(Color.linearToSrgb(min(max(rgb.b, 0), 1)), 0), 1),
                  alpha: alpha)
    }
}

// MARK: - Mixing

/// The space `Color.mix(_:_:t:in:)` interpolates through.
public enum ColorSpace: Sendable {
    /// Straight sRGB component interpolation — cheap, but saturated pairs dip
    /// through gray.
    case rgb
    /// Hue/saturation/brightness — travels the hue wheel, shortest way around.
    case hsb
    /// OKLab — perceptually even mixing; the default.
    case oklab
    /// OKLCH — holds hue identity and arcs through chroma instead of cutting
    /// across gray.
    case oklch
    /// OKHSL — like OKLCH but every step is displayable, so nothing clamps.
    case okhsl
}

public extension Color {
    /// Interpolate between two colors in a chosen space (OKLab by default,
    /// which mixes evenly). `t` clamps to `0...1`; alpha interpolates
    /// linearly. In the polar spaces hue takes the shortest arc, and an
    /// achromatic endpoint (gray, black, white) adopts the other's hue so a
    /// fade to white doesn't swing through unrelated hues.
    static func mix(_ x: Color, _ y: Color, t: Double, in space: ColorSpace = .oklab) -> Color {
        let t = min(max(t, 0), 1)
        let alpha = x.alpha + (y.alpha - x.alpha) * t
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        switch space {
        case .rgb:
            return Color(red: lerp(x.red, y.red), green: lerp(x.green, y.green),
                         blue: lerp(x.blue, y.blue), alpha: alpha)
        case .hsb:
            let a = x.hsbComponents
            let b = y.hsbComponents
            let aChromatic = a.s > 1e-9 && a.v > 1e-9
            let bChromatic = b.s > 1e-9 && b.v > 1e-9
            let ha = aChromatic ? a.h : b.h
            let hb = bChromatic ? b.h : a.h
            return Color(hue: lerpHue(ha, hb, t), saturation: lerp(a.s, b.s),
                         brightness: lerp(a.v, b.v), alpha: alpha)
        case .oklab:
            let a = OKLab(x)
            let b = OKLab(y)
            return Color(OKLab(l: lerp(a.l, b.l), a: lerp(a.a, b.a), b: lerp(a.b, b.b)),
                         alpha: alpha)
        case .oklch:
            let a = OKLCH(x)
            let b = OKLCH(y)
            let ha = a.c > 1e-5 ? a.h : b.h
            let hb = b.c > 1e-5 ? b.h : a.h
            return Color(OKLCH(l: lerp(a.l, b.l), c: lerp(a.c, b.c), h: lerpHue(ha, hb, t)),
                         alpha: alpha)
        case .okhsl:
            let a = OKHSL(x)
            let b = OKHSL(y)
            let ha = a.s > 1e-5 ? a.h : b.h
            let hb = b.s > 1e-5 ? b.h : a.h
            return Color(OKHSL(h: lerpHue(ha, hb, t), s: lerp(a.s, b.s), l: lerp(a.l, b.l)),
                         alpha: alpha)
        }
    }
}

extension Color {
    /// RGB → hue/saturation/brightness, the inverse of `init(hue:saturation:brightness:)`.
    var hsbComponents: (h: Double, s: Double, v: Double) {
        let hi = max(red, green, blue)
        let lo = min(red, green, blue)
        let d = hi - lo
        guard d > 0 else { return (0, 0, hi) }
        var h: Double
        if hi == red {
            h = (green - blue) / d
        } else if hi == green {
            h = (blue - red) / d + 2
        } else {
            h = (red - green) / d + 4
        }
        h = wrapHue(h / 6)
        return (h, hi > 0 ? d / hi : 0, hi)
    }
}

/// Below this chroma a color counts as achromatic: the published conversion
/// matrices don't cancel to exactly zero on grays (the residual is ≈ 4e-8),
/// so an exact-zero test would hand grays a garbage hue.
private let achromaticChroma = 1e-7

/// Wrap a hue in turns onto `0..<1`.
private func wrapHue(_ h: Double) -> Double {
    let w = h.truncatingRemainder(dividingBy: 1)
    return w < 0 ? w + 1 : w
}

/// Interpolate two hues (in turns) along the shorter way around the wheel.
private func lerpHue(_ a: Double, _ b: Double, _ t: Double) -> Double {
    var d = (b - a).truncatingRemainder(dividingBy: 1)
    if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
    return wrapHue(a + d * t)
}

// MARK: - OKLab core math

private func oklabFromLinear(_ r: Double, _ g: Double, _ b: Double)
    -> (l: Double, a: Double, b: Double) {
    let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    let l_ = cbrt(l)
    let m_ = cbrt(m)
    let s_ = cbrt(s)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
}

private func linearFromOKLab(_ l: Double, _ a: Double, _ b: Double)
    -> (r: Double, g: Double, b: Double) {
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b
    let lc = l_ * l_ * l_
    let mc = m_ * m_ * m_
    let sc = s_ * s_ * s_
    return (4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc,
            -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc,
            -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc)
}

/// OKLab → sRGB with gamut mapping: an out-of-gamut value is brought back by
/// reducing chroma at constant lightness and hue.
private func srgbFromOKLab(l: Double, a: Double, b: Double) -> (r: Double, g: Double, b: Double) {
    func encode(_ rgb: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
        (min(max(Color.linearToSrgb(min(max(rgb.r, 0), 1)), 0), 1),
         min(max(Color.linearToSrgb(min(max(rgb.g, 0), 1)), 0), 1),
         min(max(Color.linearToSrgb(min(max(rgb.b, 0), 1)), 0), 1))
    }
    let eps = 1e-6
    let direct = linearFromOKLab(l, a, b)
    if (-eps...1 + eps).contains(direct.r), (-eps...1 + eps).contains(direct.g),
       (-eps...1 + eps).contains(direct.b), (0...1).contains(l) {
        return encode(direct)
    }
    let lc = min(max(l, 0), 1)
    let c = (a * a + b * b).squareRoot()
    guard c > achromaticChroma else { return encode(linearFromOKLab(lc, 0, 0)) }
    let a_ = a / c
    let b_ = b / c
    let cusp = findCusp(a_, b_)
    // With c1 = 1 the intersection fraction *is* the boundary chroma.
    let cMax = max(0, gamutIntersection(a_, b_, l1: lc, c1: 1, l0: lc, cusp: cusp))
    let cMapped = min(c, cMax)
    return encode(linearFromOKLab(lc, cMapped * a_, cMapped * b_))
}

/// The largest saturation `S = C/L` displayable for a normalized hue
/// direction, via the published per-channel polynomial plus one Halley step.
private func maxSaturation(_ a: Double, _ b: Double) -> Double {
    let k: (Double, Double, Double, Double, Double)
    let w: (l: Double, m: Double, s: Double)
    if -1.88170328 * a - 0.80936493 * b > 1 {
        k = (1.19086277, 1.76576728, 0.59662641, 0.75515197, 0.56771245)
        w = (4.0767416621, -3.3077115913, 0.2309699292)
    } else if 1.81444104 * a - 1.19445276 * b > 1 {
        k = (0.73956515, -0.45954404, 0.08285427, 0.12541070, 0.14503204)
        w = (-1.2684380046, 2.6097574011, -0.3413193965)
    } else {
        k = (1.35733652, -0.00915799, -1.15130210, -0.50559606, 0.00692167)
        w = (-0.0041960863, -0.7034186147, 1.7076147010)
    }
    var s = k.0 + k.1 * a + k.2 * b + k.3 * a * a + k.4 * a * b
    let kl = 0.3963377774 * a + 0.2158037573 * b
    let km = -0.1055613458 * a - 0.0638541728 * b
    let ks = -0.0894841775 * a - 1.2914855480 * b
    let l_ = 1 + s * kl
    let m_ = 1 + s * km
    let s_ = 1 + s * ks
    let f = w.l * l_ * l_ * l_ + w.m * m_ * m_ * m_ + w.s * s_ * s_ * s_
    let f1 = 3 * (w.l * kl * l_ * l_ + w.m * km * m_ * m_ + w.s * ks * s_ * s_)
    let f2 = 6 * (w.l * kl * kl * l_ + w.m * km * km * m_ + w.s * ks * ks * s_)
    s -= f * f1 / (f1 * f1 - 0.5 * f * f2)
    return s
}

/// The cusp of the sRGB gamut slice for a normalized hue direction — the
/// (lightness, chroma) where the gamut is widest.
private func findCusp(_ a: Double, _ b: Double) -> (l: Double, c: Double) {
    let sCusp = maxSaturation(a, b)
    let rgb = linearFromOKLab(1, sCusp * a, sCusp * b)
    let lCusp = cbrt(1 / max(rgb.r, max(rgb.g, rgb.b)))
    return (lCusp, lCusp * sCusp)
}

/// Where the segment from `(l0, 0)` toward `(l1, c1)` crosses the sRGB gamut
/// boundary, as a fraction of the segment (so `t * c1` is the chroma there).
/// Lower-half crossings are exact; upper-half ones take one Halley step.
private func gamutIntersection(_ a: Double, _ b: Double, l1: Double, c1: Double, l0: Double,
                               cusp: (l: Double, c: Double)) -> Double {
    var t: Double
    if (l1 - l0) * cusp.c - (cusp.l - l0) * c1 <= 0 {
        t = cusp.c * l0 / (c1 * cusp.l + cusp.c * (l0 - l1))
    } else {
        t = cusp.c * (l0 - 1) / (c1 * (cusp.l - 1) + cusp.c * (l0 - l1))
        let dl = l1 - l0
        let kl = 0.3963377774 * a + 0.2158037573 * b
        let km = -0.1055613458 * a - 0.0638541728 * b
        let ks = -0.0894841775 * a - 1.2914855480 * b
        let lDt = dl + c1 * kl
        let mDt = dl + c1 * km
        let sDt = dl + c1 * ks
        let l = l0 * (1 - t) + t * l1
        let c = t * c1
        let l_ = l + c * kl
        let m_ = l + c * km
        let s_ = l + c * ks
        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_
        let ldt = 3 * lDt * l_ * l_
        let mdt = 3 * mDt * m_ * m_
        let sdt = 3 * sDt * s_ * s_
        let ldt2 = 6 * lDt * lDt * l_
        let mdt2 = 6 * mDt * mDt * m_
        let sdt2 = 6 * sDt * sDt * s_
        func step(_ wl: Double, _ wm: Double, _ ws: Double) -> Double {
            let f = wl * lc + wm * mc + ws * sc - 1
            let f1 = wl * ldt + wm * mdt + ws * sdt
            let f2 = wl * ldt2 + wm * mdt2 + ws * sdt2
            let u = f1 / (f1 * f1 - 0.5 * f * f2)
            return u >= 0 ? -f * u : .greatestFiniteMagnitude
        }
        let tR = step(4.0767416621, -3.3077115913, 0.2309699292)
        let tG = step(-1.2684380046, 2.6097574011, -0.3413193965)
        let tB = step(-0.0041960863, -0.7034186147, 1.7076147010)
        t += min(tR, min(tG, tB))
    }
    return t
}

// MARK: - OKHSL helpers

private let okhslMid = 0.8
private let okhslMidInv = 1.25

/// The lightness remap that makes OKHSL's `l` match familiar lightness
/// scales near black (and its inverse).
private func toe(_ x: Double) -> Double {
    let k1 = 0.206
    let k2 = 0.03
    let k3 = (1 + k1) / (1 + k2)
    return 0.5 * (k3 * x - k1 + ((k3 * x - k1) * (k3 * x - k1) + 4 * k2 * k3 * x).squareRoot())
}

private func toeInv(_ x: Double) -> Double {
    let k1 = 0.206
    let k2 = 0.03
    let k3 = (1 + k1) / (1 + k2)
    return (x * x + k1 * x) / (k3 * (x + k2))
}

/// A polynomial fit of the gamut's "soft middle" used by OKHSL's saturation
/// remap.
private func stMid(_ a: Double, _ b: Double) -> (s: Double, t: Double) {
    let s = 0.11516993 + 1 / (7.44778970 + 4.15901240 * b
        + a * (-2.19557347 + 1.75198401 * b
            + a * (-2.13704948 - 10.02301043 * b
                + a * (-4.24894561 + 5.38770819 * b + 4.69891013 * a))))
    let t = 0.11239642 + 1 / (1.61320320 - 0.68124379 * b
        + a * (0.40370612 + 0.90148123 * b
            + a * (-0.27087943 + 0.61223990 * b
                + a * (0.00299215 - 0.45399568 * b - 0.14661872 * a))))
    return (s, t)
}

/// The three chroma landmarks (`C_0`, `C_mid`, `C_max`) OKHSL stretches its
/// saturation axis over, for a lightness and normalized hue direction.
private func chromaLimits(l: Double, a: Double, b: Double)
    -> (zero: Double, mid: Double, max: Double) {
    let cusp = findCusp(a, b)
    let cMax = max(0, gamutIntersection(a, b, l1: l, c1: 1, l0: l, cusp: cusp))
    let stMax = (s: cusp.c / cusp.l, t: cusp.c / (1 - cusp.l))
    let k = cMax / min(l * stMax.s, (1 - l) * stMax.t)
    let mid = stMid(a, b)
    let ca = l * mid.s
    let cb = (1 - l) * mid.t
    let cMid = 0.9 * k * ((1 / (1 / (ca * ca * ca * ca) + 1 / (cb * cb * cb * cb)))
        .squareRoot()).squareRoot()
    let ca0 = l * 0.4
    let cb0 = (1 - l) * 0.8
    let c0 = (1 / (1 / (ca0 * ca0) + 1 / (cb0 * cb0))).squareRoot()
    return (c0, cMid, cMax)
}
