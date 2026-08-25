import Ollin

/// Clipping as drawing state: `withClip(shape) { }` confines everything drawn
/// inside the block (fills, strokes, images, text) to the shape's filled
/// region, and nested clips intersect. A field of drifting diagonal stripes
/// exists only inside a slowly turning star-shaped window; a circular lens
/// sweeps across it revealing a second palette where the two regions overlap;
/// and an orbiting dot crosses the boundary untouched, because it draws after
/// the block ends.
@main
final class Clipping: Sketch {
    override func draw() {
        background(Color(hex: 0x101418))
        let center = center

        // The window: a seven-pointed star, slowly turning.
        var star: [Vector2] = []
        for k in 0 ..< 14 {
            let radius = k % 2 == 0 ? 400.0 : 205.0
            let a = Double(k) / 14 * .tau + time * 0.05 - .pi / 2
            star.append(center + Vector2(cos(a) * radius, sin(a) * radius))
        }
        let window = Shape(star)

        // Cool stripes drift through the star; nothing lands outside it.
        withClip(window) {
            noStroke()
            translate(center)
            rotate(0.6)
            let bandWidth = 46.0
            let drift = fract(time * 0.15) * bandWidth * 2
            for i in -16 ... 16 {
                fill(i % 2 == 0 ? Color(hex: 0x2EC4B6) : Color(hex: 0x175E57))
                drawRect(Double(i) * bandWidth + drift, -height, bandWidth, height * 2)
            }
        }

        // A lens orbits the canvas; inside it, a warm palette shows only where
        // lens and star overlap (nested clips intersect).
        let lens = Circle(center: center + Vector2(cos(time * 0.6) * 260,
                                                   sin(time * 0.8) * 190),
                          radius: 190)
        withClip(window) {
            withClip(lens) {
                noStroke()
                translate(center)
                rotate(-0.6)
                let bandWidth = 46.0
                let drift = fract(time * 0.25) * bandWidth * 2
                for i in -16 ... 16 {
                    fill(i % 2 == 0 ? Color(hex: 0xFFD166) : Color(hex: 0xF6511D))
                    drawRect(Double(i) * bandWidth + drift, -height, bandWidth, height * 2)
                }
            }
        }

        // Outside the blocks, drawing is unclipped: the lens outline and an
        // orbiting dot cross the star's boundary freely.
        noFill()
        stroke(Color(hex: 0x9BF6FF).withAlpha(0.5))
        strokeWeight(2)
        drawCircle(center: lens.center, radius: lens.radius)
        let dot = center + Vector2(angle: time * 0.9) * 330
        fill(.white)
        noStroke()
        drawCircle(dot.x, dot.y, 14)

        drawCaption("withClip(shape) confines drawing to a region · nesting intersects · after the block, drawing is free")
    }
}
