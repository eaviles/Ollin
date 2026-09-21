@testable import Ollin
import Testing
import simd

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
            let before = index == 0 ? 1.0 : coated.interfaces[index - 1].ior
            let exposed = !interface.isIris
                && (before < 1.05 || interface.ior < 1.05)
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
                                                     ior: 1.5, height: 10)])
        #expect(single.optics().ghosts.isEmpty, "one surface cannot reflect twice")
    }

    /// The second bundled lens passes the same check the first does, and it is
    /// a stronger one here: the patent normalizes its table to a focal length of
    /// exactly 1, so a wrong digit anywhere in it shows as a focal length that
    /// is not 100. (One radius is unreadable in the patent's scan, and this is
    /// the check that settled it.) Ten glass surfaces, five a side of the iris,
    /// make ten pairs a side.
    @Test func theDoubleGaussFocusesWhereItsPatentSays() {
        let lens = Lens.doubleGauss
        let optics = lens.optics()
        #expect(abs(optics.focalLength - 100) < 0.05, "focal length \(optics.focalLength)")
        #expect(abs(lens.directPupilScale) < 1e-4,
                "the sensor sits at the paraxial focus: \(lens.directPupilScale)")
        #expect(optics.ghosts.count == 20)
        #expect(optics.ghosts.count <= Int(24), "every ghost fits the frame's budget")
    }

    /// Glass bends blue more than red, by the amount its Abbe number says. The
    /// index a table prints is the one at the yellow helium line, so the curve
    /// has to pass through it, and the spread between the blue and red reference
    /// lines is the definition of the Abbe number, so it has to give that back.
    @Test func eachColorMeetsItsOwnGlass() {
        let glass = LensInterface(radius: 30, thickness: 5, ior: 1.652, height: 10,
                                  abbeNumber: 58.6)
        #expect(abs(glass.index(atWavelength: 587.56) - 1.652) < 1e-12)
        let spread = glass.index(atWavelength: 486.13) - glass.index(atWavelength: 656.27)
        #expect(abs((1.652 - 1) / spread - 58.6) < 1e-6, "the Abbe number comes back out")
        #expect(glass.index(atWavelength: 475) > glass.index(atWavelength: 650))

        // Air has no dispersion worth the name, whatever number it is handed.
        let air = LensInterface(radius: 30, thickness: 5, ior: 1, height: 10, abbeNumber: 30)
        #expect(air.index(atWavelength: 475) == 1)

        // A table that prints no number gets a plausible one: a light crown
        // spreads colors far less than a dense flint.
        let crown = LensInterface.typicalAbbeNumber(forIndex: 1.517)
        let flint = LensInterface.typicalAbbeNumber(forIndex: 1.785)
        #expect(crown > 55 && crown < 70, "crown at \(crown)")
        #expect(flint > 22 && flint < 32, "flint at \(flint)")
    }

    /// So each channel's ghost is a slightly different size and sits in a
    /// slightly different place, which is the colored rim. Slightly is the word:
    /// a ghost well away from focus moves by a few percent. The one near focus
    /// is the exception, since its scale is a small difference of large numbers
    /// and a small change in the glass moves it a long way.
    @Test func theColorsPartCompanyAtTheRim() throws {
        for ghost in optics.ghosts {
            #expect(ghost.channels.count == 3)
            let scales = ghost.channels.map(\.sensorA)
            #expect(scales[0] != scales[2], "red and blue share a map in \(ghost)")
            if abs(ghost.toSensor.a) > 1 {
                let apart = abs(scales[0] - scales[2]) / abs(ghost.toSensor.a)
                #expect(apart < 0.05, "a wide ghost's colors part by \(apart)")
            }
            // Every channel still lands on the same side of the axis.
            #expect(scales.allSatisfy { ($0 < 0) == (ghost.toSensor.a < 0) })
        }
        // The ghost nearest focus parts its colors by the largest share of its own
        // size: its scale is a small difference of large numbers, so a small
        // change in the glass is a large change in it.
        func parting(_ ghost: LensGhost) -> Double {
            abs(ghost.channels[0].sensorA - ghost.channels[2].sensorA) / abs(ghost.toSensor.a)
        }
        let focused = try #require(optics.ghosts.min { abs($0.toSensor.a) < abs($1.toSensor.a) })
        let widest = try #require(optics.ghosts.max { abs($0.toSensor.a) < abs($1.toSensor.a) })
        #expect(parting(focused) > parting(widest) * 2,
                "near focus \(parting(focused)) against the widest ghost's \(parting(widest))")
    }

    /// The check the matrices never had. A real ray, followed through the real
    /// spheres by vector optics, has to land where the matrices say once it is
    /// close enough to the axis for first order to hold, on the sensor and on
    /// the iris, for every ghost of both lenses. The two are separate
    /// derivations of the same path, so agreement to parts in a million leaves
    /// neither room to be wrong.
    ///
    /// The straight-through check further up cannot stand in for this: it has no
    /// reflection in it, and the reflections are where a chain of matrices goes
    /// wrong. It did, once. The leg between the two reflections passed *through*
    /// the inner surface before reflecting off it and mixed two conventions for
    /// a ray travelling back toward the front, and every ghost came out in the
    /// wrong place at the wrong size with nothing to say so.
    @Test func everyGhostAgreesWithRealRays() {
        for lens in [Lens.heliar, Lens.doubleGauss] {
            for ghost in lens.optics().ghosts {
                let entry = SIMD2(1e-3, -0.5e-3), slope = SIMD2(2e-4, 1e-4)
                let ray = lens.trace(ghost, entry: entry, slope: slope)
                #expect(ray.isValid, "\(ghost.firstInterface),\(ghost.secondInterface) lost a paraxial ray")
                let sensor = ghost.toSensor.a * entry + ghost.toSensor.b * slope
                let iris = ghost.toIris.a * entry + ghost.toIris.b * slope
                #expect(simd_length(ray.sensor - sensor) < 1e-5 * simd_length(sensor),
                        "sensor, ghost \(ghost.firstInterface),\(ghost.secondInterface)")
                #expect(simd_length(ray.aperture - iris) < 1e-5 * simd_length(iris),
                        "iris, ghost \(ghost.firstInterface),\(ghost.secondInterface)")
                // The angle it meets each reflecting surface at, which is what the
                // coating is read by. A ray aimed at a surface's center of
                // curvature meets it head on, so the lean adds to the slope.
                let outer = simd_length(ghost.outerIncidence.pupil * entry
                                        + ghost.outerIncidence.angle * slope)
                let inner = simd_length(ghost.innerIncidence.pupil * entry
                                        + ghost.innerIncidence.angle * slope)
                #expect(abs(outer - ray.outerIncidence) < 1e-5 * ray.outerIncidence)
                #expect(abs(inner - ray.innerIncidence) < 1e-5 * ray.innerIncidence)
            }
        }
    }

    /// What first order cannot show, and the reason to follow real rays at all.
    /// Away from the axis a sphere bends a ray by more than proportion says, so a
    /// real ghost is not a scaled copy of the opening: rays through the rim land
    /// well away from where the matrices put them. And a flare is a chain through
    /// the middle of the frame, so some ghosts have to land across the center
    /// from the light.
    @Test func realGhostsDepartFromFirstOrderTowardTheRim() throws {
        let lens = Lens.heliar
        let optics = lens.optics()
        let ghost = try #require(optics.ghosts.first {
            $0.firstInterface == 2 && $0.secondInterface == 3
        })
        let slope = SIMD2(0.12, 0.0)
        func departure(_ fraction: Double) -> Double {
            let entry = SIMD2(fraction * optics.pupilRadius, 0)
            let ray = lens.trace(ghost, entry: entry, slope: slope)
            let first = ghost.toSensor.a * entry + ghost.toSensor.b * slope
            return simd_length(ray.sensor - first)
        }
        #expect(departure(0.6) > departure(0.2) * 4, "the departure grows faster than the height")
        #expect(departure(0.6) > 1, "and is millimeters on the sensor, not a rounding")

        let across = optics.ghosts.filter { $0.toSensor.b < 0 }.count
        let along = optics.ghosts.filter { $0.toSensor.b > 0 }.count
        #expect(across >= 3 && along >= 3, "\(across) across the center, \(along) on the light's side")
    }

    /// The barrel, which first order does not have. A ray well inside the front
    /// opening can still stray past the rim of an element further along, and
    /// there the lens stops it. On the Heliar's widest ghosts that happens by half
    /// the opening's height, which is why a followed ghost is so much smaller
    /// than the disc first order draws. A ray along the axis strays nowhere.
    @Test func theBarrelStopsRaysFirstOrderLetsThrough() throws {
        let lens = Lens.heliar
        let optics = lens.optics()
        let ghost = try #require(optics.ghosts.first {
            $0.firstInterface == 0 && $0.secondInterface == 2
        })
        let slope = SIMD2(0.12, 0.0)
        let middle = lens.trace(ghost, entry: .zero, slope: slope)
        let halfway = lens.trace(ghost, entry: SIMD2(0.5 * optics.pupilRadius, 0), slope: slope)
        #expect(middle.isValid && middle.relativeHeight < 1, "the chief ray passes: \(middle.relativeHeight)")
        #expect(halfway.isValid && halfway.relativeHeight > 1,
                "halfway up the opening the barrel has it: \(halfway.relativeHeight)")
        // And what crosses each surface is what does not reflect there, so a ray
        // loses a little at every glass it passes, more the steeper it meets one.
        #expect(middle.transmittance < 1 && middle.transmittance > 0.5)
    }

    /// The table the fragment reads is the formula, tabulated: a row per surface
    /// and direction, the square root stored, head on at the first column and
    /// grazing at the last.
    @Test func theCoatingTableIsTheFormulaTabulated() {
        let lens = Lens.heliar.multicoated()
        let table = lens.coatingTable(samples: 64)
        #expect(table.rows == lens.interfaces.count * 2)
        #expect(table.values.count == table.rows * 64 * 4)
        let wavelengths = Lens.channelWavelengths
        for (index, step) in [(0, 0), (2, 17), (4, 40), (8, 63)] {
            let angle = Double.pi / 2 * Double(step) / 63
            let face = lens.interfaces[index]
            let before = index == 0 ? 1 : lens.interfaces[index - 1].ior
            for side in 0..<2 {
                let n0 = side == 0 ? before : face.ior, n2 = side == 0 ? face.ior : before
                for channel in 0..<3 {
                    let expected = interfaceReflectance(
                        angle: angle, wavelength: wavelengths[channel],
                        designWavelength: face.coating ?? lens.coatingWavelength, n0: n0, n2: n2)
                    let stored = Double(table.values[((index * 2 + side) * 64 + step) * 4 + channel])
                    #expect(abs(stored * stored - expected) < 1e-5,
                            "interface \(index) side \(side) step \(step) channel \(channel)")
                }
            }
        }
        // Grazing, everything reflects, from either side.
        for row in 0..<table.rows where !lens.interfaces[row / 2].isIris {
            #expect(table.values[(row * 64 + 63) * 4] > 0.99, "row \(row) at grazing")
        }
    }

    /// A ghost is made by a pair of surfaces, and the brightest pairs are
    /// neighbors. So multicoating must never hand two neighbors coatings close
    /// together, or the whole chain comes out one color, which is what a plain
    /// front-to-back sweep does. It still has to use the whole range.
    @Test func multicoatingKeepsNeighborsApart() {
        for lens in [Lens.heliar, Lens.doubleGauss] {
            let coated = lens.multicoated(from: 440, to: 660)
            let values = coated.interfaces.compactMap(\.coating)
            #expect(values.min() == 440 && values.max() == 660)
            #expect(Set(values).count == values.count, "no two surfaces share a coating")
            let even = 220.0 / Double(values.count - 1)
            for (a, b) in zip(values, values.dropFirst()) {
                #expect(abs(a - b) > even * 1.5,
                        "neighbors at \(a) and \(b) sit closer than a sweep's \(even) apart allows")
            }
        }
    }

    /// The number the level is set against belongs to the lens: it does not move
    /// with the f-number, and a lens with better coatings carries less.
    @Test func whatTheGhostsCarryBelongsToTheLens() {
        let lens = Lens.heliar
        let wide = lens.ghostThroughput(lens.optics())
        let stopped = lens.stopped(to: 16)
        #expect(wide > 0)
        #expect(abs(stopped.ghostThroughput(stopped.optics()) - wide) < wide * 1e-9)
        // A cemented junction reflects far less than a coated air surface, so
        // the total stays a small fraction.
        #expect(wide < 0.01)
    }
}
