import Ollin

// DragToEdit: move, resize, and turn a shape with the pointer, and watch the
// file change.
//
// Run it under the live host, from the repo root:
//
//   swift run OllinLive Examples/Live/DragToEdit/Sketch.swift
//
// Hold Command over the canvas. The shape under the pointer is outlined, with
// the line that drew it named above the outline. Then:
//
//   drag the shape          the two numbers that place it become where you left it
//   drag a corner           the numbers that size it grow or shrink
//   drag the knob above it  the shape turns, if the line says which way it faces
//
// Let go and the file is written. The watcher sees the save, the sketch
// recompiles, and the shape is where you left it. The file is the only thing
// that changed, so it is your editor's undo that takes it back.
//
// Most shapes below are placed by plain numbers, which is what makes them
// draggable. Two are not, deliberately: the green dot is placed by a
// calculation, so a drag says what stands where a number would have to be, and
// the yellow one is placed by a parameter's name, so a drag sets that parameter instead
// of writing the file. That is the whole rule. A number can be dragged, a parameter
// can be set, a calculation can be neither.

@main
final class DragToEdit: Sketch {
    override var canvasSize: CanvasSize { .square(720) }

    @Param(60 ... 660) var sunX = 120.0

    override func draw() {
        background(Color(hex: 0xF4F1EA))
        noStroke()

        // A face, laid out by hand. Drag any of it, or a corner of it.
        fill(Color(hex: 0xE4572E))
        drawCircle(360, 300, 150)

        fill(Color(hex: 0xF4F1EA))
        drawCircle(310, 265, 26)
        drawCircle(415, 265, 26)

        fill(Color(hex: 0x1B1B1B))
        drawCircle(315, 270, 11)
        drawCircle(420, 270, 11)

        // A mouth, and a bar under the whole thing. Both are placed by their
        // top-left corner, so that corner stays put while the others resize.
        drawRect(315, 350, 90, 14, cornerRadius: 7)
        drawRect(210, 540, 300, 10, cornerRadius: 5)

        // A triangle and a line, to show that the other shapes drag too. The
        // line has no size on its call, so it offers the turn knob and no
        // corners: it swings about its own middle.
        fill(Color(hex: 0x2E86AB))
        drawTriangle(560, 470, 44)

        stroke(Color(hex: 0x1B1B1B))
        strokeWeight(3)
        drawLine(150, 190, 230, 130)

        // An arc carries its own two angles, so the knob above it turns those.
        noFill()
        strokeWeight(6)
        drawArc(360, 300, 190, 190, start: 0.6, stop: 2.5)

        // This one is placed by a calculation, so it cannot be dragged. Try it:
        // the host says what stands where the number would be.
        noStroke()
        fill(Color(hex: 0x9BBF3B))
        drawCircle(width - 120, 620, 34)

        // And this one is placed by a parameter. Dragging it sets the parameter, which
        // needs no recompile, and leaves the line as it is written.
        fill(Color(hex: 0xF2C14E))
        drawCircle(sunX, 120, 40)
    }
}
