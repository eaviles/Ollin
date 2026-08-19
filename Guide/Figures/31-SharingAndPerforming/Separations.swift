// figure: frame=0
//
// Guide diagram (Chapter 31): separating artwork into printable inks. One
// drawing, the three masters a print shop would need (black means full ink),
// and the overprint preview showing how those three drums will read together.
import Ollin

final class Separations: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    var plates: [Image] = []
    var preview: Image?
    var names: [String] = []

    override func setup() {
        let artwork = poster(size: 240)
        let inks: [Ink] = [.fluorescentPink, .blue, .yellow]
        let separation = artwork.separated(into: inks)
        plates = separation.layers.map(\.master)
        names = inks.map(\.name)
        preview = separation.preview()
    }

    override func draw() {
        background(paper)

        for (i, plate) in plates.enumerated() {
            let panel = Rectangle(x: 25 + Double(i) * 200, y: 62,
                                  width: 180, height: 180)
            drawImage(plate, in: panel)
            frame(panel, title: names[i].lowercased())
        }
        if let preview {
            let panel = Rectangle(x: 655, y: 62, width: 180, height: 180)
            drawImage(preview, in: panel)
            frame(panel, title: "overprinted")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one drawing, one grayscale master per drum, and the result",
                 width / 2, 288)
    }

    /// Something with flat colors, overlaps, and a gradient, so the search has
    /// both easy and hard pixels to place.
    func poster(size: Int) -> Image {
        let image = Image(width: size, height: size)
        let sky = Ramp([Color(hex: 0xFDE74C), Color(hex: 0xF06292)])
        for y in 0 ..< size {
            for x in 0 ..< size {
                let u = Double(x) / Double(size - 1)
                let v = Double(y) / Double(size - 1)
                var c = sky.color(at: v)
                if dist(u, v, 0.38, 0.42) < 0.24 { c = Color(hex: 0x2B5DD7) }
                if dist(u, v, 0.64, 0.62) < 0.20 {
                    c = Color.mix(c, Color(hex: 0x1B1B3A), t: 0.7)
                }
                image[x, y] = c
            }
        }
        return image
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
