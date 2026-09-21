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
    public var ior: Double

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

    /// The Abbe number of the glass after this interface: how much its index
    /// changes across the spectrum, the figure a glass catalog and a lens patent
    /// print beside the index. A low number is a flint, which spreads colors
    /// widely, and a high one is a crown, which hardly does.
    ///
    /// This is what gives a ghost its colored rim. Each color meets a slightly
    /// different lens, so each ghost lands at a slightly different size and
    /// place per color, and the difference shows where the ghost ends. `nil`
    /// stands in a typical value for the index, which is the right choice for a
    /// table that leaves the number out. Air ignores it.
    public var abbeNumber: Double?

    public init(radius: Double, thickness: Double, ior: Double = 1,
                height: Double, isIris: Bool = false, coating: Double? = nil,
                abbeNumber: Double? = nil) {
        self.radius = radius
        self.thickness = thickness
        self.ior = ior
        self.height = height
        self.isIris = isIris
        self.coating = coating
        self.abbeNumber = abbeNumber
    }

    /// An iris: a flat stop of a given opening radius, `thickness` to the next
    /// interface.
    public static func iris(thickness: Double, height: Double) -> LensInterface {
        LensInterface(radius: 0, thickness: thickness, ior: 1,
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
                && (i == 0 || lens.interfaces[i - 1].ior < 1.05
                    || lens.interfaces[i].ior < 1.05)
        }
        guard exposed.count > 1 else { return lens }
        // The wavelengths are evenly spaced across the range, and handed out so
        // that surfaces next to each other land far apart in it. A ghost is made
        // by a *pair* of surfaces, and the brightest pairs are neighbors, so a
        // plain front-to-back sweep gives every such pair two near-identical
        // coatings and the whole chain comes out in one color. Stepping through
        // the range by the golden ratio is the even spread that never puts two
        // neighbors close.
        let walk = exposed.indices
            .map { ($0, (Double($0) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1)) }
            .sorted { $0.1 < $1.1 }
        for (rank, entry) in walk.enumerated() {
            let t = Double(rank) / Double(exposed.count - 1)
            lens.interfaces[exposed[entry.0]].coating = from + (to - from) * t
        }
        return lens
    }

    /// The lens a flare is drawn through when none is named: the double Gauss,
    /// multicoated, stopped to f/8.
    ///
    /// Any lens wide open throws ghosts so broad that they read as haze, and a
    /// single coating makes them all one color. Stopped down a few stops with a
    /// modern coating is where a flare looks like one: a chain of separate,
    /// differently colored shapes running through the middle of the frame.
    public static let standard = Lens.doubleGauss.multicoated().stopped(to: 8)

    /// A 1950s five-element Heliar-type portrait lens of about 100mm: a
    /// cemented front doublet, a single middle element, the iris, and a
    /// cemented rear doublet. Few interfaces, so it makes few ghosts and they
    /// are large and clean, which is the classic photographic flare.
    ///
    /// The prescription is the published table from the patent literature, in
    /// the form the flare paper credited in `ATTRIBUTION.md` tabulates it, with
    /// each glass's Abbe number as the patent itself prints it.
    public static let heliar = Lens(interfaces: [
        LensInterface(radius:  30.810, thickness:  7.700, ior: 1.652, height: 14.5, abbeNumber: 58.6),
        LensInterface(radius: -89.350, thickness:  1.850, ior: 1.603, height: 14.5, abbeNumber: 38.4),
        LensInterface(radius: 580.380, thickness:  3.520, ior: 1.000, height: 14.5),
        LensInterface(radius: -80.630, thickness:  1.850, ior: 1.643, height: 12.3, abbeNumber: 47.9),
        LensInterface(radius:  28.340, thickness:  4.180, ior: 1.000, height: 12.0),
        LensInterface.iris(thickness: 3.000, height: 11.6),
        LensInterface(radius:   0.000, thickness:  1.850, ior: 1.581, height: 12.3, abbeNumber: 40.8),
        LensInterface(radius:  32.190, thickness:  7.270, ior: 1.694, height: 12.3, abbeNumber: 53.5),
        LensInterface(radius: -52.990, thickness: 81.857, ior: 1.000, height: 12.3),
    ])

    /// A 1950s six-element double Gauss of 100mm at f/2: two single elements
    /// outside, two cemented doublets facing each other across the iris. It is
    /// the layout most fast normal lenses since have been built on. Ten glass
    /// surfaces make twenty ghosts, so where the Heliar leaves a few large clean
    /// ones this strings a busier chain across the frame, in more sizes.
    ///
    /// The prescription and the Abbe numbers are the published table from the
    /// patent literature. The clear openings are the ones the realistic camera
    /// paper credited in `ATTRIBUTION.md` tabulates for it, and the last
    /// distance is the paraxial back focus the table itself works out to.
    public static let doubleGauss = Lens(interfaces: [
        LensInterface(radius:  58.950, thickness:  7.510, ior: 1.67125, height: 25.2, abbeNumber: 47.1),
        LensInterface(radius: 169.660, thickness:  0.235, ior: 1.00000, height: 25.2),
        LensInterface(radius:  38.554, thickness:  8.053, ior: 1.67125, height: 23.0, abbeNumber: 47.1),
        LensInterface(radius:  81.537, thickness:  6.550, ior: 1.69842, height: 23.0, abbeNumber: 30.1),
        LensInterface(radius:  25.502, thickness: 10.931, ior: 1.00000, height: 18.0),
        LensInterface.iris(thickness: 9.481, height: 17.1),
        LensInterface(radius: -28.992, thickness:  2.362, ior: 1.60266, height: 17.0, abbeNumber: 38.4),
        LensInterface(radius:  81.537, thickness: 12.134, ior: 1.65953, height: 20.0, abbeNumber: 57.0),
        LensInterface(radius: -40.771, thickness:  0.376, ior: 1.00000, height: 20.0),
        LensInterface(radius: 874.182, thickness:  6.443, ior: 1.71740, height: 20.0, abbeNumber: 48.1),
        LensInterface(radius: -79.459, thickness: 71.442, ior: 1.00000, height: 20.0),
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
    public var amount: Double

    /// How far off the edge of the frame a light still flares, as a fraction of
    /// the frame height. A source just outside the picture is the classic case,
    /// so this reaches past the frame by default.
    public var reach: Double

    /// How strong the star on the source itself is, over and above `amount`.
    /// `0` leaves the ghosts alone without it, which is a real choice: the chain
    /// across the frame and the star on the source are two different effects and
    /// a piece may want one and not the other.
    public var star: Double

    /// How far the star reaches from its source, as a fraction of the frame
    /// height, with the iris wide open. Stopping down grows it from there, since
    /// light bending around a smaller opening spreads further.
    public var starSize: Double

    /// How worn the iris is, `0` to `1`. A clean opening throws only the arms
    /// its blades make. Blades a little off true, specks, and hairline scratches
    /// each bend a little light of their own, and spread across the colors that
    /// is what splits and frays a real star's arms and fills between them with
    /// fine needles. `0` is the clean star.
    public var wear: Double

    /// How strong the streak through each source is. `0`, the default, leaves it
    /// out.
    ///
    /// This is what cylindrical glass does to a light. A cylinder bends light one
    /// way and not the other, so it fans a light out to either side, across
    /// itself and no other way, into one line. That line passes through the
    /// source, runs as thin as the source is wide, and tapers toward its ends.
    /// The front group of an anamorphic lens is cylindrical and throws it, and a
    /// streak filter is a glass ruled with fine cylindrical grooves, made to
    /// throw the same line on any lens. It is the long line through the lights
    /// of a night street.
    public var streak: Double

    /// How far the streak reaches each way from its source, in frame heights.
    public var streakLength: Double

    /// Which way the streak runs, in radians. `0` is level, which is how the
    /// filter is usually turned.
    public var streakAngle: Double

    /// The streak's color. On an anamorphic lens it is whatever the coatings on
    /// the cylindrical glass send back, and a streak filter is sold tinted to
    /// match. Blue is the one the look is known by.
    public var streakTint: Color

    /// How strong the ring around each source is. `0`, the default, leaves it
    /// out.
    ///
    /// Unlike the rest of a flare this is a look and not optics: the thin
    /// rainbow ring drawn around a light, red outermost. Nothing in a lens of
    /// plain spheres makes it. It is here because a flare is often wanted with
    /// one, and it says so rather than pretending.
    public var halo: Double

    /// The halo's radius, in frame heights.
    public var haloSize: Double

    /// How dirty the front of the lens is, `0` to `1`. `0`, the default, is a
    /// clean lens.
    ///
    /// Grime on the front element is far too close to be in focus, so each speck
    /// becomes a soft blur the shape and size of the iris, which is why they are
    /// never seen in an ordinary picture. Turn toward a bright light and they
    /// show, because each one scatters a little of that light into the camera,
    /// mostly onward the way it was already going. So the specks nearest the
    /// light glow brightest, they take the blades' shape, and they grow as the
    /// iris opens. Like the rest of the flare they follow how much of the
    /// source the camera can see.
    public var dirt: Double

    /// How large the source is, as the radius of the disc it fills, in
    /// fractions of the frame height.
    ///
    /// Two things follow from it. The visibility test looks at this disc, so a
    /// flare fades as an occluder covers it rather than switching off the moment
    /// the source's center goes behind something. And every ghost is a picture
    /// taken *with* the source, so a wider source softens each ghost's edge, by
    /// more the further that ghost moves as the source does. A ghost that lands
    /// almost in focus stops being a dot altogether and becomes a soft picture
    /// of the source itself. A small value gives hard, crisp ghosts, the way a
    /// distant street lamp does.
    public var sourceSize: Double

    public init(lens: Lens = .standard, amount: Double = 1, star: Double = 1,
                starSize: Double = 0.35, wear: Double = 0.5,
                streak: Double = 0, streakLength: Double = 1.1, streakAngle: Double = 0,
                streakTint: Color = Color(red: 0.35, green: 0.56, blue: 1.0),
                halo: Double = 0, haloSize: Double = 0.38, dirt: Double = 0,
                reach: Double = 0.55, sourceSize: Double = 0.015) {
        self.lens = lens
        self.amount = max(0, amount)
        self.star = max(0, star)
        self.starSize = max(0, starSize)
        self.wear = min(1, max(0, wear))
        self.streak = max(0, streak)
        self.streakLength = max(0.01, streakLength)
        self.streakAngle = streakAngle
        self.streakTint = streakTint
        self.halo = max(0, halo)
        self.haloSize = max(0.01, haloSize)
        self.dirt = min(1, max(0, dirt))
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

    /// The inverse: the matrix that takes a ray's state after this one back to
    /// its state before.
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

/// What one ghost does to the light of one color channel.
///
/// Glass bends each color by a slightly different amount, so each channel meets
/// a slightly different lens and its ghost lands at a slightly different size
/// and place. The difference is small, a few percent, and it is what puts a
/// colored rim on a ghost.
struct GhostChannel: Equatable {
    /// Pupil to sensor: `sensor = sensorA·pupil + sensorB·angle`.
    var sensorA: Double, sensorB: Double
    /// Pupil to the iris plane, the same way.
    var irisA: Double, irisB: Double
}

/// One ghost: the light that reflects off a pair of interfaces and lands on the
/// sensor anyway.
struct LensGhost: Equatable {
    /// Where the first (inner) reflection happens, as an index into the lens.
    var firstInterface: Int
    /// Where the second (outer) reflection happens.
    var secondInterface: Int
    /// Maps a point on the entrance pupil to the sensor: `sensor = a·pupil + b·angle`.
    /// Worked out at the index the prescription prints.
    var toSensor: (a: Double, b: Double)
    /// Maps the same point to the iris plane, which is what shapes the ghost.
    var toIris: (a: Double, b: Double)
    /// The same two maps once per color channel, in `Lens.channelWavelengths`
    /// order, each at the index its wavelength sees.
    var channels: [GhostChannel]
    /// How steeply a ray meets the outer reflecting surface, as a map from where
    /// it entered and the angle it came in at: the incidence angle is the length
    /// of `pupil·entry + angle·direction`. A ray through the rim of the pupil
    /// meets a curved surface far more steeply than one through the middle,
    /// which is why a coating colors the edge of a ghost differently from its
    /// center.
    var outerIncidence: (pupil: Double, angle: Double)
    /// The same for the inner reflecting surface, met on the way back.
    var innerIncidence: (pupil: Double, angle: Double)
    /// How finely light rings just inside this ghost's edge: the distance inside
    /// the iris's edge, in millimeters on the iris plane, times this, is the
    /// argument of the straight-edge diffraction pattern at 550 nm. It follows
    /// from the path between the iris and the sensor: a ghost is the iris's
    /// shadow thrown a short way, and how short sets how wide the rings are. `0`
    /// for a path that throws no usable pattern.
    var ringScale: Double = 0

    static func == (lhs: LensGhost, rhs: LensGhost) -> Bool {
        lhs.firstInterface == rhs.firstInterface && lhs.secondInterface == rhs.secondInterface
            && lhs.toSensor == rhs.toSensor && lhs.toIris == rhs.toIris
            && lhs.channels == rhs.channels
            && lhs.outerIncidence == rhs.outerIncidence
            && lhs.innerIncidence == rhs.innerIncidence
            && lhs.ringScale == rhs.ringScale
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
    /// The radius the prescription gives the iris with nothing stopped down,
    /// which is the reference the star's size is measured against.
    var openIrisRadius: Double
    /// Sensor height per unit ray angle for light that goes straight through,
    /// which is the scale that puts a ghost where the picture is.
    var directScale: Double
    /// The focal length worked out from the stack.
    var focalLength: Double
}

extension LensInterface {

    /// A typical Abbe number for a glass of this index, for a table that prints
    /// none. Ordinary glasses run along a line from the light crowns to the
    /// dense flints, with the spread between the blue and red reference lines
    /// growing steadily as the index does. Fitted to six catalog glasses along
    /// that line.
    static func typicalAbbeNumber(forIndex index: Double) -> Double {
        let spread = max(0.006, 0.00805 + 0.0834 * (index - 1.517))
        return min(70, max(22, (index - 1) / spread))
    }

    /// The index after this interface at a wavelength in nanometers.
    ///
    /// The prescription's index is the one at the yellow helium line, and the
    /// Abbe number says how far apart the blue and red reference lines sit
    /// around it. Two terms of the published dispersion series pass through
    /// both, which is as much as a catalog number can pin down.
    func index(atWavelength wavelength: Double) -> Double {
        guard ior > 1.0001 else { return ior }
        let abbe = abbeNumber ?? LensInterface.typicalAbbeNumber(forIndex: ior)
        let blue = 486.13, red = 656.27, yellow = 587.56
        let slope = ((ior - 1) / abbe) / (1 / (blue * blue) - 1 / (red * red))
        return ior + slope * (1 / (wavelength * wavelength) - 1 / (yellow * yellow))
    }
}

/// A lens as one color sees it: the same surfaces, with the index each glass
/// has at that wavelength. Every walk through the stack goes through one of
/// these, so the matrices never have to ask which color they are for.
private struct LensStack {
    let interfaces: [LensInterface]
    /// The index of the medium after each interface.
    let after: [Double]

    init(_ lens: Lens, wavelength: Double? = nil) {
        interfaces = lens.interfaces
        after = lens.interfaces.map { face in
            wavelength.map { face.index(atWavelength: $0) } ?? face.ior
        }
    }

    /// The index of the medium in front of interface `i`.
    func before(_ i: Int) -> Double { i == 0 ? 1 : after[i - 1] }

    func refraction(_ i: Int) -> RayTransfer {
        RayTransfer.refraction(radius: interfaces[i].radius, from: before(i), to: after[i])
    }

    /// Refract at interface `i`, then travel to the next one.
    func forwardStep(_ i: Int) -> RayTransfer {
        RayTransfer.travel(interfaces[i].thickness) * refraction(i)
    }

    /// The run from a ray leaving interface `a` forward (it has just reflected
    /// there, so it does not refract there) to a ray arriving at interface `b`.
    /// Pass `interfaces.count` for `b` to reach the sensor.
    func forwardRun(after a: Int, to b: Int) -> RayTransfer {
        var m = RayTransfer.travel(interfaces[a].thickness)
        var k = a + 1
        while k < b {
            m = forwardStep(k) * m
            k += 1
        }
        return m
    }

    /// Travel back to interface `i`, then pass through it toward the front. This
    /// is the leg between the two reflections.
    ///
    /// One convention holds through the whole chain: a height is a real height,
    /// and a slope is measured along the way the ray is travelling. So a ray
    /// running back toward the front covers a positive distance, and the surface
    /// it meets is the same sphere seen from behind: its radius changes sign and
    /// its two media change places. (Undoing the forward refraction instead, by
    /// the inverse matrix, is the same physics written with slopes measured along
    /// the axis, and the two cannot be mixed in one product.)
    func backwardStep(_ i: Int) -> RayTransfer {
        RayTransfer.refraction(radius: -interfaces[i].radius, from: after[i], to: before(i))
            * RayTransfer.travel(interfaces[i].thickness)
    }

    /// The ray arriving at each interface from the front, before it refracts.
    func arrivals() -> [RayTransfer] {
        var result: [RayTransfer] = []
        var run = RayTransfer.identity
        for i in interfaces.indices {
            result.append(run)
            run = forwardStep(i) * run
        }
        return result
    }

    /// Everything one ghost path does: the ray arriving at the outer reflecting
    /// surface, the ray arriving back at the inner one, the whole path to the
    /// sensor, and the path as far as the iris.
    func ghostPath(first: Int, second: Int, iris: Int?, arrivals: [RayTransfer])
        -> (outer: RayTransfer, inner: RayTransfer, full: RayTransfer, iris: RayTransfer) {
        let outer = arrivals[second]
        // Forward to the outer reflection, bounce, walk back through every
        // surface strictly between the two, cross the last gap to the inner one,
        // bounce again, then run out to the sensor. The inner surface is never
        // passed through: the ray arrives at it from behind, inside the glass
        // that follows it, and leaves the same way. It is met from behind, so as
        // a mirror it is the same sphere with its radius turned over.
        var m = RayTransfer.reflection(radius: interfaces[second].radius) * outer
        for k in stride(from: second - 1, to: first, by: -1) {
            m = backwardStep(k) * m
        }
        m = RayTransfer.travel(interfaces[first].thickness) * m
        let inner = m
        m = RayTransfer.reflection(radius: -interfaces[first].radius) * m
        let full = forwardRun(after: first, to: interfaces.count) * m
        // The iris plane is where the ghost takes its shape. When both
        // reflections sit behind the iris the light reaches it before bouncing,
        // so that leg is the plain forward run.
        let irisMatrix: RayTransfer
        if let ap = iris {
            irisMatrix = first > ap ? arrivals[ap] : (forwardRun(after: first, to: ap) * m)
        } else {
            irisMatrix = full
        }
        return (outer, inner, full, irisMatrix)
    }
}

extension Lens {

    /// The index of the medium in front of interface `i`.
    private func indexBefore(_ i: Int) -> Double {
        i == 0 ? 1 : interfaces[i - 1].ior
    }

    /// Whether interface `i` reflects. The iris is an opening, not a surface,
    /// and a boundary between two identical media reflects nothing.
    private func reflects(_ i: Int) -> Bool {
        !interfaces[i].isIris && abs(indexBefore(i) - interfaces[i].ior) > 1e-9
    }

    /// What the straight-through path does to a point on the entrance pupil.
    /// Near zero says the sensor sits at the focal plane, which is where a lens
    /// focused on the far distance puts it.
    var directPupilScale: Double { directMatrix.a }

    /// The matrix for light that passes straight through, from the entrance
    /// pupil to the sensor.
    private var directMatrix: RayTransfer {
        let stack = LensStack(self)
        var m = RayTransfer.identity
        for i in interfaces.indices { m = stack.forwardStep(i) * m }
        return m
    }

    /// The focal length, read off the refracting stack. The lower-left term of
    /// a system matrix is the negative reciprocal of the focal length.
    var focalLength: Double {
        let stack = LensStack(self)
        var m = RayTransfer.identity
        for i in interfaces.indices {
            m = stack.refraction(i) * m
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
            return LensOptics(ghosts: [], pupilRadius: 0, irisRadius: 0, openIrisRadius: 0,
                              directScale: 0, focalLength: 0)
        }
        let irisIndex = interfaces.firstIndex { $0.isIris }
        let f = focalLength
        let openHeight = irisIndex.map { interfaces[$0].height } ?? interfaces[0].height
        let stopped = fStop.map { abs(f) / (2 * $0) } ?? .infinity

        // The lens at the index the table prints, which places the ghosts, and
        // once more per color channel, which is what separates their rims.
        let reference = LensStack(self)
        let referenceArrivals = reference.arrivals()
        let wavelengths = Lens.channelWavelengths
        let colored = (0..<3).map { LensStack(self, wavelength: wavelengths[$0]) }
        let coloredArrivals = colored.map { $0.arrivals() }

        var ghosts: [LensGhost] = []
        for second in interfaces.indices where reflects(second) {
            for first in 0..<second where reflects(first) {
                if let ap = irisIndex, (first < ap) != (second < ap) { continue }
                let path = reference.ghostPath(first: first, second: second, iris: irisIndex,
                                               arrivals: referenceArrivals)
                guard path.full.a.isFinite, path.full.b.isFinite,
                      abs(path.full.a) > 1e-9 else { continue }
                let channels = (0..<3).map { channel -> GhostChannel in
                    let own = colored[channel].ghostPath(first: first, second: second,
                                                         iris: irisIndex,
                                                         arrivals: coloredArrivals[channel])
                    guard own.full.a.isFinite, own.full.b.isFinite, abs(own.full.a) > 1e-9 else {
                        return GhostChannel(sensorA: path.full.a, sensorB: path.full.b,
                                            irisA: path.iris.a, irisB: path.iris.b)
                    }
                    return GhostChannel(sensorA: own.full.a, sensorB: own.full.b,
                                        irisA: own.iris.a, irisB: own.iris.b)
                }
                // A paraxial surface normal at height h leans by h over the
                // radius, and the incidence angle is the ray's slope measured
                // against it: slope plus lean, so that a ray aimed at the center
                // of curvature, whose slope is minus the lean, meets the surface
                // head on. Both are linear in where the ray entered and the angle
                // it came in at, so the incidence is too. `radius` is the radius
                // as the ray meets it, turned over for a surface met from behind.
                func incidence(_ arriving: RayTransfer, radius: Double) -> (pupil: Double, angle: Double) {
                    let lean = radius == 0 ? 0 : 1 / radius
                    return (arriving.c + arriving.a * lean, arriving.d + arriving.b * lean)
                }
                // The stretch from the iris to the sensor, as one matrix. Its
                // upper-right term over the beam's own magnification is the
                // distance the iris's shadow is effectively thrown, which is what
                // the width of the rings inside its edge goes by.
                var ringScale = 0.0
                if irisIndex != nil, abs(path.iris.a) > 1e-9 {
                    let onward = path.full * path.iris.inverse
                    let magnification = path.full.a / path.iris.a
                    if abs(onward.b) > 1e-6, abs(magnification) > 1e-9 {
                        ringScale = (2 * abs(magnification) / (550e-6 * abs(onward.b))).squareRoot()
                    }
                }
                ghosts.append(LensGhost(
                    firstInterface: first, secondInterface: second,
                    toSensor: (path.full.a, path.full.b),
                    toIris: (path.iris.a, path.iris.b),
                    channels: channels,
                    outerIncidence: incidence(path.outer, radius: interfaces[second].radius),
                    innerIncidence: incidence(path.inner, radius: -interfaces[first].radius),
                    ringScale: ringScale))
            }
        }
        return LensOptics(ghosts: ghosts,
                          pupilRadius: interfaces[0].height,
                          irisRadius: min(openHeight, stopped),
                          openIrisRadius: openHeight,
                          directScale: directMatrix.b,
                          focalLength: f)
    }
}

// MARK: - Exact rays

/// One real ray followed along a ghost's path: where it lands, where it crossed
/// the iris, and what it took to get there.
///
/// The matrices above are the first-order picture, in which every ghost is a
/// scaled and shifted copy of the opening. A real lens is not first order. Its
/// surfaces are spheres, and a ray through the rim of a sphere is bent by more
/// than the rule of proportion says, by more the further out it goes. That is
/// what stretches a ghost toward the edge of the frame, and what folds the light
/// inside one into bright rims and cores: a caustic is where neighboring rays
/// land on top of each other. Nothing short of following the rays shows it.
struct TracedRay: Equatable {
    /// Where the ray meets the sensor, in millimeters off the axis.
    var sensor: SIMD2<Double>
    /// Where it crossed the iris plane, which is what the iris's shape is read at.
    var aperture: SIMD2<Double>
    /// The furthest it strayed toward the rim of any element, as a fraction of
    /// that element's clear opening. Past 1 the barrel stopped it.
    var relativeHeight: Double
    /// What its two reflections sent back, as a fraction of the light.
    var reflectance: Double
    /// What every refraction along the way let through. It runs smoothly to
    /// nothing as a ray nears the angle at which it could no longer leave a
    /// glass, so the rays beside a lost one are already dark.
    var transmittance = 1.0
    /// The angle it met the outer reflecting surface at, and the inner one, in
    /// radians off each surface's own normal.
    var outerIncidence = 0.0, innerIncidence = 0.0
    /// `false` when the ray missed a surface it had to meet, or could not leave
    /// a glass (total internal reflection on a refraction). Such a ray lands
    /// nowhere; it is kept only so that a grid of rays stays a grid.
    var isValid: Bool
}

extension Lens {

    /// Follow one ray along a ghost's path through the real surfaces.
    ///
    /// The surfaces are met in the order the path names them, never by which is
    /// nearest, and each sphere is carried past its own clear opening by its
    /// defining equation, so a ray outside the glass still lands somewhere
    /// continuous. Those rays are never drawn, since their `relativeHeight` is
    /// past 1. They are what lets a sparse grid of rays be interpolated right up
    /// to the edge of the glass instead of stopping a cell short of it.
    ///
    /// - Parameters:
    ///   - entry: where the ray crosses the plane through the front vertex, in
    ///     millimeters.
    ///   - slope: its direction there, as the tangent of its angle off the axis
    ///     each way, which is the same number the matrices call the angle.
    ///   - wavelength: in nanometers, or `nil` for the index the table prints.
    func trace(_ ghost: LensGhost, entry: SIMD2<Double>, slope: SIMD2<Double>,
               wavelength: Double? = nil) -> TracedRay {
        let count = interfaces.count
        let after = interfaces.map { face in wavelength.map { face.index(atWavelength: $0) } ?? face.ior }
        func before(_ i: Int) -> Double { i == 0 ? 1 : after[i - 1] }
        var vertices = [Double](repeating: 0, count: count + 1)
        for i in 0..<count { vertices[i + 1] = vertices[i] + interfaces[i].thickness }

        var origin = SIMD3<Double>(entry.x, entry.y, 0)
        var direction = simd_normalize(SIMD3<Double>(slope.x, slope.y, 1))
        var ray = TracedRay(sensor: .zero, aperture: .zero, relativeHeight: 0,
                            reflectance: 1, isValid: true)
        var metOuter = false
        let light = wavelength ?? 550

        // Meet interface `i`, then reflect there or pass through it. `forward`
        // says which way the ray is travelling, which decides the two media.
        func meet(_ i: Int, reflecting: Bool, forward: Bool) -> Bool {
            let face = interfaces[i]
            var normal: SIMD3<Double>
            if face.radius == 0 {
                guard abs(direction.z) > 1e-12 else { return false }
                origin += direction * ((vertices[i] - origin.z) / direction.z)
                normal = SIMD3(0, 0, direction.z > 0 ? -1 : 1)
            } else {
                let center = SIMD3<Double>(0, 0, vertices[i] + face.radius)
                let offset = origin - center
                let b = simd_dot(offset, direction)
                let disc = b * b - (simd_dot(offset, offset) - face.radius * face.radius)
                guard disc >= 0 else { return false }
                // The pole of the sphere that is the lens surface, not the far
                // side of the ball it is cut from.
                let root = face.radius * direction.z > 0 ? -disc.squareRoot() : disc.squareRoot()
                origin += direction * (-b + root)
                normal = simd_normalize(origin - center)
                if simd_dot(normal, direction) > 0 { normal = -normal }
            }
            if face.isIris {
                ray.aperture = SIMD2(origin.x, origin.y)
                return true
            }
            let height = (origin.x * origin.x + origin.y * origin.y).squareRoot()
            ray.relativeHeight = max(ray.relativeHeight, height / max(face.height, 1e-9))

            let n0 = forward ? before(i) : after[i]
            let n2 = forward ? after[i] : before(i)
            let cosine = min(1, max(0, -simd_dot(normal, direction)))
            if reflecting {
                if metOuter { ray.innerIncidence = acos(cosine) } else { ray.outerIncidence = acos(cosine) }
                metOuter = true
                ray.reflectance *= interfaceReflectance(
                    angle: acos(cosine), wavelength: light,
                    designWavelength: face.coating ?? coatingWavelength, n0: n0, n2: n2)
                direction -= normal * (2 * simd_dot(direction, normal))
                return true
            }
            guard abs(n0 - n2) > 1e-12 else { return true }
            let eta = n0 / n2
            let k = 1 - eta * eta * (1 - cosine * cosine)
            guard k >= 0 else { return false }     // cannot leave the glass
            ray.transmittance *= 1 - uncoatedReflectance(angle: acos(cosine), n0: n0, n2: n2)
            direction = simd_normalize(direction * eta + normal * (eta * cosine - k.squareRoot()))
            return true
        }

        // Forward to the outer reflection, back to the inner one, forward again
        // to the sensor.
        for i in 0...ghost.secondInterface {
            guard meet(i, reflecting: i == ghost.secondInterface, forward: true) else {
                ray.isValid = false; return ray
            }
        }
        for i in stride(from: ghost.secondInterface - 1, through: ghost.firstInterface, by: -1) {
            guard meet(i, reflecting: i == ghost.firstInterface, forward: false) else {
                ray.isValid = false; return ray
            }
        }
        for i in (ghost.firstInterface + 1)..<count {
            guard meet(i, reflecting: false, forward: true) else {
                ray.isValid = false; return ray
            }
        }
        guard direction.z > 1e-9 else { ray.isValid = false; return ray }
        origin += direction * ((vertices[count] - origin.z) / direction.z)
        ray.sensor = SIMD2(origin.x, origin.y)
        return ray
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

    /// The wavelengths a ghost is followed in when its colors part enough to
    /// see. Three samples of a spectrum give three hard bands, red then yellow
    /// then white, where a lens gives a smooth run of color; seven close the
    /// gaps.
    static let spectrumWavelengths: [Double] = [430, 470, 510, 550, 590, 630, 670]

    /// What each of those wavelengths adds to the picture, in linear light, with
    /// the seven together adding up to white.
    static let spectrumColors: [SIMD3<Double>] = {
        let raw = spectrumWavelengths.map { ApertureStar.linearColor(ofWavelength: $0) }
        let total = raw.reduce(SIMD3<Double>.zero, +)
        return raw.map { $0 / SIMD3(max(total.x, 1e-9), max(total.y, 1e-9), max(total.z, 1e-9)) }
    }()

    /// Whether interface `i` can carry a coating: a surface with air on one side.
    func isExposed(_ i: Int) -> Bool {
        !interfaces[i].isIris && (indexBefore(i) < 1.05 || interfaces[i].ior < 1.05)
    }

    /// How steeply the light meets each of a ghost's two reflecting surfaces,
    /// and which media sit either side of them.
    ///
    /// `pupil` is how far off the axis the ray entered, measured along the same
    /// line as the angle. The middle of the pupil is the ray a whole ghost is
    /// scored by; the rim is where the same ghost meets its surfaces most
    /// steeply, which is why the two ends of one ghost are colored differently,
    /// and why a ghost changes color as the source crosses the frame.
    func ghostIncidence(_ ghost: LensGhost, angle: Double, pupil: Double = 0)
        -> (outer: (angle: Double, from: Double, to: Double),
            inner: (angle: Double, from: Double, to: Double)) {
        let outer = interfaces[ghost.secondInterface]
        let inner = interfaces[ghost.firstInterface]
        let outerAngle = abs(ghost.outerIncidence.pupil * pupil + ghost.outerIncidence.angle * angle)
        let innerAngle = abs(ghost.innerIncidence.pupil * pupil + ghost.innerIncidence.angle * angle)
        // Coming back, the light meets the inner surface from the far side.
        return ((outerAngle, indexBefore(ghost.secondInterface), outer.ior),
                (innerAngle, inner.ior, indexBefore(ghost.firstInterface)))
    }

    /// What each ghost reflects, per channel, for light arriving at `angle`. The
    /// light bounces twice, so the two reflectances multiply.
    func ghostReflectance(_ ghost: LensGhost, angle: Double, pupil: Double = 0) -> SIMD3<Double> {
        let (outer, inner) = ghostIncidence(ghost, angle: angle, pupil: pupil)
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

    /// What every reflecting surface sends back, at every angle it can be met
    /// at, from both sides, ready to be read per pixel.
    ///
    /// A ghost is one color only along the single ray through the middle of the
    /// pupil. Every other ray meets the two surfaces at its own angle, and a
    /// coating's color depends on that angle, so the color runs across a ghost
    /// from its middle to its rim. Working the coating out per pixel would cost
    /// far too much, and nothing in it depends on the light, so it is tabulated
    /// once per lens: a row per surface and direction, a column per angle from
    /// head on to grazing.
    ///
    /// Row `2·i` is interface `i` met from the front, the way an outer
    /// reflection meets it, and row `2·i + 1` is the same interface met from
    /// behind, the way an inner one does. The values are the *square root* of
    /// the reflectance per channel: a good coating sends back a few parts in a
    /// hundred thousand, and the root keeps that well inside what a half-float
    /// texture resolves.
    func coatingTable(samples: Int = 128) -> (rows: Int, samples: Int, values: [Float]) {
        let rows = max(1, interfaces.count * 2)
        var values = [Float](repeating: 0, count: rows * samples * 4)
        let wavelengths = Lens.channelWavelengths
        for index in interfaces.indices {
            let design = interfaces[index].coating ?? coatingWavelength
            let front = indexBefore(index), back = interfaces[index].ior
            for side in 0..<2 {
                let n0 = side == 0 ? front : back
                let n2 = side == 0 ? back : front
                for step in 0..<samples {
                    let angle = Double.pi / 2 * Double(step) / Double(samples - 1)
                    let at = ((index * 2 + side) * samples + step) * 4
                    for channel in 0..<3 {
                        let value = interfaceReflectance(angle: angle,
                                                         wavelength: wavelengths[channel],
                                                         designWavelength: design,
                                                         n0: n0, n2: n2)
                        values[at + channel] = Float(value.squareRoot())
                    }
                    values[at + 3] = 1
                }
            }
        }
        return (rows, samples, values)
    }

    /// How much of the light entering the lens its ghosts carry altogether, as
    /// a fraction: every ghost's two reflectances, times the share of the front
    /// opening whose light clears the iris on that path.
    ///
    /// This is the number the flare's level is set against. It does not depend
    /// on how nearly a ghost comes to focus, which is the point: a ghost that
    /// lands near focus is a small hot spot and one that lands far from it is a
    /// wide faint veil, and both carry what their coatings let through. Setting
    /// the level by the hottest spot instead lets one tiny ghost decide how
    /// bright all the others are. The angle is a fixed representative one and
    /// the iris is taken wide open, so the number belongs to the lens and does
    /// not move when the light or the f-number does.
    func ghostThroughput(_ optics: LensOptics) -> Double {
        guard optics.pupilRadius > 0 else { return 0 }
        var total = 0.0
        for ghost in optics.ghosts {
            let reflect = ghostReflectance(ghost, angle: 0.15)
            let luminance = 0.2126 * reflect.x + 0.7152 * reflect.y + 0.0722 * reflect.z
            let cleared = optics.openIrisRadius / max(abs(ghost.toIris.a), 1e-9)
            let share = min(1, (cleared * cleared) / (optics.pupilRadius * optics.pupilRadius))
            total += luminance * share
        }
        return total
    }
}
