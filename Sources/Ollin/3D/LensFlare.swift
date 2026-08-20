import Foundation
import simd

/// One optical interface in a lens: the boundary between two media, spherical
/// or flat.
///
/// A lens is described the way its designer describes it, as a stack of these
/// read from the front of the barrel toward the sensor. Every distance is in
/// millimeters, which is what a published prescription uses.
public struct LensInterface: Equatable, Sendable {

    /// The signed curvature radius. Positive curves toward the subject,
    /// negative away from it, and `0` means a flat surface (an infinite
    /// radius). The iris is always flat.
    public var radius: Double

    /// The distance from this interface to the next one. The last interface's
    /// thickness is the back focal distance, the gap to the sensor.
    public var thickness: Double

    /// The refractive index of the medium *after* this interface. Air is `1`.
    public var refractiveIndex: Double

    /// The radius of the clear opening. Only two of these matter to a flare:
    /// the front interface, which is the entrance pupil, and the iris.
    public var height: Double

    /// Whether this interface is the iris, the adjustable opening that shapes
    /// every ghost and the star.
    public var isIris: Bool

    /// The wavelength in nanometers this surface's coating is tuned for, or
    /// `nil` to use the lens's own. A coating is a quarter of a wavelength
    /// thick, so it cancels that wavelength best and the ones either side of it
    /// least. Setting different wavelengths on different surfaces is what a
    /// multicoated lens does, and it is why its ghosts come out in different
    /// colors instead of all in one. Only a surface with air on one side can
    /// carry a coating: a cemented junction already has cement between its two
    /// glasses.
    public var coating: Double?

    public init(radius: Double, thickness: Double, refractiveIndex: Double = 1,
                height: Double, isIris: Bool = false, coating: Double? = nil) {
        self.radius = radius
        self.thickness = thickness
        self.refractiveIndex = refractiveIndex
        self.height = height
        self.isIris = isIris
        self.coating = coating
    }

    /// An iris: a flat stop of a given opening radius, `thickness` to the next
    /// interface.
    public static func iris(thickness: Double, height: Double) -> LensInterface {
        LensInterface(radius: 0, thickness: thickness, refractiveIndex: 1,
                      height: height, isIris: true)
    }
}

/// A photographic lens, described as the stack of interfaces light crosses on
/// its way to the sensor.
///
/// This is what gives a flare its own character. Light that reflects off two of
/// these interfaces instead of passing through them comes back to the sensor in
/// the wrong place, and that misplaced light is a *ghost*. Which ghosts a lens
/// makes, where they sit, how big they are, and what color they are all follow
/// from the stack, so two lenses flare differently for the same reason they
/// look different: the glass is arranged differently.
///
/// You rarely build one by hand. `Lens.heliar` is bundled, and a lens patent
/// prints the same table this type holds, so a published prescription can be
/// typed in directly.
public struct Lens: Equatable, Sendable {

    /// The interfaces, front of the barrel first.
    public var interfaces: [LensInterface]

    /// The wavelength in nanometers the anti-reflective coating is tuned for.
    /// A coating cancels its own wavelength best and the ones either side of it
    /// least, which is why ghosts are colored rather than gray. Around 550 is
    /// the usual choice, the middle of what the eye sees best.
    public var coatingWavelength: Double

    /// The f-number the iris is stopped down to. Higher closes the iris, which
    /// makes every ghost smaller and harder edged. `nil` leaves the iris wide
    /// open at the opening the prescription gives it.
    public var fStop: Double?

    public init(interfaces: [LensInterface], coatingWavelength: Double = 550,
                fStop: Double? = nil) {
        self.interfaces = interfaces
        self.coatingWavelength = coatingWavelength
        self.fStop = fStop
    }

    /// The same lens stopped down to an f-number.
    public func stopped(to fStop: Double) -> Lens {
        var lens = self
        lens.fStop = max(0.5, fStop)
        return lens
    }

    /// The same lens with its exposed surfaces coated for a spread of
    /// wavelengths instead of all for one, which is how a modern lens is made.
    ///
    /// One coating everywhere leaves every ghost the same color, the single
    /// magenta cast of an older lens. Spreading the coatings is what puts a
    /// lens's ghosts in greens, ambers, and blues, since each surface then
    /// passes on a different part of the spectrum.
    public func multicoated(from: Double = 440, to: Double = 660) -> Lens {
        var lens = self
        let exposed = lens.interfaces.indices.filter { i in
            !lens.interfaces[i].isIris
                && (i == 0 || lens.interfaces[i - 1].refractiveIndex < 1.05
                    || lens.interfaces[i].refractiveIndex < 1.05)
        }
        guard exposed.count > 1 else { return lens }
        for (step, index) in exposed.enumerated() {
            let t = Double(step) / Double(exposed.count - 1)
            lens.interfaces[index].coating = from + (to - from) * t
        }
        return lens
    }

