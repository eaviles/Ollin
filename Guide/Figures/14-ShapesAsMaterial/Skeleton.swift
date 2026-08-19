// figure: frame=0
//
// Guide diagram (Chapter 14): the medial axis. On the left a lobed blob and
// the skeleton running down the middle of every lobe; on the right the same
// skeleton drawn as the inscribed disks its radii describe, each one kissing
// the outline it came from.
import Ollin

final class Skeleton: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let outline = Color(hex: 0x2B2B2B, alpha: 0.35)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        seed(4)

        let left = Rectangle(x: 45, y: 62, width: 370, height: 300)
        let right = Rectangle(x: 465, y: 62, width: 370, height: 300)

        frame(left, title: "the skeleton: branches down every lobe")
        frame(right, title: "the radii: the disks that fit inside")

        for (i, panel) in [left, right].enumerated() {
            let center = Vector2(panel.x + panel.width / 2,
                                 panel.y + panel.height / 2)
            let shape = Shape(blob(around: center, radius: 108))
            let axis = medialAxis(of: shape, spacing: 3, prune: 14)

            if i == 0 {
                noFill()
                stroke(outline)
                strokeWeight(1.6)
                drawShape(shape)

                stroke(accent)
                strokeWeight(2.6)
                for branch in axis.branches {
                    drawPolyline(branch.points, closed: branch.isClosed)
                }
            } else {
                noFill()
                stroke(accent.withAlpha(0.7))
                strokeWeight(1.2)
                for branch in axis.branches {
                    for (j, point) in branch.points.enumerated()
                    where j % 18 == 0 && branch.radii[j] > 12 {
                        drawCircle(center: point, radius: branch.radii[j])
                    }
                }

                // The outline last, so the disks visibly stop at it.
                noFill()
                stroke(outline)
                strokeWeight(1.6)
                drawShape(shape)
            }
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a shape reduced to its bones, thickness and all",
                 width / 2, 400)
    }

    /// A closed lobed outline: a circle whose radius is walked by noise
    /// sampled around a circle, so the curve closes exactly.
    func blob(around center: Vector2, radius: Double) -> [Vector2] {
        (0 ..< 240).map { i in
            let angle = Double(i) / 240 * .tau
            let wobble = signedNoise(cos(angle) * 0.85 + 3, sin(angle) * 0.85 + 7)
            return center + Vector2(cos(angle), sin(angle)) * (radius * (1 + wobble * 0.36))
        }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
