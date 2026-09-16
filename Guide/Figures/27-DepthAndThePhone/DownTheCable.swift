// figure: frame=0 themed
//
// Guide diagram (Chapter 27): the one conversation that runs from the Mac to the
// phone. A sketch asks for a mode and declares the pictures to look for; the phone
// answers with what it is doing and what it could not use. Then the cable comes out
// and goes back in, and the whole declaration is said again without anybody asking,
// which is the part a reader would otherwise get wrong.
//
// Every frame's byte count is read from the shipped encoder, and the two pictures
// are really fitted for the cable by the shipped rule, so the figure cannot
// disagree with what the wire does.
import Foundation
import Ollin
import OllinDiagram
import OllinPhone
import OllinSamplePhotos

final class DownTheCable: Sketch {
    override var canvasSize: CanvasSize { .size(880, 664) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// One line of the conversation: which way it goes, what it says, and how many
    /// bytes it really is on the wire.
    struct Line {
        let down: Bool
        let kind: String
        let detail: String
        let bytes: Int?
    }

    var lines: [Line] = []
    var replay: [Line] = []

    override func setup() {
        // Two real pictures, fitted for the cable by the shipped rule, so the sizes
        // on the arrows are the sizes that would travel.
        let blankets = PhoneReference.picture(SamplePhoto.textiles.load(),
                                              printedWidth: 0.21, named: "blankets")
        let page = PhoneReference.picture(SamplePhoto.page.load(),
                                          printedWidth: 0.15, named: "page")
        let answer = PhoneStateSample(timestamp: 0, mode: .markers, isSupported: true,
                                      referenceCount: 2, referencesAreDeclared: true,
                                      status: "Looking for what the sketch sent")

        lines = [
            Line(down: true, kind: "mode", detail: "Markers",
                 bytes: PhoneWire.encode(.mode(.markers)).count),
            Line(down: true, kind: "library", detail: "2 references coming",
                 bytes: PhoneWire.encode(.library(count: 2)).count),
            Line(down: true, kind: "reference", detail: "blankets · printed 21 cm across",
                 bytes: blankets.map { PhoneWire.encode(.reference($0)).count }),
            Line(down: true, kind: "reference", detail: "page · printed 15 cm across",
                 bytes: page.map { PhoneWire.encode(.reference($0)).count }),
            Line(down: false, kind: "state", detail: "Markers · looking for 2",
                 bytes: PhoneWire.encode(.state(answer)).count),
        ]
        replay = [
            Line(down: true, kind: "mode", detail: "Markers", bytes: nil),
            Line(down: true, kind: "library", detail: "2 references coming", bytes: nil),
            Line(down: true, kind: "reference", detail: "blankets, then page", bytes: nil),
        ]
    }

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()

        let macX = 168.0
        let phoneX = 712.0

        drawText("the sketch says what to look for, and the phone says what it made of it",
                 40, 26, size: 15, color: theme.ink, align: .left, .top)
        drawText("byte counts are the shipped encoder's own",
                 40, 50, size: 12, color: theme.muted, align: .left, .top)

        // The two ends, and the lifelines under them.
        drawText("the sketch, on the Mac", macX, 92, size: 13, color: theme.ink,
                 align: .center, .middle)
        drawText("Ollin Capture, on the iPhone", phoneX, 92, size: 13, color: theme.ink,
                 align: .center, .middle)
        withState {
            stroke(theme.border)
            strokeWeight(2)
            drawLine(macX, 112, macX, 626)
            drawLine(phoneX, 112, phoneX, 626)
        }

        // The conversation, one arrow a row.
        var y = 150.0
        for line in lines {
            arrow(line, at: y, macX: macX, phoneX: phoneX, theme: theme)
            y += 46
        }
        // What the answer is for, said where the answer lands.
        drawText("with any it could not use, in sentences: the only place",
                 (macX + phoneX) / 2, y - 34, size: 12, color: theme.muted,
                 align: .center, .top)
        drawText("a picture the phone refuses is ever heard about",
                 (macX + phoneX) / 2, y - 18, size: 12, color: theme.muted,
                 align: .center, .top)

        // The break, and the same declaration said again by itself.
        let breakY = y + 34
        withState {
            stroke(theme.accent(0.55))
            strokeWeight(2)
            var x = macX - 40
            while x < phoneX + 40 {
                drawLine(x, breakY, x + 9, breakY)
                x += 18
            }
        }
        drawText("the cable comes out, and goes back in", width / 2, breakY + 12,
                 size: 13, color: theme.accent, align: .center, .top)

        y = breakY + 80
        for line in replay {
            arrow(line, at: y, macX: macX, phoneX: phoneX, theme: theme)
            y += 40
        }
        drawText("nobody asked twice: the sketch declared once, in setup()",
                 width / 2, y - 2, size: 13, color: theme.muted, align: .center, .top)
    }

    /// One arrow across, with its kind, what it says, and its size on the wire.
    private func arrow(_ line: Line, at y: Double, macX: Double, phoneX: Double,
                       theme: DiagramTheme) {
        let color = line.down ? theme.accent : theme.ink(0.75)
        let from = line.down ? macX : phoneX
        let to = line.down ? phoneX : macX
        let head = line.down ? -1.0 : 1.0
        withState {
            stroke(color)
            strokeWeight(line.down ? 2.5 : 1.5)
            drawLine(from, y, to, y)
            drawLine(to, y, to + head * 12, y - 5)
            drawLine(to, y, to + head * 12, y + 5)
        }
        var label = line.kind + " · " + line.detail
        if let bytes = line.bytes { label += "  " + size(bytes) }
        drawText(label, (macX + phoneX) / 2, y - 10, size: 13, color: theme.ink,
                 align: .center, .bottom)
    }

    /// A frame's size the way a person reads one: bytes while it is small, and
    /// kilobytes once a picture is in it.
    private func size(_ bytes: Int) -> String {
        bytes < 2048 ? "\(bytes) bytes" : String(format: "%.0f KB", Double(bytes) / 1024)
    }
}
