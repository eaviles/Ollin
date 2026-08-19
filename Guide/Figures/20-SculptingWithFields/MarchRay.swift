// figure: frame=0
//
// Guide diagram (Chapter 20): sphere tracing, one ray. From the eye, ask the
// field how far the nearest surface is; that distance is a safe hop, because
// nothing can be closer. Hop, ask again, repeat; the hops shrink as the ray
// closes in, and the surface is found without ever stepping through it.
import Ollin

final class MarchRay: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let accent = Color(hex: 0xE4572E)

    // The same scene the diagram draws, as a distance function for the steps.
    let c1 = Vector2(680, 230), r1 = 90.0
    let c2 = Vector2(745, 330), r2 = 70.0
    let c3 = Vector2(360, 445), r3 = 110.0
    let k = 70.0

    func distance(_ p: Vector2) -> Double {
        let d1 = p.distance(to: c1) - r1
        let d2 = p.distance(to: c2) - r2
        let h = max(k - abs(d1 - d2), 0) / k
        let blob = min(d1, d2) - h * h * k * 0.25
        return min(blob, p.distance(to: c3) - r3)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        noStroke()

        // The surfaces being marched past and toward.
        let blob = SDF.circle(radius: r1).at(c1)
            .smoothUnion(SDF.circle(radius: r2).at(c2), k: k)
            .union(SDF.circle(radius: r3).at(c3))
            .colored(Color(hex: 0x2B2B2B, alpha: 0.85))
        drawSDF(blob)

        // The march: hop by the reported distance until the surface is close.
        let eye = Vector2(70, 265)
        let dir = (Vector2(680, 242) - eye).normalized
        var p = eye
        var points: [Vector2] = [p]
        for _ in 0 ..< 14 {
            let d = distance(p)
            if d < 2 { break }
            p = p + dir * d
            points.append(p)
        }

        // The safe-hop circles, then the ray, then the sample points.
        noFill()
        stroke(Color(hex: 0x2B2B2B, alpha: 0.35))
        strokeWeight(1.5)
        for q in points.dropLast() {
            drawCircle(center: q, radius: distance(q))
        }
        stroke(accent)
        strokeWeight(2.5)
        drawPolyline(points)
        noStroke()
        fill(accent)
        for q in points { drawCircle(center: q, radius: 6) }

        // The eye.
        fill(ink)
        drawTriangle(Vector2(eye.x - 26, eye.y - 16), Vector2(eye.x - 26, eye.y + 16),
                     Vector2(eye.x + 2, eye.y))

        textSize(26)
        textAlign(.left, .middle)
        drawText("the eye", 34, 310)
        drawText("each circle: how far the field says is safe", 130, 90)
        fill(.white)
        textAlign(.center, .middle)
        drawText("the surface", 690, 270)
    }
}
