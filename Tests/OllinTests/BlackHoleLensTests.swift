import CoreGraphics
import CSpectralData
import Foundation
import Ollin
import Testing

/// Invariants over the `Shaders/BlackHole` example's physics. The light paths, the
/// disk's shift and flux, and the color of heat are read from the example's own
/// `physics.metal`, so these check the file that ships, run on the GPU in the
/// float precision the picture uses. The reference for each invariant is worked out
/// here in double precision from a closed form or an exact integral, never from
/// the shader.
///
/// Units are the example's: the horizon radius is 1, so the photon sphere is at
/// 1.5, the innermost stable orbit at 3, and the far-field bend is 2 / b.
@Suite
@MainActor
struct BlackHoleLensTests {

    // MARK: Where light goes

    /// Every ray's swept angle, from a camera held at 26 horizon radii (the
    /// example's own distance), against the exact orbit integral. The rays run
    /// from nearly straight at the hole, past the edge of the shadow, to
    /// straight away from it. A hundred-thousandth of a radian is a fiftieth of a
    /// pixel at the example's field of view.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSweptAngleIsTheExactOrbitIntegral() throws {
        let r0 = 26.0
        let angles = stride(from: 0.02, through: 3.1, by: 0.02).map { $0 }
        let traced = try #require(LensProbe.trace(angles.map { LensProbe.inPlane(r0: r0, offAxis: $0) }))
        var worst = 0.0, worstAt = 0.0, compared = 0
        for (angle, t) in zip(angles, traced) {
            guard let exact = Orbit.sweep(r0: r0, offAxis: angle) else {
                #expect(t.escaped == 0, "a ray at \(angle) rad falls in, but the shader let it escape")
                continue
            }
            #expect(t.escaped == 1, "a ray at \(angle) rad escapes, but the shader lost it")
            guard t.escaped == 1 else { continue }
            compared += 1
            let error = abs(t.swept - exact)
            if error > worst { worst = error; worstAt = angle }
        }
        #expect(compared > 100)
        #expect(worst < 1e-5, "worst error \(worst) rad at \(worstAt) rad off the hole")
    }

    /// Far from the hole the bend is 4GM / (c² b), 2 / b in these units.
    /// Einstein's closed form is the first term of the exact answer, whose next
    /// term is (15π/32) / b times it; so the bend measured from a camera far
    /// away must exceed the closed form by a fraction no bigger than that, and
    /// the excess must shrink as b grows.
    @Test(.enabled(if: Snapshot.hasMetal))
    func farOutTheBendIsFourGMOverCSquaredB() throws {
        let r0 = 1e5
        let impacts = [30.0, 100.0, 300.0]
        let held = (1 - 1 / r0).squareRoot()
        let angles = impacts.map { asin($0 * held / r0) }
        let traced = try #require(LensProbe.trace(angles.map { LensProbe.inPlane(r0: r0, offAxis: $0) }))
        var excesses: [Double] = []
        for ((b, angle), t) in zip(zip(impacts, angles), traced) {
            #expect(t.escaped == 1)
            #expect(abs(t.impact - b) < 1e-3 * b, "impact \(t.impact) for \(b)")
            // A straight line from the camera would sweep π - angle.
            let bend = t.swept - (Double.pi - angle)
            let closedForm = 2 / b
            let excess = bend / closedForm - 1
            let nextTerm = 15 * Double.pi / 32 / b
            #expect(excess > 0 && excess < 1.2 * nextTerm,
                    "at b = \(b) the bend \(bend) is \(excess) over 2/b; the next term is \(nextTerm)")
            excesses.append(excess)
        }
        #expect(excesses == excesses.sorted(by: >), "the excess over 2/b must shrink as b grows: \(excesses)")
    }

    /// The shadow's edge. A camera held at r0 sees the hole take every ray
    /// closer than sin θ = (3√3 / 2)(1 / r0) sqrt(1 - 1 / r0) to the center:
    /// Synge's angle for the photon sphere's capture cross-section. The traced
    /// rays must switch from falling in to escaping within a twentieth of a
    /// percent of it, at three distances.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theShadowIsSyngesCircle() throws {
        for r0 in [8.0, 26.0, 60.0] {
            let synge = asin(1.5 * 3.0.squareRoot() / r0 * (1 - 1 / r0).squareRoot())
            let angles = (0 ..< 121).map { synge * (0.97 + 0.0005 * Double($0)) }
            let traced = try #require(LensProbe.trace(angles.map { LensProbe.inPlane(r0: r0, offAxis: $0) }))
            let first = try #require(traced.firstIndex { $0.escaped == 1 }, "nothing escaped at r0 = \(r0)")
            #expect(traced[first...].allSatisfy { $0.escaped == 1 },
                    "rays past the edge fell in at r0 = \(r0)")
            let edge = angles[first] / synge - 1
            #expect(abs(edge) < 5e-4, "the shadow's edge is \(edge) off Synge's angle at r0 = \(r0)")
        }
    }

    /// A star straight behind the hole is seen as a ring: the rays that leave
    /// the camera at the ring's angle all reach the sky exactly opposite the
    /// camera, having swept half a turn. The ring's angle from the traced rays
    /// must match the exact orbit integral, and approach the closed form of
    /// the weak field, sqrt(4GM D_ls / (c² D_l D_s)), which is sqrt(2 / r0) here
    /// with the star at infinity, as the camera backs away: the gap closes as
    /// 1 / sqrt(r0), so each factor of ten in distance divides it by about
    /// three.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStarBehindTheHoleIsARingAtTheClosedFormAngle() throws {
        var gaps: [Double] = []
        for r0 in [26.0, 1000.0, 1e5] {
            let exact = try #require(Orbit.ringAngle(r0: r0))
            let angles = (0 ..< 101).map { exact * (0.99 + 0.0002 * Double($0)) }
            let traced = try #require(LensProbe.trace(angles.map { LensProbe.inPlane(r0: r0, offAxis: $0) }))
            // The sweep falls through π as the angle grows; interpolate the
            // crossing.
            var ring: Double?
            for i in 1 ..< traced.count where traced[i - 1].swept > .pi && traced[i].swept <= .pi {
                let a = traced[i - 1].swept - .pi, b = traced[i].swept - .pi
                ring = angles[i - 1] + (angles[i] - angles[i - 1]) * a / (a - b)
            }
            let measured = try #require(ring, "no ring near \(exact) rad at r0 = \(r0)")
            #expect(abs(measured / exact - 1) < 2e-4,
                    "ring at \(measured) rad against the exact \(exact) at r0 = \(r0)")
            let closedForm = (2 / r0).squareRoot()
            gaps.append(measured / closedForm - 1)
        }
        // 10% over the closed form at the example's distance, 1.6% at a
        // thousand horizon radii, 0.17% at a hundred thousand.
        #expect(gaps[0] > 0.09 && gaps[0] < 0.11, "gap at 26: \(gaps[0])")
        #expect(gaps[2] > 0 && gaps[2] < 0.002, "gap at 1e5: \(gaps[2])")
        #expect(gaps[0] / gaps[1] > 5 && gaps[1] / gaps[2] > 8 && gaps[1] / gaps[2] < 12,
                "the gap must close as 1 / sqrt(r0): \(gaps)")
    }

    /// The same ring in the finished picture: the example's own shader, with the
    /// disk and the stars off and its beacon star placed straight behind the
    /// hole, rendered and measured. This is what checks the camera: a pixel's
    /// distance from the center must turn into the angle the physics was given.
    /// The ring's radius is read as the brightness-weighted mean of the pixels
    /// round it (a finite star makes the ring a band, whose two edges sit
    /// evenly either side of the true ring).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theRingInThePictureIsWhereTheOrbitPutsIt() throws {
        for r0 in [26.0, 1e4] {
            let ring = try #require(Orbit.ringAngle(r0: r0))
            let side = 256
            // Frame the ring at 80 pixels from the center.
            let spread = tan(ring) * Double(side / 2) / 80
            let picture = LensPicture(side: side, r0: r0, spread: spread)
            let image = try #require(OllinApp.image(of: picture, frame: 0))
            let pixels = try #require(Pixels(image))
            var sum = 0.0, weighted = 0.0
            for y in 0 ..< side {
                for x in 0 ..< side {
                    let dx = Double(x) + 0.5 - Double(side) / 2, dy = Double(y) + 0.5 - Double(side) / 2
                    let rho = (dx * dx + dy * dy).squareRoot()
                    guard rho > 40, rho < 120 else { continue }
                    let w = pixels.linearGreen(x, y)
                    sum += w
                    weighted += w * rho
                }
            }
            #expect(sum > 10, "no ring drawn at r0 = \(r0)")
            let measured = atan(weighted / sum / Double(side / 2) * spread)
            let pixel = 2 * spread / Double(side)
            #expect(abs(measured - ring) < 0.5 * pixel,
                    "ring at \(measured) rad, the orbit puts it at \(ring), at r0 = \(r0)")
            if r0 > 1000 {
                let closedForm = (2 / r0).squareRoot()
                #expect(abs(measured / closedForm - 1) < 0.01,
                        "ring at \(measured), the closed form says \(closedForm)")
            }
        }
    }

    // MARK: The disk

    /// Seen from straight above, every point of the disk moves across the line
    /// of sight, and all that is left of the shift is the climb out of the well
    /// and the camera's own blueshift: g = sqrt(1 - 1.5 / r) / sqrt(1 - 1 / r0).
    /// Seen nearly edge-on, the side turning toward the camera is bluer than
    /// that and the side turning away redder, since the disk turns
    /// counter-clockwise seen from above, and near the inner edge the approach
    /// is fast enough to lift g above 1.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDiskIsBlueWhereItTurnsTowardTheCamera() throws {
        let r0 = 26.0
        // Face-on: the camera on the axis, rays at a spread of angles, azimuths.
        var above: [LensProbe.Ray] = []
        for i in 0 ..< 60 {
            let off = 0.12 + 0.004 * Double(i), turn = Double(i) * 0.7
            let ray = SIMD3(sin(off) * cos(turn), -cos(off), sin(off) * sin(turn))
            above.append(.init(camera: SIMD3(0, r0, 0), ray: ray, inner: 3, outer: 30))
        }
        let fromAbove = try #require(LensProbe.trace(above))
        var hit = 0
        for t in fromAbove where t.hits > 0 {
            hit += 1
            let expected = (1 - 1.5 / t.hitRadius).squareRoot() / (1 - 1 / r0).squareRoot()
            #expect(abs(t.shift - expected) < 1e-5, "g \(t.shift) at r \(t.hitRadius), expected \(expected)")
            #expect(abs(t.lz) < 1e-5)
        }
        #expect(hit > 40)

        // Nearly edge-on, from +z: the disk's left (-x) turns toward the camera.
        let camera = SIMD3(0, r0 * sin(0.05), r0 * cos(0.05))
        func aimed(at point: SIMD3<Double>) -> LensProbe.Ray {
            let d = point - camera
            return .init(camera: camera, ray: d / (d * d).sum().squareRoot(), inner: 3, outer: 30)
        }
        let left = try #require(LensProbe.trace([aimed(at: SIMD3(-4, 0, 0))])?.first)
        let right = try #require(LensProbe.trace([aimed(at: SIMD3(4, 0, 0))])?.first)
        #expect(left.hits > 0 && right.hits > 0)
        let still = (1 - 1.5 / left.hitRadius).squareRoot() / (1 - 1 / r0).squareRoot()
        #expect(left.shift > 1 && left.shift > still, "the approaching side's g is \(left.shift)")
        #expect(right.shift < still, "the receding side's g is \(right.shift) against \(still)")
        #expect(left.lz > 0 && right.lz < 0)
    }

    /// The disk's heat over radius, from Page and Thorne: nothing at the inner
    /// edge (the gas stops being held there), a peak of exactly 1 at r = 4.776,
    /// and a fall toward r^-3 far out (7.1 times less at 120 than at 60, where
    /// r^-3 alone would say 8).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDiskIsHottestAtFourPointEightAndColdAtItsEdge() throws {
        let radii = [3.0, 3.0001, 4.5, 4.7755, 5.1, 60, 120]
        let values = try #require(LensProbe.values(radii)).map(\.w)
        #expect(values[0] < 1e-6 && values[1] < 1e-3)
        #expect(abs(values[3] - 1) < 1e-4, "peak \(values[3])")
        #expect(values[2] < values[3] && values[4] < values[3])
        let tail = values[5] / values[6]
        #expect(tail > 6.5 && tail < 8, "doubling r from 60 should divide the flux by about 7, on its way to 8: \(tail)")
    }

    // MARK: The color of heat

    /// A black body's color, from the shader's fitted observer, against the
    /// CIE 1931 tables themselves: Planck's law summed with the tabulated
    /// color matching functions every 5 nm, in double precision. The
    /// chromaticity must agree to 0.003 at four temperatures from candle to sky
    /// (the fit's own error, largest in the red at 2000 K, is 0.0027 there and
    /// under 0.001 from 4000 K up), and brightness must grow with temperature in
    /// the tables' proportion.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theColorOfHeatIsTheCIEObserversBlackBody() throws {
        let temperatures = [2000.0, 4000.0, 6500.0, 10000.0]
        let shader = try #require(LensProbe.values(temperatures))
        for (kelvin, xyz) in zip(temperatures, shader) {
            let reference = CIE.blackbody(kelvin)
            let sum = xyz.x + xyz.y + xyz.z, refSum = reference.x + reference.y + reference.z
            let dx = xyz.x / sum - reference.x / refSum
            let dy = xyz.y / sum - reference.y / refSum
            #expect(abs(dx) < 0.003 && abs(dy) < 0.003,
                    "chromaticity off by (\(dx), \(dy)) at \(kelvin) K")
        }
        let brighter = shader[3].y / shader[1].y
        let referenceBrighter = CIE.blackbody(10000).y / CIE.blackbody(4000).y
        #expect(abs(brighter / referenceBrighter - 1) < 0.01,
                "10000 K over 4000 K is \(brighter) against \(referenceBrighter)")
    }
}

