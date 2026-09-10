// figure: frame=0 themed
//
// Guide diagram (Chapter 30): a slit scan. Forty-eight consecutive frames of
// the bundled film, just under two seconds of a dancer with the camera locked
// off, are pushed into a frame history and read back with a delay that varies
// across the picture, so each column shows a different moment. Left, the
// newest frame; right, the same history read with time running across it: the
// arm that swung through those two seconds comes back as a comb of sleeves.
import Ollin
import OllinDiagram
import OllinSamplePhotos
import OllinVideo

final class SlitScanDelay: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    var newest: Image?
    var scanned: Image?

    override func setup() {
        let clip = VideoPlayer(url: SampleClip.dance.url)
        clip.isMuted = true

        let history = Ollin.SlitScan(capacity: 48)
        for step in 0 ..< 48 {
            // The film's own frames, one after the next, at the size the panel
            // draws: a history holds every frame whole, so its depth times its
            // frame size is what it costs.
            clip.seek(to: 1 + Double(step) / 25)
            guard let shot = clip.snapshot()?.resized(width: 300, height: 300) else { continue }
            history.append(shot)
            newest = shot
        }
        scanned = history.image(delay: { uv in uv.x })
    }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)
        if let newest { drawImage(newest, in: left) }
        if let scanned { drawImage(scanned, in: right) }

        frame(left, title: "the newest frame")
        frame(right, title: "delay running left to right")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every column is a different moment of the same clip",
                 width / 2, 396)
    }

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
}
