// figure: frame=40
//
// Guide payoff (Chapter 9): a picture painted with type. One of the bundled
// photographs, read at a small working size under a grid of letters: each
// letter takes the pixel's color and scales by its brightness, so the words
// dissolve into the picture and the picture assembles itself out of the words.
import Ollin
import OllinSamplePhotos

final class TypeMosaic: Sketch {
    @Param("Columns", 24...80) var columns = 64
    @Param("Message") var message = "OLLIN "
    @Param("Breathe", 0...1) var breathe = 0.5

    var source: Image?

    override func setup() {
        noiseSeed(3)
        source = SamplePhoto.portrait.load().resized(width: 160, height: 160)
        textFont(OutlineFont.systemBold)
        textMode(.atlas)                   // thousands of glyphs a frame
        textAlign(.center, .middle)
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        guard let source else { return }
        let chars = Array(message.isEmpty ? "OLLIN " : message)
        let cell = width / Double(columns)
        let rows = Int(height / cell)
        var k = 0

        for row in 0..<rows {
            for col in 0..<columns {
                let u = (Double(col) + 0.5) / Double(columns)
                let v = (Double(row) + 0.5) / Double(rows)
                let c = source[Int(u * Double(source.width - 1)),
                               Int(v * Double(source.height - 1))]
                let brightness = c.red * 0.2126 + c.green * 0.7152 + c.blue * 0.0722

                // Bright pixels get big letters; a slow noise field makes the
                // whole picture breathe without changing what it says.
                let sway = 1 + signedNoise(u * 3, v * 3, time * 0.25) * 0.18 * breathe
                textSize(cell * (0.4 + 1.25 * brightness * brightness) * sway)
                fill(Color.mix(c, .white, brightness * 0.22))
                drawText(String(chars[k % chars.count]),
                         (Double(col) + 0.5) * cell, (Double(row) + 0.5) * cell)
                k += 1
            }
        }
    }
}