// MARK: - The exact orbit

/// The Schwarzschild orbit of light in double precision: (du/dφ)² = 1/b² − u²(1 − u)
/// with u = 1 / r, integrated by Gauss-Legendre quadrature with the turning
/// point's square-root singularity taken out by substitution.
private enum Orbit {
    static func p(_ u: Double, _ b: Double) -> Double { 1 / (b * b) - u * u + u * u * u }

    /// The smallest positive root of u²(1 − u) = 1 / b², where an incoming ray
    /// turns round; nil when there is none (the hole takes the ray).
    static func turning(_ b: Double) -> Double? {
        let target = 1 / (b * b)
        guard 4.0 / 27.0 > target else { return nil }
        var lo = 0.0, hi = 2.0 / 3.0
        for _ in 0 ..< 200 {
            let mid = 0.5 * (lo + hi)
            if mid * mid * (1 - mid) < target { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }

    /// ∫ from ua to ut of du / sqrt(p), with u = ut − s².
    static func toTurn(from ua: Double, to ut: Double, _ b: Double) -> Double {
        let top = (ut - ua).squareRoot()
        return Quadrature.integrate(0, top, panels: 64) { s in
            2 * s / max(p(ut - s * s, b), 1e-300).squareRoot()
        }
    }

    /// The angle a ray sweeps from a camera held at r0, leaving `offAxis`
    /// radians from the line to the hole, until it reaches the sky; nil when
    /// the hole takes it.
    static func sweep(r0: Double, offAxis angle: Double) -> Double? {
        let u0 = 1 / r0
        let b = r0 * sin(angle) / (1 - u0).squareRoot()
        let ut = turning(b)
        if cos(angle) <= 0 {
            // Leaving outward, straight to u = 0. Nearly sideways the camera
            // sits just past the turning point, where 1 / sqrt(p) is nearly
            // singular, so go round by the turning point when there is one.
            if let ut, ut >= u0 { return toTurn(from: 0, to: ut, b) - toTurn(from: u0, to: ut, b) }
            return Quadrature.integrate(0, u0, panels: 64) { u in 1 / p(u, b).squareRoot() }
        }
        guard let ut, ut > u0 else { return nil }
        return toTurn(from: u0, to: ut, b) + toTurn(from: 0, to: ut, b)
    }

    /// The angle off the hole at which a camera held at r0 sees a star straight
    /// behind the hole: the ray that sweeps exactly half a turn.
    static func ringAngle(r0: Double) -> Double? {
        var lo = 1e-7, hi = 1.2
        for _ in 0 ..< 100 {
            let mid = 0.5 * (lo + hi)
            guard let s = sweep(r0: r0, offAxis: mid) else { lo = mid; continue }
            if s > .pi { lo = mid } else { hi = mid }
        }
        return 0.5 * (lo + hi)
    }
}

/// Composite Gauss-Legendre quadrature, 16 nodes a panel.
private enum Quadrature {
    static let rule: [(x: Double, w: Double)] = {
        let n = 16
        var out: [(Double, Double)] = []
        for i in 1 ... n {
            var x = cos(Double.pi * (Double(i) - 0.25) / (Double(n) + 0.5))
            var derivative = 0.0
            for _ in 0 ..< 100 {
                var p0 = 1.0, p1 = x
                for k in 2 ... n {
                    let pk = ((2 * Double(k) - 1) * x * p1 - (Double(k) - 1) * p0) / Double(k)
                    p0 = p1
                    p1 = pk
                }
                derivative = Double(n) * (x * p1 - p0) / (x * x - 1)
                let step = p1 / derivative
                x -= step
                if abs(step) < 1e-16 { break }
            }
            out.append((x, 2 / ((1 - x * x) * derivative * derivative)))
        }
        return out
    }()

    static func integrate(_ a: Double, _ b: Double, panels: Int, _ f: (Double) -> Double) -> Double {
        let width = (b - a) / Double(panels)
        var sum = 0.0
        for k in 0 ..< panels {
            let mid = a + width * (Double(k) + 0.5)
            for node in rule { sum += node.w * f(mid + 0.5 * width * node.x) }
        }
        return 0.5 * width * sum
    }
}

// MARK: - The CIE tables

private enum CIE {
    static func load<T>(_ tuple: T) -> [Double] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Double.self)) }
    }
    static let x = load(ollin_spectral_xbar), y = load(ollin_spectral_ybar), z = load(ollin_spectral_zbar)

    /// Planck's law weighed by the 1931 observer, every 5 nm from 380 to 780.
    static func blackbody(_ kelvin: Double) -> SIMD3<Double> {
        var sum = SIMD3<Double>.zero
        for i in 0 ..< x.count {
            let micrometers = (OLLIN_SPECTRAL_LAMBDA_MIN + OLLIN_SPECTRAL_LAMBDA_STEP * Double(i)) * 1e-3
            let planck = 1 / (pow(micrometers, 5) * (exp(14387.77 / (micrometers * kelvin)) - 1))
            sum += planck * SIMD3(x[i], y[i], z[i])
        }
        return sum * OLLIN_SPECTRAL_LAMBDA_STEP
    }
}

