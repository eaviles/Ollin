import Ollin
import Testing

/// Pure CPU checks on `Ray3`, the picking math a pointer runs on: what it hits,
/// what it misses, what sits behind it, and the degenerate cases that would
/// otherwise divide by zero. No Metal, so these run everywhere including CI.
@Suite
struct Ray3Tests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool {
        abs(a - b) <= eps
    }

    @Test func theDirectionIsKeptAtLengthOne() {
        // Every distance a hit reports is in the units of the direction, so the
        // direction is scaled here rather than at each call site.
        let ray = Ray3(origin: .zero, direction: Vector3(0, 0, -5))
        #expect(close(ray.direction.length, 1))
        #expect(ray.direction == Vector3(0, 0, -1))
        #expect(close(ray.point(at: 3).z, -3))
    }

    @Test func aRayCanBeBuiltFromTwoPoints() {
        let ray = Ray3(from: Vector3(1, 0, 0), toward: Vector3(4, 0, 0))
        #expect(ray.direction == Vector3(1, 0, 0))
        #expect(ray.point(at: 3) == Vector3(4, 0, 0))
        #expect(close(ray.distanceAlong(Vector3(4, 0, 0)), 3))
    }

    @Test func aBallInFrontAnswersItsNearFace() {
        // A ball of radius 1 with its middle 5 away is first met at 4.
        let ray = Ray3(origin: .zero, direction: Vector3(0, 0, -1))
        let hit = ray.hit(sphereAt: Vector3(0, 0, -5), radius: 1)
        #expect(hit != nil)
        #expect(close(hit ?? 0, 4))
    }

    @Test func aBallBehindIsNeverHit() {
        // The whole point of a ray rather than a line: what is behind the pointer
        // is not being pointed at.
        let ray = Ray3(origin: .zero, direction: Vector3(0, 0, -1))
        #expect(ray.hit(sphereAt: Vector3(0, 0, 5), radius: 1) == nil)
    }

    @Test func aBallOffToTheSideIsMissed() {
        let ray = Ray3(origin: .zero, direction: Vector3(0, 0, -1))
        #expect(ray.hit(sphereAt: Vector3(2, 0, -5), radius: 1) == nil)
        // Grazing it counts: the edge is still the ball.
        #expect(ray.hit(sphereAt: Vector3(1, 0, -5), radius: 1) != nil)
    }

    @Test func aRayStartingInsideABallLeavesByTheFarSide() {
        // The near root is behind the origin here, so answering it would put a held
        // thing behind the hand.
        let ray = Ray3(origin: .zero, direction: Vector3(0, 0, -1))
        let hit = ray.hit(sphereAt: .zero, radius: 2)
        #expect(close(hit ?? 0, 2))
    }

    @Test func aBoxIsMetAtItsNearFace() {
        // A 2 by 2 by 2 box with its middle 5 away is first met at 4.
        let ray = Ray3(origin: .zero, direction: Vector3(0, 0, -1))
        let hit = ray.hit(boxAt: Vector3(0, 0, -5), size: Vector3(2, 2, 2))
        #expect(close(hit ?? 0, 4))
        // Past a corner, and behind, both miss.
        #expect(ray.hit(boxAt: Vector3(3, 0, -5), size: Vector3(2, 2, 2)) == nil)
        #expect(ray.hit(boxAt: Vector3(0, 0, 5), size: Vector3(2, 2, 2)) == nil)
    }

    @Test func aRayParallelToASlabIsJudgedByWhereItSits() {
        // The direction has a zero component here, which is the case a naive slab
        // test divides by. Inside the slab it may still hit; outside it never can.
        let along = Ray3(origin: Vector3(0, 0, 0), direction: Vector3(0, 0, -1))
        #expect(along.hit(boxAt: Vector3(0, 0, -5), size: Vector3(2, 2, 2)) != nil)
        let above = Ray3(origin: Vector3(0, 9, 0), direction: Vector3(0, 0, -1))
        #expect(above.hit(boxAt: Vector3(0, 0, -5), size: Vector3(2, 2, 2)) == nil)
    }

    @Test func aFloorIsMetWhereTheRayCrossesIt() {
        let ray = Ray3(origin: Vector3(0, 2, 0), direction: Vector3(0, -1, 0))
        let hit = ray.hit(planeAt: .zero, normal: .unitY)
        #expect(close(hit ?? 0, 2))
        // Running along the surface, and running away from it, both answer nothing.
        let flat = Ray3(origin: Vector3(0, 2, 0), direction: Vector3(1, 0, 0))
        #expect(flat.hit(planeAt: .zero, normal: .unitY) == nil)
        let away = Ray3(origin: Vector3(0, 2, 0), direction: Vector3(0, 1, 0))
        #expect(away.hit(planeAt: .zero, normal: .unitY) == nil)
    }

    @Test func aRayWithNoDirectionHitsNothing() {
        // A pointer that has not been given a heading yet must answer nothing
        // rather than divide by zero.
        let ray = Ray3(origin: .zero, direction: .zero)
        #expect(ray.direction == .zero)
        #expect(ray.hit(sphereAt: Vector3(0, 0, -5), radius: 1) == nil)
        #expect(ray.hit(boxAt: Vector3(0, 0, -5), size: Vector3(2, 2, 2)) == nil)
        #expect(ray.hit(planeAt: .zero, normal: .unitY) == nil)
        #expect(close(ray.distance(to: Vector3(3, 0, 0)), 3))
    }

    @Test func theDistanceToAPointIsMeasuredSquareToTheLine() {
        let ray = Ray3(origin: .zero, direction: Vector3(0, 0, -1))
        #expect(close(ray.distance(to: Vector3(2, 0, -5)), 2))
        // A point behind the origin is measured off the line, not off the origin.
        #expect(close(ray.distance(to: Vector3(3, 0, 4)), 3))
    }
}
