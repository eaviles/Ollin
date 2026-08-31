import Ollin

/// A concave star with a hole punched through it — the headline for `drawShape`
/// and the vector `Shape` type. A five-point star is concave, so a convex
/// `drawPolygon` fan can't fill it correctly; `Shape` triangulates it properly,
/// and a smaller star nested inside is cut out as a hole by even-odd winding.
/// The inner radius pulses and the whole thing rotates.
@main
final class Star: Sketch {
    override func draw() {
        background(Color(white: 0.07))
        let center = center
        let spin = time * 0.3
        let r = shortSide * 0.4
        let pulse = map(sin(time), -1, 1, 0.32, 0.55)

        let outer = star(center, points: 5, outer: r, inner: r * pulse, rotation: spin)
        let hole = star(center, points: 5, outer: r * 0.42, inner: r * 0.42 * pulse, rotation: spin)

        fill(Color(red: 1.0, green: 0.82, blue: 0.25))
        stroke(.black)
        strokeWeight(6)
        drawShape(Shape(outer: outer, holes: [hole]))
    }

    /// The 2n points of an n-pointed star, alternating outer and inner radius.
    private func star(_ center: Vector2, points: Int,
                      outer: Double, inner: Double, rotation: Double) -> [Vector2] {
        let n = points * 2
        return (0..<n).map { i in
            let radius = i % 2 == 0 ? outer : inner
            let a = rotation + Double(i) / Double(n) * .tau
            return center + Vector2(angle: a) * radius
        }
    }
}