// MARK: - The probes

/// Runs the example's `physics.metal` on the GPU: one texel a ray (or a value),
/// the inputs packed into the kernel's parameter bytes.
@MainActor
private final class LensProbe: Sketch {
    struct Ray {
        var camera: SIMD3<Double>
        var ray: SIMD3<Double>
        var inner: Double
        var outer: Double
    }

    struct Traced {
        var escaped: Double
        var swept: Double
        var impact: Double
        var lz: Double
        var hits: Int
        var hitRadius: Double
        var shift: Double
    }

    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // OllinTests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // the repository
        .appendingPathComponent("Examples/Shaders/BlackHole")

    /// The kernels, written as if they sat beside the example so the include
    /// finds its file.
    static let source = """
    #include "physics.metal"

    kernel void probe_rays(texture2d<float, access::write> out [[texture(0)]],
                           constant float4 *rays [[buffer(11)]],
                           uint2 gid [[thread_position_in_grid]]) {
        float4 c = rays[gid.x * 2], d = rays[gid.x * 2 + 1];
        LensTrace t = lens_trace(c.xyz, normalize(d.xyz), c.w, d.w);
        if (gid.y == 0) {
            out.write(float4(t.escaped, t.swept, t.impact, t.lz), gid);
        } else {
            float g = t.hits > 0 ? disk_shift(t.hit0.w, t.lz, length(c.xyz), 1.0) : 0.0;
            out.write(float4(float(t.hits), t.hit0.w, g, 0.0), gid);
        }
    }

    kernel void probe_values(texture2d<float, access::write> out [[texture(0)]],
                             constant float4 *inputs [[buffer(11)]],
                             uint2 gid [[thread_position_in_grid]]) {
        float v = inputs[gid.x / 4][gid.x % 4];
        out.write(float4(blackbody_xyz(v), disk_flux(v)), gid);
    }
    """

