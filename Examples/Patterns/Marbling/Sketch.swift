import Ollin

/// Paper marbling in closed form.
///
/// A `Marbling` bath composes the classic moves: bull's-eyes of alternating
/// ink dropped onto the bath, a comb pulled down through them (the feathered
/// nonpareil), a finer comb pulled back up, and a vortex stirred into one
/// corner. Every operation is an exact point transform, so the finished
/// paper is pure vector geometry:
///
/// ```sh
/// swift run Example-Patterns-Marbling --export-svg /tmp/marbling.svg
/// ```
///
/// Click to drop fresh ink; drag and release to pull a stylus through the
/// bath. Each variation seeds a different paper.
@main
final class Marbling_Example: Sketch {
    private let paper = Color(hex: 0xEFE7D6)
    private let inks = [Color(hex: 0x1F2A44), Color(hex: 0xA43B2A),
                        Color(hex: 0xC8912F), Color(hex: 0xEFE7D6),
                        Color(hex: 0x3A6B5C)]

    private var bath = Marbling()
    private var pressPoint = Vector2.zero

    override func setup() {
        bath = Marbling()

        // Bull's-eyes: concentric drops of alternating ink, the base every
        // raked pattern starts from.
        for column in 0 ..< 3 {
            let center = Vector2(width * (0.25 + 0.25 * Double(column)),
                                 height * random(0.35, 0.65))
            let rings = 12
            for ring in 0 ..< rings {
                let radius = map(Double(ring), 0, Double(rings - 1), 230, 30)
                bath.drop(at: center, radius: radius + random(-8, 8),
                          color: inks[(column + ring) % inks.count])
            }
        }

        // A loose scatter of stones between the eyes.
        for _ in 0 ..< 14 {
            bath.drop(at: randomVector(in: canvasRectangle.inset(by: 90)),
                      radius: random(14, 44), color: randomChoice(inks))
        }

        // The nonpareil rake: a comb pulled down, a finer comb pulled back
        // up half a tooth over, feathering every boundary. Falloffs well
        // under the tooth spacing keep the drops legible between teeth.
        bath.comb(through: Vector2(0, height / 2), direction: .unitY,
                  spacing: 110, strength: 260, falloff: 30)
        bath.comb(through: Vector2(55, height / 2), direction: -.unitY,
                  spacing: 110, strength: 170, falloff: 22)

        // One stirred curl for asymmetry.
        bath.swirl(at: Vector2(width * random(0.3, 0.7),
                               height * random(0.3, 0.7)),
                   strength: random(320, 480), falloff: 150)
    }

    override func draw() {
        background(paper)
        noStroke()
        drawMarbling(bath)
        drawCaption("click drops ink, a drag pulls the stylus")
    }

    override func mousePressed() {
        pressPoint = Vector2(mouseX, mouseY)
    }

    override func mouseReleased() {
        let release = Vector2(mouseX, mouseY)
        let pull = release - pressPoint
        if pull.length > 24 {
            bath.tine(through: pressPoint, direction: pull,
                      strength: pull.length, falloff: 60)
        } else {
            bath.drop(at: release, radius: random(24, 64),
                      color: randomChoice(inks))
        }
    }
}