    /// A 1950s five-element Heliar-type portrait lens of about 100mm: a
    /// cemented front doublet, a single middle element, the iris, and a
    /// cemented rear doublet. Few interfaces, so it makes few ghosts and they
    /// are large and clean, which is the classic photographic flare.
    ///
    /// The prescription is the published table from the patent literature, in
    /// the form the flare paper credited in `ATTRIBUTION.md` tabulates it.
    public static let heliar = Lens(interfaces: [
        LensInterface(radius:  30.810, thickness:  7.700, refractiveIndex: 1.652, height: 14.5),
        LensInterface(radius: -89.350, thickness:  1.850, refractiveIndex: 1.603, height: 14.5),
        LensInterface(radius: 580.380, thickness:  3.520, refractiveIndex: 1.000, height: 14.5),
        LensInterface(radius: -80.630, thickness:  1.850, refractiveIndex: 1.643, height: 12.3),
        LensInterface(radius:  28.340, thickness:  4.180, refractiveIndex: 1.000, height: 12.0),
        LensInterface.iris(thickness: 3.000, height: 11.6),
        LensInterface(radius:   0.000, thickness:  1.850, refractiveIndex: 1.581, height: 12.3),
        LensInterface(radius:  32.190, thickness:  7.270, refractiveIndex: 1.694, height: 12.3),
        LensInterface(radius: -52.990, thickness: 81.857, refractiveIndex: 1.000, height: 12.3),
    ])
}

/// The lens flare a camera adds to a scene: the ghosts a bright light leaves
/// when some of it reflects around inside the lens instead of passing through.
///
/// Everything the renderer models is light and surface. A flare is neither. It
/// is the *camera* misbehaving, so it composites in linear light with the rest
/// of the frame, before the tone map, the way the light in a real lens reaches
/// the sensor before the film responds to it.
public struct LensFlare: Equatable, Sendable {

    /// The lens whose interfaces make the ghosts.
    public var lens: Lens

    /// How strong the flare is. `1` is the default reading, `0` removes it, and
    /// higher pushes it past what a lens would really do.
    ///
    /// A flare is a lens defect, and a piece may want it in small measure or not
    /// at all, so this is the honesty dial: turn it down until the flare reads as
    /// light in the camera rather than as paint on the picture.
    ///
    /// The frame's brightest source sets the scale and the others fall off
    /// against it, so this means the same thing whatever numbers a sketch lights
    /// its scene with. What each ghost does relative to the others, in size,
    /// place, and color, is the lens's business and not this dial's.
    public var strength: Double

    /// How far off the edge of the frame a light still flares, as a fraction of
    /// the frame height. A source just outside the picture is the classic case,
    /// so this reaches past the frame by default.
    public var reach: Double

    /// How much of the frame the visibility test looks at around a source, as a
    /// fraction of the frame height. This is the size the source is treated as
    /// having: a flare fades as an occluder covers that disc, rather than
    /// switching off the moment the source's center goes behind something.
    public var sourceSize: Double

    public init(lens: Lens = .heliar, strength: Double = 1,
                reach: Double = 0.55, sourceSize: Double = 0.035) {
        self.lens = lens
        self.strength = max(0, strength)
        self.reach = max(0, reach)
        self.sourceSize = max(0.001, sourceSize)
    }
}

// MARK: - Paraxial ray transfer

/// A 2 by 2 ray transfer matrix acting on a paraxial ray `(height, angle)`.
///
/// First-order optics treats every interface as a linear map on a ray measured
/// by how far off the axis it is and how steeply it runs, so a whole lens is
/// one matrix product. That is what makes a flare cheap enough to draw every
/// frame: the reflections happen in the matrix, not in a ray trace.
struct RayTransfer: Equatable {
    var a: Double, b: Double, c: Double, d: Double

    static let identity = RayTransfer(a: 1, b: 0, c: 0, d: 1)

