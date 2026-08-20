@testable import Ollin
import Testing

/// Pure CPU checks on the lens-flare optics: the ray transfer through the lens,
/// which interface pairs make a ghost, where each one lands, and what the
/// coating leaves of the light. No Metal device, so these run everywhere.
@Suite
struct LensFlareTests {

    private let optics = Lens.heliar.optics()

    /// The strongest single check that the whole matrix chain is right, and it
    /// needs no reference numbers: a lens prescription is written focused on the
    /// far distance, which puts the sensor at the focal plane. A ray running
    /// parallel to the axis then lands on the axis whatever height it came in
    /// at, so the straight-through path must carry almost none of the pupil, and
    /// the sensor height per unit angle must come out as the focal length.
    @Test func theSensorSitsAtTheFocalPlane() {
        #expect(abs(Lens.heliar.directPupilScale) < 0.02,
                "the pupil should barely reach the sensor: \(Lens.heliar.directPupilScale)")
        #expect(abs(optics.directScale - optics.focalLength) / optics.focalLength < 0.01,
                "\(optics.directScale) should be the focal length \(optics.focalLength)")
        // A hundred millimeter portrait lens, which is what this prescription is.
        #expect(abs(optics.focalLength - 99.24) < 0.1)
    }

    /// Light that reflects across the iris would have to cross the opening three
    /// times, so those pairs are left out. Every ghost keeps both of its bounces
    /// on one side.
    @Test func noGhostReflectsAcrossTheIris() throws {
        let iris = try #require(Lens.heliar.interfaces.firstIndex { $0.isIris })
        #expect(!optics.ghosts.isEmpty)
        for ghost in optics.ghosts {
            #expect(ghost.firstInterface < ghost.secondInterface)
            #expect((ghost.firstInterface < iris) == (ghost.secondInterface < iris),
                    "ghost \(ghost.firstInterface)-\(ghost.secondInterface) crosses the iris")
            #expect(ghost.firstInterface != iris && ghost.secondInterface != iris,
                    "the iris is an opening, not a surface: it reflects nothing")
        }
    }

    /// Nine interfaces, one of them the iris, leaves five reflecting surfaces in
    /// front of the opening and three behind it. Ten pairs plus three.
    @Test func theBundledLensMakesThirteenGhosts() {
        #expect(optics.ghosts.count == 13)
    }

    /// A coating is a quarter of its own wavelength thick, so it cancels that
    /// wavelength best. What survives at the ends of the spectrum is what colors
    /// a ghost.
    @Test func theCoatingIsWeakestAtItsOwnWavelength() {
        let tuned = coatedReflectance(angle: 0.1, wavelength: 550, designWavelength: 550,
                                      n0: 1, n2: 1.65)
        let red = coatedReflectance(angle: 0.1, wavelength: 650, designWavelength: 550,
                                    n0: 1, n2: 1.65)
        let blue = coatedReflectance(angle: 0.1, wavelength: 475, designWavelength: 550,
                                     n0: 1, n2: 1.65)
        #expect(tuned < red, "the tuned wavelength should pass through: \(tuned) vs \(red)")
        #expect(tuned < blue, "the tuned wavelength should pass through: \(tuned) vs \(blue)")
        // And it earns its name: a coated surface beats a bare one head on.
        let bare = uncoatedReflectance(angle: 0.1, n0: 1, n2: 1.65)
        #expect(tuned < bare, "coated \(tuned) should reflect less than bare \(bare)")
    }

    /// Leaving glass for air, past the critical angle nothing crosses and the
    /// light turns around whole. The reflectance has to reach 1 there, and reach
    /// it smoothly, or a ghost jumps as the source drifts.
    @Test func theLightAllTurnsAroundPastTheCriticalAngle() {
        let critical = asin(1 / 1.581)
        #expect(coatedReflectance(angle: critical + 0.02, wavelength: 550,
                                  designWavelength: 550, n0: 1.581, n2: 1) == 1)
        #expect(uncoatedReflectance(angle: critical + 0.02, n0: 1.581, n2: 1) == 1)
        // Climbing to the critical angle the reflectance only rises, and by the
        // time it arrives it is already nearly all of the light. So there is no
        // step where the model hands over: the last value before the boundary
        // meets the 1 that lies past it. (The rise is steep near the end, which
        // is what Fresnel does, so this checks where it arrives rather than how
        // fast it climbs.)
        var previous = 0.0
        for step in 0...600 {
            let angle = critical * Double(step) / 600
            let value = coatedReflectance(angle: angle, wavelength: 550,
                                          designWavelength: 550, n0: 1.581, n2: 1)
            #expect(value - previous > -0.02,
                    "the reflectance fell back approaching the critical angle, at \(angle)")
            previous = value
        }
        let arriving = coatedReflectance(angle: critical - 1e-6, wavelength: 550,
                                         designWavelength: 550, n0: 1.581, n2: 1)
        #expect(arriving > 0.98 && arriving <= 1,
                "it should reach the critical angle already whole: \(arriving)")
    }

    /// A cemented junction has cement between its glasses and so cannot be
    /// coated, but it does not reflect nothing either. It has to land between an
    /// exposed coated surface and zero.
    @Test func aCementedJunctionReflectsLittleButNotNothing() {
        let cemented = uncoatedReflectance(angle: 0.1, n0: 1.652, n2: 1.603)
        let coated = coatedReflectance(angle: 0.1, wavelength: 550, designWavelength: 550,
                                       n0: 1, n2: 1.65)
        #expect(cemented > 1e-5, "a cemented junction still reflects: \(cemented)")
        #expect(cemented < coated, "\(cemented) should be under a coated surface's \(coated)")
        // The dispatcher has to pick the right one for each.
        #expect(interfaceReflectance(angle: 0.1, wavelength: 550, designWavelength: 550,
                                     n0: 1.652, n2: 1.603) == cemented)
        #expect(interfaceReflectance(angle: 0.1, wavelength: 550, designWavelength: 550,
                                     n0: 1, n2: 1.65) == coated)
    }

    /// Stopping down closes the opening, which is what shrinks every ghost
    /// together. Wide open, the prescription's own opening is the limit.
    @Test func stoppingDownClosesTheIris() {
        let wide = Lens.heliar.optics().irisRadius
        let mid = Lens.heliar.stopped(to: 8).optics().irisRadius
        let tight = Lens.heliar.stopped(to: 22).optics().irisRadius
        #expect(wide > mid && mid > tight)
        #expect(abs(wide - 11.6) < 1e-9, "wide open is the prescription's opening: \(wide)")
        // Half the focal length over the f-number, which is what an f-number means.
        #expect(abs(tight - Lens.heliar.focalLength / 44) < 1e-9)
    }

    /// Multicoating puts a different wavelength on each exposed surface, which
    /// is what puts a lens's ghosts in different colors. A cemented junction
    /// takes none, because there is nowhere to put it.
    @Test func multicoatingSpreadsAcrossTheExposedSurfacesOnly() throws {
        let plain = Lens.heliar
        let coated = plain.multicoated(from: 440, to: 660)
        #expect(plain.interfaces.allSatisfy { $0.coating == nil })
        for (index, interface) in coated.interfaces.enumerated() {
            let before = index == 0 ? 1.0 : coated.interfaces[index - 1].refractiveIndex
            let exposed = !interface.isIris
                && (before < 1.05 || interface.refractiveIndex < 1.05)
            if exposed {
                let value = try #require(interface.coating)
                #expect(value >= 440 && value <= 660, "interface \(index) at \(value)")
            } else {
                #expect(interface.coating == nil, "interface \(index) cannot be coated")
            }
        }
        // And it has to change the picture, or it is decoration.
        let ghost = try #require(coated.optics().ghosts.first { $0.firstInterface == 0 })
        #expect(plain.ghostReflectance(ghost, angle: 0.2)
                != coated.ghostReflectance(ghost, angle: 0.2))
    }

    /// Every ghost lands on the line from the source through the middle of the
    /// frame, which is the whole shape of a lens flare. In this model that is
    /// not drawn in, it follows: a ghost's place on the sensor is one number
    /// times the ray angle, so it can only be a multiple of where the source is.
    @Test func everyGhostLandsOnTheLineThroughTheFrameCenter() {
        for ghost in optics.ghosts {
            #expect(ghost.toSensor.a.isFinite && ghost.toSensor.b.isFinite)
            #expect(abs(ghost.toSensor.a) > 1e-9, "a ghost with no scale cannot be drawn")
        }
        // One lands on the far side of the center and one past the source, which
        // is what makes a flare a chain across the frame rather than a halo.
        let multiples = optics.ghosts.map { $0.toSensor.b / optics.directScale }
        #expect(multiples.contains { $0 < 0 })
        #expect(multiples.contains { $0 > 1 })
    }

    /// The ray transfer matrices are the model's whole arithmetic, so they get
    /// checked against what first-order optics says they mean.
    @Test func theRayTransferMatricesDoWhatTheySay() {
        // Travel leaves the angle alone and moves the height by distance times angle.
        let after = RayTransfer.travel(10).applied(height: 1, angle: 0.1)
        #expect(abs(after.height - 2) < 1e-12 && abs(after.angle - 0.1) < 1e-12)
        // A flat interface bends nothing at the axis, only rescales the angle.
        let flat = RayTransfer.refraction(radius: 0, from: 1, to: 1.5)
        #expect(flat.c == 0 && abs(flat.d - 1 / 1.5) < 1e-12)
        // A flat mirror turns a ray around without bending it, which in this
        // unfolded model leaves the ray untouched.
        #expect(RayTransfer.reflection(radius: 0) == .identity)
        // A single curved surface bends light by the power the lensmaker's rule
        // gives it, which the matrix carries as that power over the index the
        // light ends up in.
        let surface = RayTransfer.refraction(radius: 50, from: 1, to: 1.5)
        let power = (1.5 - 1.0) / 50
        #expect(abs(surface.c + power / 1.5) < 1e-12, "surface power \(-surface.c * 1.5)")
        // And an inverse undoes its own matrix.
        let round = surface.inverse * surface
        #expect(abs(round.a - 1) < 1e-12 && abs(round.b) < 1e-12
                && abs(round.c) < 1e-12 && abs(round.d - 1) < 1e-12)
    }

    /// A lens with nothing to reflect off makes no ghosts rather than failing,
    /// and the renderer's gate reads that as nothing to draw.
    @Test func aLensWithTooFewSurfacesMakesNoGhosts() {
        #expect(Lens(interfaces: []).optics().ghosts.isEmpty)
        let single = Lens(interfaces: [LensInterface(radius: 30, thickness: 50,
                                                     refractiveIndex: 1.5, height: 10)])
        #expect(single.optics().ghosts.isEmpty, "one surface cannot reflect twice")
    }
}