    static func kernel(_ entry: String) -> ComputeKernel {
        ComputeKernel(entry: entry, source, file: folder.appendingPathComponent("Probe.swift").path)
    }

    override var canvasSize: CanvasSize { .square(8) }

    private var jobs: [(kernel: ComputeKernel, params: ComputeParams, out: ComputeTexture)] = []

    override func draw() {
        background(.black)
        for job in jobs { compute(job.kernel, writing: job.out, params: job.params) }
    }

    private func run() -> [[SIMD4<Double>]]? {
        guard OllinApp.image(of: self, frame: 0) != nil else { return nil }
        var out: [[SIMD4<Double>]] = []
        for job in jobs {
            guard let floats = job.out.snapshot() else { return nil }
            out.append(stride(from: 0, to: floats.count, by: 4).map {
                SIMD4(Double(floats[$0]), Double(floats[$0 + 1]), Double(floats[$0 + 2]), Double(floats[$0 + 3]))
            })
        }
        return out
    }

    /// A camera held on the +z axis at r0, the ray `offAxis` radians from the
    /// line to the hole, turning toward +x. No disk.
    static func inPlane(r0: Double, offAxis angle: Double) -> Ray {
        Ray(camera: SIMD3(0, 0, r0), ray: SIMD3(sin(angle), 0, -cos(angle)), inner: 0, outer: 0)
    }

