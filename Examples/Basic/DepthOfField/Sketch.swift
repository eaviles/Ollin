import Ollin

/// Depth of field, *earned* rather than faked. A blurred photograph isn't a sharp
/// image with a blur filter on top — it's countless light rays that each landed in a
/// slightly different place because they passed through the lens out of focus. This
/// sketch renders that literally. A handful of smooth 3D curves are drawn not as
/// lines but as a haze of faint samples scattered along them, and each sample is
/// displaced within a disc whose radius grows with how far that point sits from the
/// focal plane. Where a curve crosses the focus it stays a crisp bright ribbon; away
/// from it the samples spread into soft bokeh. The blur *emerges* from the statistics
/// of where the light fell — there is no blur filter anywhere.
///
/// Three shipped pieces make it possible, summing as light in a linear float buffer:
///   • `blendMode(.add)` — every sample adds light to the pile.
///   • `noClear()` — the canvas isn't cleared, so the sparse per-frame spray
///     accumulates across frames and refines into dense, smooth ribbons.
///   • `toneMap(.aces)` — light piles up well past full brightness in float; the
///     film-like curve rolls those highlights into a glow instead of clipping.
///
/// A mild perspective makes near samples larger, so out-of-focus foreground curves
/// bloom into big soft discs while distant ones stay small — the look of a fast lens.
/// The scene turns slowly, so each ribbon racks through the fixed focal plane as it
/// rotates. **Drag left↔right to move the focal plane** and pull focus through the
/// depth yourself. **Press any key** to toggle colour-shift: the R/G/B contributions
/// of each sample scatter by slightly different radii, so the bokeh grows
/// chromatic-aberration fringes — the same emergent trick, applied per channel.
///
/// Inspired by Anders Hoff's depth-of-field and colour-shift technique (inconvergent).
@main
final class DepthOfField_Example: Sketch {
    /// A smooth closed curve through the unit box — a 3D Lissajous figure.
    private struct Ribbon {
        var fx, fy, fz: Double   // integer frequencies (closed curve)
        var px, py, pz: Double   // phases
        var hue: Double          // its own colour, evenly spaced round the wheel
    }
    private var ribbons: [Ribbon] = []
    private var colourShift = true

    private let ribbonCount = 9
    private let samplesPerRibbon = 700

    override func setup() {
        seed(4)
        background(Color(red: 0.015, green: 0.015, blue: 0.03))   // the one base wipe
        noClear()                                                 // then accumulate

        for i in 0 ..< ribbonCount {
            ribbons.append(Ribbon(
                fx: Double(Int(random(1, 4))), fy: Double(Int(random(1, 4))),
                fz: Double(Int(random(1, 4))),
                px: random(.tau), py: random(.tau), pz: random(.tau),
                hue: Double(i) / Double(ribbonCount)))
        }
    }

    override func keyPressed() {
        colourShift.toggle()
    }

    override func draw() {
        toneMap(.aces)           // roll the accumulated highlights into a glow
        blendMode(.add)          // samples sum as light
        noStroke()

        let cx = width / 2, cy = height / 2
        let radius = min(width, height) * 0.30
        let angle = time * 0.10                      // a slow turn around the vertical axis
        let cosA = cos(angle), sinA = sin(angle)

        // Fixed focal plane by default (so the depth-of-field read stays crisp while
        // the ribbons rotate through it); drag to rack it through the depth yourself.
        let focus = mouseIsPressed ? map(mouseX, 0, width, -0.9, 0.9) : 0.0

        let blurStrength = radius * 0.14             // bokeh disc radius per unit of defocus
        let caStrength = colourShift ? 0.16 : 0.0

        for r in ribbons {
            let c = Color(hue: r.hue, saturation: 0.8, brightness: 1)
            for _ in 0 ..< samplesPerRibbon {
                // A random point along the curve; over many frames the whole ribbon
                // fills in — this is the progressive refinement accumulation gives.
                let t = random()
                let px3 = 0.95 * sin(r.fx * t * .tau + r.px)
                let py3 = 0.95 * sin(r.fy * t * .tau + r.py)
                let pz3 = 0.95 * sin(r.fz * t * .tau + r.pz)

                // Rotate (x, z) around the vertical axis, then perspective-project so
                // near samples sit larger than far ones.
                let rx = px3 * cosA + pz3 * sinA
                let rz = -px3 * sinA + pz3 * cosA
                let persp = 2.4 / (rz + 3.0)
                let sx = cx + rx * radius * persp
                let sy = cy - py3 * radius * persp

                let defocus = abs(rz - focus)        // distance from the focal plane
                let blur = defocus * blurStrength * persp
                let dotSize = (0.5 + defocus * 1.4) * persp * scale
                // Energy conservation: as the light spreads over a wider disc, each
                // sample dims so the ribbon's total brightness stays roughly constant.
                let alpha = 0.085 / (1 + defocus * 6)

                let u = discSample() * blur          // an offset within the bokeh disc
                if caStrength > 0 {
                    // Each channel lands at a slightly different radius, so the disc
                    // grows a coloured rim — chromatic aberration, earned the same way.
                    let ca = caStrength * min(defocus, 1)
                    fill(Color(red: c.red, green: 0, blue: 0, alpha: alpha))
                    drawCircle(sx + u.x * (1 + ca), sy + u.y * (1 + ca), dotSize)
                    fill(Color(red: 0, green: c.green, blue: 0, alpha: alpha))
                    drawCircle(sx + u.x, sy + u.y, dotSize)
                    fill(Color(red: 0, green: 0, blue: c.blue, alpha: alpha))
                    drawCircle(sx + u.x * (1 - ca), sy + u.y * (1 - ca), dotSize)
                } else {
                    fill(Color(red: c.red, green: c.green, blue: c.blue, alpha: alpha))
                    drawCircle(sx + u.x, sy + u.y, dotSize)
                }
            }
        }

        blendMode(.normal)
        drawCaption("drag to rack focus · press a key: colour-shift \(colourShift ? "on" : "off")")
    }

    /// A point in the unit disc, uniform over its *area* (so the bokeh fills evenly,
    /// not bunched at the centre): radius via `sqrt` of a uniform sample.
    private func discSample() -> Vector2 {
        let r = random().squareRoot()
        let a = random(.tau)
        return Vector2(cos(a) * r, sin(a) * r)
    }
}
