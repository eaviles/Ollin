import Ollin
import Testing

/// Pure CPU checks on `Vector3`'s geometry surface — length, dot/cross,
/// distance, interpolation, projection, the `xy` drop. No Metal, so these run
/// everywhere including CI.
@Suite
struct Vector3Tests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool {
        abs(a - b) <= eps
    }

    @Test func lengthAndNormalize() {
        let v = Vector3(2, 3, 6)
        #expect(v.length == 7)
        #expect(v.lengthSquared == 49)
        #expect(close(v.normalized.length, 1))
        #expect(Vector3.zero.normalized == .zero)
    }

    @Test func arithmetic() {
        let a = Vector3(1, 2, 3), b = Vector3(4, 5, 6)
        #expect(a + b == Vector3(5, 7, 9))
        #expect(b - a == Vector3(3, 3, 3))
        #expect(-a == Vector3(-1, -2, -3))
        #expect(a * 2 == Vector3(2, 4, 6))
        #expect(2 * a == a * 2)
        #expect(b / 2 == Vector3(2, 2.5, 3))
        var c = a
        c += b; #expect(c == a + b)
        c -= b; #expect(c == a)
        c *= 3; #expect(c == a * 3)
        c /= 3; #expect(c == a)
    }

    @Test func dotAndCross() {
        #expect(Vector3.unitX.dot(.unitY) == 0)
        #expect(Vector3.unitX.dot(.unitX) == 1)
        // The axes cycle: x × y = z, y × z = x, z × x = y.
        #expect(Vector3.unitX.cross(.unitY) == .unitZ)
        #expect(Vector3.unitY.cross(.unitZ) == .unitX)
        #expect(Vector3.unitZ.cross(.unitX) == .unitY)
        // Anti-commutative.
        #expect(Vector3.unitY.cross(.unitX) == -Vector3.unitZ)
    }

    @Test func distance() {
        let a = Vector3.zero, b = Vector3(2, 3, 6)
        #expect(a.distance(to: b) == 7)
        #expect(a.distanceSquared(to: b) == 49)
    }

    @Test func lerp() {
        let a = Vector3.zero, b = Vector3(10, 20, 30)
        #expect(a.lerp(to: b, 0) == a)
        #expect(a.lerp(to: b, 1) == b)
        #expect(a.lerp(to: b, 0.5) == Vector3(5, 10, 15))
    }

    @Test func limitAndProject() {
        #expect(Vector3(0, 0, 10).limited(to: 3) == Vector3(0, 0, 3))
        #expect(Vector3(1, 1, 1).limited(to: 10) == Vector3(1, 1, 1))
        #expect(Vector3(3, 4, 5).projected(onto: .unitZ) == Vector3(0, 0, 5))
        #expect(Vector3(3, 4, 5).projected(onto: .zero) == .zero)
    }

    @Test func componentHelpers() {
        let v = Vector3(1, 2, 3)
        #expect(v.xy == Vector2(1, 2))
        #expect(v.with(x: 9) == Vector3(9, 2, 3))
        #expect(v.with(y: 9) == Vector3(1, 9, 3))
        #expect(v.with(z: 9) == Vector3(1, 2, 9))
    }
}
