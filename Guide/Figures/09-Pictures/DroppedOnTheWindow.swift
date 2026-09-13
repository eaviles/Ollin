// figure: frame=0 themed
//
// Guide diagram (Chapter 9): a picture dropped on the window. A file leaves
// the Finder on the left, crosses to the sketch window, and lands where the
// pointer let go: filesDropped() fires once there, with mouseX and mouseY at
// the drop point, droppedFiles() hands over the path, and loadImage reads it.
// A second file that is not a picture is still a path, so the sketch names it
// in the corner rather than losing it. A drop is a gesture a still cannot
// show, so the figure shows what the sketch is told.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class DroppedOnTheWindow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    private var picture = Image(width: 1, height: 1)

    override func setup() {
        picture = SamplePhoto.marigolds.load().resized(width: 400, height: 400)
    }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        // The file, as the Finder shows it.
        let file = Rectangle(x: 64, y: 176, width: 140, height: 168)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(file, cornerRadius: 8)
        noStroke()
        drawImage(picture, in: Rectangle(x: file.x + 12, y: file.y + 12, width: 116, height: 116))
        drawText("marigolds.jpg", file.center.x, file.y + 146, size: 12, color: theme.ink,
                 align: .center, .middle)

        // The window: a dark stage, the way the Dropped example starts.
        let window = Rectangle(x: 300, y: 40, width: 540, height: 400)
        fill(Color(hex: 0x1C1A1F))
        noStroke()
        drawRect(window, cornerRadius: 12)

        // Where the file landed, and the picture placed there, a little turned.
        let drop = Vector2(600, 236)
        let w = 190.0, h = w * Double(picture.height) / Double(picture.width)
        withState {
            translate(drop)
            rotate(-0.08)
            noStroke()
            fill(Color(white: 0, alpha: 0.35))
            drawRect(-w / 2 + 8, -h / 2 + 12, w + 16, h + 16)
            fill(.white)
            drawRect(-w / 2 - 8, -h / 2 - 8, w + 16, h + 16)
            drawImage(picture, -w / 2, -h / 2, w, h)
        }

        // The path that is not a picture, named in the corner.
        drawText("not a picture: notes.txt", window.x + 24, window.y + window.height - 22,
                 size: 14, color: Color(hex: 0xE8A33D), align: .left, .middle)

        // The drag, from the file to the drop point, as a dotted trail.
        let start = Vector2(file.x + file.width + 6, file.center.y - 10)
        let control = Vector2(430, 70)
        noStroke()
        fill(theme.accent)
        for i in 0...27 {
            let t = Double(i) / 30
            let p = quadratic(start, control, drop, t)
            drawCircle(p.x, p.y, 2.2)
        }

        // The drop point, and what the sketch reads there. A dark halo under
        // the crosshair keeps it legible over the flowers.
        noFill()
        for (color, weight) in [(Color(white: 0, alpha: 0.7), 6.0), (theme.accent, 2.0)] {
            stroke(color)
            strokeWeight(weight)
            drawLine(drop.x - 14, drop.y, drop.x + 14, drop.y)
            drawLine(drop.x, drop.y - 14, drop.x, drop.y + 14)
            drawCircle(drop.x, drop.y, 7)
        }
        noStroke()
        textSize(13)
        let label = "mouseX, mouseY"
        let lw = textWidth(label)
        fill(Color(hex: 0x000000, alpha: 0.88))
        drawRect(drop.x + 16, drop.y - 24, lw + 12, 22, cornerRadius: 5)
        drawText(label, drop.x + 22, drop.y - 13, size: 13, color: theme.accent, align: .left, .middle)

        // Callouts.
        callout("the Finder hands over a path,", "not a picture",
                at: Vector2(64, 70), leader: Vector2(134, 106), to: Vector2(134, 172))
        callout("a file that is not a picture", "is still a path to name",
                at: Vector2(64, 398), leader: Vector2(262, 410), to: Vector2(window.x + 18, 418))

        diagramCaption("filesDropped() fires once, with mouseX and mouseY at the drop",
                       at: 470, theme: theme)
        noStroke()
        drawText("droppedFiles() hands over the paths, oldest first, and empties itself; a drop is live input, so a take never records one",
                 width / 2, 498, size: 13, color: theme.muted, align: .center, .top)
    }

    private func quadratic(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ t: Double) -> Vector2 {
        let u = 1 - t
        return a * (u * u) + b * (2 * u * t) + c * (t * t)
    }

    private func callout(_ line1: String, _ line2: String, at p: Vector2,
                         leader from: Vector2, to target: Vector2) {
        noStroke()
        drawText(line1, p.x, p.y, size: 14, color: theme.ink, align: .left, .top)
        drawText(line2, p.x, p.y + 22, size: 14, color: theme.ink, align: .left, .top)
        stroke(theme.accent)
        strokeWeight(2)
        drawLine(from, target)
        noStroke()
        fill(theme.accent)
        drawCircle(target.x, target.y, 4)
    }
}
