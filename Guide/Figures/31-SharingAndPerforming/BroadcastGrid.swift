// figure: frame=0 themed
//
// Guide diagram (Chapter 31): the named frame rates, and the grid a broadcast
// asks for. Every number here is read from `FrameRate` itself: the fraction a
// name keeps, the decimal it is said as, and the frames a ten-second export
// writes. Under the table, one second of a clip at three rates with a tick per
// frame, and a loupe on the second mark, where the thirtieth NTSC frame lands a
// millisecond past the second because that is where the fraction puts it. At
// the foot, an hour of frames written at a plain 30 against the same frames on
// the exact fraction, worked out from the two rates.
import Foundation
import Ollin
import OllinDiagram

final class BroadcastGrid: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let named: [(spelling: String, rate: FrameRate, which: String)] = [
        (".film", .film, "film"),
        (".pal", .pal, "PAL and SECAM video"),
        (".ntsc", .ntsc, "NTSC video, the 29.97 of broadcast"),
        (".ntscFilm", .ntscFilm, "film slowed for NTSC"),
        (".ntscDouble", .ntscDouble, "NTSC at double rate"),
    ]

    override func draw() {
        background(theme.paper)
        textFont(.system)

        // The table: what each name keeps, read from the type.
        let top = 44.0, rowH = 24.0
        let cols = [50.0, 150.0, 262.0, 362.0, 478.0, 594.0]
        let heads = ["name", "the fraction", "as said", "exactly", "frames in 10 s", "which is"]
        for (c, head) in heads.enumerated() {
            drawText(head, cols[c], top, size: 12, color: theme.muted, align: .left, .middle)
        }
        stroke(theme.border)
        strokeWeight(1)
        drawLine(cols[0], top + 13, 840, top + 13)
        for (i, entry) in named.enumerated() {
            let y = top + 30 + Double(i) * rowH
            let r = entry.rate
            drawText(entry.spelling, cols[0], y, size: 14, color: theme.ink, align: .left, .middle)
            drawText("\(r.frames)/\(r.seconds)", cols[1], y, size: 14, color: theme.ink, align: .left, .middle)
            drawText(r.description, cols[2], y, size: 14, color: theme.ink, align: .left, .middle)
            drawText(String(format: "%.5f", r.framesPerSecond), cols[3], y, size: 13,
                     color: theme.muted, align: .left, .middle)
            drawText("\(r.frames(in: 10))", cols[4], y, size: 14, color: theme.ink, align: .left, .middle)
            drawText(entry.which, cols[5], y, size: 13, color: theme.muted, align: .left, .middle)
        }

        // One second of a clip at three rates, a tick per frame.
        let laneX0 = 120.0, laneX1 = 560.0, secondY = 232.0
        let lanes: [(FrameRate, Double)] = [(.film, secondY), (.pal, secondY + 34), (.ntsc, secondY + 68)]
        drawText("one second of a clip", laneX0, secondY - 30, size: 12, color: theme.muted, align: .left, .middle)
        func px(_ seconds: Double) -> Double { laneX0 + seconds * (laneX1 - laneX0) }
        for (rate, y) in lanes {
            drawText(spelling(of: rate), laneX0 - 14, y, size: 14, color: theme.ink, align: .right, .middle)
            stroke(theme.ink(0.5))
            strokeWeight(1)
            drawLine(laneX0, y, laneX1 + 24, y)
            var k = 0
            while rate.seconds(for: k) <= 1.03 {
                let t = rate.seconds(for: k)
                stroke(k == rate.frames(in: 1) ? theme.accent : theme.ink(0.7))
                strokeWeight(k == rate.frames(in: 1) ? 2 : 1)
                drawLine(px(t), y - 7, px(t), y + 7)
                k += 1
            }
            drawText("frame \(rate.frames(in: 1))", laneX1 + 32, y, size: 12, color: theme.muted,
                     align: .left, .middle)
        }
        // The second mark, across the lanes.
        stroke(theme.accent(0.6))
        strokeWeight(1)
        drawLine(px(1), secondY - 16, px(1), secondY + 84)
        drawText("frame 0", laneX0, secondY + 92, size: 12, color: theme.muted, align: .center, .top)
        drawText("1 s", px(1), secondY + 92, size: 12, color: theme.muted, align: .center, .top)

        // The loupe: eight milliseconds around the second mark, where a
        // millisecond is wide enough to see.
        let loupe = Rectangle(x: 700, y: secondY - 28, width: 150, height: 124)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(loupe, cornerRadius: 8)
        let msWide = loupe.width / 8
        func lx(_ seconds: Double) -> Double { loupe.x + loupe.width / 2 + (seconds - 1) * 1000 * msWide }
        stroke(theme.accent(0.6))
        strokeWeight(1)
        drawLine(lx(1), loupe.y + 8, lx(1), loupe.y + loupe.height - 22)
        for (rate, y) in lanes {
            let k = rate.frames(in: 1)
            let t = rate.seconds(for: k)
            stroke(theme.accent)
            strokeWeight(2)
            drawLine(lx(t), y - 7, lx(t), y + 7)
            noStroke()
            let off = (t - 1) * 1000
            let said = off == 0 ? "on the second" : String(format: "+%.0f ms", off)
            drawText(said, lx(t) + 8, y, size: 11, color: theme.muted, align: .left, .middle)
        }
        noStroke()
        drawText("eight milliseconds, under a loupe", loupe.center.x, loupe.y + loupe.height - 10,
                 size: 10.5, color: theme.muted, align: .center, .middle)
        stroke(theme.ink(0.25))
        strokeWeight(1)
        drawLine(px(1) + 4, secondY - 16, loupe.x, loupe.y + 8)
        drawLine(px(1) + 4, secondY + 84, loupe.x, loupe.y + loupe.height - 8)

        // An hour of frames, on a plain 30 and on the fraction.
        let hourY = 372.0
        let plain = FrameRate(30)
        let hourOfFrames = plain.frames(in: 3600)
        let onFraction = FrameRate.ntsc.seconds(for: hourOfFrames)
        let onDecimal = FrameRate(29.97).seconds(for: hourOfFrames)
        noStroke()
        drawText("an hour of frames, \(hourOfFrames) of them", 50, hourY, size: 12,
                 color: theme.muted, align: .left, .middle)
        let lines = [
            ("at 30", "3600.0 s", "the rate the writer rounds to when it is not told the fraction"),
            ("at .ntsc", String(format: "%.1f s", onFraction),
             String(format: "%.1f s later: %d frames of drift on the timeline", onFraction - 3600,
                    plain.frames(in: onFraction - 3600))),
            ("at FrameRate(29.97)", String(format: "%.4f s", onDecimal),
             String(format: "%.1f ms off .ntsc, one part in a million", (onDecimal - onFraction) * 1000)),
        ]
        for (i, line) in lines.enumerated() {
            let y = hourY + 28 + Double(i) * 26
            drawText(line.0, 50, y, size: 14, color: theme.ink, align: .left, .middle)
            drawText(line.1, 230, y, size: 14, color: theme.ink, align: .left, .middle)
            drawText(line.2, 360, y, size: 12.5, color: theme.muted, align: .left, .middle)
        }

        diagramCaption("a named rate is its fraction, so every frame sits on the timeline's grid",
                       at: 486, theme: theme)
        drawText("the window runs at the display's rate, not one of these; frameRate on the sketch reads what it measured",
                 width / 2, 516, size: 13, color: theme.muted, align: .center, .top)
    }

    private func spelling(of rate: FrameRate) -> String {
        named.first(where: { $0.rate == rate })?.spelling ?? rate.description
    }
}
