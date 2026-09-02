@testable import Ollin
import Testing
import Foundation

/// Checks on the two fitting helpers: `RadialBasis`, which puts a smooth field through
/// scattered values, and `Fit.minimize`, which walks a handful of numbers downhill.
///
/// Both are checked against laws rather than against numbers somebody read off a run.
/// A field that is slightly wrong still looks like a smooth field, and a minimizer that
/// has stopped early still hands back a plausible answer, so eyeballing either one proves
/// nothing. The two laws that carry the most weight:
///
/// - **The field passes through its data.** That is the definition of interpolating, so
///   with no smoothing asked for it has to hold to floating-point precision.
/// - **The field reproduces any flat plane exactly, everywhere.** Data taken from
///   `a + bx + cy` is fitted by the polynomial tail alone, with every bump weight zero, and
///   the fit is unique, so that must be the answer. This is the test that the tail is
///   really there and really fitted: drop it and the check fails away from the points
///   while still passing at them.
@Suite
struct RadialBasisTests {

    private static let kernels: [RadialBasis<Vector2, Double>.Kernel] = [
        .thinPlate, .linear, .cubic, .multiquadric(scale: 40),
        .inverseMultiquadric(scale: 40), .gaussian(scale: 200),
    ]

    private static let scattered = [
        Vector2(120, 140), Vector2(700, 300), Vector2(400, 860),
        Vector2(880, 760), Vector2(240, 620), Vector2(540, 120),
    ]

