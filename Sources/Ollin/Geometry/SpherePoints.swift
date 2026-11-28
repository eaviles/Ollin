import Foundation

/// `count` points spread evenly over a sphere centered on the origin: every
/// point has close to the same share of the surface, and nothing bunches at
/// the poles the way rings of latitude and longitude do.
///
/// It is the Fibonacci lattice. The sphere is cut into `count` bands of equal
/// height, which are also bands of equal area, and point `i` sits at the
/// middle height of band `i`, the golden angle further around the vertical
/// axis than the point before it. No point lands on a pole, and no two share
/// a height.
///
/// The points run from the top (`+y`) to the bottom, so the array index
/// doubles as a height, the handle for a ramp of size or color. Pure closed
/// form: no randomness, the same arguments always give the same points, and
/// the count is exact. At a `radius` of 1 the points are also unit
/// directions, to aim lights or rays along.
///
/// ```swift
/// for p in spherePoints(count: 800, radius: 2) {
///     drawPoint(p.x, p.y, p.z)
/// }
/// ```
///
/// - Parameters:
///   - count: How many points. Zero or less returns none; one returns a
///     single point on the equator.
///   - radius: The sphere's radius, 1 by default.
/// - Returns: The points, top to bottom.
public func spherePoints(count: Int, radius: Double = 1) -> [Vector3] {
    latticePoints(count: count, bands: 2 * count, radius: radius)
}

/// `count` points spread evenly over the upper half of a sphere (`y` above
/// zero): a dome. They are the upper half of `spherePoints(count: 2 * count)`,
/// so a dome and the sphere it was cut from agree point for point.
///
/// ```swift
/// let lamps = hemispherePoints(count: 60, radius: 4)
/// ```
///
/// - Parameters:
///   - count: How many points. Zero or less returns none.
///   - radius: The dome's radius, 1 by default.
/// - Returns: The points, from the top down to the rim.
public func hemispherePoints(count: Int, radius: Double = 1) -> [Vector3] {
    latticePoints(count: count, bands: 4 * count, radius: radius)
}

/// The first `count` points of the lattice whose heights step down by
/// `4 / bands` of the radius at a time, the first one half a step under the
/// top. With `bands` at twice the count the points reach the bottom; at four
/// times the count they stop at the equator.
private func latticePoints(count: Int, bands: Int, radius: Double) -> [Vector3] {
    guard count > 0 else { return [] }
    var points: [Vector3] = []
    points.reserveCapacity(count)
    let step = 2 / Double(bands)
    for i in 0 ..< count {
        let y = 1 - (2 * Double(i) + 1) * step
        let ring = Swift.max(0, 1 - y * y).squareRoot()
        let angle = Double(i) * .goldenAngle
        points.append(Vector3(cos(angle) * ring * radius, y * radius, sin(angle) * ring * radius))
    }
    return points
}
