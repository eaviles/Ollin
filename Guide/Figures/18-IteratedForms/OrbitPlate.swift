// figure: frame=0
//
// Guide payoff (Chapter 18): a plate of four orbits. Four different iterated
// rules, all of them handed to the same plotting function, because the
// chapter's whole claim is that what you are looking at is the density of an
// orbit rather than a drawn shape.
import Ollin

final class OrbitPlate: Sketch {
    @Param("Points per panel", 20_000...220_000) var budget = 90_000
    @Param("Dot size", 0.6...3.0) var dotSize = 1.1
    @Param("Ink", 0.05...0.6) var inkAlpha = 0.18

    let paper = Color(hex: 0x14151A)
    let ramp = Ramp([
        Color(hex: 0xE8663C), Color(hex: 0xE8B23C),
        Color(hex: 0x49B8A0), Color(hex: 0x7C6FD1),
    ])

    override func draw() {
        seed(3)
        background(paper)
        noStroke()

        let panels = grid(columns: 2, rows: 2, padding: 70, gutter: 44)
        for (index, cell) in panels.cells.enumerated() {
            let inner = cell.frame.inset(by: .all(26))
            plot(orbit(index), in: inner, ink: ramp.color(at: Double(index) / 3))
            label(index, in: cell.frame)
        }
    }

    // Four rules, four clouds of points. Nothing below this line knows which
    // rule made the cloud it is drawing.
    func orbit(_ index: Int) -> [Vector2] {
        switch index {
        case 0:
            return ifsPoints(.barnsleyFern, count: budget).map { Vector2($0.x, -$0.y) }
        case 1:
            let map = ChaoticMap.clifford()
            var p = Vector2(0.1, 0.1)
            var trail: [Vector2] = []
            trail.reserveCapacity(budget)
            for _ in 0 ..< budget {
                p = map.next(p)
                trail.append(p)
            }
            return trail
        case 2:
            // A ring of mutually tangent mirrors, plus one filling their hole.
            // Tangency is the whole game: overlap them and the lace tears.
            let count = 5
            let r = sin(.pi / Double(count))
            var mirrors = (0 ..< count).map { i -> Circle in
                let a = .tau * Double(i) / Double(count)
                return Circle(center: Vector2(cos(a), sin(a)), radius: r)
            }
            mirrors.append(Circle(center: .zero, radius: 1 - r))
            return inversionLimitSet(of: mirrors, count: budget / 3)
        default:
            return kleinianLimitSet(.lace).points
        }
    }

    // The one plotting function. Fit the cloud to its panel, then lay every
    // point down at the same low alpha so that crowding is what makes a
    // region bright.
    func plot(_ cloud: [Vector2], in frame: Rectangle, ink: Color) {
        fill(ink.withAlpha(inkAlpha))
        drawPoints(fitted(cloud, in: frame), size: dotSize)
    }

    func label(_ index: Int, in frame: Rectangle) {
        let names = ["a chaos game", "a chaotic map", "circles as mirrors", "a Kleinian group"]
        fill(Color(hex: 0x8A8FA0))
        textFont(OutlineFont.systemMedium)
        textSize(20)
        textAlign(.left, .top)
        drawText(names[index], frame.x + 4, frame.y + 4)
    }
}
