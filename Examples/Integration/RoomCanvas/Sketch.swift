import Foundation
import Ollin
import OllinRoom

/// One piece across several machines. Open this sketch on two Macs on the same
/// network and they find each other by the room's name alone: no server, no
/// address to type, nothing to configure.
///
/// What the room gives the sketch is the whole demonstration:
///
/// - **One clock.** The beads travel along a wall that is `seatCount` canvases
///   wide, driven by `room.time` rather than the sketch's own `time`. Each
///   machine starts whenever it starts, and they still move as one.
/// - **One seat each.** A machine draws the whole wall and slides it by its own
///   seat, so screen 0 shows the left canvas and screen 1 the next one along.
///   Ask for a fixed seat with `Room(named: "wall", seat: 1)` when the machines
///   stand in a known order.
/// - **Shared knobs.** Every `@Param` below travels, so turning `speed` on any
///   machine turns it on all of them.
///
/// With one machine it still runs: one seat, one canvas, and the readout says
/// the room is empty. The system asks for permission to use the local network
/// the first time a sketch opens a room, and a sketch run from a terminal
/// inherits the terminal's answer.
@main
final class RoomCanvas: Sketch {

    @Param(0.2...3.0, group: "Motion") var speed = 1.0
    @Param(4...40, group: "Motion") var beads = 16
    @Param(0.2...1.4, group: "Look") var weight = 0.7
    @Param(group: "Look") var ink = Color(red: 0.98, green: 0.36, blue: 0.24)

    let room = Room(named: "wall")

    private let paper = Color(red: 0.07, green: 0.08, blue: 0.11)

    override func setup() {
        // Every knob travels, so whoever is standing next to a machine can turn
        // one and the whole room follows.
        room.shareAll()
        extend(room)
    }

    override func draw() {
        background(paper)

        let seats = Double(room.seatCount)
        let wall = width * seats

        withState {
            // Each machine draws the whole wall and slides its own seat into view.
            translate(-Double(room.seat) * width, 0)
            drawWall(width: wall)
        }

        drawSeatEdges()
        drawReadout()
    }

    /// The piece itself: a run of beads crossing the whole wall, and a rope
    /// threaded through them.
    private func drawWall(width wall: Double) {
        let clock = room.time * speed
        var path: [Vector2] = []
        for index in 0..<beads {
            let phase = Double(index) / Double(beads)
            let x = ((clock * 0.12 + phase).truncatingRemainder(dividingBy: 1)) * wall
            let y = height * (0.5 + 0.28 * sin(clock * 0.9 + phase * 6.283))
            path.append(Vector2(x, y))
        }

        noFill()
        stroke(ink.withAlpha(0.35))
        strokeWeight(2 * weight)
        for index in 1..<path.count {
            // A bead that wrapped around the end has no line back to the start.
            if path[index].x > path[index - 1].x {
                drawLine(path[index - 1], path[index])
            }
        }

        noStroke()
        for (index, point) in path.enumerated() {
            let phase = Double(index) / Double(beads)
            fill(ink.withAlpha(0.55 + 0.45 * phase))
            drawCircle(center: point, radius: 12 + 26 * weight * (0.4 + 0.6 * phase))
        }
    }

    /// A hairline down each seam, so a wall of screens shows where one machine
    /// ends and the next begins.
    private func drawSeatEdges() {
        guard room.seatCount > 1 else { return }
        stroke(Color.white.withAlpha(0.12))
        strokeWeight(1)
        drawLine(0, 0, 0, height)
        drawLine(width, 0, width, height)
    }

    /// Who is here, which seat this machine has, and how well the clocks agree.
    private func drawReadout() {
        let scale = width / 1080
        let margin = 40 * scale

        noStroke()
        fill(Color.white.withAlpha(0.75))
        textSize(24 * scale)
        drawText("room: wall   seat \(room.seat + 1) of \(room.seatCount)", margin, margin + 24 * scale)

        textSize(19 * scale)
        fill(Color.white.withAlpha(0.5))
        let company = room.isAlone ? "alone: open this sketch on another Mac" : room.peers.joined(separator: ", ")
        drawText("\(room.name)   |   \(company)", margin, margin + 56 * scale)

        let agreement: String
        if let error = room.clockError {
            agreement = room.ownsClock ? "this machine keeps the clock" : String(format: "clock within %.0f ms", error * 1000)
        } else {
            agreement = "asking for the time"
        }
        drawText(agreement, margin, margin + 84 * scale)
        if let problem = room.problem {
            fill(Color(red: 1, green: 0.5, blue: 0.4))
            drawText(problem, margin, margin + 112 * scale)
        }

        // The hand turns once every four seconds on the room's clock, so two
        // machines side by side show it in the same place.
        let hand = room.time * (.pi / 2)
        let center = Vector2(width - margin - 44 * scale, margin + 44 * scale)
        noFill()
        stroke(Color.white.withAlpha(0.25))
        strokeWeight(2 * scale)
        drawCircle(center: center, radius: 40 * scale)
        stroke(ink)
        drawLine(center, center + Vector2(cos(hand), sin(hand)) * (34 * scale))
    }
}
