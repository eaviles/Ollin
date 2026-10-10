@testable import Ollin
import Testing
import Foundation

/// The slope of a fitted field, and of any function a sketch writes.
///
/// `RadialBasis` reports its slope from each kernel's closed-form derivative, so it is
/// read against two oracles that share none of that code: central differences of the
/// field's own value, at points away from the data (where every kernel is smooth), and
/// a fitted plane, whose gradient is the plane's slope everywhere because the fit is
/// the plane. The numerical helpers are read against derivatives worked out by hand.
@Suite
struct FieldSlopeTests {

    private static let kernels: [RadialBasis<Vector2, Double>.Kernel] = [
        .thinPlate, .linear, .cubic, .multiquadric(scale: 40),
        .inverseMultiquadric(scale: 40), .gaussian(scale: 200),
    ]

    private static let scattered = [
        Vector2(120, 140), Vector2(700, 300), Vector2(400, 860),
        Vector2(880, 760), Vector2(240, 620), Vector2(540, 120),
    ]

    /// Probes across the canvas, none within 20 pixels of a data point, where the
    /// linear kernel's cones and thin plate's log term are both smooth.
    private static let probes: [Vector2] = {
        var random = SplitMix64(seed: 112)
        var found: [Vector2] = []
        while found.count < 40 {
            let p = Vector2(Double.random(in: -100 ... 1180, using: &random),
                            Double.random(in: -100 ... 1180, using: &random))
            if scattered.allSatisfy({ $0.distance(to: p) > 20 }) { found.append(p) }
        }
        return found
    }()

