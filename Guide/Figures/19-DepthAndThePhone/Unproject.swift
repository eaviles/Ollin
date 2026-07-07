// figure: frame=0
//
// Guide diagram (Chapter 19): unprojection. A pixel plus its depth becomes a
// 3D point: slide off the image center, scale by depth over focal length,
// and step out along the ray.
import Ollin

final class Unproject: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let lens = Vector2(150, 320)
        let pixel = Vector2(230, 296)
        let point = Vector2(710, 152)
        let dir = (point - lens).normalized

        // The image plane, and the pixel on it.
        stroke(ink.withAlpha(0.55)); strokeWeight(2.5)
        drawLine(230, 180, 230, 460)

        // The ray, dashed, from the lens through the pixel out to the point.
        stroke(accent); strokeWeight(3)
        var t = 0.0
        let total = lens.distance(to: point)
        while t < total - 8 {
            let a = lens + dir * t
            let b = lens + dir * min(t + 14, total - 8)
            drawLine(a.x, a.y, b.x, b.y)
            t += 26
        }
        noStroke()

        // The lens, the pixel, the recovered 3D point.
        fill(ink)
        drawCircle(center: lens, radius: 9)
        fill(accent)
        drawCircle(center: pixel, radius: 7)
        drawCircle(center: point, radius: 10)

        // Depth: the stretch of ray past the image plane.
        let mid = pixel + (point - pixel) * 0.5
        fill(ink)
        textSize(26)
        textAlign(.center, .middle)
        drawText("depth: how far along the ray", mid.x, mid.y + 52)
        textAlign(.left, .middle)
        drawText("the 3D point", point.x - 60, point.y - 38)
        drawText("the lens", lens.x - 44, lens.y + 44)
        drawText("a pixel (u, v)", pixel.x - 16, pixel.y + 40)
        fill(ink.withAlpha(0.6))
        drawText("the image", 208, 152)

        // The recipe, in one line.
        fill(ink)
        textSize(22)
        drawText("x = (u − cx) · depth / fx      y = −(v − cy) · depth / fy      z = −depth",
                 70, 500)
    }
}
