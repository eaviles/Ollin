import Ollin

/// One poster, three drums: splitting a sketch into spot-ink printing masters.
///
/// A risograph or screen-print press has no full-color mode. It prints one ink
/// at a time, each pass a translucent layer that darkens the paper, and the
/// colors mix where the layers overlap: blue over yellow reads green, pink
/// over yellow reads orange. `separated(into:paper:)` works that press in
/// reverse: for every pixel it finds the ink coverages whose overprint comes
/// closest, and hands back one grayscale master per ink, black where the drum
/// should print.
///
/// The canvas is the poster itself, which is the whole point: draw normally,
/// declare the `printInks`, and the separation is an export away. The `view` parameter
/// in the inspector flips to the three masters, or to the overprint preview
/// screened through `halftoned()` so the dots the press would lay down are
/// visible, each ink's grid at its own angle. Write the actual print files
/// (masters plus a registration-marked preview) with:
///
///     --export-separations poster.png [--screen halftone]
enum SeparationView: String, CaseIterable, ParamOption { case artwork, masters, preview }

@main
final class PrintSeparationSketch: Sketch {
    override var printInks: [Ink]? { [.fluorescentPink, .blue, .yellow] }

    @Param(style: .segmented, icon: "square.3.layers.3d") var view: SeparationView = .artwork

    private let labelFont = OutlineFont.system

    private var artwork = Image(width: 1, height: 1)
    private var separation: PrintSeparation?
    private var screenedPreview = Image(width: 1, height: 1)

    override func setup() {
        noStroke()
        artwork = paint()

        // The whole pipeline is CPU work, done once: separate, then screen a
        // copy for the dot preview (the masters keep their continuous tones).
        let sep = artwork.separated(into: printInks ?? [])
        separation = sep
        screenedPreview = sep.halftoned(pitch: 8).preview()
    }

    override func draw() {
        switch view {
        case .artwork:
            drawImage(artwork, in: Rectangle(x: 0, y: 0, width: width, height: height))
        case .preview:
            drawImage(screenedPreview, in: Rectangle(x: 0, y: 0, width: width, height: height))
        case .masters:
            drawMasters()
        }
    }

    /// The three drums side by side: what each one prints, black = full ink.
    private func drawMasters() {
        background(Color(hex: 0x101014))
        guard let separation else { return }

        let tile = 480.0, gutter = 40.0
        let origin = (width - tile * 2 - gutter) / 2

        textFont(labelFont)
        textSize(16)
        textAlign(.left, .middle)

        for (i, layer) in separation.layers.enumerated() {
            let x = origin + Double(i % 2) * (tile + gutter)
            let y = origin + Double(i / 2) * (tile + gutter + 40)
            drawImage(layer.master, in: Rectangle(x: x, y: y, width: tile, height: tile))
            fill(layer.ink.color)
            drawRect(x, y + tile + 12, 18, 18)
            fill(.white)
            let coverage = Int((layer.averageInk * 100).rounded())
            drawText("\(layer.ink.name.lowercased())  \(coverage)% ink", x + 28, y + tile + 21)
        }

        drawCaption("one grayscale master per drum, black where the ink lands")
    }

    /// A little sunrise poster painted the way the press will print it: each
    /// ink's coverage darkens the paper (base times the ink, weighted by how
    /// much of it lands), so overlaps mix into the overprint colors for free.
    private func paint() -> Image {
        let w = 1080, h = 1080
        let image = Image(width: w, height: h)
        let pink = Ink.fluorescentPink.color
        let blue = Ink.blue.color
        let yellow = Ink.yellow.color

        func inked(_ base: Color, _ ink: Color, _ coverage: Double) -> Color {
            let a = clamp(coverage, 0, 1)
            return Color(red: base.red * (1 - a + a * ink.red),
                         green: base.green * (1 - a + a * ink.green),
                         blue: base.blue * (1 - a + a * ink.blue))
        }

        for y in 0..<h {
            for x in 0..<w {
                let u = Double(x) / Double(w - 1)
                let v = Double(y) / Double(h - 1)

                // A yellow sun with a glow that fades with distance, a blue
                // mountain range behind, a pink one in front. Each ridge is a
                // wavy line; coverage turns on just below it.
                let sun = dist(u, v, 0.63, 0.30)
                let glow = clamp(1 - sun * 2.2, 0, 1) * 0.5
                let disk = 1 - smoothstep(0.155, 0.165, sun)
                let backRidge = 0.56 + 0.06 * sin(u * 7 + 1.2)
                let back = smoothstep(backRidge - 0.005, backRidge + 0.005, v)
                let frontRidge = 0.74 + 0.08 * sin(u * 4.2 + 4.0)
                let front = smoothstep(frontRidge - 0.005, frontRidge + 0.005, v)

                var c = Color.white
                c = inked(c, yellow, glow + disk)
                // The pink hill knocks the blue out behind it (all but a thin
                // violet shadow), the way a printer traps a foreground shape.
                c = inked(c, blue, back * 0.85 * (1 - front * 0.85))
                c = inked(c, pink, front * 0.9 + disk * 0.3)
                image[x, y] = c
            }
        }
        return image
    }
}
