import Ollin

/// Iridescent and glittering shapes. Two filters give any shape a jewelled finish:
/// `.iridescence` washes it with the flowing rainbow sheen of a soap film, and
/// `.glitter` scatters twinkling sparkle flecks (dust plus the occasional bright
/// cross flare) across it. Each shape is drawn into its own `compose { }` layer and
/// post-filtered, so the effect lands on just that shape; the glitter flashes run
/// past 1.0 in linear light, so a following `.bloom` makes them glow.
@main
final class Glitter_Example: Sketch {
    override func draw() {
        background(Color(hex: 0x0B0E14))

        compose {
            // A soap-film heart: the sheen flows across the fill.
            layer {
                noStroke()
                fill(Color(white: 0.82))
                drawHeart(width * 0.30, height * 0.32, 420)
            }
            .post(.iridescence(amount: 0.85, scale: 2.2, bands: 2.4, shift: time * 0.22))

            // A glitter star: white dust and flares over a deep pink, bloomed.
            layer {
                noStroke()
                fill(Color(hex: 0xC2185B))
                drawStar(width * 0.72, height * 0.33, 250, 125, points: 5)
            }
            .post(.glitter(density: 110, amount: 1.3, phase: time * 2.4),
                  .bloom(threshold: 0.8, amount: 1.1, radius: 9))

            // An opal ring, both at once: an iridescent wash under colored sparkle.
            layer {
                noStroke()
                fill(Color(white: 0.7))
                drawRing(width * 0.5, height * 0.72, 130, 210)
            }
            .post(.iridescence(amount: 0.7, scale: 3.2, bands: 3, shift: 0.6 + time * 0.15),
                  .glitter(density: 150, amount: 0.9, size: 0.8, saturation: 0.8,
                           phase: 1.7 + time * 1.8),
                  .bloom(threshold: 0.85, amount: 0.9, radius: 7))
        }
    }
}