    /// The exact gradient agrees with central differences of the value to a part
    /// in a million of its size, for every kernel, smoothed or not.
    @Test(arguments: kernels)
    func theGradientMatchesCentralDifferences(kernel: RadialBasis<Vector2, Double>.Kernel) throws {
        let values = [0.1, 0.9, 0.4, 0.65, 0.2, 0.8]
        for smoothing in [0.0, 0.05] {
            let field = try #require(RadialBasis(points: Self.scattered, values: values,
                                                 kernel: kernel, smoothing: smoothing))
            for p in Self.probes {
                let exact = field.gradient(at: p)
                let h = 1e-3
                let numeric = Vector2(
                    (field.value(at: p + Vector2(h, 0)) - field.value(at: p - Vector2(h, 0))) / (2 * h),
                    (field.value(at: p + Vector2(0, h)) - field.value(at: p - Vector2(0, h))) / (2 * h))
                let scale = max(numeric.length, 1e-6)
                #expect((exact - numeric).length / scale < 1e-6, "\(kernel) at \(p): \(exact) against \(numeric)")
            }
        }
    }

    /// Data on a plane is fitted by the tail alone, so the gradient is the plane's
    /// slope everywhere, data points included, with every kernel.
    @Test(arguments: kernels)
    func aPlanesGradientIsItsSlope(kernel: RadialBasis<Vector2, Double>.Kernel) throws {
        let plane = { (p: Vector2) in 3 - 0.002 * p.x + 0.0035 * p.y }
        let field = try #require(RadialBasis(points: Self.scattered,
                                             values: Self.scattered.map(plane), kernel: kernel))
        for p in Self.probes + Self.scattered {
            let g = field.gradient(at: p)
            #expect(abs(g.x + 0.002) < 1e-9 && abs(g.y - 0.0035) < 1e-9, "\(kernel) at \(p): \(g)")
        }
    }

    /// In three dimensions too: the exact gradient against the numerical helper.
    @Test func aSpaceFieldsGradientMatchesTheHelper() throws {
        let points = [Vector3(0, 0, 0), Vector3(1, 0.2, 0.1), Vector3(0.3, 1, 0.4),
                      Vector3(0.2, 0.5, 1), Vector3(0.9, 0.8, 0.7), Vector3(0.5, 0.1, 0.6)]
        let field = try #require(RadialBasis(points: points, values: [0, 1, 0.5, 0.2, 0.9, 0.4]))
        for p in [Vector3(0.5, 0.5, 0.5), Vector3(-0.3, 0.7, 0.2), Vector3(1.2, -0.1, 0.9)] {
            let exact = field.gradient(at: p)
            let numeric = gradient(at: p) { field.value(at: $0) }
            #expect((exact - numeric).length / numeric.length < 1e-6)
        }
    }

    /// The derivative along a direction is linear in it, it is the gradient's dot
    /// product for a field of numbers, and for a warp the two axes' derivatives are
    /// the Jacobian's columns, read against central differences of each component.
    @Test func theDerivativeAlongADirectionIsTheJacobian() throws {
        let values = [0.1, 0.9, 0.4, 0.65, 0.2, 0.8]
        let field = try #require(RadialBasis(points: Self.scattered, values: values))
        let warp = try #require(RadialBasis(points: Self.scattered, values: Self.scattered.map {
            $0 + Vector2(40 * sin($0.y * 0.01), 30 * cos($0.x * 0.013))
        }))
        let colors = try #require(RadialBasis(points: Array(Self.scattered.prefix(4)),
                                              values: [Color.red, .green, .blue, .white]))
        for p in Self.probes.prefix(10) {
            let direction = Vector2(0.6, -0.8)
            let along = field.derivative(at: p, along: direction)
            #expect(abs(along - field.gradient(at: p).dot(direction)) < 1e-15)
            #expect(abs(field.derivative(at: p, along: direction * 3) - 3 * along) < 1e-15)

            let h = 1e-3
            let dx = warp.derivative(at: p, along: Vector2(1, 0))
            let dy = warp.derivative(at: p, along: Vector2(0, 1))
            let numericX = (warp.value(at: p + Vector2(h, 0)) - warp.value(at: p - Vector2(h, 0))) / (2 * h)
            let numericY = (warp.value(at: p + Vector2(0, h)) - warp.value(at: p - Vector2(0, h))) / (2 * h)
            #expect((dx - numericX).length < 1e-6 * max(numericX.length, 1))
            #expect((dy - numericY).length < 1e-6 * max(numericY.length, 1))

            let rate = colors.derivative(at: p, along: Vector2(1, 0))
            let ahead = colors.value(at: p + Vector2(h, 0)), behind = colors.value(at: p - Vector2(h, 0))
            for (got, a, b) in zip3(rate.channels, ahead.channels, behind.channels) {
                #expect(abs(got - (a - b) / (2 * h)) < 1e-7)
            }
        }
    }

    // MARK: The numerical helpers

    /// Smooth functions to many digits, a cubic far from zero, and a quadratic
    /// exactly at a step of its own choosing.
    @Test func derivativeReadsKnownSlopes() {
        for x in stride(from: -3.0, through: 3.0, by: 0.37) {
            #expect(abs(derivative(at: x) { sin($0) } - cos(x)) < 1e-9)
            #expect(abs(derivative(at: x) { exp($0) } - exp(x)) / exp(x) < 1e-9)
        }
        let cubic = derivative(at: 1000) { $0 * $0 * $0 }
        #expect(abs(cubic - 3e6) / 3e6 < 1e-9)
        #expect(derivative(at: 7, step: 0.5) { $0 * $0 } == 14)
        // A step of zero or less, or not a number, takes the automatic one.
        #expect(abs(derivative(at: 1, step: 0) { sin($0) } - cos(1)) < 1e-9)
        #expect(abs(derivative(at: 1, step: -2) { sin($0) } - cos(1)) < 1e-9)
        #expect(abs(derivative(at: 1, step: .nan) { sin($0) } - cos(1)) < 1e-9)
    }

    /// The plane's and space's gradients against hand-worked partials.
    @Test func gradientReadsKnownSlopes() {
        let f2 = { (p: Vector2) in p.x * p.x * p.y + sin(p.y) }
        for p in [Vector2(0.3, -1.2), Vector2(2, 0.5), Vector2(-540, 300)] {
            let g = gradient(at: p, field: f2)
            let want = Vector2(2 * p.x * p.y, p.x * p.x + cos(p.y))
            #expect((g - want).length / max(want.length, 1) < 1e-8, "\(p): \(g) against \(want)")
        }
        let f3 = { (p: Vector3) in p.x * p.y * p.z + exp(0.5 * p.z) }
        for p in [Vector3(0.3, -1.2, 0.8), Vector3(2, 0.5, -1)] {
            let g = gradient(at: p, field: f3)
            let want = Vector3(p.y * p.z, p.x * p.z, p.x * p.y + 0.5 * exp(0.5 * p.z))
            #expect((g - want).length / want.length < 1e-8)
        }
        // A quadratic bowl at a given step is exact.
        let bowl = gradient(at: Vector2(3, -4), step: 0.25) { $0.x * $0.x + 2 * $0.y * $0.y }
        #expect(bowl == Vector2(6, -16))
    }

    private func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
        zip(a, zip(b, c)).map { ($0, $1.0, $1.1) }
    }
}
