import Ollin

/// Authoring an image pixel by pixel, then recoloring it at draw time. `setup()`
/// makes a blank `Image` and writes every pixel with `image[x, y] = …`, painting
/// a flowing colormap field with no asset on disk. `draw()` then draws that field
/// large under an animated `tint(_:)` — a warm↔cool wash that also pulses its
/// opacity, letting the background show through at the thin end.
///
/// The strip of swatches along the bottom reads the field back with `image[x, y]`
/// (a get): they show the *authored* colors, unaffected by the tint, because
/// `tint` only multiplies as the image is drawn — it never edits the stored pixels.
@main
final class PixelField: Sketch {
    var field: Image?

    override func setup() {
        noStroke()

        // A blank square image, authored one pixel at a time.
        let size = 120
        let image = Image(width: size, height: size)
        for py in 0..<size {
            for px in 0..<size {
                let u = Double(px) / Double(size - 1)
                let v = Double(py) / Double(size - 1)
                // A smooth diagonal wave blended with value noise, mapped through
                // a perceptual colormap.
                let wave = unipolar(sin((u + v) * .tau))
                let value = wave * 0.6 + noise(u * 3, v * 3) * 0.4
                image[px, py] = Colormap.turbo.color(at: min(1, max(0, value)))
            }
        }
        field = image
    }

    override func draw() {
        background(Color(white: 0.08))
        guard let field else { return }

        let side = width * 0.62
        let x = (width - side) / 2
        let y = height * 0.12

        // Animated tint: a warm↔cool wash whose alpha pulses, so the image fades
        // toward the background and back.
        let k = unipolar(sin(time * 2.4))
        withState {
            tint(Color(red: 0.7 + 0.3 * k, green: 0.85, blue: 1.0 - 0.3 * k,
                       alpha: 0.55 + 0.45 * k))
            drawImage(field, x, y, side, side)
        }

        // Read the field's middle row back (a get) and lay the true colors out as
        // swatches — untouched by the tint above.
        let count = 16
        let gap = side / Double(count)
        let sy = y + side + height * 0.05
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let px = Int(t * Double(field.width - 1))
            fill(field[px, field.height / 2])
            drawRect(x + Double(i) * gap, sy, gap - 6 * scale, gap - 6 * scale)
        }
    }
}
