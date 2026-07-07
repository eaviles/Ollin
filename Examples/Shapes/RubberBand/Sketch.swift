import Ollin

/// Convex hull: the rubber band around a drifting herd of points. Every
/// frame each point wanders on its own noise path, the hull is recomputed,
/// and the band snaps to the outermost points; corners light up because
/// they're the points doing the work. The hull itself is then stroked into
/// a region, so the band has real thickness.
@main
final class RubberBand: Sketch {
    override func draw() {
        background(Color(hex: 0x101318))
        seed(3)

        // A herd of points, each on its own slow noise walk.
        let herd = (0 ..< 42).map { i -> Vector2 in
            let n = Double(i) * 7.31
            return Vector2(
                width * (0.5 + signedNoise(n, time * 0.07) * 0.36),
                height * (0.5 + signedNoise(n + 400, time * 0.07) * 0.36))
        }

        let hull = convexHull(of: herd)

        // The band, as a stroked region with a soft fill inside it.
        if hull.count >= 3 {
            noStroke()
            fill(Color(hex: 0x1B2436))
            drawPolygon(hull)
            fill(Color(hex: 0xE8B44A))
            drawShape(Contour(hull, closed: true).stroked(width: 7, join: .round))
        }

        // The herd, with the working corners lit.
        noStroke()
        fill(Color(hex: 0x8B97AB))
        drawCircles(herd, radius: 6)
        fill(.white)
        drawCircles(hull, radius: 9)
    }
}
