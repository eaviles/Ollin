import Ollin
import Testing

/// Pure CPU checks on `Vector2`'s geometry surface — dot/cross, distance,
/// angles, rotation, interpolation, projection. No Metal, so these run
/// everywhere including CI.
@Suite
struct Vector2Tests {

    /// A loose float comparison for trig-derived results.
    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool {
        abs(a - b) <= eps
    }

    private func close(_ a: Vector2, _ b: Vector2, _ eps: Double = 1e-9) -> Bool {
        close(a.x, b.x, eps) && close(a.y, b.y, eps)
    }

    @Test func lengthAndNormalize() {
        let v = Vector2(3, 4)
        #expect(v.length == 5)
        #expect(v.lengthSquared == 25)
        #expect(close(v.normalized.length, 1))
        #expect(Vector2.zero.normalized == .zero)
    }

    @Test func polarInitAndAngle() {
        let v = Vector2(angle: .pi / 2, length: 2)
        #expect(close(v.x, 0))
        #expect(close(v.y, 2))
        #expect(close(Vector2(1, 1).angle, .pi / 4))
        #expect(close(Vector2.unitX.angle, 0))
    }

    @Test func dotAndCross() {
        let a = Vector2(1, 0), b = Vector2(0, 1)
        #expect(a.dot(b) == 0)        // perpendicular
        #expect(a.dot(a) == 1)
        #expect(a.cross(b) == 1)      // b is CCW from a
        #expect(b.cross(a) == -1)
        #expect(a.perpendicular == b) // 90° CCW
    }

    @Test func distance() {
        let a = Vector2(0, 0), b = Vector2(3, 4)
        #expect(a.distance(to: b) == 5)
        #expect(a.distanceSquared(to: b) == 25)
    }

    @Test func signedAngleBetween() {
        let a = Vector2(1, 0)
        #expect(close(a.angle(to: Vector2(0, 1)), .pi / 2))
        #expect(close(a.angle(to: Vector2(0, -1)), -.pi / 2))
    }

    @Test func lerp() {
        let a = Vector2(0, 0), b = Vector2(10, 20)
        #expect(a.lerp(to: b, 0) == a)
        #expect(a.lerp(to: b, 1) == b)
        #expect(a.lerp(to: b, 0.5) == Vector2(5, 10))
    }

    @Test func rotate() {
        let v = Vector2(1, 0)
        #expect(close(v.rotated(by: .pi / 2), Vector2(0, 1)))
        // Rotating 180° about a pivot reflects through it.
        let pivot = Vector2(2, 2)
        #expect(close(Vector2(3, 2).rotated(by: .pi, around: pivot), Vector2(1, 2)))
    }

    @Test func limit() {
        let v = Vector2(3, 4)               // length 5
        #expect(close(v.limited(to: 5).length, 5))   // unchanged at the cap
        #expect(close(v.limited(to: 10).length, 5))  // under the cap: unchanged
        #expect(close(v.limited(to: 1).length, 1))   // clamped down
    }

    @Test func project() {
        let v = Vector2(3, 4)
        #expect(close(v.projected(onto: Vector2(5, 0)), Vector2(3, 0)))
        #expect(v.projected(onto: .zero) == .zero)
    }

    @Test func compoundOperators() {
        var p = Vector2(1, 1)
        p += Vector2(2, 3)
        #expect(p == Vector2(3, 4))
        p -= Vector2(1, 1)
        #expect(p == Vector2(2, 3))
        p *= 2
        #expect(p == Vector2(4, 6))
        p /= 2
        #expect(p == Vector2(2, 3))
    }

    @Test func withComponent() {
        let v = Vector2(1, 2)
        #expect(v.with(x: 9) == Vector2(9, 2))
        #expect(v.with(y: 9) == Vector2(1, 9))
    }
}