    /// Trace rays through `lens_trace`, 120 to a dispatch (the parameter bytes
    /// are bound directly and top out at 4 KB).
    static func trace(_ rays: [Ray]) -> [Traced]? {
        let probe = LensProbe()
        let entry = kernel("probe_rays")
        for start in stride(from: 0, to: rays.count, by: 120) {
            let batch = rays[start ..< min(start + 120, rays.count)]
            var params = ComputeParams()
            for r in batch {
                params.append(SIMD4<Float>(Float(r.camera.x), Float(r.camera.y), Float(r.camera.z), Float(r.inner)))
                params.append(SIMD4<Float>(Float(r.ray.x), Float(r.ray.y), Float(r.ray.z), Float(r.outer)))
            }
            probe.jobs.append((entry, params, ComputeTexture(width: batch.count, height: 2, format: .rgba32Float)))
        }
        guard let results = probe.run() else { return nil }
        var traced: [Traced] = []
        for (job, texels) in zip(probe.jobs, results) {
            let width = job.out.width
            for i in 0 ..< width {
                let a = texels[i], b = texels[width + i]
                traced.append(Traced(escaped: a.x, swept: a.y, impact: a.z, lz: a.w,
                                     hits: Int(b.x.rounded()), hitRadius: b.y, shift: b.z))
            }
        }
        return traced
    }