    /// Travel a distance through a homogeneous medium.
    static func travel(_ distance: Double) -> RayTransfer {
        RayTransfer(a: 1, b: distance, c: 0, d: 1)
    }

    /// Refraction at a spherical interface, from index `from` into index `to`.
    /// A `radius` of 0 is flat, which drops the curvature term.
    static func refraction(radius: Double, from n1: Double, to n2: Double) -> RayTransfer {
        let power = radius == 0 ? 0 : (n1 - n2) / (n2 * radius)
        return RayTransfer(a: 1, b: 0, c: power, d: n1 / n2)
    }

    /// Reflection off a spherical interface. A flat one leaves the ray alone,
    /// which is right: a flat mirror turns the ray around without bending it.
    static func reflection(radius: Double) -> RayTransfer {
        RayTransfer(a: 1, b: 0, c: radius == 0 ? 0 : 2 / radius, d: 1)
    }

    /// The inverse, which is what a ray traveling back through an interface it
    /// already crossed needs. Translations are not inverted: a ray running
    /// backward still covers a positive distance in its own direction.
    var inverse: RayTransfer {
        let det = a * d - b * c
        guard abs(det) > 1e-12 else { return .identity }
        return RayTransfer(a: d / det, b: -b / det, c: -c / det, d: a / det)
    }

    static func * (lhs: RayTransfer, rhs: RayTransfer) -> RayTransfer {
        RayTransfer(a: lhs.a * rhs.a + lhs.b * rhs.c,
                    b: lhs.a * rhs.b + lhs.b * rhs.d,
                    c: lhs.c * rhs.a + lhs.d * rhs.c,
                    d: lhs.c * rhs.b + lhs.d * rhs.d)
    }

    /// Apply to a ray, returning the ray that arrives at the far side.
    func applied(height: Double, angle: Double) -> (height: Double, angle: Double) {
        (a * height + b * angle, c * height + d * angle)
    }
}

/// One ghost: the light that reflects off a pair of interfaces and lands on the
/// sensor anyway.
struct LensGhost: Equatable {
    /// Where the first (inner) reflection happens, as an index into the lens.
    var firstInterface: Int
    /// Where the second (outer) reflection happens.
    var secondInterface: Int
    /// Maps a point on the entrance pupil to the sensor: `sensor = a·pupil + b·angle`.
    var toSensor: (a: Double, b: Double)
    /// Maps the same point to the iris plane, which is what shapes the ghost.
    var toIris: (a: Double, b: Double)

    static func == (lhs: LensGhost, rhs: LensGhost) -> Bool {
        lhs.firstInterface == rhs.firstInterface && lhs.secondInterface == rhs.secondInterface
            && lhs.toSensor == rhs.toSensor && lhs.toIris == rhs.toIris
    }
}

/// The paraxial description of a lens: the ghost list plus the few scalars a
/// flare needs. Built once per lens and cached, because none of it moves when
/// the light does.
struct LensOptics: Equatable {
    /// Every ghost the interface pairs make, brightest geometry first.
    var ghosts: [LensGhost]
    /// The radius of the front opening, in millimeters.
    var pupilRadius: Double
    /// The radius of the iris opening after the f-number is applied.
    var irisRadius: Double
    /// Sensor height per unit ray angle for light that goes straight through,
    /// which is the scale that puts a ghost where the picture is.
    var directScale: Double
    /// The focal length worked out from the stack.
    var focalLength: Double
}

extension Lens {

    /// The index of the medium in front of interface `i`.
    private func indexBefore(_ i: Int) -> Double {
        i == 0 ? 1 : interfaces[i - 1].refractiveIndex
    }

    /// Whether interface `i` reflects. The iris is an opening, not a surface,
    /// and a boundary between two identical media reflects nothing.
    private func reflects(_ i: Int) -> Bool {
        !interfaces[i].isIris && abs(indexBefore(i) - interfaces[i].refractiveIndex) > 1e-9
    }

    /// Refract at interface `i`, then travel to the next one.
    private func forwardStep(_ i: Int) -> RayTransfer {
        RayTransfer.travel(interfaces[i].thickness)
            * RayTransfer.refraction(radius: interfaces[i].radius,
                                     from: indexBefore(i), to: interfaces[i].refractiveIndex)
    }

