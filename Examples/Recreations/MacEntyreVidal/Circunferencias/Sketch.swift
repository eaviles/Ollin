//  Recreation after Eduardo Mac Entyre - the generative paintings of the
//  1960s built from families of circles, read from Pintura generativa (1967,
//  acrylic on canvas, 150 x 100 cm) and Pintura generativa (1970, acrylic on
//  canvas) in the Museo de Arte Moderno de Buenos Aires, and Generative
//  Painting: Black, Red, Orange (1965, oil on canvas, 164.9 x 150.4 cm) in
//  the Museum of Modern Art, New York. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or his estate.
//  https://coleccion.museomoderno.org/index.php/Detail/works/16392
//  https://www.moma.org/collection/works/78340
//
//  An original Ollin interpretation, written from the paintings and from the
//  1960 manifesto's own glossary, where a generator is "the line or figure
//  that by its movement engenders in its turn a different or new geometric
//  body". Nothing was ported: the pictures were drawn with a compass on
//  tracing paper and painted by hand. The ranges, the looks, and the motion
//  are this sketch's own.

import Foundation
import Ollin

/// Circunferencias (Eduardo Mac Entyre, Buenos Aires, from 1960). The
/// generative painters started from the point and the line of concrete art
/// and, they wrote, allowed them movement. Mac Entyre's line was a circle.
/// He drew one with a compass, then drew it again with its center moved a
/// little, and again, the same step every time, until the family closed on
/// itself or ran out. The centers walk a ring about the middle of the
/// picture, so the circles make a rosette that passes through one point and
/// touches one rim, or they walk a short straight path, so the circles make a
/// lobe. Where two families cross, the thin lines beat against each other
/// and the flat disc reads as a sphere, a lens, or a flower. The paintings
/// of 1967 set the families white and green inside a red disc on green; by
/// 1970 they were cyan, pink, and lilac over a purple band on black; the one
/// in New York is red and orange on black, four lobes in a clover.
///
/// This sketch deals a picture from the seed. A disc holds `families`
/// families of circles. Each family has one radius and one generator: a
/// ring, whose circles sit with their centers at one distance from the
/// middle and one constant angle apart, as many as close the turn; or a
/// path, whose circles sit with their centers along one straight line, one
/// constant step apart. The dealt numbers keep every circle inside the disc,
/// and a few families share a center distance and differ only by a few
/// pixels of radius, the bundles his pictures have. `look` picks the ground
/// and the paints. Over one cycle of `seconds` every ring family turns by
/// exactly one of its own steps, so the picture comes back to itself, and
/// every path family slides one step along its line, its first circle
/// fading in and its last fading out. A press deals the next picture.
///
/// `--export-svg` gives every circle back as a circle at its family's
/// radius, so the family can be read from the file: the centers of a ring
/// family lie at one distance from the middle, one constant angle apart, and
/// their count closes the turn; the centers of a path family lie on one line,
/// one constant step apart.
@main
final class Circunferencias: Sketch {
    /// The ground, the disc, and the paints, after three of the paintings.
    enum Look: String, CaseIterable, ParamOption {
        /// 1967: white and green circles in a red disc with a white rim, on green.
        case verde
        /// 1970: cyan, pink, and lilac circles over a purple band, on black.
        case violeta
        /// 1965: red and orange lobes on black, with no disc drawn.
        case negro
    }

    @Param(icon: "paintpalette") var look = Look.verde
    @Param(1 ... 6, icon: "circle.circle") var families = 4
    @Param(4 ... 60, icon: "clock") var seconds = 12.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    /// How a family's generator moves its center.
    enum Generator {
        /// Around the middle: `distance` out, `count` circles one turn apart.
        case ring(distance: Double, count: Int, phase: Double)
        /// Along a line: `count` circles from `start` one `step` apart.
        case path(start: Vector2, direction: Vector2, step: Double, count: Int)
    }

    struct Family {
        var radius: Double
        var generator: Generator
        var color: Color
        var weight: Double
    }

    private struct Dealt: Equatable { var families: Int; var look: Look; var seed: Int }
    private var dealtFor: Dealt?
    private var dealt: [Family] = []
    private var pressed = false

    /// The disc the families live in, in canvas pixels.
    private var discRadius: Double { look == .negro ? 0.47 * shortSide : 0.36 * shortSide }
    private var middle: Vector2 { Vector2(width / 2, height / 2) }

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(families: families, look: look, seed: variation)
        if dealtFor != wanted {
            dealtFor = wanted
            deal()
        }
        let phase = (time / max(1, seconds)).truncatingRemainder(dividingBy: 1)

        // The ground, the band, the rim, and the disc.
        let r = discRadius
        switch look {
        case .verde:
            background(Color(hex: 0x1F7A3F))
            noStroke()
            fill(Color(hex: 0xEDE6D6))
            drawCircle(center: middle, radius: r * 1.16)
            fill(Color(hex: 0xD9481E))
            drawCircle(center: middle, radius: r)
        case .violeta:
            background(Color(hex: 0x0B0A10))
            noStroke()
            fill(Color(hex: 0x3B2A8F))
            drawRect(middle.x - 0.14 * width, 0, 0.28 * width, height)
        case .negro:
            background(Color(hex: 0x0A0808))
        }