    /// `blackbody_xyz(v)` in xyz and `disk_flux(v)` in w, for each value.
    static func values(_ inputs: [Double]) -> [SIMD4<Double>]? {
        let probe = LensProbe()
        var params = ComputeParams()
        for start in stride(from: 0, to: inputs.count, by: 4) {
            var row = SIMD4<Float>(repeating: 0)
            for k in 0 ..< min(4, inputs.count - start) { row[k] = Float(inputs[start + k]) }
            params.append(row)
        }
        probe.jobs.append((kernel("probe_values"), params,
                           ComputeTexture(width: inputs.count, height: 1, format: .rgba32Float)))
        return probe.run()?.first
    }
}

/// The example's picture itself: its `blackhole.metal`, with the disk and the
/// star field off and the beacon straight behind the hole.
@MainActor
private final class LensPicture: Sketch {
    let side: Int
    let r0: Double
    let spread: Double

    init(side: Int, r0: Double, spread: Double) {
        self.side = side
        self.r0 = r0
        self.spread = spread
        super.init()
    }

    required init() {
        side = 64
        r0 = 26
        spread = 0.5
        super.init()
    }

    override var canvasSize: CanvasSize { .square(side) }

    override func draw() {
        background(.black)
        let url = LensProbe.folder.appendingPathComponent("blackhole.metal")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let elevation: Float = 0.3
        let lens = Shader(text, params: [
            Float(r0), elevation, 0, Float(2 * atan(spread)), 3, 0,
            4500, 1, 1, 0, 0, 0,
            0, 0.2,
            .pi, -elevation,
            4,
        ], file: LensProbe.folder.appendingPathComponent("Sketch.swift").path)
        drawImage(generate(lens).image, 0, 0)
    }
}

/// An image's pixels as 8-bit RGBA, read back through a known format.
private struct Pixels {
    let width: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bytes = data
    }

    /// The green channel at (x, y), top-left origin, back in linear light.
    func linearGreen(_ x: Int, _ y: Int) -> Double {
        let v = Double(bytes[(y * width + x) * 4 + 1]) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