    /// The run from a ray leaving interface `a` forward (it has just reflected
    /// there, so it does not refract there) to a ray arriving at interface `b`.
    /// Pass `interfaces.count` for `b` to reach the sensor.
    private func forwardRun(after a: Int, to b: Int) -> RayTransfer {
        var m = RayTransfer.travel(interfaces[a].thickness)
        var k = a + 1
        while k < b {
            m = forwardStep(k) * m
            k += 1
        }
        return m
    }

    /// Travel back to interface `i`, then undo its refraction. This is the leg
    /// between the two reflections.
    private func backwardStep(_ i: Int) -> RayTransfer {
        RayTransfer.refraction(radius: interfaces[i].radius,
                               from: indexBefore(i), to: interfaces[i].refractiveIndex).inverse
            * RayTransfer.travel(interfaces[i].thickness)
    }

    /// What the straight-through path does to a point on the entrance pupil.
    /// Near zero says the sensor sits at the focal plane, which is where a lens
    /// focused on the far distance puts it.
    var directPupilScale: Double { directMatrix.a }

    /// The matrix for light that passes straight through, from the entrance
    /// pupil to the sensor.
    private var directMatrix: RayTransfer {
        var m = RayTransfer.identity
        for i in interfaces.indices { m = forwardStep(i) * m }
        return m
    }

    /// The focal length, read off the refracting stack. The lower-left term of
    /// a system matrix is the negative reciprocal of the focal length.
    var focalLength: Double {
        var m = RayTransfer.identity
        for i in interfaces.indices {
            m = RayTransfer.refraction(radius: interfaces[i].radius,
                                       from: indexBefore(i), to: interfaces[i].refractiveIndex) * m
            if i < interfaces.count - 1 { m = RayTransfer.travel(interfaces[i].thickness) * m }
        }
        return m.c == 0 ? 0 : -1 / m.c
    }

    /// Work out everything a flare needs from the prescription: which pairs of
    /// interfaces make a ghost, and what each pair does to the light.
    ///
    /// Only paths with exactly two reflections are ghosts. One reflection sends
    /// the light back out of the front, and four is dim enough to ignore. Both
    /// reflections have to sit on the same side of the iris: light that
    /// reflects across it would have to cross the opening three times, and the
    /// opening is small, so that path carries almost nothing.
    func optics() -> LensOptics {
        guard interfaces.count >= 2 else {
            return LensOptics(ghosts: [], pupilRadius: 0, irisRadius: 0,
                              directScale: 0, focalLength: 0)
        }
        let irisIndex = interfaces.firstIndex { $0.isIris }
        let f = focalLength
        let openHeight = irisIndex.map { interfaces[$0].height } ?? interfaces[0].height
        let stopped = fStop.map { abs(f) / (2 * $0) } ?? .infinity

        var ghosts: [LensGhost] = []
        // The forward run to each interface, so a pair's matrices are a few
        // multiplications rather than a walk from the front every time.
        var forwardTo: [RayTransfer] = []
        var run = RayTransfer.identity
        for i in interfaces.indices {
            forwardTo.append(run)          // the ray arriving at interface i
            run = forwardStep(i) * run
        }

        for second in interfaces.indices where reflects(second) {
            for first in 0..<second where reflects(first) {
                if let ap = irisIndex, (first < ap) != (second < ap) { continue }
                // Forward to the outer reflection, bounce, walk back to the
                // inner one, bounce again, then run out to the sensor.
                var m = RayTransfer.reflection(radius: interfaces[second].radius) * forwardTo[second]
                for k in stride(from: second, through: first + 1, by: -1) {
                    m = backwardStep(k - 1) * m
                }
                m = RayTransfer.reflection(radius: interfaces[first].radius) * m
                let full = forwardRun(after: first, to: interfaces.count) * m
                // The iris plane is where the ghost takes its shape. When both
                // reflections sit behind the iris the light reaches it before
                // bouncing, so that leg is the plain forward run.
                let irisMatrix: RayTransfer
                if let ap = irisIndex {
                    irisMatrix = first > ap ? forwardTo[ap] : (forwardRun(after: first, to: ap) * m)
                } else {
                    irisMatrix = full
                }
                guard full.a.isFinite, full.b.isFinite, abs(full.a) > 1e-9 else { continue }
                ghosts.append(LensGhost(firstInterface: first, secondInterface: second,
                                        toSensor: (full.a, full.b),
                                        toIris: (irisMatrix.a, irisMatrix.b)))
            }
        }
        return LensOptics(ghosts: ghosts,
                          pupilRadius: interfaces[0].height,
                          irisRadius: min(openHeight, stopped),
                          directScale: directMatrix.b,
                          focalLength: f)
    }
}

