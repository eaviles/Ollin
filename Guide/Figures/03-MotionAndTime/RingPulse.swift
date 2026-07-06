// figure: gif duration=4 fps=25 width=540
//
// Guide payoff (Chapter 3): a perfectly looping kinetic piece. Waves of light
// chase around five rings of fixed dots; every time term completes whole
// cycles in `loopTime` seconds, so the last frame hands off to the first.
import Ollin

final class RingPulse: Sketch {
    @Param("Waves", 1...6) var waves = 3
    @Param("Pulse width", 0.1...0.9) var pulseWidth = 0.35

    let loopTime = 4.0
    let ramp = Ramp([
        Color(hex: 0x5E60CE), Color(hex: 0x64DFDF),
        Color(hex: 0xFFB703), Color(hex: 0xE56B6F),
    ])

    override func draw() {
        background(Color(hex: 0x0E1116))
        noStroke()
        let beat = time * .tau / loopTime          // one full cycle per loop
        for ring in 0..<5 {
            let radius = 110.0 + Double(ring) * 82
            let count = 14 + ring * 6
            let base = ramp.color(at: Double(ring) / 4)
            var direction = 1.0
            if ring % 2 == 1 { direction = -1 }
            for i in 0..<count {
                let angle = Double(i) / Double(count) * .tau
                let wave = sin(angle * Double(waves) - beat * 2 * direction)
                let lit = Easing.smoothStep(map(wave, 1 - pulseWidth * 2, 1, 0, 1, clamp: true))
                fill(Color.mix(base, Color(hex: 0xFFF6E8), t: lit * 0.4))
                let x = width / 2 + cos(angle) * (radius + lit * 18)
                let y = height / 2 + sin(angle) * (radius + lit * 18)
                drawCircle(x, y, 6 + lit * 20)
            }
        }
    }
}
