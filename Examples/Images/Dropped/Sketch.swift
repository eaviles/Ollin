import Ollin

/// Drop a picture on the window. The sketch starts as an empty frame with a
/// prompt, and every picture dropped on it lands where it was dropped, a
/// little turned, on top of the ones before. `droppedFiles()` hands over the
/// paths, `mouseX`/`mouseY` say where they landed, and `loadImage` reads
/// anything the system can decode; a file that is not a picture is named in
/// the corner instead. Press any key to clear the table.
@main
final class Dropped: Sketch {

    struct Placed {
        var picture: Image
        var at: Vector2
        var turn: Double
        var scale: Double
    }

    @Param("Size", 0.2 ... 1, icon: "photo", group: "Table") var size = 0.5
    @Param("Tilt", 0 ... 0.4, icon: "rotate.right", group: "Table") var tilt = 0.12

    private var placed: [Placed] = []
    private var refused: [String] = []

    override func filesDropped() {
        // Files come as paths; each is either a picture, placed at the drop,
        // or something else, named so the drop is never silent.
        for path in droppedFiles() {
            if let picture = loadImage(path) {
                placed.append(Placed(picture: picture, at: mouse, turn: random(-tilt, tilt),
                                     scale: random(0.85, 1.15)))
            } else {
                refused.append(path.split(separator: "/").last.map(String.init) ?? path)
                if refused.count > 4 { refused.removeFirst() }
            }
        }
    }

    override func keyPressed() {
        placed.removeAll()
        refused.removeAll()
    }

    override func draw() {
        background(Color(hex: 0x1C1A1F))

        if placed.isEmpty {
            // The prompt: a dashed frame and a line of text.
            noFill()
            stroke(Color(white: 1, alpha: 0.25))
            strokeWeight(2 * scale)
            let inset = width * 0.12
            drawRect(inset, inset, width - 2 * inset, height - 2 * inset)
            noStroke()
            fill(Color(white: 1, alpha: 0.6))
            textSize(28 * scale)
            textAlign(.center, .middle)
            drawText("drop a picture here", width / 2, height / 2)
        }

        for item in placed {
            let w = width * size * item.scale
            let h = w * Double(item.picture.height) / Double(max(item.picture.width, 1))
            withState {
                translate(item.at)
                rotate(item.turn)
                // A paper border under the picture, and a soft shadow under that.
                noStroke()
                fill(Color(white: 0, alpha: 0.35))
                drawRect(-w / 2 + 8, -h / 2 + 12, w + 16, h + 16)
                fill(.white)
                drawRect(-w / 2 - 8, -h / 2 - 8, w + 16, h + 16)
                drawImage(item.picture, -w / 2, -h / 2, w, h)
            }
        }

        if !refused.isEmpty {
            noStroke()
            fill(Color(hex: 0xE8A33D))
            textSize(16 * scale)
            textAlign(.left, .bottom)
            drawText("not a picture: " + refused.joined(separator: ", "), 24, height - 24)
        }
        drawCaption("Drop pictures from the Finder; any key clears them.")
    }
}