// MARK: - Anti-reflective coating

/// How much light one coated interface reflects, at a wavelength and an angle.
///
/// A lens interface carries a quarter-wave coating that makes the two
/// reflections off its two faces cancel. The cancellation is exact only at the
/// wavelength the coating is cut for, and only head on, so what survives is
/// both colored and angle dependent. This is where a ghost gets its color, and
/// why a ghost near the middle of the frame is a different color from one near
/// the corner.
///
/// Written from the published thin-film interference formula, credited in
/// `ATTRIBUTION.md`.
///
/// - Parameters:
///   - angle: the angle of incidence, in radians.
///   - wavelength: the light's wavelength, in nanometers.
///   - designWavelength: the wavelength the coating is tuned for, in nanometers.
///   - n0: the index of the medium the light arrives through.
///   - n2: the index of the medium beyond the interface.
func coatedReflectance(angle: Double, wavelength: Double, designWavelength: Double,
                       n0: Double, n2: Double) -> Double {
    // The coating that cancels best sits at the geometric mean of the two
    // media, but no real material goes below about 1.38.
    let n1 = max((n0 * n2).squareRoot(), 1.38)
    let thickness = designWavelength / 4 / n1

    let sin0 = min(1, max(-1, sin(angle)))
    let sin1 = sin0 * n0 / n1
    let sin2 = sin0 * n0 / n2
    // Past the critical angle nothing crosses into the far medium: the light
    // turns around whole, and a coating that works by cancelling the reflection
    // off the far face has nothing to cancel.
    guard abs(sin1) <= 1, abs(sin2) <= 1 else { return 1 }
    let theta0 = angle, theta1 = asin(sin1), theta2 = asin(sin2)
    // The cancellation needs a wave running into the far medium, and that wave
    // flattens out as the angle approaches critical, taking the coating's effect
    // with it. Weighting by how squarely the far wave still travels carries the
    // reflectance smoothly up to the whole-of-it that lies past the critical
    // angle, instead of stepping there.
    let coating = cos(theta2)
    let bare = uncoatedReflectance(angle: angle, n0: n0, n2: n2)

    // Head on the sine and tangent forms both become singular, so take the
    // normal-incidence limit there instead.
    if theta0 + theta1 <= 1e-6 || theta1 + theta2 <= 1e-6 {
        let r01 = (n0 - n1) / (n0 + n1)
        let r12 = (n1 - n2) / (n1 + n2)
        let t01 = 2 * n0 / (n0 + n1)
        let inner = t01 * t01 * r12
        let phase = 4 * Double.pi / wavelength * thickness * n1
        let amplitude = r01 * r01 + inner * inner + 2 * r01 * inner * cos(phase)
        return min(1, max(0, amplitude))
    }

    // Amplitudes for the reflection and transmission at the outer face, split
    // by polarization: only waves of the same polarization interfere.
    let rs01 = -sin(theta0 - theta1) / sin(theta0 + theta1)
    let rp01 = tan(theta0 - theta1) / tan(theta0 + theta1)
    let ts01 = 2 * sin(theta1) * cos(theta0) / sin(theta0 + theta1)
    let tp01 = ts01 * cos(theta0 - theta1)
    // The inner face, reached after crossing the coating.
    let rs12 = -sin(theta1 - theta2) / sin(theta1 + theta2)
    let rp12 = tan(theta1 - theta2) / tan(theta1 + theta2)
    // The inner reflection reaches the outside again after two crossings.
    let innerS = ts01 * ts01 * rs12
    let innerP = tp01 * tp01 * rp12

    // How far the inner path runs behind the outer one, as a phase.
    let dy = thickness * n1
    let dx = tan(theta1) * dy
    let delay = (dx * dx + dy * dy).squareRoot()
    let relativePhase = 4 * Double.pi / wavelength * (delay - dx * sin0)

    let outS = rs01 * rs01 + innerS * innerS + 2 * rs01 * innerS * cos(relativePhase)
    let outP = rp01 * rp01 + innerP * innerP + 2 * rp01 * innerP * cos(relativePhase)
    let coated = min(1, max(0, (outS + outP) / 2))
    return coated * coating + bare * (1 - coating)
}

