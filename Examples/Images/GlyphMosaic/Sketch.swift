import Ollin
import OllinSamplePhotos

/// A portrait rebuilt as a grid of glyphs, under a light that passes over it.
///
/// `drawGlyphMosaic` samples an image cell by cell and places, in each cell,
/// the character whose measured ink matches the brightness underneath: bright
/// cores earn solid blocks, mid tones the checkered and crossed marks, faint
/// edges a lone dot, and true shadow stays empty. The ramp is not hand-ordered;
/// every glyph in the set is measured in the active font, so any string works
/// as a palette of marks. The bundled bitmap font covers the whole default
/// `GlyphSet.technical` set, and its chunky pixel forms are the classic look.
///
/// The picture is one of the bundled sample photographs, a young woman in a
/// lace headdress, read at 176 pixels: a mosaic reads one value per cell. A
/// slow band of light sweeps across it once per loop, so the mosaic re-reads
/// the face live: characters promote and demote as the light passes through
/// their cells.
@main
final class GlyphMosaic: Sketch {
    override var loopDuration: Double? { 10 }

    private var picture = Image(width: 1, height: 1)
    private let source = Image(width: 176, height: 176, color: .black)

    override func setup() {
        picture = SamplePhoto.portrait.load().resized(width: source.width, height: source.height)
    }

    override func draw() {
        light(phase: loopProgress(over: 10) * .tau)
        background(.black)
        textFont(BitmapFont.builtIn)
        noStroke()
        fill(.white)

        // The default set ends in full-cell blocks and shades, which tile
        // into solid regions at the bright end. This set tops out at discrete
        // filled marks instead, so even the brightest cells stay separate
        // glyphs with black gutters, and any string works the same way.
        let marks = "·⠂∙•⠒1x∷+=⠶✕▪∴≡⁘┼⠿※╬◌═◇○▖▘▝▗⊘⊞◐⊗✚✜▚▞⣤▤◈⊠□▣⣶◆●◉▧▨▦░▒⊡◘▩◙⣿■"
        drawGlyphMosaic(source, columns: 64, characters: marks,
                        in: canvasRectangle.inset(by: 64))
        drawCaption("every mark chosen by its measured ink; empty cells are true shadow")
    }

    /// The photograph under a broad band of light that makes one turn per
    /// loop, so the mosaic's perfect-loop export closes exactly. The band
    /// never takes a cell to black, so the face is always there to read.
    private func light(phase: Double) {
        let n = source.width
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1
                let band = unipolar(sin(2.6 * (u * cos(phase) + v * sin(phase)) - phase))
                let lift = 0.45 + 0.55 * band
                let c = picture[x, y]
                source[x, y] = Color(red: clamp(c.red * lift, 0, 0.9),
                                     green: clamp(c.green * lift, 0, 0.9),
                                     blue: clamp(c.blue * lift, 0, 0.9))
            }
        }
    }
}
