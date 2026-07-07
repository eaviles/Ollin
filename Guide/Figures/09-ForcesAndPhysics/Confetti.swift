// figure: frame=85
//
// Guide listing (Chapter 9): forces by hand. Every piece of confetti feels
// gravity, the same gust of wind, and drag. The force sum is divided by the
// piece's mass, so the light pieces get flung and the heavy ones plow down.
import Ollin

final class Confetti: Sketch {
    var positions: [Vector2] = []
    var velocities: [Vector2] = []
    var masses: [Double] = []

    let palette = [
        Color(hex: 0xF25C54), Color(hex: 0xF2CC8F),
        Color(hex: 0x81B29A), Color(hex: 0x8187B9), Color(hex: 0xF2EFE8),
    ]

    override func setup() {
        seed(7)
        for _ in 0 ..< 210 {
            positions.append(Vector2(random(width), random(-1600, height)))
            velocities.append(.zero)
            masses.append(random(1, 6))
        }
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x101318))
        let gust = signedNoise(time * 0.5) * 3800    // one wind, shared by all

        for i in positions.indices {
            // Gather this frame's pushes, then let mass decide their effect.
            var force = Vector2(0, 340) * masses[i]      // gravity
            force += Vector2(gust, 0)                    // wind
            force += velocities[i] * -2.2                // drag, against motion
            let acceleration = force / masses[i]

            velocities[i] += acceleration * deltaTime
            positions[i] += velocities[i] * deltaTime

            // A piece that leaves the bottom rejoins the shower at the top.
            if positions[i].y > height + 30 {
                positions[i] = Vector2(random(width), -30)
                velocities[i] = .zero
            }

            withState {
                translate(positions[i])
                rotate(velocities[i].angle)
                fill(palette[i % palette.count])
                drawRect(center: .zero, width: 10 + masses[i] * 7, height: 9)
            }
        }
    }
}