/// How much light a plain uncoated interface reflects, at an angle.
///
/// A cemented junction between two glasses cannot be coated: the cement is
/// already between them. It reflects very little, since the two indices are
/// close, but it does not reflect nothing, and the faint ghosts it makes are
/// part of the lens's character.
func uncoatedReflectance(angle: Double, n0: Double, n2: Double) -> Double {
    let sin0 = min(1, max(-1, sin(angle)))
    let sin2 = sin0 * n0 / n2
    guard abs(sin2) <= 1 else { return 1 }   // past the critical angle, all of it
    let cos0 = (1 - sin0 * sin0).squareRoot()
    let cos2 = (1 - sin2 * sin2).squareRoot()
    let rs = (n0 * cos0 - n2 * cos2) / (n0 * cos0 + n2 * cos2)
    let rp = (n0 * cos2 - n2 * cos0) / (n0 * cos2 + n2 * cos0)
    return min(1, max(0, (rs * rs + rp * rp) / 2))
}

/// What one interface of a lens reflects, coated where a coating can go.
///
/// Only a surface with air on one side carries one, so a cemented junction
/// falls back to plain Fresnel.
func interfaceReflectance(angle: Double, wavelength: Double, designWavelength: Double,
                          n0: Double, n2: Double) -> Double {
    let exposed = n0 < 1.05 || n2 < 1.05
    guard exposed else { return uncoatedReflectance(angle: angle, n0: n0, n2: n2) }
    return coatedReflectance(angle: angle, wavelength: wavelength,
                             designWavelength: designWavelength, n0: n0, n2: n2)
}

extension Lens {

    /// The wavelengths in nanometers the three channels stand for. The picture
    /// is made of three numbers, so the spectrum is sampled three times.
    static let channelWavelengths = SIMD3<Double>(650, 510, 475)

    /// How steeply the light meets each of a ghost's two reflecting surfaces,
    /// and which media sit either side of them.
    ///
    /// Follow the middle of the pupil through the stack, so each bounce knows
    /// the height it happens at: a paraxial surface normal at height `h` leans
    /// by `h / radius`, and the angle to that normal is what the coating
    /// responds to. This is why a ghost changes color as the source crosses the
    /// frame, and why the two bounces of one ghost are colored differently.
    func ghostIncidence(_ ghost: LensGhost, angle: Double)
        -> (outer: (angle: Double, from: Double, to: Double),
            inner: (angle: Double, from: Double, to: Double)) {
        var height = 0.0
        var slope = angle
        for i in 0..<ghost.secondInterface {
            (height, slope) = forwardStep(i).applied(height: height, angle: slope)
        }
        let outer = interfaces[ghost.secondInterface]
        let outerAngle = abs(slope - (outer.radius == 0 ? 0 : height / outer.radius))
        // Turn around and walk back to the inner reflection.
        (height, slope) = RayTransfer.reflection(radius: outer.radius)
            .applied(height: height, angle: slope)
        for k in stride(from: ghost.secondInterface, through: ghost.firstInterface + 1, by: -1) {
            (height, slope) = backwardStep(k - 1).applied(height: height, angle: slope)
        }
        let inner = interfaces[ghost.firstInterface]
        let innerAngle = abs(slope - (inner.radius == 0 ? 0 : height / inner.radius))
        // Coming back, the light meets the inner surface from the far side.
        return ((outerAngle, indexBefore(ghost.secondInterface), outer.refractiveIndex),
                (innerAngle, inner.refractiveIndex, indexBefore(ghost.firstInterface)))
    }

    /// What each ghost reflects, per channel, for light arriving at `angle`. The
    /// light bounces twice, so the two reflectances multiply.
    func ghostReflectance(_ ghost: LensGhost, angle: Double) -> SIMD3<Double> {
        let (outer, inner) = ghostIncidence(ghost, angle: angle)
        let wavelengths = Lens.channelWavelengths
        var product = SIMD3<Double>(1, 1, 1)
        let outerDesign = interfaces[ghost.secondInterface].coating ?? coatingWavelength
        let innerDesign = interfaces[ghost.firstInterface].coating ?? coatingWavelength
        for channel in 0..<3 {
            product[channel] =
                interfaceReflectance(angle: outer.angle, wavelength: wavelengths[channel],
                                     designWavelength: outerDesign,
                                     n0: outer.from, n2: outer.to)
                * interfaceReflectance(angle: inner.angle, wavelength: wavelengths[channel],
                                       designWavelength: innerDesign,
                                       n0: inner.from, n2: inner.to)
        }
        return product
    }
}
