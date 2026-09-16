// figure: frame=0 themed
//
// Guide diagram (Chapter 1): what `ollin doctor` is for. Each line of the
// report is a question a broken setup would otherwise answer somewhere else
// entirely, so the right column names the failure the line replaces.
import Ollin
import OllinDiagram

final class CheckingTheMachine: Sketch {
    override var canvasSize: CanvasSize { .size(940, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// One reported answer: its mark, the line as printed, the note or fix
    /// under it, and the failure that line is standing in for.
    struct Answer {
        var mark: String
        var settled: Bool
        var line: String
        var under: String
        var isFix: Bool
        var instead: String
    }

    let answers: [Answer] = [
        Answer(mark: "ok", settled: true,
               line: "The Swift compiler: Swift 6.4",
               under: "/Applications/Xcode.app/.../usr/bin/swiftc", isFix: false,
               instead: "an error in a file you never wrote"),
        Answer(mark: "ok", settled: true,
               line: "The Metal device: Apple M2",
               under: "ray tracing, mesh shaders, temporal scaling", isFix: false,
               instead: "a capability that quietly does nothing"),
        Answer(mark: "ok", settled: true,
               line: "The shader compiler: compiles on this device",
               under: "", isFix: false,
               instead: "a window that never opens"),
        Answer(mark: "--", settled: false,
               line: "The ollin command: not on your PATH",
               under: "fix: Scripts/ollin install", isFix: true,
               instead: "command not found, three folders away"),
        Answer(mark: "--", settled: false,
               line: "The camera: refused",
               under: "fix: System Settings > Privacy & Security > Camera", isFix: true,
               instead: "a black frame"),
    ]

    override func draw() {
        background(theme.paper)
        textFont(.system)

        textFont(.systemMono)
        drawText("$ ollin doctor", 40, 44, size: 17, color: theme.muted, align: .left, .middle)
        textFont(.system)
        drawText("the failure it saves you from", 600, 44,
                 size: 17, color: theme.ink, align: .left, .middle)

        let card = Rectangle(x: 40, y: 72, width: 478, height: 356)
        withState {
            fill(theme.card)
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(card, cornerRadius: 10)
        }

        for (index, answer) in answers.enumerated() {
            let y = 110.0 + Double(index) * 68
            report(answer, y: y, in: card)
            leader(from: card.x + card.width + 14, to: 592, y: y)
            drawText(answer.instead, 600, y,
                     size: 16, color: theme.ink, align: .left, .middle)
        }

        legend(y: 470)
        diagramCaption("every line is a question a broken setup answers somewhere else",
                       at: 514, theme: theme)
    }

    /// One printed line: the mark in its own column, then the answer, then
    /// whatever the report puts under it.
    private func report(_ answer: Answer, y: Double, in card: Rectangle) {
        textFont(.systemMono)
        drawText(answer.mark, card.x + 24, y,
                 size: 15, color: answer.settled ? theme.muted : theme.accent,
                 align: .left, .middle)
        drawText(answer.line, card.x + 66, y, size: 15, color: theme.ink, align: .left, .middle)
        if !answer.under.isEmpty {
            drawText(answer.under, card.x + 66, y + 22, size: 13,
                     color: answer.isFix ? theme.accent : theme.muted,
                     align: .left, .middle)
        }
        textFont(.system)
    }

    /// The faint run of dots that ties a report line to the failure it replaces.
    private func leader(from x1: Double, to x2: Double, y: Double) {
        withState {
            noStroke()
            fill(theme.ink(0.22))
            var x = x1
            while x < x2 {
                drawCircle(x, y, 1.2)
                x += 7
            }
        }
    }

    /// What the three marks mean, which is the whole of how the report is read.
    private func legend(y: Double) {
        let marks: [(String, String, Bool)] = [
            ("ok", "settled", true),
            ("--", "worth knowing, nothing waiting on it", false),
            ("no", "would stop a sketch, and exits nonzero", false),
        ]
        textSize(15)
        var x = 40.0
        for (mark, meaning, settled) in marks {
            textFont(.systemMono)
            drawText(mark, x, y, size: 15,
                     color: settled ? theme.muted : theme.accent, align: .left, .middle)
            textFont(.system)
            let label = "  \(meaning)"
            drawText(label, x + 24, y, size: 15, color: theme.muted, align: .left, .middle)
            x += 24 + textWidth(label) + 34
        }
    }
}
