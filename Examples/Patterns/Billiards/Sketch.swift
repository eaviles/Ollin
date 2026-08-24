import Ollin

/// **Billiards**: one rule, four rooms, four completely different pictures.
///
/// A ball goes straight until it meets the wall, then leaves at the angle it
/// arrived at. That is the whole of it. Everything you see is the shape of the
/// room talking.
///
/// The circle keeps every chord the same distance from the middle, so the path
/// wraps a smaller circle it can never enter, and the hole in the middle is
/// that circle. The ellipse sorts paths into two kinds by whether they pass
/// between the two foci, and you can watch a path stay on its own side of that
/// line forever. The stadium is a circle cut in half and pulled apart, and the
/// hole disappears: the path fills the room. The square with a post in it does
/// the same for the same reason.
///
/// Try it: `spread` sends a fan of balls off at slightly different angles. In
/// the two orderly rooms they stay a fan. In the two disorderly ones they are
/// strangers within a dozen bounces, which is the whole difference between the
/// left half of this picture and the right.
@main
final class BilliardsSketch: Sketch {
    @Param(20 ... 600, icon: "arrow.triangle.turn.up.right.diamond") var bounces = 260.0
    @Param(1 ... 9, icon: "line.3.horizontal") var balls = 3.0
    @Param(0 ... 0.4, icon: "angle") var spread = 0.06
    @Param(0 ... 1, icon: "arrow.clockwise") var aim = 0.31

    private let paper = Color(hex: 0x10131A)
    private let chalk = Color(hex: 0xF2ECDD)
    private let warm = Color(hex: 0xE0724A)
    private let cool = Color(hex: 0x5A8FC7)

    override func draw() {
        background(paper)

        let cell = Vector2(width / 2, height / 2)
        let radius = min(cell.x, cell.y) * 0.36
        // Where a ball is let go matters as much as the room. In a circle it
        // sets how big the hole in the middle is, and starting at the middle
        // leaves no hole at all. In the room with a post, the middle is inside
        // the post, where a ball would be trapped.
        let topLeft = Vector2(cell.x * 0.5, cell.y * 0.52)
        let topRight = Vector2(cell.x * 1.5, cell.y * 0.52)
        let lowLeft = Vector2(cell.x * 0.5, cell.y * 1.46)
        let lowRight = Vector2(cell.x * 1.5, cell.y * 1.46)
        let half = radius * 0.94

        let rooms: [(String, Billiard, Vector2, Vector2)] = [
            ("a circle: a hole in the middle it can never enter",
             Billiard(.circle(Circle(center: topLeft, radius: radius))),
             topLeft, topLeft + Vector2(0, -radius * 0.62)),
            ("an ellipse: two kinds of path, decided by the foci",
             Billiard(.ellipse(center: topRight, radii: Vector2(radius * 1.25, radius * 0.72))),
             topRight, topRight + Vector2(0, -radius * 0.36)),
            ("a stadium: pull the halves apart and the hole goes",
             Billiard(.stadium(center: lowLeft, straight: radius * 1.1, radius: radius * 0.82)),
             lowLeft, lowLeft + Vector2(0, -radius * 0.4)),
            ("a square with a post: the same thing happens",
             Billiard(.polygon(square(around: lowRight, half: half)),
                      obstacles: [Circle(center: lowRight, radius: radius * 0.3)]),
             lowRight, lowRight + Vector2(-half * 0.62, -half * 0.44)),
        ]

        for (index, room) in rooms.enumerated() {
            drawRoom(room.1, at: room.2, from: room.3, caption: room.0, warmer: index >= 2)
        }
    }

    private func square(around center: Vector2, half: Double) -> Contour {
        Contour([center + Vector2(-half, -half), center + Vector2(half, -half),
                 center + Vector2(half, half), center + Vector2(-half, half)], closed: true)
    }

    private func drawRoom(_ room: Billiard, at center: Vector2, from start: Vector2,
                          caption: String, warmer: Bool) {
        // The room itself.
        noFill()
        stroke(chalk.withAlpha(0.28))
        strokeWeight(1.6)
        let outline = room.outline()
        drawPolyline(outline.points, closed: outline.isClosed)
        for post in room.obstacles { drawCircle(post) }
        for focus in room.foci {
            fill(chalk.withAlpha(0.35))
            noStroke()
            drawCircle(focus.x, focus.y, 3)
            noFill()
        }

        // The balls, let go from the same place a hair apart.
        let count = Int(balls.rounded())
        strokeWeight(0.9)
        for ball in 0 ..< count {
            let offset = count > 1 ? (Double(ball) / Double(count - 1) - 0.5) * spread : 0
            let heading = aim * .tau + offset
            let path = room.path(from: start, heading: heading, bounces: Int(bounces))
            guard path.count > 2 else { continue }
            let tone = count > 1 ? Double(ball) / Double(count - 1) : 0.5
            stroke(Color.mix(warmer ? warm : cool, chalk, t: tone).withAlpha(0.4))
            drawPolyline(path)
        }

        textSize(15)
        textAlign(.center)
        fill(chalk.withAlpha(0.5))
        drawText(caption, center.x, center.y + height * 0.2)
    }
}
