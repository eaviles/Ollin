// figure: frame=0 themed
//
// Guide diagram (Chapter 9): what a sketch reads while a pushed feed listens.
// One row of messages at the moments the server sent them, under it the
// connection the feed keeps alive by itself, and under that what the sketch
// reads: everything the connection was up for at the moment it was said, and
// the message from the blink arriving right after the redial rather than
// being lost.
import Ollin
import OllinDiagram

final class MessagesThatPushThemselves: Sketch {
    override var canvasSize: CanvasSize { .size(880, 570) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.12) }
    var quiet: Color { theme.ink(0.45) }
    var accent: Color { theme.accent }
    var good: Color { Color(hex: darkTheme ? 0x5BAD9C : 0x3E7C74) }

    /// The moments the server had something to say. One of them lands while
    /// the connection is down, and that is the one the diagram is about.
    let saidAt: [Double] = [0.6, 1.3, 1.7, 3.4, 6.6, 7.3]
    let blink = 3.4

    /// The connection: up, dropped, two failed redials with widening waits,
    /// then up again.
    let dropAt = 2.6
    let redials: [(at: Double, works: Bool)] = [(3.1, false), (4.1, false), (6.1, true)]
    let reopenAt = 6.1

    let span = 8.0
    var left: Double { 78 }
    var right: Double { width - 46 }

    func x(_ at: Double) -> Double { left + at / span * (right - left) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // The three rows share one time axis, and the two moments that matter
        // are where the connection drops and where it is back.
        drawMoment(at: dropAt, from: 132, to: 470)
        drawMoment(at: reopenAt, from: 132, to: 470)

        drawSaid(axis: 140)
        drawConnection(labelAt: 246, axis: 306)
        drawRead(labelAt: 396, axis: 452)
        drawClosingNote(top: 502)
    }

    func drawMoment(at when: Double, from top: Double, to bottom: Double) {
        stroke(ink.withAlpha(0.08))
        strokeWeight(1)
        drawLine(x(when), top, x(when), bottom)
    }

    // MARK: What the server said, when it said it

    func drawSaid(axis y: Double) {
        withState {
            noStroke()
            fill(ink)
            textSize(17)
            textAlign(.left, .baseline)
            drawText("Every message the server sends", left, 52)

            fill(quiet)
            textSize(13)
            drawText("no schedule: each one goes out the moment something happens", left, 76)
        }

        stroke(faint)
        strokeWeight(1)
        drawLine(left, y, x(span), y)

        for at in saidAt {
            withState {
                noStroke()
                fill(at == blink ? accent : good)
                drawCircle(x(at), y, 7)
            }
        }

        withState {
            noStroke()
            fill(accent)
            textSize(11)
            textAlign(.center, .baseline)
            drawText("said into the blink", x(blink), y - 16)
        }
    }

    // MARK: The connection the feed keeps alive

    func drawConnection(labelAt labelY: Double, axis y: Double) {
        label("the connection", at: labelY,
              note: "the feed redials on its own; the sketch never has to")

        stroke(faint)
        strokeWeight(1)
        drawLine(left, y, x(span), y)

        // Up, down, up: the band is only drawn while the socket is open.
        stroke(good)
        strokeWeight(5)
        drawLine(x(0), y, x(dropAt), y)
        drawLine(x(reopenAt), y, x(span), y)

        for redial in redials where !redial.works {
            let px = x(redial.at)
            stroke(accent)
            strokeWeight(2)
            drawLine(px - 5, y - 5, px + 5, y + 5)
            drawLine(px - 5, y + 5, px + 5, y - 5)
        }

        // The widening waits between redials, drawn as the gaps they are.
        let rule = y + 24
        for (from, to, note) in [(dropAt, 3.1, "wait"), (3.1, 4.1, "twice"), (4.1, reopenAt, "four times")] {
            stroke(accent.withAlpha(0.5))
            strokeWeight(1)
            drawLine(x(from), rule, x(to), rule)
            drawLine(x(from), rule - 4, x(from), rule + 4)
            drawLine(x(to), rule - 4, x(to), rule + 4)
            withState {
                noStroke()
                fill(accent.withAlpha(0.85))
                textSize(11)
                textAlign(.center, .top)
                drawText(note, (x(from) + x(to)) / 2, rule + 7)
            }
        }

        // The greeting rides every open, which is what keeps a subscription
        // alive across the blink.
        for at in [0.0, reopenAt] {
            stroke(quiet)
            strokeWeight(1.5)
            drawLine(x(at), y - 22, x(at), y - 8)
            withState {
                noStroke()
                fill(quiet)
                textSize(11)
                textAlign(at == 0 ? .left : .center, .baseline)
                drawText("greeting", at == 0 ? x(at) - 2 : x(at), y - 28)
            }
        }
    }

    // MARK: What the sketch reads

    func drawRead(labelAt labelY: Double, axis y: Double) {
        label("messages()", at: labelY,
              note: "everything since the last frame, oldest first")

        stroke(faint)
        strokeWeight(1)
        drawLine(left, y, x(span), y)

        for at in saidAt where at != blink {
            withState {
                noStroke()
                fill(good)
                drawCircle(x(at), y, 7)
            }
        }

        // The message from the blink arrives right after the redial: the
        // stream was resumed from the last id seen, so it was kept, not lost.
        let arrived = reopenAt + 0.12
        withState {
            noFill()
            stroke(accent)
            strokeWeight(2)
            drawCircle(x(arrived), y, 7)

            stroke(accent.withAlpha(0.45))
            strokeWeight(1)
            drawLine(x(blink), y, x(arrived) - 11, y)
            drawLine(x(arrived) - 17, y - 4, x(arrived) - 11, y)
            drawLine(x(arrived) - 17, y + 4, x(arrived) - 11, y)
        }
        withState {
            noStroke()
            fill(accent)
            textSize(11)
            textAlign(.center, .top)
            drawText("resumed by its id, late but not lost", x(arrived), y + 13)
        }

        // The problem read lights for exactly the stretch the connection is
        // down, and nothing already read goes away.
        withState {
            noStroke()
            fill(accent.withAlpha(0.16))
            drawRect(corner: Vector2(x(dropAt), y - 46), width: x(reopenAt) - x(dropAt), height: 18)
            fill(accent)
            textSize(11)
            textAlign(.left, .middle)
            drawText("problem: the connection closed", x(dropAt) + 9, y - 37)
        }
    }

    func label(_ name: String, at y: Double, note: String) {
        withState {
            noStroke()
            fill(ink)
            textSize(15)
            textAlign(.left, .baseline)
            drawText(name, left, y)
            let width = textWidth(name)

            fill(quiet)
            textSize(12)
            drawText(note, left + width + 12, y)
        }
    }

    // MARK: The line under it all

    func drawClosingNote(top: Double) {
        withState {
            noStroke()
            fill(ink)
            textSize(13)
            textAlign(.left, .top)
            drawText("A piece on a wall outlives any socket, so the redialing is the feed's job.",
                     left, top)
            drawText("The sketch reads what arrived, and says what is happening.",
                     left, top + 22)
        }
    }
}
