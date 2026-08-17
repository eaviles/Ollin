// figure: frame=0
//
// Guide diagram (Chapter 7): a picture wound from one thread. A bold
// crescent, the same picture mid-winding, and the finished winding, so the
// greedy chord choice and the accumulation both read.
import Ollin

final class WoundFromThread: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    var picture = Image(width: 1, height: 1)
    var early: [StringArt.Chord] = []
    var finished: [StringArt.Chord] = []
    var pins: [Vector2] = []
    var finishedPins: [Vector2] = []

    override func setup() {
        picture = makeCrescent(size: 160)
        let panels = Self.panels
        let midway = StringArt(of: picture,
                               center: panels[1].center,
                               radius: 122, pins: 140, chords: 350, ink: 0.12,
                               resolution: 200)
        early = midway.step(350)
        pins = midway.pins
        let whole = StringArt(of: picture,
                              center: panels[2].center,
                              radius: 122, pins: 140, chords: 1600, ink: 0.12,
                              resolution: 200)
        finished = whole.step(1600)
        finishedPins = whole.pins
    }

    override func draw() {
        background(paper)
        let panels = Self.panels

        drawImage(picture, in: panels[0].inset(by: 26))

        noFill()
        stroke(ink.withAlpha(0.38))
        strokeWeight(0.7)
        for chord in early { drawLine(chord.from, chord.to) }
        for chord in finished { drawLine(chord.from, chord.to) }

        noStroke()
        fill(ink)
        drawCircles(pins, radius: 1.1)
        drawCircles(finishedPins, radius: 1.1)

        frame(panels[0], title: "the picture")
        frame(panels[1], title: "350 chords in")
        frame(panels[2], title: "the finished winding")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one thread over 140 pins, each chord wound toward the darkness that remains",
                 width / 2, 364)
    }

    static let panels = [Rectangle(x: 25, y: 66, width: 262, height: 262),
                         Rectangle(x: 309, y: 66, width: 262, height: 262),
                         Rectangle(x: 593, y: 66, width: 262, height: 262)]

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }

    /// A bold crescent on white: the strong tonal masses the winding reads
    /// best.
    func makeCrescent(size: Int) -> Image {
        let image = Image(width: size, height: size, color: .white)
        for py in 0 ..< size {
            for px in 0 ..< size {
                let u = (Double(px) + 0.5) / Double(size) * 2 - 1
                let v = (Double(py) + 0.5) / Double(size) * 2 - 1
                let disk = (u * u + v * v).squareRoot()
                guard disk < 0.72 else { continue }
                let inDisk = 1 - smoothstep(0.68, 0.72, disk)
                let bite = dist(u, v, 0.32, -0.26)
                let crescent = inDisk * smoothstep(0.56, 0.66, bite)
                image[px, py] = Color(white: 0.84 - 0.7 * crescent)
            }
        }
        return image
    }
}
