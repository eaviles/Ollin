// figure: frame=240
//
// Guide listing (Chapter 19): the self-warp. Two gradient-cored orbs orbit at
// their own paces; the field measures their motion and stretches their history
// into ribbons trailing the orbits (strength below 1, the ribbon regime).
import Ollin

final class SelfWarp: Sketch {
    var warp: SimField!

    override func setup() {
        warp = makeSimField(.selfWarp(amount: 0.55, refresh: 0.05))
    }

    override func draw() {
        withField(warp) {
            background(Color(hex: 0x08080F))
            noStroke()
            let c = bounds.center
            orb(at: c + Vector2(cos(time * 1.15), sin(time * 1.15)) * 310,
                radius: 84, Color(red: 1.0, green: 0.45, blue: 0.15))
            orb(at: c + Vector2(cos(-time * 0.74 + 2.1), sin(-time * 0.74 + 2.1)) * 215,
                radius: 66, Color(red: 0.2, green: 0.75, blue: 1.0))
        }
        drawImage(warp.image, 0, 0)
    }

    func orb(at center: Vector2, radius: Double, _ color: Color) {
        fill(.radial(center: center, radius: radius,
                     [.white, color, color.withAlpha(0)]))
        drawCircle(center: center, radius: radius)
    }
}
