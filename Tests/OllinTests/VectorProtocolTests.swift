import Ollin
import Testing

/// The shared `Vector` surface: that generic code reaches it, that a type
/// outside Ollin can conform, and that moving the shared members off the two
/// concrete types did not change a single bit of arithmetic.
///
/// Plain `import Ollin`, no `@testable`, on purpose: only a plain import sees
/// what a sketch sees.
@Suite
struct VectorProtocolTests {

    // MARK: Generic reach

    private func midpoint<V: Vector>(_ a: V, _ b: V) -> V { a.lerp(to: b, 0.5) }

    private func steer<V: Vector>(from position: V, toward target: V,
                                  speed: Double, turn: Double) -> V {
        let desired = (target - position).normalized * speed
        return desired.limited(to: turn)
    }

    @Test func oneHelperServesBothTypes() {
        #expect(midpoint(Vector2(0, 0), Vector2(10, 4)) == Vector2(5, 2))
        #expect(midpoint(Vector3(0, 0, 0), Vector3(10, 4, 2)) == Vector3(5, 2, 1))

        #expect(steer(from: Vector2(0, 0), toward: Vector2(10, 0),
                      speed: 4, turn: 1.5) == Vector2(1.5, 0))
        #expect(steer(from: Vector3(0, 0, 0), toward: Vector3(0, 0, 10),
                      speed: 4, turn: 1.5) == Vector3(0, 0, 1.5))
    }

    @Test func theConstantsAreReachableGenerically() {
        func constants<V: Vector>(_: V.Type) -> [V] { [.zero, .one, .unitX, .unitY] }
        #expect(constants(Vector2.self) == [Vector2(0, 0), Vector2(1, 1),
                                            Vector2(1, 0), Vector2(0, 1)])
        #expect(constants(Vector3.self) == [Vector3(0, 0, 0), Vector3(1, 1, 1),
                                            Vector3(1, 0, 0), Vector3(0, 1, 0)])
    }

    @Test func centroidTakesEitherElement() {
        // The Vector2 form is pinned in `Vector2Tests.centroid`.
        // The Vector3 form is new: the collection helper used to be Vector2 only.
        #expect([Vector3]().centroid == nil)
        #expect([Vector3(0, 0, 0), Vector3(4, 0, 2),
                 Vector3(2, 6, 4)].centroid == Vector3(2, 2, 2))
    }

    // MARK: The headline split

    @Test func crossAnswersADifferentQuestionInEachDimension() {
        let a = Vector2(3, 1), b = Vector2(1, 3)
        // 2D: a signed area, one number saying which side b is on.
        let side: Double = a.cross(b)
        #expect(side == 8)
        #expect(b.cross(a) == -8)

        // 3D: the perpendicular direction, and its z is the 2D answer.
        let a3 = Vector3(3, 1, 0), b3 = Vector3(1, 3, 0)
        let normal: Vector3 = a3.cross(b3)
        #expect(normal == Vector3(0, 0, 8))
        #expect(normal.z == side)
    }

    // MARK: A type of one's own

    /// Four components, conforming from outside Ollin. If this compiles, the
    /// protocol's requirements are everything a conformer needs, and the whole
    /// shared surface comes free.
    struct Vector4: Vector, Hashable {
        var x, y, z, w: Double

        static let zero = Vector4(x: 0, y: 0, z: 0, w: 0)
        static let one = Vector4(x: 1, y: 1, z: 1, w: 1)
        static let unitX = Vector4(x: 1, y: 0, z: 0, w: 0)
        static let unitY = Vector4(x: 0, y: 1, z: 0, w: 0)

        var lengthSquared: Double { x * x + y * y + z * z + w * w }
        func dot(_ o: Vector4) -> Double { x * o.x + y * o.y + z * o.z + w * o.w }
        func with(x n: Double) -> Vector4 { Vector4(x: n, y: y, z: z, w: w) }
        func with(y n: Double) -> Vector4 { Vector4(x: x, y: n, z: z, w: w) }

        static func + (a: Vector4, b: Vector4) -> Vector4 {
            Vector4(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, w: a.w + b.w)
        }
        static func - (a: Vector4, b: Vector4) -> Vector4 {
            Vector4(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z, w: a.w - b.w)
        }
        static prefix func - (v: Vector4) -> Vector4 {
            Vector4(x: -v.x, y: -v.y, z: -v.z, w: -v.w)
        }
        static func * (v: Vector4, s: Double) -> Vector4 {
            Vector4(x: v.x * s, y: v.y * s, z: v.z * s, w: v.w * s)
        }
        static func / (v: Vector4, s: Double) -> Vector4 {
            Vector4(x: v.x / s, y: v.y / s, z: v.z / s, w: v.w / s)
        }
    }

    @Test func anOutsideTypeGetsTheWholeSharedSurface() {
        let v = Vector4(x: 1, y: 2, z: 2, w: 4)
        #expect(v.length == 5)
        #expect(v.normalized.length == 1)
        #expect(v.distance(to: .zero) == 5)
        #expect(v.limited(to: 2.5) == v * 0.5)
        #expect(Vector4.zero.lerp(to: v, 0.5) == v * 0.5)
        #expect(v.projected(onto: .unitX) == Vector4(x: 1, y: 0, z: 0, w: 0))
        #expect(midpoint(Vector4.zero, v) == v * 0.5)
        var acc = Vector4.zero
        acc += v; acc *= 2; acc -= v; acc /= 1
        #expect(acc == v)
    }

    // MARK: Byte identity

    /// A reproducible spread of awkward values, so the identity checks below
    /// land on bits that round rather than on tidy integers.
    private func spread(_ n: Int) -> [(Double, Double, Double)] {
        var state = UInt64(0x9E3779B97F4A7C15)
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) * (1.0 / 9007199254740992.0) * 2000 - 1000
        }
        return (0..<n).map { _ in (next(), next(), next()) }
    }

    /// `lerp` used to be written out component by component. It is now
    /// `self + (other - self) * t` on the shared surface, which is the same
    /// three operations in the same order. Every bit, not nearly.
    @Test func lerpKeepsItsExactArithmetic() {
        for (a, b, c) in spread(300) {
            let t = (c + 1000) / 2000
            let p = Vector2(a, b), q = Vector2(b, c)
            let old = Vector2(p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t)
            #expect(p.lerp(to: q, t) == old)

            let p3 = Vector3(a, b, c), q3 = Vector3(c, a, b)
            let old3 = Vector3(p3.x + (q3.x - p3.x) * t,
                               p3.y + (q3.y - p3.y) * t,
                               p3.z + (q3.z - p3.z) * t)
            #expect(p3.lerp(to: q3, t) == old3)
        }
    }

    /// `length` used to square the components in place rather than read
    /// `lengthSquared`, and the derived measurements followed it.
    @Test func theMeasurementsKeepTheirExactArithmetic() {
        for (a, b, c) in spread(300) {
            let p = Vector2(a, b), q = Vector2(b, c)
            #expect(p.length == (a * a + b * b).squareRoot())
            #expect(p.distance(to: q) == ((p - q).x * (p - q).x
                                          + (p - q).y * (p - q).y).squareRoot())
            #expect(p.normalized == (p.length > 0 ? p / p.length : .zero))
            #expect(p.projected(onto: q) == q * (p.dot(q) / q.lengthSquared))

            let p3 = Vector3(a, b, c)
            #expect(p3.length == (a * a + b * b + c * c).squareRoot())
            #expect(p3.normalized == (p3.length > 0 ? p3 / p3.length : .zero))
        }
    }

    /// The one branch with a guard: a vector at or under the cap comes back
    /// untouched, and one over it is scaled by the cap over the true length.
    @Test func limitedKeepsItsExactArithmetic() {
        for (a, b, c) in spread(300) {
            let cap = (c + 1001) / 2
            let p = Vector2(a, b)
            let lsq = p.lengthSquared
            let old = (lsq > cap * cap && lsq > 0) ? p * (cap / lsq.squareRoot()) : p
            #expect(p.limited(to: cap) == old)
        }
    }
}