        // The families, each circle at its family's radius.
        noFill()
        strokeCap(.butt)
        for family in dealt {
            strokeWeight(family.weight)
            switch family.generator {
            case let .ring(distance, count, start):
                // One full step per cycle: the picture at the end of the cycle
                // is the picture at its start with the circles renumbered.
                let step = 2 * .pi / Double(count)
                stroke(family.color)
                for k in 0 ..< count {
                    let angle = start + (Double(k) + phase) * step
                    drawCircle(center: middle + Vector2(angle: angle, length: distance),
                               radius: family.radius)
                }
            case let .path(start, direction, step, count):
                // The family slides one step along its line per cycle; the
                // circle entering fades in over the first step and the one
                // leaving fades out over the last, so the count holds.
                for k in 0 ..< count {
                    let along = Double(k) + phase
                    let fade = min(1, min(along, Double(count) - along))
                    stroke(family.color.withAlpha(fade))
                    drawCircle(center: start + direction * (along * step), radius: family.radius)
                }
            }
        }

        // The hub he painted at the middle of a rosette, filled so the file
        // keeps it apart from the families.
        if look != .negro {
            noStroke()
            fill(look == .verde ? Color(hex: 0xEDE6D6) : Color(hex: 0x7FE8F0))
            drawCircle(center: middle, radius: 7)
            fill(look == .verde ? Color(hex: 0xD9481E) : Color(hex: 0xF04E98))
            drawCircle(center: middle, radius: 3.5)
        }
    }

    /// Deals the families from the seed: a generator, a radius, a paint, and a
    /// weight each, every circle kept inside the disc.
    private func deal() {
        randomSeed(variation)
        dealt = []
        let r = discRadius
        let paints: [Color]
        switch look {
        case .verde:   paints = [Color(hex: 0xF2EDE0), Color(hex: 0x9FD88A), Color(hex: 0xF2EDE0), Color(hex: 0x2E9B4E)]
        case .violeta: paints = [Color(hex: 0x7FE8F0), Color(hex: 0xF04E98), Color(hex: 0xE8E0FF), Color(hex: 0xB08CFF), Color(hex: 0xF2EDE0)]
        case .negro:   paints = [Color(hex: 0xE8402A), Color(hex: 0xF08A2E), Color(hex: 0xC8302A), Color(hex: 0xF2B35A)]
        }

        if look == .negro {
            // The clover: lobes on evenly spaced spokes, each a path family
            // whose circles walk out from near the middle, overlapping there.
            let lobes = max(2, min(families, 6))
            let count = Int(random(16, 30))
            let startFraction = random(0.05, 0.15)
            let walkFraction = random(0.25, 0.45)
            let radius = r / (1 + startFraction + walkFraction)
            let step = radius * walkFraction / Double(count - 1)
            let tilt = random(0, 2 * .pi)
            for lobe in 0 ..< lobes {
                let direction = Vector2(angle: tilt + Double(lobe) * 2 * .pi / Double(lobes))
                dealt.append(Family(radius: radius,
                                    generator: .path(start: middle + direction * (radius * startFraction),
                                                     direction: direction, step: step, count: count),
                                    color: paints[lobe % paints.count],
                                    weight: 0.9))
            }
            return
        }

        var paintIndex = 0
        for i in 0 ..< families {
            let bundle = i == 0 ? 1 : (random(1) < 0.6 ? Int(random(2, 4)) : 1)
            let distance: Double
            let radius: Double
            let count: Int
            // Every family passes through the middle, or nearly, and the
            // first touches the rim: the center distance is the radius, half
            // the disc for the first and less for the rest. The 1970 look
            // sets more circles to a turn and lets a family's ring sit a
            // little inside its radius, so the lines pile up at the middle.
            radius = i == 0 ? r / 2 : r * random(0.12, 0.44)
            switch look {
            case .verde, .negro:
                distance = radius
                count = i == 0 ? Int(random(12, 22)) : Int(random(14, 32))
            case .violeta:
                distance = i == 0 ? radius : radius * random(0.86, 1)
                count = i == 0 ? Int(random(24, 40)) : Int(random(28, 48))
            }
            let phase = random(0, 2 * .pi)
            for b in 0 ..< bundle {
                // A bundle repeats the family a few pixels of radius apart,
                // the way his thin lines come in threes.
                let apart = random(4, 8)
                let bundled = radius - Double(b) * apart
                guard bundled > 8 else { break }
                dealt.append(Family(radius: bundled,
                                    generator: .ring(distance: distance, count: count, phase: phase),
                                    color: paints[paintIndex % paints.count],
                                    weight: b == 0 ? 0.9 : 0.7))
                paintIndex += 1
            }
        }
    }
}
