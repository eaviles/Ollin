import Ollin
import OllinSamplePhotos

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
/// Here a slab of pebbles rides across a photograph of Cozumel at dusk. It is
/// the same slab twice: on the left as a plain paste, on the right cloned. Watch
/// the right one take the color it lands in without ever changing its pebbles,
/// while the left keeps a hard rim it never earned. `amount` sweeps from a plain
/// paste to a full clone once a cycle, so the seam closes in front of you.
///
/// The photograph is chosen and framed for one reason: a rim wants quiet ground.
/// The correction is measured around the rim and spread inward, so a rim laid
/// across a hard edge spreads that edge into the patch and the whole thing blows
/// out. This picture keeps its brightness in a narrow band while its color runs
/// from grey-violet to pink, which is what a clone is for, and the frame here is
/// the left square of it, since the sun in the right third is the one hard thing
/// in it. Both slabs ride well above the horizon for the same reason.
///
/// Try it: hold `amount` at 1 and drag `patchHue`, or move a slab down onto the
/// horizon and watch that line smear inward. That is the technique's own limit
/// rather than a bug.
@main
final class SeamlessClone_Example: Sketch {

    @Param("Amount", 0...1, icon: "slider.horizontal.3")
    var amount = 1.0

    @Param("Patch hue", 0...1, icon: "paintpalette")
    var patchHue = 0.58

    @Param("Sweep the amount", icon: "repeat")
    var sweeping = false

    private var backdropPicture = Image(width: 1, height: 1)

    override func setup() {
        seed(7)
        // The left square of the photograph. The sun sits in its right third,
        // and a rim laid across something that bright spreads it inward, so the
        // crop takes the calm end and leaves the glare out of the frame.
        let whole = SamplePhoto.boats.load()
        backdropPicture = whole.cropped(x: 0, y: 0, width: whole.height, height: whole.height)
    }

    override func draw() {
        background(Color(white: 0.05))

        let sweep = sweeping ? (0.5 - 0.5 * cos(time * 0.6)) : amount
        let drift = sin(time * 0.35)

        // The backdrop is a photograph, and which one matters. The clone keeps
        // the patch's own range of tone and only moves where that range sits, so
        // a patch dropped somewhere much darker than itself has its shadows
        // pushed below black and clips. That is the technique being honest
        // rather than failing, and it is why this picture is the one here whose
        // brightness stays in a narrow band while its color runs from pink to
        // turquoise: the slab travels from sky to water and lands in a different
        // color every time without ever landing in the dark.
        let backdrop = makeRenderTarget()
        withTarget(backdrop) {
            drawImage(backdropPicture, in: canvasRectangle, fit: .cover)
        }

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
                let p = center + Vector2(angle: a) * r
                fill(Color(hue: patchHue, saturation: 0.24,
                           brightness: 0.50 + noise(p.x * 0.016, p.y * 0.016) * 0.20))
                drawCircle(p.x, p.y, 7 + noise(Double(i) * 0.31) * 8)
            }
        }

        // Both slabs ride in the sky, well above the horizon. The rim is where
        // the correction is measured, so a rim laid across a hard edge spreads
        // that edge inward and the patch blows out. The sky is the quiet ground
        // this picture offers, and it still runs from grey-violet on the left to
        // the sun's pink on the right, which is the color the clone has to take.
        let leftAt = Vector2(width * 0.27, height * 0.30 + drift * height * 0.10)
        let rightAt = Vector2(width * 0.73, height * 0.30 + drift * height * 0.10)

        let plain = makeRenderTarget()
        withTarget(plain) { pebbles(at: leftAt) }
        let clone = makeRenderTarget()
        withTarget(clone) { pebbles(at: rightAt) }

        // The left slab is pasted with the seam left in, the right one cloned.
        let pasted = backdrop.combined(with: plain, .seamlessClone(amount: 0))
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
