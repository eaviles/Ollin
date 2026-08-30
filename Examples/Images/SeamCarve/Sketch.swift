import Ollin

/// A painted skyline made narrower two ways, so the difference is the point.
///
/// Seam carving takes a picture's width away one *seam* at a time: a run of
/// pixels, one per row, that walks from the top edge to the bottom. The seam
/// it takes is the one that costs the least, so the smooth sky between the
/// towers goes first and the towers hold their width. Squeeze the same picture
/// instead and everything narrows together.
///
/// The red lines on the source are the seams that are about to go. The width
/// breathes over the loop; hold the mouse to squeeze the picture rather than
/// carve it, and watch the towers lean.
///
/// The source is painted once in `setup()` (a graded sky, three grained towers
/// with windows, and a grained ground), so the sketch carries no asset. The
/// seams are worked out once as well, into a `SeamMap`, which is what lets any
/// width be read back per frame.
@main
final class SeamCarve: Sketch {
    override var loopDuration: Double? { 10 }

    private let sourceWidth = 320
    private let sourceHeight = 180
    private let narrowest = 228

    private var source = Image(width: 320, height: 180, color: .black)
    private var map: SeamMap?
    private var lines: [Contour] = []

    override func setup() {
        seed(7)
        paint()
        map = source.seamMap()
        // Every fifth seam of the ones the loop takes: enough to read as a
        // field of paths without drawing thousands of points a frame.
        if let map {
            lines = stride(from: 0, to: sourceWidth - narrowest, by: 5).map { map.seam($0) }
        }
    }

    override func draw() {
        background(Color(hex: 0x101014))

        // The width breathes from full to narrow and back.
        let swing = (1 - cos(loopProgress(over: 10) * .tau)) / 2
        let target = Int(round(Double(sourceWidth) - swing * Double(sourceWidth - narrowest)))
        let zoom = 2.2
        let sourceBox = Rectangle(corner: Vector2(140, 96),
                                  width: Double(sourceWidth) * zoom,
                                  height: Double(sourceHeight) * zoom)

        // The source, with the paths that are about to go drawn over it.
        drawImage(source, in: sourceBox)
        withState {
            translate(sourceBox.corner)
            scale(zoom)
            noFill()
            stroke(Color(hex: 0xFF4B3E, alpha: 0.55))
            strokeWeight(1 / zoom)
            let showing = Int(round(swing * Double(lines.count)))
            for line in lines.prefix(showing) { drawPolyline(line.points) }
        }
        label("the picture, and the paths it is about to give up", above: sourceBox)

        // The same picture at the same width, carved or squeezed.
        let resultTop = sourceBox.corner.y + sourceBox.height + 118
        let resultBox = Rectangle(center: Vector2(width / 2,
                                                  resultTop + Double(sourceHeight) * zoom / 2),
                                  width: Double(target) * zoom,
                                  height: Double(sourceHeight) * zoom)
        if mouseIsPressed {
            drawImage(source, in: resultBox)
            label("squeezed to \(target) pixels: everything narrows together", above: resultBox)
        } else {
            if let carved = map?.image(target) { drawImage(carved, in: resultBox) }
            label("carved to \(target) pixels: the sky goes, the towers hold", above: resultBox)
        }

        drawCaption("seam carving: the cheapest way down goes first; hold the mouse to squeeze instead")
    }

    /// A small label over a panel's top edge.
    private func label(_ text: String, above box: Rectangle) {
        withState {
            fill(Color(white: 0.72))
            textSize(19)
            textAlign(.center)
            drawText(text, box.center.x, box.corner.y - 18)
        }
    }

    /// The picture the carve reads: a graded sky with faint cloud, three towers
    /// with lit windows, and a ground. The towers and the ground carry fine
    /// grain, so no way down through them is ever free; the sky is smooth
    /// across, which is what makes it the cheap way and the first to go.
    private func paint() {
        let horizon = 138
        let towers: [(left: Int, right: Int, top: Int, tone: Double)] = [
            (44, 84, 52, 0.30),
            (116, 152, 28, 0.22),
            (206, 262, 66, 0.34),
        ]

        for y in 0 ..< sourceHeight {
            let v = Double(y) / Double(sourceHeight)
            for x in 0 ..< sourceWidth {
                let u = Double(x) / Double(sourceWidth)
                var color: Color

                if y >= horizon {
                    let grain = signedNoise(Double(x) * 0.9, Double(y) * 0.9) * 0.05
                    color = Color(white: clamp(0.13 + (v - 0.76) * 0.4 + grain, 0, 1))
                } else {
                    let cloud = signedFbm(u * 3.2, v * 2.4, octaves: 3) * 0.05
                    let t = clamp(v * 1.5 + cloud, 0, 1)
                    color = Color.mix(Color(hex: 0x2A3358), Color(hex: 0xE8A25C), t)
                }

                for tower in towers where x >= tower.left && x < tower.right && y >= tower.top {
                    let grain = signedNoise(Double(x) * 1.7, Double(y) * 1.7) * 0.05
                    let lit = (x - tower.left) % 9 < 4 && (y - tower.top) % 12 < 6
                        && y < horizon + 22
                    color = lit
                        ? Color.mix(Color(hex: 0xF6D9A0), Color(white: tower.tone), 0.25)
                        : Color(white: clamp(tower.tone + grain, 0, 1))
                }

                source[x, y] = color
            }
        }
    }
}
