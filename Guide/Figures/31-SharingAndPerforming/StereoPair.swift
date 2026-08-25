// figure: frame=0 themed
//
// Guide listing (Chapter 31): what the two numbers of a stereo pair do, seen
// from above. Two eyes a fixed distance apart look parallel at a screen placed
// at the convergence distance. Each object has a line drawn from each eye
// through it, and where those lines cross the screen is where that eye sees the
// object. On the screen the two land together. Nearer, the lines have already
// crossed by the time they arrive, so the left eye's mark sits to the right of
// the right eye's. Farther, they spread the other way. The page cannot show
// depth, so this shows the geometry that makes depth instead.
import Foundation
import Ollin
import OllinDiagram

final class StereoPair: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    /// The plan view, in canvas points: the eyes low down, the screen across.
    private let eyeY = 470.0
    private let screenY = 250.0
    private let centerX = 440.0
    private let interocular = 64.0

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    private var ink: Color { theme.ink }
    private var quiet: Color { Color(hex: darkTheme ? 0x9A958D : 0x6B6459) }
    private let near = Color(hex: 0xC24A4A)
    private let far = Color(hex: 0x3E7CB1)
    private let onScreen = Color(hex: 0x4F8F5B)

    private var leftEye: Vector2 { Vector2(centerX - interocular / 2, eyeY) }
    private var rightEye: Vector2 { Vector2(centerX + interocular / 2, eyeY) }

    override func draw() {
        background(paper)
        noStroke()
        textFont(OutlineFont.systemMedium)

        screen()
        object(at: Vector2(640, 128), color: far, name: "farther",
               note: "the marks spread apart", labelAt: Vector2(640, 66), align: .center)
        object(at: Vector2(470, screenY), color: onScreen, name: "at the screen",
               note: "the marks land together", labelAt: Vector2(496, 268), align: .left)
        object(at: Vector2(296, 352), color: near, name: "nearer",
               note: "the marks cross over", labelAt: Vector2(296, 372), align: .center)
        eyes()
    }

    /// The screen: the plane at the convergence distance, and the one place the
    /// two eyes are aimed to agree.
    private func screen() {
        withState {
            stroke(Color(hex: 0xB7B1A6))
            strokeWeight(1.5)
            drawLine(56, screenY, 824, screenY)

            // The distance being named, measured where it is measured from.
            stroke(Color(hex: 0xCFC8BC))
            strokeWeight(1)
            drawLine(86, eyeY, 86, screenY)
            drawLine(78, eyeY, 94, eyeY)
            drawLine(78, screenY, 94, screenY)

            noStroke()
            fill(quiet)
            textSize(15)
            withState {
                translate(76, (eyeY + screenY) / 2)
                rotate(-.pi / 2)
                textAlign(.center, .bottom)
                drawText("convergence", 0, 0)
            }
            fill(ink)
            textSize(16)
            textAlign(.right, .bottom)
            drawText("the screen", 820, screenY - 12)
        }
    }

    /// One object, and where each eye puts it on the screen.
    ///
    /// Each line runs from an eye through the object and a little way past, so
    /// the crossing on the screen is part of the same line rather than a
    /// separate claim. Nothing here is a special case: the three objects differ
    /// only in where they stand.
    private func object(at point: Vector2, color: Color, name: String,
                        note: String, labelAt: Vector2, align: TextAlignH) {
        let stop = min(point.y, screenY) - 28
        let eyes = [(leftEye, "L"), (rightEye, "R")]
        let marks = eyes.map { eye, _ -> Vector2 in
            let travel = (screenY - eye.y) / (point.y - eye.y)
            return Vector2(eye.x + travel * (point.x - eye.x), screenY)
        }

        withState {
            stroke(color.withAlpha(0.55))
            strokeWeight(1.2)
            for (eye, _) in eyes {
                let travel = (stop - eye.y) / (point.y - eye.y)
                drawLine(eye, Vector2(eye.x + travel * (point.x - eye.x), stop))
            }

            // Where each eye lands, named, because which mark is which is the
            // whole difference between something in front of the screen and
            // something behind it.
            noStroke()
            fill(color)
            for mark in marks { drawRect(center: mark, width: 3, height: 14) }
            let spread = abs(marks[1].x - marks[0].x)
            textSize(13)
            textAlign(.center, .bottom)
            if spread > 5 {
                for (mark, label) in zip(marks, eyes.map(\.1)) {
                    drawText(label, mark.x, screenY - 11)
                }
            } else {
                // Both eyes land in the same place, so there is one mark to name.
                drawText("L R", marks[0].x, screenY - 11)
            }
            if spread > 5 {
                stroke(color)
                strokeWeight(2.5)
                drawLine(Vector2(min(marks[0].x, marks[1].x), screenY + 12),
                         Vector2(max(marks[0].x, marks[1].x), screenY + 12))
            }

            noStroke()
            fill(color)
            drawCircle(point.x, point.y, 9)
            fill(ink)
            textSize(17)
            textAlign(align, .top)
            drawText(name, labelAt.x, labelAt.y)
            fill(quiet)
            textSize(14)
            drawText(note, labelAt.x, labelAt.y + 23)
        }
    }

    /// The pair itself: two eyes a measured distance apart, looking parallel.
    private func eyes() {
        withState {
            // Parallel, not toed in. The lines run straight up the page.
            stroke(Color(hex: 0xC3BCB0))
            strokeWeight(1)
            for eye in [leftEye, rightEye] { drawLine(eye.x, eye.y, eye.x, 336) }

            noStroke()
            fill(ink)
            for eye in [leftEye, rightEye] { drawCircle(eye.x, eye.y, 11) }

            stroke(ink)
            strokeWeight(1.5)
            drawLine(leftEye.x, eyeY + 28, rightEye.x, eyeY + 28)
            drawLine(leftEye.x, eyeY + 22, leftEye.x, eyeY + 34)
            drawLine(rightEye.x, eyeY + 22, rightEye.x, eyeY + 34)

            noStroke()
            fill(ink)
            textSize(16)
            textAlign(.center, .top)
            drawText("interocular", centerX, eyeY + 40)
            fill(quiet)
            textSize(14)
            textAlign(.right, .middle)
            drawText("left eye", leftEye.x - 18, eyeY)
            textAlign(.left, .middle)
            drawText("right eye", rightEye.x + 18, eyeY)
        }
    }
}
