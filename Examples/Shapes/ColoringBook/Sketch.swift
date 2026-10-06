import Ollin

/// A coloring book that colors itself. A ring of circles, a wave across the
/// page, and a few straight strokes drift on looping noise, and every patch
/// their lines wall off comes back as a region of its own
/// (`regions(enclosedBy:)`): two overlapping circles make three patches, a
/// line through them makes six, and the bare page ringed by several circles
/// is a patch like any other. Each region is filled with a crayon keyed to
/// its own center (a slow noise field read there), so a patch keeps its
/// color while the lines move and a patch cut in two becomes two colors. The
/// lines are drawn over the fills in ink, so the picture reads as a page
/// colored in, and the count in the caption follows the drawing.
///
/// The page's own edge is one of the outlines, so the strokes cut the whole
/// page into patches and nothing is left uncolored. Turn `fillsRegions` off
/// for the page before anyone picked up a crayon.
///
/// ```sh
/// swift run Example-Shapes-ColoringBook --export-svg /tmp/coloring-book.svg
/// ```
///
/// Every region is a plain `Shape`, so the SVG carries each patch as its own
/// filled path and the lines as strokes, ready for a plotter or a cutter.
@main
final class ColoringBook: Sketch {
    @Param(2 ... 8, icon: "circle") var circles = 5
    @Param(0 ... 6, icon: "line.diagonal") var strokes = 3
    @Param(icon: "paintpalette") var fillsRegions = true
    @Param(icon: "circle.dotted") var marksCenters = false

    private let period = 24.0
    override var loopDuration: Double? { period }

    private let paper = Color(hex: 0xF7F2E8)
    private let ink = Color(hex: 0x221F1C)
    private let crayons = Palette(Color(hex: 0xE8553E), Color(hex: 0xF2A93B), Color(hex: 0xF4D35E),
                                  Color(hex: 0x6DB36D), Color(hex: 0x3B8EA5), Color(hex: 0x7A5CA3),
                                  Color(hex: 0xE88BB0), Color(hex: 0x9BC9C0))

    override func draw() {
        background(paper)
        let phase = loopProgress(over: period)
        let outlines = drawing(at: phase)
        let patches = regions(enclosedBy: outlines)

        if fillsRegions {
            noStroke()
            for patch in patches {
                fill(crayon(for: patch))
                drawShape(patch)
            }
        }

        noFill()
        stroke(ink)
        strokeWeight(3 * scale)
        strokeJoin(.round)
        strokeCap(.round)
        for outline in outlines.dropFirst() {
            drawPolyline(outline.points, closed: outline.isClosed)
        }

        if marksCenters {
            noStroke()
            fill(ink)
            for patch in patches { drawCircle(center: patch.centroid, radius: 4 * scale) }
        }

        drawCaption("\(patches.count) regions")
    }

    /// The crayon for a patch, read off a slow field at the patch's own
    /// center, so the color belongs to the place rather than to the patch's
    /// number in the list.
    private func crayon(for patch: Shape) -> Color {
        let at = patch.centroid
        let pick = noise(at.x / width * 3.2 + 7, at.y / height * 3.2 + 3)
        return crayons[min(Int(pick * Double(crayons.count)), crayons.count - 1)]
    }

    /// The page's edge, a ring of drifting circles, one wave, and the
    /// straight strokes, each a plain `Contour`.
    private func drawing(at phase: Double) -> [Contour] {
        var outlines = [canvasRectangle.contour]
        let center = Vector2(width / 2, height / 2)
        for i in 0 ..< circles {
            let k = Double(i)
            let home = center + Vector2(angle: k / Double(circles) * .tau - .tau / 4, length: 230 * scale)
            let drift = Vector2(signedNoise(k * 2.3 + 10, loop: phase, radius: 0.6),
                                signedNoise(k * 2.3 + 50, loop: phase, radius: 0.6)) * 120 * scale
            let radius = (190 + 50 * signedNoise(k * 1.1 + 90, loop: phase, radius: 0.6)) * scale
            outlines.append(Circle(center: home + drift, radius: radius).contour())
        }
        let wave = (0 ... 12).map { j -> Vector2 in
            let t = Double(j) / 12
            return Vector2(-40 * scale + t * (width + 80 * scale),
                           height / 2 + signedNoise(t * 3 + 200, loop: phase, radius: 0.8) * 230 * scale)
        }
        outlines.append(Contour(curveThrough: wave, closed: false))
        for i in 0 ..< strokes {
            let k = Double(i) + 300
            let angle = k * 0.9 + signedNoise(k, loop: phase, radius: 0.5) * 0.6
            let along = Vector2(angle: angle, length: 1)
            let middle = center + along.perpendicular * (signedNoise(k + 7, loop: phase, radius: 0.5) * 320 * scale)
            outlines.append(Contour([middle - along * 900 * scale, middle + along * 900 * scale], closed: false))
        }
        return outlines
    }
}
