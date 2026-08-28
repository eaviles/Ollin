import Ollin

// DragToEdit: move a shape with the pointer and watch the file change.
//
// Run it under the live host, from the repo root:
//
//   swift run OllinLive Examples/Live/DragToEdit/Sketch.swift
//
// Hold Command over the canvas. The shape under the pointer is outlined, with
// the line that drew it named above the outline. Drag it, let go, and the two
// numbers in that line become the numbers you dragged to. The watcher sees the
// save, the sketch recompiles, and the shape is where you left it. The file is
// the only thing that changed, so it is your editor's undo that takes it back.
//
// Every shape below is placed by plain numbers, which is what makes it
// draggable. The last one is placed by an expression instead, deliberately: a
// Command-drag on it says what stands where a number would have to be. That is
// the whole rule. A number can be moved, a calculation cannot.

@main
final class DragToEdit: Sketch {
    override var canvasSize: CanvasSize { .square(720) }

    override func draw() {
        background(Color(hex: 0xF4F1EA))
        noStroke()

        // A face, laid out by hand. Drag any of it.
        fill(Color(hex: 0xE4572E))
        drawCircle(360, 300, 150)

        fill(Color(hex: 0xF4F1EA))
        drawCircle(310, 265, 26)
        drawCircle(415, 265, 26)

        fill(Color(hex: 0x1B1B1B))
        drawCircle(315, 270, 11)
        drawCircle(420, 270, 11)

        // A mouth, and a bar under the whole thing.
        drawRect(315, 350, 90, 14, cornerRadius: 7)
        drawRect(210, 540, 300, 10, cornerRadius: 5)

        // A triangle and a line, to show that the other shapes drag too.
        fill(Color(hex: 0x2E86AB))
        drawTriangle(560, 470, 44)

        stroke(Color(hex: 0x1B1B1B))
        strokeWeight(3)
        drawLine(150, 190, 230, 130)

        // This one is placed by a calculation, so it cannot be dragged. Try it:
        // the host says what stands where the number would be.
        noStroke()
        fill(Color(hex: 0x9BBF3B))
        drawCircle(width - 120, 620, 34)
    }
}
