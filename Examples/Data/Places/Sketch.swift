import Ollin

/// A drawing built out of a JSON document.
///
/// `loadJSON` reads the file once in `setup()` and hands back a value you reach
/// through by name and by index. Nothing is decoded into a type first, so the
/// shape of the document is the shape of the code: `point["at"]["x"]` walks the
/// nesting, `paths.array` loops the pairs, and `.number` / `.text` / `.color`
/// ask for the kind you want at the end of the walk.
///
/// A key that isn't there answers null rather than stopping, which is what makes
/// the walk safe to write in one line. One station in the file carries no
/// `tint`; it draws in the fallback color instead of needing a check at every
/// step, and nothing else in the sketch has to know it is missing. Cairn is the
/// one: it is the gray station.
///
/// The survey is invented. What is worth copying is the reading.
@main
final class Places: Sketch {
    private var document: JSON?

    /// A slow drift so the stations breathe rather than sitting still.
    private var pulse: Double { (sin(time * 0.6) + 1) / 2 }

    override func setup() {
        document = loadJSON(resource: "places", withExtension: "json", in: .module)
    }

    override func draw() {
        background(Color(hex: 0x101317))

        guard let document else {
            return drawStatus("places.json could not be read", style: .warning)
        }

        let points = document["points"].array
        guard !points.isEmpty else {
            return drawStatus("places.json holds no points", style: .warning)
        }

        drawPaths(document["paths"].array, between: points)
        for point in points { drawPoint(point) }
        drawTitle(document["survey"])
        drawCaption("a survey read from JSON; the paths are index pairs into the points")
    }

    // MARK: The drawing

    /// Each path is a pair of indices into the points, so a line is drawn
    /// between whichever two stations it names.
    private func drawPaths(_ paths: [JSON], between points: [JSON]) {
        noFill()
        stroke(Color(white: 1, alpha: 0.16))
        strokeWeight(1.5)
        for path in paths {
            guard let from = path[0].int, let to = path[1].int,
                  points.indices.contains(from), points.indices.contains(to) else { continue }
            let a = position(of: points[from])
            let b = position(of: points[to])
            drawLine(a, b)
        }
    }

    private func drawPoint(_ point: JSON) {
        let at = position(of: point)
        let weight = point["weight"].number ?? 0.5
        // The station with no tint in the file lands here, and that is the
        // whole handling it needs.
        let tint = point["tint"].color ?? Color(white: 0.55)
        let radius = 10 + weight * 34

        noStroke()
        fill(tint.withAlpha(0.14))
        drawCircle(center: at, radius: radius + 10 + pulse * weight * 14)

        fill(tint)
        drawCircle(center: at, radius: radius)

        fill(.white)
        textFont(OutlineFont.systemMedium)
        textSize(15 * scale)
        textAlign(.center, .top)
        drawText(point["name"].text ?? "", at.x, at.y + radius + 14)
    }

    private func drawTitle(_ survey: JSON) {
        noStroke()
        fill(.white)
        textFont(OutlineFont.system)
        textSize(30 * scale)
        textAlign(.left, .top)
        drawText(survey.title.text ?? "", 96, 88)

        fill(Color(white: 0.45))
        textFont(OutlineFont.systemMedium)
        textSize(14 * scale)
        drawText(survey.subtitle.text ?? "", 96, 134)
    }

    // MARK: Mapping

    /// The file stores positions as fractions of the canvas, so the drawing
    /// fits whatever size the sketch runs at.
    private func position(of point: JSON) -> Vector2 {
        let inset = bounds.inset(by: .all(190))
        return inset.point(u: point["at"]["x"].number ?? 0.5,
                           v: point["at"]["y"].number ?? 0.5)
    }
}
