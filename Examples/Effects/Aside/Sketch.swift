import Ollin

/// `aside { }` is the multi-input half of `compose { }`. Most layers composite on
/// their own; an *aside* is a helper layer drawn only to **feed** another layer's
/// effect — a mask, a displacement map, the other half of a cross-dissolve. The
/// compositor draws it into its own off-screen surface and manages the texture, so
/// you never thread an intermediate layer by hand.
///
/// Two asides here. The vivid color field is **displaced** by a blurred, drifting
/// red/green map (an aside read as a vector field, so the colors ripple as if seen
/// through water — mid-gray means no shift, red/green push the sample around). A
/// fine grid of bright dots is then **masked** by a soft moving spotlight (an aside
/// read as a reveal) and added as light, so the grid only shows where the light
/// falls. Each aside carries its own `.post(.gaussianBlur(...))` to soften it.
///
/// Try it: change a `.displaced(by:amount:)` amount, swap `.masked` for `.mixed`
/// (a cross-dissolve toward the aside), move the spotlight, or give an aside a
/// different `.post(...)`.
@main
final class Aside_Example: Sketch {
    override func draw() {
        background(Color(white: 0.04))

        // The spotlight's drifting center, shared by the mask aside below.
        let sx = width * (0.5 + 0.32 * cos(time * 0.5))
        let sy = height * (0.5 + 0.32 * sin(time * 0.4))

        compose {
            // A field of overlapping hue discs, displaced by a slow ripple so it
            // flows like ink in water. The aside is a blurred map of drifting
            // red/green blobs over mid-gray, read as a displacement vector field
            // (half resolution — a displacement map is smooth, so detail is wasted).
            layer {
                noStroke()
                for i in 0 ..< 7 {
                    let t = time * 0.15 + Double(i) * .tau / 7
                    let x = width * 0.5 + cos(t) * width * 0.28
                    let y = height * 0.5 + sin(t * 1.2) * height * 0.28
                    fill(Color(hue: Double(i) / 7, saturation: 0.8, brightness: 0.9))
                    drawCircle(x, y, 320)
                }
            }
            .displaced(by: aside {
                background(Color(white: 0.5))          // mid-gray = no shift
                noStroke()
                for i in 0 ..< 5 {
                    let t = time * 0.5 + Double(i)
                    let x = width * 0.5 + cos(t * 1.1) * width * 0.40
                    let y = height * 0.5 + sin(t) * height * 0.40
                    fill(Color(red: unipolar(sin(t)),
                               green: unipolar(cos(t * 1.3)),
                               blue: 0.5, alpha: 0.6))
                    drawCircle(x, y, 360)
                }
            }.post(.gaussianBlur(radius: 40)).scaled(0.5),
            amount: 0.05)

            // A fine grid of bright dots, revealed only under a soft spotlight and
            // added as light. The spotlight is an aside — a white disc blurred soft,
            // read as the mask (white shows the grid through, black hides it).
            layer {
                noStroke(); fill(.white)
                let step = 46.0
                var y = step
                while y < height {
                    var x = step
                    while x < width { drawCircle(x, y, 6); x += step }
                    y += step
                }
            }
            .masked(by: aside {
                noStroke(); fill(.white)
                drawCircle(sx, sy, 240)
            }.post(.gaussianBlur(radius: 60)))
            .blended(.add)
        }

        drawCaption("aside { }: a displacement map + a spotlight mask, fed into compose layers")
    }
}