    /// With no smoothing the field has to hit every value it was given. Anything else is
    /// not interpolation, whatever it looks like in between.
    @Test(arguments: kernels)
    func theFieldPassesThroughItsData(kernel: RadialBasis<Vector2, Double>.Kernel) throws {
        let values = [0.1, 0.9, 0.4, 0.65, 0.2, 0.8]
        let field = try #require(RadialBasis(points: Self.scattered, values: values,
                                             kernel: kernel))
        for (point, value) in zip(Self.scattered, values) {
            #expect(abs(field.value(at: point) - value) < 1e-7,
                    "at \(point) the field reads \(field.value(at: point)), not \(value)")
        }
    }

    /// Data taken from a flat plane must come back as that plane, at the fitted points and
    /// everywhere else. The polynomial tail fits it with every bump weight at zero, and the
    /// solution is unique, so that has to be the answer.
    @Test(arguments: kernels)
    func aFlatPlaneComesBackExactly(kernel: RadialBasis<Vector2, Double>.Kernel) throws {
        func plane(_ p: Vector2) -> Double { 3.5 + 0.012 * p.x - 0.004 * p.y }
        let field = try #require(RadialBasis(points: Self.scattered,
                                             values: Self.scattered.map(plane),
                                             kernel: kernel))
        // Read it well away from the fitted points, including outside their hull, which is
        // where a missing tail shows and a check made only at the points would not.
        for probe in [Vector2(500, 500), Vector2(30, 900), Vector2(1500, -200),
                      Vector2(-400, 1400)] {
            #expect(abs(field.value(at: probe) - plane(probe)) < 1e-6,
                    "at \(probe) the field reads \(field.value(at: probe)), not \(plane(probe))")
        }
    }

    /// Smoothing is a dial, so it has to behave like one: more of it means the field is
    /// allowed to miss its data by more, without exception along the way.
    @Test func smoothingLetsTheFieldMissByMore() throws {
        let values = [0.1, 0.9, 0.4, 0.65, 0.2, 0.8]
        var previous = -1.0
        for smoothing in [0.0, 0.01, 0.1, 1.0, 10.0] {
            let field = try #require(RadialBasis(points: Self.scattered, values: values,
                                                 smoothing: smoothing))
            let miss = zip(Self.scattered, values)
                .map { abs(field.value(at: $0) - $1) }
                .reduce(0, +)
            #expect(miss > previous - 1e-12, "smoothing \(smoothing) missed by \(miss)")
            previous = miss
        }
        #expect(previous > 0.05, "the largest smoothing barely moved the field")
    }

    /// The same fit at two coordinate scales has to smooth by the same amount. Smoothing
    /// sits on the diagonal of a kernel matrix whose entries grow with how far apart the
    /// points are, so a raw number would mean something different on a canvas of pixels
    /// than on the same layout measured in fractions: at 1 it did nothing at all over
    /// hundreds of pixels. Measuring it against the typical bump is what makes the parameter
    /// mean one thing, and this is the check that it does.
    @Test func smoothingMeansTheSameThingAtAnyScale() throws {
        let values = [0.1, 0.9, 0.4, 0.65, 0.2, 0.8]
        func missAtScale(_ scale: Double) throws -> Double {
            let scaled = Self.scattered.map { Vector2($0.x * scale, $0.y * scale) }
            let field = try #require(RadialBasis(points: scaled, values: values, smoothing: 0.1))
            return zip(scaled, values).map { abs(field.value(at: $0) - $1) }.reduce(0, +)
        }
        let small = try missAtScale(0.001)
        let large = try missAtScale(1000)
        #expect(abs(small - large) < 1e-6,
                "the same smoothing missed by \(small) at one scale and \(large) at another")
        #expect(small > 0.01, "smoothing 0.1 should be doing something")
    }

    /// Each channel of a color field is the field its own numbers would have made alone.
    /// They share one solve, which is the point, and sharing must not mix them.
    @Test func everyChannelIsFittedOnItsOwn() throws {
        let colors = [Color(red: 0.9, green: 0.2, blue: 0.1), Color(red: 0.1, green: 0.7, blue: 0.3),
                      Color(red: 0.4, green: 0.4, blue: 0.95), Color(red: 0.8, green: 0.9, blue: 0.2),
                      Color(red: 0.2, green: 0.1, blue: 0.6), Color(red: 0.5, green: 0.6, blue: 0.4)]
        let together = try #require(RadialBasis(points: Self.scattered, values: colors))
        let reds = try #require(RadialBasis(points: Self.scattered, values: colors.map(\.red)))
        for probe in [Vector2(300, 300), Vector2(640, 480), Vector2(900, 120)] {
            #expect(abs(together.value(at: probe).red - reds.value(at: probe)) < 1e-9)
        }
    }

    /// A field of vectors is a warp: pin a few places to where they should go, and the
    /// places themselves must land exactly there.
    @Test func aFieldOfVectorsMovesItsPinnedPlacesExactly() throws {
        let targets = Self.scattered.map { Vector2($0.x + 40, $0.y - 25) }
        let warp = try #require(RadialBasis(points: Self.scattered, values: targets))
        for (from, to) in zip(Self.scattered, targets) {
            #expect(warp.value(at: from).distance(to: to) < 1e-6)
        }
    }

    /// Points that all sit on one line leave the plane undetermined: any tilt across the
    /// line fits the data equally well. That is a genuine failure to fit rather than a
    /// number to guess at, so it comes back as nothing.
    @Test func pointsOnOneLineCannotPinAPlaneDown() {
        let line = (0 ..< 5).map { Vector2(Double($0) * 100, Double($0) * 100) }
        #expect(RadialBasis(points: line, values: [0.0, 1, 0, 1, 0]) == nil)
    }

    /// Nothing to fit, or a mismatched pair of lists, is nothing rather than a crash.
    @Test func anEmptyOrMismatchedFitIsNothing() {
        #expect(RadialBasis(points: [Vector2](), values: [Double]()) == nil)
        #expect(RadialBasis(points: Self.scattered, values: [0.1, 0.2]) == nil)
    }

    /// Three points in space still pin a field, which is the whole of the 3D claim.
    @Test func itFitsInSpaceToo() throws {
        let places = [Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(0, 100, 0),
                      Vector3(0, 0, 100), Vector3(60, 40, 20)]
        let values = [0.0, 1, 2, 3, 1.5]
        let field = try #require(RadialBasis(points: places, values: values))
        for (place, value) in zip(places, values) {
            #expect(abs(field.value(at: place) - value) < 1e-7)
        }
    }
}

