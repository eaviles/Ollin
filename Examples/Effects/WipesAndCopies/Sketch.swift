import Ollin
import OllinSamplePhotos

/// Wipes, copies, and a glowing edge, one picker across them.
///
/// - **wipes**: two photographs taking turns, each wiped into the other by a new
///   order every few seconds: a straight edge, doors opening from the middle,
///   blinds, shuffled bars, rings popping outward, a clock hand, blocks in a
///   shuffled order, a checker of diamonds, and a soft noise dissolve. Every one
///   is the same call, `Combine.wipe`, given a different `WipeOrder`, and the name
///   of the one running is written under the picture.
/// - **copies**: one petal drawn in the middle of a layer, copied around a ring
///   (each copy turned to face out, so the ring is a flower), into a grid, and
///   along a line, each copy a step smaller, more turned, and further around the
///   hue wheel than the last, the steps swaying as it plays.
/// - **edge glow**: a word and a star with a band of light along their edges and
///   spots of three colors racing around them, beating together.
///
/// Try it: in `wipes`, set `feather` to 0 for hard edges or past 0.3 for a slow
/// melt; in `copies`, push `count` up and `shrink` down until the ring becomes a
/// spiral.
@main
final class WipesAndCopies: Sketch {
    enum Look: String, CaseIterable, ParamOption { case wipes, copies, edgeGlow }

    @Param(style: .segmented, icon: "rectangle.righthalf.inset.filled") var look = Look.wipes
    @Param(0 ... 0.5, icon: "aqi.medium") var feather = 0.08
    @Param(1 ... 24, icon: "square.on.square") var count = 9
    @Param(0.6 ... 1, icon: "arrow.down.right.and.arrow.up.left") var shrink = 0.94
    @Param(4 ... 40, icon: "sun.max") var glowWidth = 22.0

    override var loopDuration: Double? { 27 }

    private var photos: [Image] = []
    let font = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold

    /// The nine orders the wipes take in turn, with the code that makes each.
    let orders: [(WipeOrder, String)] = [
        (.directional(), ".directional()"),
        (.directional().folded(), ".directional().folded()"),
        (.directional(angle: .pi / 2).tiled(10), ".directional(angle: .pi / 2).tiled(10)"),
        (.directional(angle: 0.3).bands(18).shuffled(seed: 4), ".directional(angle: 0.3).bands(18).shuffled(seed: 4)"),
        (.radial().bands(7), ".radial().bands(7)"),
        (.angular(), ".angular()"),
        (.cells(columns: 9, rows: 9).shuffled(seed: 2), ".cells(columns: 9, rows: 9).shuffled(seed: 2)"),
        (.cells(columns: 7, rows: 7).checker().diamond(), ".cells(columns: 7, rows: 7).checker().diamond()"),
        (.noise(size: 0.18, seed: 5), ".noise(size: 0.18, seed: 5)"),
    ]

    override func setup() {
        photos = [SamplePhoto.talavera.load(), SamplePhoto.marigolds.load(), SamplePhoto.textiles.load()]
    }

    override func draw() {
        switch look {
        case .wipes: drawWipes()
        case .copies: drawCopies()
        case .edgeGlow: drawEdgeGlow()
        }
    }

    // MARK: Wipes

    /// Three seconds an order: two seconds of wipe and a second at rest.
    private func drawWipes() {
        let beat = time / 3
        let index = Int(beat) % orders.count
        let progress = min(1, beat.truncatingRemainder(dividingBy: 1) * 1.5)
        let from = photos[index % photos.count], to = photos[(index + 1) % photos.count]
        let a = makeRenderTarget(), b = makeRenderTarget()
        withTarget(a) { drawImage(from, in: Rectangle(x: 0, y: 0, width: width, height: height), fit: .cover) }
        withTarget(b) { drawImage(to, in: Rectangle(x: 0, y: 0, width: width, height: height), fit: .cover) }
        let eased = progress * progress * (3 - 2 * progress)
        drawImage(a.combined(with: b, .wipe(orders[index].0, progress: eased, feather: feather)).image, 0, 0)
        caption(orders[index].1)
    }

    /// The order's code on a dark strip at the bottom.
    private func caption(_ text: String) {
        noStroke()
        fill(Color(white: 0, alpha: 0.55))
        drawRect(0, height - 64, width, 64)
        fill(.white)
        textFont(.systemMono)
        textSize(26)
        textAlign(.center, .center)
        drawText(text, width / 2, height - 32)
    }

    // MARK: Copies

    /// A petal in the middle of its layer, laid out around a ring, in a grid,
    /// and along a line in turn, nine seconds each.
    private func drawCopies() {
        background(Color(hex: 0x14161C))
        let sway = sin(time * 0.7)
        let stage = Int(time / 9) % 3
        // A grid shrinks the whole layer into a cell, so its petal is drawn to fill
        // the layer; around the ring and along the line the copies keep its size.
        let size = stage == 1 ? 3.2 : 1.0
        let petal = makeRenderTarget()
        withTarget(petal) {
            noStroke()
            fill(Color(hex: 0xE8A24A))
            drawEllipse(width / 2, height / 2 - 40 * size, 46 * size, 120 * size)
            fill(Color(hex: 0xF6D9A0))
            drawCircle(width / 2, height / 2 - 120 * size, 16 * size)
        }
        let layout: Filter.CopyLayout
        switch stage {
        case 0: layout = .ring(radius: 0.18, facesOut: true)
        case 1: layout = .grid(columns: Int(Double(count).squareRoot().rounded(.up)))
        default: layout = .line(from: Vector2(0.12, 0.62), to: Vector2(0.88, 0.38))
        }
        let copies = petal.filtered(.repeated(layout, count: count, scale: shrink,
                                              rotation: stage == 0 ? 0.05 * sway : 0.12 * sway,
                                              opacity: 0.96, hueShift: 0.22 + 0.1 * sway))
        drawImage(copies.image, 0, 0)
        caption([".ring(radius: 0.18, facesOut: true)", ".grid(columns: \(Int(Double(count).squareRoot().rounded(.up))))",
                 ".line(from:to:)"][stage])
    }

    // MARK: Edge glow

    /// A word and a star, their edges lit and circled by three colors of spot.
    private func drawEdgeGlow() {
        background(Color(hex: 0x0B0C10))
        let layer = makeRenderTarget()
        withTarget(layer) {
            noStroke()
            fill(Color(hex: 0x1D2230))
            withState {
                translate(width * 0.5, height * 0.34)
                rotate(time * 0.1)
                drawStar(0, 0, 230, 100, points: 5)
            }
            fill(Color(hex: 0x262C3D))
            textFont(font)
            textSize(250)
            textAlign(.center, .center)
            drawText("Ollin", width * 0.5, height * 0.74)
        }
        let glow = Filter.edgeGlow(width: glowWidth,
                                   colors: [Color(hex: 0x7B2FF7), Color(hex: 0x00E0FF), Color(hex: 0xFF5A8A)],
                                   spots: 3, spotSize: 0.05, pulse: 0.6, bloom: 0.6, phase: time)
        drawImage(layer.filtered(glow).image, 0, 0)
    }
}
