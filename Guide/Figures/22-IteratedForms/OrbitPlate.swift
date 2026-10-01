// figure: frame=240 probe
//
// Guide payoff (Chapter 22): a plate of four orbits. Four different iterated
// rules, all of them handed to the same plotting function, because the
// chapter's whole claim is that what you are looking at is the density of an
// orbit rather than a drawn shape. The clouds condense point by point over
// six seconds and then hold for two. The pinned frame is four seconds in,
// with each cloud about a third of the way grown and its newest landings
// bright.
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
    var clouds: [[Vector2]] = []
    var builtFor = 0

    // Six seconds of points landing, then two seconds of the finished plate.
    override var loopDuration: Double? { 8 }

    override func setup() {
        build()
    }

    override func draw() {
        if builtFor != budget { build() }
        background(paper)
        noStroke()

        // How much of each cloud has landed so far. The ease-in keeps the
        // first few hundred points on screen long enough to watch them land,
        // before the flood.
        let seconds = loopProgress(over: 8) * 8
        let grown = Easing.easeInCubic(min(seconds / 6, 1))

        let panels = grid(columns: 2, rows: 2, padding: 70, gutter: 44)
        for (index, cell) in panels.cells.enumerated() {
            let inner = cell.frame.inset(by: .all(26))
            plot(clouds[index], in: inner, ink: ramp.color(at: Double(index) / 3), grown: grown)
            label(index, in: cell.frame)
        }
    }

    // The four clouds are built once, and again only when the point budget
    // moves. The same seed makes the same clouds every time.
    func build() {
        seed(3)
        clouds = (0 ..< 4).map { orbit($0) }
        builtFor = budget
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
            // A contour's points come in order along the curve. Shuffled, they
            // land all over it at once, the way the other three clouds do.
            return shuffled(kleinianLimitSet(.lace).points)
        }
    }

    // The one plotting function. Fit the whole cloud to its panel, then lay
    // down the points that have landed so far, every one at the same low
    // alpha, so that crowding is what makes a region bright. The newest few
    // go down at full ink while the cloud is still growing, so you can watch
    // the game being played.
    func plot(_ cloud: [Vector2], in frame: Rectangle, ink: Color, grown: Double) {
        let placed = fitted(cloud, in: frame)
        let landed = Int(Double(placed.count) * grown)
        let fresh = grown < 1 ? 200 : 0
        fill(ink.withAlpha(inkAlpha))
        drawPoints(Array(placed.prefix(landed)), size: dotSize)
        fill(ink)
        drawPoints(Array(placed.prefix(landed).suffix(fresh)), size: dotSize + 0.5)
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
