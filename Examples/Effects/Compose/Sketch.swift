import Ollin

/// `compose { }` is the declarative form of layered effects. Instead of making each
/// off-screen layer, filtering it, and compositing it back by hand, you declare the
/// whole stack as one block: each `layer { }` is drawn, run through its
/// `.post(...)` filters, and composited in its `.blended(...)` mode, in the order
/// written. The intermediate layers are managed for you.
///
/// Three layers here: a **blurred** color-field backdrop (rendered at half
/// resolution, since a blur throws detail away), a ring of **bloomed** dots added
/// as light, and a slowly turning lattice **screened** on top as a faint structural
/// overlay.
///
/// Try it: reorder the `layer { }` blocks (the first sits beneath the rest), change
/// a `.blended(...)`, add a `.post(...)` to a layer, or drop a layer's `.scale(...)`.
@main
final class Compose_Example: Sketch {
    override func draw() {
        background(Color(white: 0.03))

        compose {
            // Beneath everything: large drifting blobs, softened to a haze. Half
            // resolution because the blur hides it.
            layer {
                noStroke()
                for i in 0 ..< 5 {
                    let t = time * 0.2 + Double(i) * .tau / 5
                    let x = width * 0.5 + cos(t) * width * 0.30
                    let y = height * 0.5 + sin(t * 1.3) * height * 0.30
                    fill(Color(hue: Double(i) / 5, saturation: 0.7, brightness: 0.6))
                    drawCircle(x, y, 240)
                }
            }
            .post(.gaussianBlur(radius: 48))
            .scaled(0.5)

            // A breathing ring of bright dots that bloom, added as light so the glow
            // brightens the haze rather than covering it.
            layer {
                noStroke()
                let n = 60
                for i in 0 ..< n {
                    let a = Double(i) / Double(n) * .tau + time * 0.4
                    let r = 320 + sin(time * 1.5 + Double(i) * 0.4) * 70
                    let x = width * 0.5 + cos(a) * r
                    let y = height * 0.5 + sin(a) * r
                    fill(Color(hue: Double(i) / Double(n), saturation: 0.85, brightness: 1))
                    drawCircle(x, y, 12)
                }
            }
            .post(.bloom(threshold: 0.4, amount: 1.8, radius: 30))
            .blended(.add)

            // A slowly turning lattice, dim enough to read as structure rather than a
            // cage, screened on top so it brightens the scene beneath it.
            layer {
                withState {
                    translate(center)
                    rotate(time * 0.05)
                    translate(-width / 2, -height / 2)
                    stroke(Color(white: 0.45)); strokeWeight(2); noFill()
                    let step = 90.0
                    var x = -step
                    while x < width + step { drawLine(x, -step, x, height + step); x += step }
                    var y = -step
                    while y < height + step { drawLine(-step, y, width + step, y); y += step }
                }
            }
            .blended(.screen)
        }

        drawCaption("compose { }: blurred backdrop + bloomed ring + screened lattice")
    }
}
