// figure: frame=50
//
// Guide figure (Chapter 14): four chaotic maps as density plates. Each panel
// iterates one formula millions of times and lets the visits pile up as
// faint additive dots, so the places the orbit loves glow. Two Clifford
// maps above, two de Jong maps below, each a different set of constants.
import Ollin

final class Plates: Sketch {
    let maps = [ChaoticMap.clifford(),
                ChaoticMap.clifford(a: -1.7, b: 1.3, c: -0.1, d: -1.2),
                ChaoticMap.deJong(),
                ChaoticMap.deJong(a: 1.4, b: -2.3, c: 2.4, d: -2.1)]
    var currents = [Vector2](repeating: Vector2(0.1, 0.1), count: 4)
    let perFrame = 30_000

    override func setup() {
        noClear()
        noStroke()
    }

    override func draw() {
        if frameCount == 1 { background(Color(hex: 0x0B0D12)) }

        blendMode(.add)
        pointSize(1)
        for (i, map) in maps.enumerated() {
            let cx = width * (i % 2 == 0 ? 0.27 : 0.73)
            let cy = height * (i < 2 ? 0.27 : 0.74)
            let reach = width * 0.115

            var points = [Vector2]()
            points.reserveCapacity(perFrame)
            var p = currents[i]
            for _ in 0 ..< perFrame {
                p = map.next(p)
                points.append(Vector2(cx + p.x * reach, cy + p.y * reach))
            }
            currents[i] = p

            fill(Color(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.045))
            drawPoints(points)
        }
    }
}
