// figure: frame=0
//
// Guide diagram (Chapter 9): what a sketch reads while a feed is asking. One
// row of requests along a time axis, each labeled with what the server said,
// and under it the two numbers a sketch actually draws from: the count of
// answers that differed, which does not move for a request that brought back
// the same bytes, and the problem, which lights while the requests are failing
// and never takes the last good answer away.
import Ollin

final class NumbersThatKeepArriving: Sketch {
    override var canvasSize: CanvasSize { .size(880, 570) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.12)
    let quiet = Color(hex: 0x2B2B2B, alpha: 0.45)
    let accent = Color(hex: 0xC1553B)
    let good = Color(hex: 0x3E7C74)

    /// What each request came back with, at the minute it landed. The gaps are
    /// the schedule: one interval while things are well, then doubling while
    /// they are not.
    enum Reply { case fresh, unchanged, failed }
    let polls: [(at: Double, reply: Reply, label: String)] = [
        (0, .fresh, "200"),
        (1, .unchanged, "304"),
        (2, .unchanged, "304"),
        (3, .failed, "500"),
        (4, .failed, "500"),
        (6, .failed, "500"),
        (10, .fresh, "200"),
        (11, .unchanged, "304"),
    ]

    let span = 11.5
    var left: Double { 78 }
    var right: Double { width - 46 }

    func x(_ at: Double) -> Double { left + at / span * (right - left) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // The three rows share one time axis, and the two moments that matter
        // are where the failures start and where an answer comes back.
        drawMoment(at: 3, from: 132, to: 470)
        drawMoment(at: 10, from: 132, to: 470)

        drawPolls(axis: 140)
        drawUpdates(labelAt: 246, base: 340)
        drawProblem(labelAt: 412, base: 466)
        drawClosingNote(top: 502)
    }

    func drawMoment(at when: Double, from top: Double, to bottom: Double) {
        stroke(ink.withAlpha(0.08))
        strokeWeight(1)
        drawLine(x(when), top, x(when), bottom)
    }

    // MARK: The requests

    func drawPolls(axis y: Double) {
        withState {
            noStroke()
            fill(ink)
            textSize(17)
            textAlign(.left, .baseline)
            drawText("Every request the feed makes", left, 52)

            fill(quiet)
            textSize(13)
            drawText("the wait doubles while it fails, and goes back to the interval on the next answer",
                     left, 76)
        }

        stroke(faint)
        strokeWeight(1)
        drawLine(left, y, x(span), y)

        for poll in polls {
            let px = x(poll.at)
            withState {
                switch poll.reply {
                case .fresh:
                    noStroke()
                    fill(good)
                    drawCircle(px, y, 7)
                case .unchanged:
                    noFill()
                    stroke(quiet)
                    strokeWeight(1.5)
                    drawCircle(px, y, 6)
                case .failed:
                    stroke(accent)
                    strokeWeight(2)
                    drawLine(px - 5, y - 5, px + 5, y + 5)
                    drawLine(px - 5, y + 5, px + 5, y - 5)
                }
            }
            withState {
                noStroke()
                fill(poll.reply == .failed ? accent : quiet)
                textSize(12)
                textAlign(.center, .baseline)
                drawText(poll.label, px, y - 18)
            }
        }

        // The three widening waits, drawn as the gaps they are.
        let rule = y + 28
        for (from, to, note) in [(3.0, 4.0, "wait"), (4.0, 6.0, "twice"), (6.0, 10.0, "four times")] {
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
    }

    // MARK: What the sketch reads

    func drawUpdates(labelAt labelY: Double, base: Double) {
        label("updates", at: labelY, note: "answers that differed from the one before")

        let step = 26.0
        stroke(faint)
        strokeWeight(1)
        drawLine(left, base, x(span), base)

        // One at the first answer, and one more at the answer that changed.
        noFill()
        stroke(good)
        strokeWeight(2.5)
        drawLine(x(0), base - step, x(10), base - step)
        drawLine(x(10), base - step, x(10), base - step * 2)
        drawLine(x(10), base - step * 2, x(span), base - step * 2)

        withState {
            noStroke()
            fill(quiet)
            textSize(12)
            textAlign(.right, .middle)
            drawText("1", left - 12, base - step)
            drawText("2", left - 12, base - step * 2)
        }

        withState {
            noStroke()
            fill(quiet)
            textSize(11)
            textAlign(.left, .top)
            drawText("the same bytes came back, so nothing moved", x(1), base + 9)
        }
    }

    func drawProblem(labelAt labelY: Double, base: Double) {
        label("problem", at: labelY, note: "why the last request failed, and nil once one arrives")

        stroke(faint)
        strokeWeight(1)
        drawLine(left, base, x(span), base)

        noStroke()
        fill(accent.withAlpha(0.16))
        drawRect(corner: Vector2(x(3), base - 22), width: x(10) - x(3), height: 22)

        withState {
            noStroke()
            fill(accent)
            textSize(11)
            textAlign(.left, .middle)
            drawText("the server answered 500", x(3) + 9, base - 11)
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
            drawText("The last good answer is there the whole time the requests are failing.",
                     left, top)
            drawText("A sketch keeps drawing it, with the notice over the top.",
                     left, top + 22)
        }
    }
}
