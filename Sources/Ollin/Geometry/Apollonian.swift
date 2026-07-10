import Foundation

/// The Apollonian gasket: fill a circle with an endless foam of mutually
/// tangent circles. Start with three equal circles kissing inside the rim,
/// then forever fill every three-way gap with the one circle that exactly
/// touches all three of its parents, by the Descartes circle theorem (four
/// mutually tangent circles' curvatures satisfy a fixed quadratic, so the
/// fourth follows from any three plus the one already known).
///
/// The construction is a closed form with no randomness: the same enclosing
/// circle and `minRadius` always produce the same foam. Circles come back in
/// generation order (the three seeds first, then breadth-first by gap), so
/// the index doubles as an age for tinting:
///
/// ```swift
/// let foam = apollonianGasket(in: Circle(center: center, radius: 480), minRadius: 3)
/// for (i, c) in foam.enumerated() {
///     fill(Colormap.viridis.color(at: Double(i) / Double(foam.count)))
///     drawCircle(c)
/// }
/// ```
///
/// - Parameters:
///   - circle: The enclosing circle to fill.
///   - minRadius: Stop filling a gap once its circle would be smaller than
///     this (the detail knob; smaller = more, tinier circles).
///   - rotation: Spins the three seed circles around the center, in radians.
///     0 puts one seed straight up.
///   - maxCount: A safety cap on how many circles to emit.
/// - Returns: The interior circles in generation order (the enclosing circle
///   is not included).
public func apollonianGasket(in circle: Circle,
                             minRadius: Double,
                             rotation: Double = 0,
                             maxCount: Int = 20_000) -> [Circle] {
    let R = circle.radius
    guard R > 0 else { return [] }
    let floorRadius = Swift.max(minRadius, R * 1e-5)

    // Curvature-and-center bookkeeping: the enclosing circle counts negative
    // (it touches the others from outside), and every circle is stored as its
    // curvature k plus its center scaled by k, which is the pair the complex
    // Descartes theorem's linear "other root" step works in.
    var ks: [Double] = [-1 / R]
    var kzs: [Vector2] = [Vector2(circle.center.x * ks[0], circle.center.y * ks[0])]
    var out: [Circle] = []

    func append(k: Double, kz: Vector2) -> Int {
        ks.append(k)
        kzs.append(kz)
        out.append(Circle(center: Vector2(kz.x / k, kz.y / k), radius: 1 / k))
        return ks.count - 1
    }

    // Three equal seeds kissing each other and the rim: radius (2√3 − 3)·R,
    // centers a third of a turn apart.
    let seedRadius = (2 * 3.0.squareRoot() - 3) * R
    let d = R - seedRadius
    var seeds: [Int] = []
    for i in 0..<3 {
        let angle = rotation - .pi / 2 + Double(i) * 2 * .pi / 3
        let center = Vector2(circle.center.x + d * cos(angle),
                             circle.center.y + d * sin(angle))
        let k = 1 / seedRadius
        seeds.append(append(k: k, kz: Vector2(center.x * k, center.y * k)))
    }

    // Every gap is a triple of mutually tangent circles plus the fourth one
    // already touching all three (its "parent"). The Descartes quadratic's two
    // roots are that parent and the gap's new circle, so the child is the
    // other root: a plain linear jump, no square roots and no sign ambiguity.
    func child(of triple: (Int, Int, Int), parent: Int) -> (k: Double, kz: Vector2)? {
        let (a, b, c) = triple
        let k = 2 * (ks[a] + ks[b] + ks[c]) - ks[parent]
        guard k > 0, 1 / k >= floorRadius else { return nil }
        let kz = Vector2(2 * (kzs[a].x + kzs[b].x + kzs[c].x) - kzs[parent].x,
                         2 * (kzs[a].y + kzs[b].y + kzs[c].y) - kzs[parent].y)
        return (k, kz)
    }

    // Breadth-first over the gaps: the central gap between the three seeds
    // (whose known fourth tangent is the enclosing circle), and the three rim
    // gaps (whose known fourth is the opposite seed).
    var queue: [(triple: (Int, Int, Int), parent: Int)] = [
        ((seeds[0], seeds[1], seeds[2]), 0),
        ((0, seeds[0], seeds[1]), seeds[2]),
        ((0, seeds[1], seeds[2]), seeds[0]),
        ((0, seeds[0], seeds[2]), seeds[1]),
    ]
    var head = 0
    while head < queue.count, out.count < maxCount {
        let (triple, parent) = queue[head]
        head += 1
        guard let c = child(of: triple, parent: parent) else { continue }
        let new = append(k: c.k, kz: c.kz)
        // The new circle splits its gap into three smaller ones, each against
        // a pair of its parents, with the leftover parent as the known fourth.
        queue.append(((triple.0, triple.1, new), triple.2))
        queue.append(((triple.1, triple.2, new), triple.0))
        queue.append(((triple.0, triple.2, new), triple.1))
    }

    return out
}
