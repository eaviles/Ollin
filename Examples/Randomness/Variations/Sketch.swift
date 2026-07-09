import Ollin

/// A composition built once per variation: the palette, the scatter, the sizes,
/// and the solid-or-outline mix are all drawn from the sketch's seeded
/// randomness in `setup()`, so every seed is a different piece and the same
/// seed is always the same piece. The caption shows the `variation` the run
/// grew from. Explore the seed space from the inspector's Variation card
/// (step, randomize, or jump), proof a whole range with
/// `--export-grid sheet.png --seeds 25`, then re-render a keeper at full
/// resolution with `--export out.png --seed N`.
@main
final class Variations: Sketch {
    struct Disc {
        var center: Vector2
        var radius: Double
        var color: Color
        var outlined: Bool
        var phase: Double
    }

    var backdrop = Color.black
    var discs: [Disc] = []

    /// Curated backdrop-and-inks pairings; each variation picks one.
    let palettes: [(backdrop: Color, inks: [Color])] = [
        (Color(hex: 0x101418), [Color(hex: 0x64DFDF), Color(hex: 0xFFB703),
                                Color(hex: 0xE56B6F), Color(hex: 0x5E60CE)]),
        (Color(hex: 0x171214), [Color(hex: 0xF4A261), Color(hex: 0xE76F51),
                                Color(hex: 0x2A9D8F), Color(hex: 0xE9C46A)]),
        (Color(hex: 0x0D1321), [Color(hex: 0xF7B2BD), Color(hex: 0x748CAB),
                                Color(hex: 0xF0EBD8), Color(hex: 0x3E5C76)]),
        (Color(hex: 0x1A1423), [Color(hex: 0xB8F2E6), Color(hex: 0xFFA69E),
                                Color(hex: 0xAED9E0), Color(hex: 0xFAF3DD)]),
        (Color(hex: 0x14181B), [Color(hex: 0xC9F299), Color(hex: 0x7FD8BE),
                                Color(hex: 0xFCB0B3), Color(hex: 0xF7EF99)]),
    ]

    override func setup() {
        let palette = randomChoice(palettes)
        backdrop = palette.backdrop

        // An even-but-organic scatter whose spacing (and so the piece's
        // density) is itself part of the variation.
        let margin = 90 * scale
        let field = Rectangle(x: margin, y: margin,
                              width: width - margin * 2, height: height - margin * 2)
        let spacing = random(70, 130) * scale
        discs = poissonDisk(in: field, radius: spacing).map { point in
            Disc(center: point,
                 radius: random(0.22, 0.62) * spacing,
                 color: randomChoice(palette.inks).withAlpha(random(0.55, 0.95)),
                 outlined: random() < 0.3,
                 phase: random(.tau))
        }
    }

    override func draw() {
        background(backdrop)
        for disc in discs {
            // A gentle per-disc breath; the composition itself holds still.
            let radius = disc.radius * (1 + 0.06 * sin(time * 0.8 + disc.phase))
            if disc.outlined {
                noFill()
                stroke(disc.color)
                strokeWeight(max(1.5, radius * 0.16))
            } else {
                noStroke()
                fill(disc.color)
            }
            drawCircle(disc.center.x, disc.center.y, radius)
        }
        drawCaption("Variation \(variation)")
    }
}
