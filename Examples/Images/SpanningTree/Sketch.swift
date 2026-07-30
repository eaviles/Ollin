import Ollin

/// A leaf drawn as the shortest tree through its stipples.
///
/// `spanningTree(of:points:)` stipples an image and then joins the dots with
/// the minimum spanning tree: the least total line that still reaches every
/// dot. Where the single-line tour meanders, the tree branches, so the same
/// dots come out as veins: trunks along the dark midrib, capillaries feathering
/// into the shading. The drawing plays out in plotting order, chain by chain,
/// a pen working through its queue.
///
/// The chains are plain `Contour`s, so the same sketch exports clean vector
/// line work: try `--export-svg out.svg --frame 900` (the full-tree moment),
/// each chain one pen-down stroke.
@main
final class SpanningTree: Sketch {
    override var loopDuration: Double? { 24 }

    private var chains: [Contour] = []
    private var lengths: [Double] = []
    private var totalLength = 0.0

    override func setup() {
        seed(6)
        let frame = canvasRectangle.inset(by: 120)
        chains = spanningTree(of: paint(), points: 4000, in: frame, iterations: 45)
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

    /// The picture the tree reproduces: a shaded leaf, dark along the midrib
    /// and fading to the margins, on white so the cutoff keeps the paper bare.
    private func paint() -> Image {
        let n = 340
        let image = Image(width: n, height: n, color: .white)
        let r = 1.05, d = 0.62   // the two arcs whose lens is the leaf
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1
                var tone = 1.0

                if dist(u, v, -d, 0) < r, dist(u, v, d, 0) < r {
                    // Inside the leaf: darkest at the rib, lighter outward,
                    // with a touch more light toward the tip.
                    let halfWidth = (r * r - v * v).squareRoot() - d
                    let across = clamp(abs(u) / max(halfWidth, 1e-4), 0, 1)
                    tone = 0.12 + 0.78 * pow(across, 1.2) + 0.05 * (1 - (v + 1) / 2)
                }

                // The stem, dropping from the lens's lower tip.
                if v > 0.78, v < 0.98, abs(u) < 0.022 + (v - 0.78) * 0.06 {
                    tone = min(tone, 0.24)
                }

                image[x, y] = Color(white: clamp(tone, 0, 1))
            }
        }
        return image
    }
}
