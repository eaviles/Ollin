// figure: frame=0
//
// Guide diagram (Chapter 13): diffusion-limited aggregation. Left, the rule:
// a walker wanders in from anywhere and freezes at its first touch of the
// cluster. Right, what thousands of such arrivals build: dendrites, because
// the tips always touch first.
import Ollin

final class FrozenWalkers: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    var smallCluster: DiffusionLimitedAggregation!
    var bigCluster: DiffusionLimitedAggregation!
    var walk: [Vector2] = []

    override func setup() {
        let left = panel(0), right = panel(1)

        smallCluster = DiffusionLimitedAggregation(
            seeds: [Vector2(left.x + 185, left.y + 210)], particleRadius: 5, seed: 4)
        smallCluster.step(60)

        bigCluster = DiffusionLimitedAggregation(
            seeds: [Vector2(right.x + 185, right.y + 170)], particleRadius: 2.3,
            bounds: right.inset(by: .all(10)), seed: 12)
        bigCluster.step(780)

        // An illustrative random walk drifting in until it touches the small
        // cluster (drawn by hand so the path itself is visible).
        // The right panel freezes eight hundred of them.
        var rng = SplitMix64(seed: 21)
        var p = Vector2(left.x + 40, left.y + 40)
        walk = [p]
        while walk.count < 4000 {
            let angle = Double.random(in: 0 ..< .tau, using: &rng)
            // A gentle inward pull keeps the illustration inside the panel.
            let inward = (smallCluster.particles[0].position - p).normalized * 2.2
            p += Vector2(angle: angle, length: 7) + inward
            p = Vector2(min(max(p.x, left.x + 14), left.x + left.width - 14),
                        min(max(p.y, left.y + 14), left.y + left.height - 14))
            walk.append(p)
            if smallCluster.positions.contains(where: { p.distance(to: $0) < 12 }) { break }
        }
    }

    func panel(_ i: Int) -> Rectangle {
        Rectangle(x: 50 + Double(i) * 420, y: 60, width: 370, height: 340)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)

        // Left: the rule.
        let left = panel(0)
        frame(left, title: "a walker wanders in, freezes at first touch")
        noStroke()
        fill(ink)
        drawCircles(smallCluster.positions, radius: 5)
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawPolyline(walk)
        noStroke()
        fill(accent)
        if let last = walk.last { drawCircle(center: last, radius: 6) }
        label("frozen", (walk.last ?? .zero) + Vector2(-46, 4), color: accent)

        // Right: what that builds.
        let right = panel(1)
        frame(right, title: "eight hundred arrivals later")
        noStroke()
        fill(ink)
        drawCircles(bigCluster.positions, radius: 2.3)

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("tips touch first, so tips grow: the hollows never fill", width / 2, 428)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }

    func label(_ text: String, _ at: Vector2, color: Color? = nil) {
        noStroke()
        fill(color ?? faint)
        textAlign(.center, .middle)
        drawText(text, at: at)
    }
}
