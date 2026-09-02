import Ollin

/// Layered effects, written both ways, and the ways are the same. The
/// imperative path makes each off-screen layer by hand (`makeRenderTarget()` +
/// `withTarget { }`), filters it (`filtered(_:)`), and composites it back
/// (`drawImage` under a `blendMode`); the `compose { }` DSL declares the same
/// stack as one block, each `layer { }` run through its `.post(...)` filters
/// and composited in its `.blended(...)` mode, the intermediates managed for
/// you. **Both paths produce the same frame**; flip the parameter and nothing moves.
/// That equivalence is the teaching point: the DSL is shorthand over the calls
/// you already know, not a second renderer.
///
/// Three layers either way: a **blurred** color-field backdrop rendered at half
/// resolution (`.scaled(0.5)` / `makeRenderTarget(scale: 0.5)`, since a blur
/// throws detail away), a ring of **bloomed** dots added as light so the glow
/// brightens the haze rather than covering it, and a slowly turning lattice
/// **screened** on top as a faint structural overlay. Nothing leaves the GPU
/// between steps.
///
/// Try it: reorder the layers (the first sits beneath the rest), change a blend
/// mode in both paths, or raise `.bloom(...)`'s `threshold` (which marks glow).
@main
final class Layers_Example: Sketch {

    /// Flip between the `compose { }` DSL and the hand-rolled layer path.
    @Param(icon: "square.3.layers.3d") var usesCompose = true

    override func draw() {
        background(Color(white: 0.03))

        if usesCompose {
            compose {
                layer { drawBlobs() }
                    .post(.gaussianBlur(radius: 48))
                    .scaled(0.5)

                layer { drawRing() }
                    .post(.bloom(threshold: 0.4, amount: 1.8, radius: 30))
                    .blended(.add)

                layer { drawLattice() }
                    .blended(.screen)
            }
        } else {
            let backdrop = makeRenderTarget(scale: 0.5)
            withTarget(backdrop) { background(.clear); drawBlobs() }
            drawImage(backdrop.filtered(.gaussianBlur(radius: 48)).image, 0, 0)

            let ring = makeRenderTarget()
            withTarget(ring) { background(.clear); drawRing() }
            withState {
                blendMode(.add)
                drawImage(ring.filtered(.bloom(threshold: 0.4, amount: 1.8, radius: 30)).image, 0, 0)
            }

            let lattice = makeRenderTarget()
            withTarget(lattice) { background(.clear); drawLattice() }
            withState {
                blendMode(.screen)
                drawImage(lattice.image, 0, 0)
            }
        }

        drawCaption(usesCompose
            ? "compose { }: blurred backdrop + bloomed ring + screened lattice"
            : "by hand: makeRenderTarget + filtered + drawImage, the same frame")
    }

    /// Beneath everything: large drifting blobs, softened to a haze by the blur.
    private func drawBlobs() {
        noStroke()
        for i in 0 ..< 5 {
            let t = time * 0.2 + Double(i) * .tau / 5
            let x = width * 0.5 + cos(t) * width * 0.30
            let y = height * 0.5 + sin(t * 1.3) * height * 0.30
            fill(Color(hue: Double(i) / 5, saturation: 0.7, brightness: 0.6))
            drawCircle(x, y, 240)
        }
    }

    /// A breathing ring of bright dots for the bloom to pick out.
    private func drawRing() {
        noStroke()
        let n = 60
        for i in 0 ..< n {
            let a = Double(i) / Double(n) * .tau + time * 0.4
            let r = 320 + sin(time * 1.5 + Double(i) * 0.4) * 70
            fill(Color(hue: Double(i) / Double(n), saturation: 0.85, brightness: 1))
            drawCircle(width * 0.5 + cos(a) * r, height * 0.5 + sin(a) * r, 12)
        }
    }

    /// A slowly turning lattice, dim enough to read as structure rather than a cage.
    private func drawLattice() {
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
}
