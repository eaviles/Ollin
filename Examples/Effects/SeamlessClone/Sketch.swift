import Ollin

/// `.seamlessClone` drops one layer into another so the join disappears. The patch
/// keeps every mark you drew into it and gives up its own color and brightness,
/// taking on whatever surrounds it instead.
///
/// The recipe is the one gradient-domain compositing has always used. Around the
/// rim of the patch, measure how far the patch's color sits from the backdrop's.
/// Spread that difference across the inside of the patch as smoothly as anything
/// can be spread. Add it back. On the rim that lands exactly on the backdrop, so
/// there is no join to see, and inside it is the patch nudged by the gentlest
/// correction that reaches it. Only the slow, low part of the patch's color is
/// replaced, which is why the detail survives.
///
/// Here a slab of pebbles rides across a drifting wash of color. It is the same
/// slab twice: on the left as a plain paste, on the right cloned. Watch the right
/// one take the color it lands in without ever changing its pebbles. The slider along the bottom sweeps `amount` from a plain paste to a
/// full clone once a cycle, so the seam closes in front of you.
///
/// Try it: hold `amount` at 1 and drag `patchHue`, or drop the patch on a backdrop
/// with a hard edge running under its rim and watch that edge smear inward. That
/// last one is the technique's own limit rather than a bug, and it is why a rim is
/// best kept on quiet ground.
@main
final class SeamlessClone_Example: Sketch {

    @Param("Amount", 0...1, icon: "slider.horizontal.3")
    var amount = 1.0

    @Param("Patch hue", 0...1, icon: "paintpalette")
    var patchHue = 0.58

    @Param("Sweep the amount", icon: "repeat")
    var sweeping = false

    override func setup() { seed(7) }

    override func draw() {
        background(Color(white: 0.05))

        let sweep = sweeping ? (0.5 - 0.5 * cos(time * 0.6)) : amount
        let drift = sin(time * 0.35)

        // The backdrop: a broad wash of color at a fairly even brightness. Even
        // brightness on purpose. The clone keeps the patch's own range of tone and
        // only moves where that range sits, so a patch dropped somewhere much
        // darker than itself has its shadows pushed below black and clips. That is
        // the technique being honest rather than failing, and a backdrop that
        // varies mostly in *color* shows the effect without running into it.
        let backdrop = renderTarget()
        withTarget(backdrop) {
            noStroke()
            for i in 0 ..< 5 {
                let t = Double(i) / 4
                let a = time * 0.12 + t * .tau * 0.8
                fill(Color(hue: 0.52 + t * 0.42, saturation: 0.55, brightness: 0.62,
                           alpha: i == 0 ? 1 : 0.6))
                drawCircle(width * (0.5 + cos(a) * 0.42),
                           height * (0.5 + sin(a * 1.3) * 0.42), 620)
            }
        }
        let washed = backdrop.filtered(.gaussianBlur(radius: 90))

        // The patch, drawn twice at two places. Its own color is deliberately wrong
        // for where it lands: cool and flat against a warm, graded backdrop.
        func pebbles(at center: Vector2) {
            noStroke()
            fill(Color(hue: patchHue, saturation: 0.20, brightness: 0.60))
            drawCircle(center.x, center.y, 165)
            // Real photographic texture is a modest wobble around a mean, not a
            // full sweep of tone. Gradient-domain cloning keeps whatever range the
            // patch has and only moves its mean, so a high-contrast patch on a dark
            // backdrop crushes to black. That is the technique being honest rather
            // than failing, and it is why the wobble here is kept small.
            for i in 0 ..< 260 {
                let a = Double(i) * 2.39996
                let r = 162 * sqrt(Double(i) / 260)
                let p = center + Vector2(cos(a), sin(a)) * r
                fill(Color(hue: patchHue, saturation: 0.24,
                           brightness: 0.50 + noise(p.x * 0.016, p.y * 0.016) * 0.20))
                drawCircle(p.x, p.y, 7 + noise(Double(i) * 0.31) * 8)
            }
        }

        let leftAt = Vector2(width * 0.27, height * 0.45 + drift * height * 0.20)
        let rightAt = Vector2(width * 0.73, height * 0.45 + drift * height * 0.20)

        let plain = renderTarget()
        withTarget(plain) { pebbles(at: leftAt) }
        let clone = renderTarget()
        withTarget(clone) { pebbles(at: rightAt) }

        // The left slab is pasted with the seam left in, the right one cloned.
        let pasted = washed.combined(with: plain, .seamlessClone(amount: 0))
        let healed = pasted.combined(with: clone, .seamlessClone(amount: sweep))
        drawImage(healed.image, 0, 0)

        // Labels, and the amount the right slab is being cloned at.
        fill(.white)
        textSize(30)
        textAlign(.center)
        drawText("pasted", leftAt.x, height * 0.92)
        drawText("cloned at \(String(format: "%.2f", sweep))", rightAt.x, height * 0.92)

        drawCaption("Seamless clone. Both slabs are the same; the right one keeps its "
                    + "pebbles and takes the color it lands in.")
    }
}
