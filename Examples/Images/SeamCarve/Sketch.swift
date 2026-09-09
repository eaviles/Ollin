import Ollin
import OllinSamplePhotos

/// A Guanajuato alley made narrower two ways, so the difference is the point.
///
/// Seam carving takes a picture's width away one *seam* at a time: a run of
/// pixels, one per row, that walks from the top edge to the bottom. The seam
/// it takes is the one that costs the least, so the plain sky over the alley
/// goes first and the walls hold their width. Squeeze the same picture instead
/// and everything narrows together.
///
/// The red lines on the source are the seams that are about to go. The width
/// breathes over the loop; hold the mouse to squeeze the picture rather than
/// carve it, and watch the walls lean.
///
/// The seams are worked out once, into a `SeamMap`, which is what lets any
/// width be read back per frame.
@main
final class SeamCarve: Sketch {
    override var loopDuration: Double? { 10 }

    private let sourceWidth = 220
    private let sourceHeight = 220
    private let narrowest = 156

    private var source = Image(width: 1, height: 1)
    private var map: SeamMap?
    private var lines: [Contour] = []

    override func setup() {
        seed(7)
        // Carving runs on the picture's own pixels, so the photograph is scaled
        // down once here and both panels drawn back up from it.
        source = SamplePhoto.alley.load().resized(width: sourceWidth, height: sourceHeight)
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
        let zoom = 1.88
        let sourceBox = Rectangle(corner: Vector2((width - Double(sourceWidth) * 1.88) / 2, 70),
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
        let resultTop = sourceBox.corner.y + sourceBox.height + 96
        let resultBox = Rectangle(center: Vector2(width / 2,
                                                  resultTop + Double(sourceHeight) * zoom / 2),
                                  width: Double(target) * zoom,
                                  height: Double(sourceHeight) * zoom)
        if mouseIsPressed {
            drawImage(source, in: resultBox)
            label("squeezed to \(target) pixels: everything narrows together", above: resultBox)
        } else {
            if let carved = map?.image(target) { drawImage(carved, in: resultBox) }
            label("carved to \(target) pixels: the sky goes, the walls hold", above: resultBox)
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
}
