import Ollin
import OllinSamplePhotos

/// A face drawn as the shortest tree through its stipples.
///
/// `spanningTree(of:points:)` stipples an image and then joins the dots with
/// the minimum spanning tree: the least total line that still reaches every
/// dot. Where the single-line tour meanders, the tree branches, so the same
/// dots come out as veins: trunks through the shadows, capillaries feathering
/// into the light. The drawing plays out in plotting order, chain by chain,
/// a pen working through its queue.
///
/// The chains are plain `Contour`s, so the same sketch exports clean vector
/// line work: try `--export-svg out.svg --frame 900` (the full-tree moment),
/// each chain one pen-down stroke.
///
/// The picture is one of the bundled sample photographs, an elderly woman in
/// a yellow scarf, handed over as a small copy: the stipple reads density,
/// not detail.
@main
final class SpanningTree: Sketch {
    override var loopDuration: Double? { 24 }

    private var chains: [Contour] = []
    private var lengths: [Double] = []
    private var totalLength = 0.0

    override func setup() {
        seed(6)
        let frame = canvasRectangle.inset(by: 120)
        let picture = SamplePhoto.scarf.load().resized(width: 340, height: 340)
        chains = spanningTree(of: picture, points: 4000, in: frame, iterations: 45)
        lengths = chains.map { chain in
            var length = 0.0
            for i in 1 ..< chain.points.count {
                length += chain.points[i - 1].distance(to: chain.points[i])
            }
            return length
        }
        totalLength = lengths.reduce(0, +)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        guard totalLength > 0 else { return }

        // Draw in, hold, unwind: an eased out-and-back sweep of the plot.
        let sweep = Easing.smoothstep(pingPong(over: 24))
        var budget = totalLength * sweep

        noFill()
        stroke(Color(hex: 0x1C3324))
        strokeWeight(1.4 * scale)
        strokeJoin(.round)
        for (chain, length) in zip(chains, lengths) {
            if budget >= length {
                drawPolyline(chain.points)
                budget -= length
                continue
            }
            // The chain mid-draw: walk to the budgeted length and cut there.
            var partial = [chain.points[0]]
            var spent = 0.0
            for i in 1 ..< chain.points.count {
                let step = chain.points[i - 1].distance(to: chain.points[i])
                if spent + step >= budget {
                    let t = step > 0 ? (budget - spent) / step : 0
                    partial.append(chain.points[i - 1].lerp(to: chain.points[i], t))
                    break
                }
                spent += step
                partial.append(chain.points[i])
            }
            if partial.count > 1 { drawPolyline(partial) }
            if sweep < 1, let pen = partial.last {
                fill(Color(hex: 0x1C3324))
                noStroke()
                drawCircle(pen.x, pen.y, 5 * scale)
            }
            break
        }

        drawCaption("4,000 stipples joined by the shortest spanning tree")
    }
}
