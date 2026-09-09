import Ollin
import OllinSamplePhotos

/// Pulling a palette out of a photograph. `extractPalette(from:)` clusters an
/// image's pixels in a perceptual space and hands back the colors it is mostly
/// made of, most-used first.
///
/// The picture is one of the bundled sample photographs, a woman before a wall
/// of cempasúchil, the marigolds of Día de Muertos: one saturated orange over
/// most of the frame, a pink blouse, gray hair, and the greens of the stems.
/// The wide row is what the extraction found. The first swatch is the color the
/// picture is most made of, so the marigolds come first however many colors are
/// asked for.
///
/// The count cycles. Asking for fewer colors than the picture holds makes the
/// clustering merge the nearest ones rather than drop them, which is why the
/// pink and the gray survive down to three and fold into the orange at two.
@main
final class PaletteFromImage: Sketch {
    var photograph = Image(width: 1, height: 1)
    var extracted: [Palette] = []   // one per count, so `draw()` never clusters

    override func setup() {
        noStroke()
        photograph = SamplePhoto.marigolds.load()

        // Clustering is setup-time work. Extract once per count we might show.
        extracted = (1...8).map { extractPalette(from: photograph, count: $0) }
    }

    override func draw() {
        background(Color(hex: 0x101014))

        // Cycle through the counts, holding each for a beat.
        let count = 2 + Int(time * 0.5) % 7
        let palette = extracted[count - 1]

        let side = width - 180.0
        let frame = Rectangle(x: 90, y: 80, width: side, height: side * 0.66)
        drawImage(photograph, in: frame, fit: .cover)

        // What the extraction found, in order: the first swatch is the color
        // the picture is most made of.
        let barY = frame.y + frame.height + 44
        let step = side / Double(palette.count)
        for i in 0..<palette.count {
            fill(palette[i])
            drawRect(90 + Double(i) * step, barY, step, 130, cornerRadius: 4)
        }

        drawCaption("\(count) colors extracted from the photograph, most used first")
    }
}
