import Ollin

/// Layered effects: draw into off-screen layers, filter them on the GPU, and
/// composite the results. Two layers here: a soft, **blurred** backdrop and a
/// crisp foreground that **blooms**, its bright parts bleeding glowing light.
///
/// The pieces: `renderTarget()` makes an off-screen layer; `withTarget { }`
/// redirects drawing into it (scoped like `withState`); `layer.filtered(_:)` runs
/// a GPU filter and hands back a new layer; `drawImage(layer.image)` composites
/// it. Nothing leaves the GPU between steps: the slow path other tools fall into
/// (reading a layer back to the CPU to combine it) never happens.
///
/// Try it: change `.bloom(...)`'s `threshold` (which marks glow), drop the
/// backdrop's `scale` (it's already half-resolution, since blur never needs full
/// detail), or swap the foreground's `.add` for `.normal`.
@main
final class Bloom_Example: Sketch {
    override func draw() {
        background(Color(white: 0.03))

        // A hazy backdrop: large drifting blobs, rendered at half resolution and
        // blurred. A blur throws detail away, so the layer needn't be full-res.
        let backdrop = renderTarget(scale: 0.5)
        withTarget(backdrop) {
            background(.clear)
            noStroke()
            for i in 0 ..< 5 {
                let t = time * 0.2 + Double(i) * .tau / 5
                let x = width * 0.5 + cos(t) * width * 0.30
                let y = height * 0.5 + sin(t * 1.3) * height * 0.30
                fill(Color(hue: Double(i) / 5, saturation: 0.7, brightness: 0.55))
                drawCircle(x, y, 220)
            }
        }
        drawImage(backdrop.filtered(.gaussianBlur(radius: 44)).image, 0, 0)

        // A crisp foreground: a breathing ring of bright dots.
        let marks = renderTarget()
        withTarget(marks) {
            background(.clear)
            noStroke()
            let n = 48
            for i in 0 ..< n {
                let a = Double(i) / Double(n) * .tau + time * 0.4
                let r = 300 + sin(time * 1.5 + Double(i) * 0.4) * 70
                let x = width * 0.5 + cos(a) * r
                let y = height * 0.5 + sin(a) * r
                fill(Color(hue: Double(i) / Double(n), saturation: 0.85, brightness: 1))
                drawCircle(x, y, 11)
            }
        }
        // Bloom is self-contained (sharp dots + their glow); add it as light over
        // the backdrop so the glow brightens rather than covers.
        blendMode(.add)
        drawImage(marks.filtered(.bloom(threshold: 0.4, intensity: 1.8, radius: 28)).image, 0, 0)

        withState {
            blendMode(.normal)
            drawCaption("layered effects: blurred backdrop + bloomed foreground")
        }
    }
}