/// Checks on `Fit.minimize`.
@Suite
struct FitTests {

    /// A bowl with its bottom at a known place. If the walk cannot find that, nothing
    /// else it reports means anything.
    @Test func itFindsTheBottomOfABowl() {
        let result = Fit.minimize(from: [0, 0], steps: 900, rate: 0.4) { p in
            let dx = p[0] - 3.25, dy = p[1] + 1.75
            return dx * dx + dy * dy
        }
        #expect(abs(result.values[0] - 3.25) < 1e-3, "x landed at \(result.values[0])")
        #expect(abs(result.values[1] + 1.75) < 1e-3, "y landed at \(result.values[1])")
        #expect(result.cost < 1e-5)
    }

    /// One parameter measured in hundreds beside one measured in thousandths, both of which have
    /// to arrive. This is what the per-parameter step scaling is for: a single step size either
    /// crawls along the wide parameter or throws the narrow one across its whole range, and a
    /// bowl this lopsided is where that shows.
    @Test func parametersOnVeryDifferentScalesBothArrive() {
        let result = Fit.minimize(from: [0, 0], steps: 4000, rate: 0.5) { p in
            let wide = (p[0] - 800) / 800
            let narrow = (p[1] - 0.004) / 0.004
            return wide * wide + narrow * narrow
        }
        #expect(abs(result.values[0] - 800) < 8, "the wide parameter stopped at \(result.values[0])")
        #expect(abs(result.values[1] - 0.004) < 4e-5,
                "the narrow parameter stopped at \(result.values[1])")
    }

    /// A parameter given a range stays inside it, including when the bottom of the bowl is
    /// outside and the walk keeps pushing that way.
    @Test func aParameterStaysInsideItsRange() {
        let result = Fit.minimize(from: [0], bounds: [-1 ... 1], steps: 400, rate: 0.2) { p in
            let d = p[0] - 50
            return d * d
        }
        #expect(result.values[0] <= 1 + 1e-12)
        #expect(result.values[0] > 0.99, "it should have pressed against the top of the range")
    }

    /// The job it is actually for: recover a shape from marks scattered around it. The
    /// marks carry a fixed wobble, so the answer is near the truth rather than at it, and
    /// the seed is pinned so the check means the same thing every run.
    @Test func itRecoversACircleFromMarksAroundIt() {
        var rng = SplitMix64(seed: 7)
        let truth = (x: 512.0, y: 460.0, r: 210.0)
        let marks = (0 ..< 90).map { i -> Vector2 in
            let a = Double(i) / 90 * .pi * 2
            let wobble = Double.random(in: -6 ... 6, using: &rng)
            return Vector2(truth.x + cos(a) * (truth.r + wobble),
                           truth.y + sin(a) * (truth.r + wobble))
        }
        let result = Fit.minimize(from: [400, 400, 100], steps: 2000, rate: 4) { p in
            let center = Vector2(p[0], p[1])
            return marks.reduce(0.0) { total, mark in
                let off = center.distance(to: mark) - p[2]
                return total + off * off
            }
        }
        #expect(abs(result.values[0] - truth.x) < 3, "center x \(result.values[0])")
        #expect(abs(result.values[1] - truth.y) < 3, "center y \(result.values[1])")
        #expect(abs(result.values[2] - truth.r) < 3, "radius \(result.values[2])")
    }

    /// A walk that has arrived says so, rather than spending every step it was given.
    @Test func itSaysWhenItHasSettled() {
        let result = Fit.minimize(from: [1], steps: 5000, rate: 0.1) { p in p[0] * p[0] }
        #expect(result.settled)
        #expect(result.steps < 5000, "it used all \(result.steps) steps")
    }
}
