import Ollin

/// SVG import: vector artwork read into `Shape`s and drawn two ways.
///
/// The left panel draws the bundled rocket badge as authored: `loadSVG` /
/// `SVG(resource:in:)` reads paths, basic shapes, groups, and transforms into
/// elements that keep their fills and strokes, and `drawSVG(_:in:)` fits the
/// document into a rectangle. The right panel mines the same file as bare
/// geometry: every contour respaced with `resampled(spacing:)` and redrawn as
/// dots that swell in waves, the treatment any imported artwork opens up
/// (booleans, offsets, hatching, plotting all start the same way).
@main
final class SVGImport: Sketch {
    var art: SVG?

    override func setup() {
        art = SVG(resource: "rocket", in: .module)
    }

    override func draw() {
        background(Color(hex: 0x1A1E30))
        guard let art else { return }

        let margin = 70.0 * scale
        let panelWidth = (width - margin * 3) / 2
        let panelHeight = height - margin * 2

        // As authored: fills, strokes, and stacking order from the file.
        drawSVG(art, in: Rectangle(x: margin, y: margin,
                                   width: panelWidth, height: panelHeight))

        // As geometry: the same contours, respaced into even dots.
        let fitted = art.fitted(in: Rectangle(x: margin * 2 + panelWidth, y: margin,
                                              width: panelWidth, height: panelHeight))
        noStroke()
        fill(Color(hex: 0xBFD3FF))
        for contour in fitted.contours {
            let dots = contour.resampled(spacing: 7 * scale)
            for point in dots.points {
                let swell = 1 + 0.8 * sin(time * 2 + point.y * 0.02)
                drawCircle(center: point, radius: 1.4 * scale * swell)
            }
        }
    }
}
