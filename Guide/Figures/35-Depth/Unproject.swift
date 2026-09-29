// figure: frame=0 themed
//
// Guide diagram (Chapter 35): unprojection. A pixel plus its depth becomes a
// 3D point: slide off the image center, scale by depth over focal length,
// and set it that far out along the forward axis. The depth is drawn where
// it is measured, along that axis to the foot of the point, not along the ray.
import Ollin
import OllinDiagram

final class Unproject: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        let lens = Vector2(150, 320)
        let pixel = Vector2(230, 296)
        let point = Vector2(710, 152)
        let foot = Vector2(point.x, lens.y)
        let dir = (point - lens).normalized

        // The forward axis: out of the lens, through the image center.
        stroke(theme.ink(0.35)); strokeWeight(2)
        drawLine(lens.x, lens.y, 818, lens.y)
        noStroke()
        fill(theme.ink(0.35))
        drawTriangle(834, lens.y, 816, lens.y - 8, 816, lens.y + 8)

        // The image plane, with its center where the axis crosses it.
        stroke(ink.withAlpha(0.55)); strokeWeight(2.5)
        drawLine(230, 180, 230, 380)

        // The drop from the point to the axis, square to it.
        stroke(theme.ink(0.45)); strokeWeight(2)
        var s = point.y + 14
        while s < foot.y - 4 {
            drawLine(foot.x, s, foot.x, min(s + 8, foot.y - 4))
            s += 16
        }
        drawLine(foot.x - 14, foot.y, foot.x - 14, foot.y - 14)
        drawLine(foot.x - 14, foot.y - 14, foot.x, foot.y - 14)

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

        // Depth: a dimension line under the axis, from the lens to the foot.
        let dim = 410.0
        stroke(ink); strokeWeight(2)
        drawLine(lens.x, dim, foot.x, dim)
        drawLine(lens.x, dim - 10, lens.x, dim + 10)
        drawLine(foot.x, dim - 10, foot.x, dim + 10)
        stroke(theme.ink(0.3)); strokeWeight(1.5)
        drawLine(lens.x, lens.y + 14, lens.x, dim - 12)
        drawLine(foot.x, lens.y + 6, foot.x, dim - 12)
        noStroke()

        // The lens, the image center, the pixel, the recovered 3D point.
        fill(ink)
        drawCircle(center: lens, radius: 9)
        drawCircle(230, lens.y, 4)
        fill(accent)
        drawCircle(center: pixel, radius: 7)
        drawCircle(center: point, radius: 10)

        fill(ink)
        textSize(26)
        textAlign(.center, .middle)
        drawText("depth: how far along the forward axis", (lens.x + foot.x) / 2, dim + 30)
        textAlign(.right, .middle)
        drawText("the lens", lens.x - 22, lens.y)
        drawText("a pixel (u, v)", pixel.x - 14, pixel.y - 26)
        textAlign(.left, .middle)
        drawText("the 3D point", point.x - 60, point.y - 38)
        drawText("(cx, cy)", 244, lens.y + 24)
        fill(ink.withAlpha(0.6))
        drawText("the image", 208, 152)
        textSize(22)
        drawText("forward", 730, lens.y - 22)

        // The recipe, in one line.
        fill(ink)
        textSize(22)
        drawText("x = (u − cx) · depth / fx      y = −(v − cy) · depth / fy      z = −depth",
                 70, 500)
    }
}
