import Ollin

/// A picture and a box rarely have the same shape, and `fit:` says what to do
/// about it. The same landscape goes into the same three tall boxes:
/// `.stretch` squashes it, which the round sun reports at once; `.contain` keeps
/// its proportions and leaves the box showing above and below; `.cover` keeps
/// them too and fills the box, paying for it with the left and right edges, so
/// the lone tree goes over the side.
///
/// The picture is painted in `setup()`, so the sketch carries no asset. The
/// panel at the foot is it, at the shape it really is.
///
/// See Docs/Drawing/Images.md.
@main
final class Fit: Sketch {
    private var picture = Image(width: 480, height: 320, color: .white)

    let paper = Color(hex: 0xF2EDE6)
    let ink = Color(hex: 0x24262E)

    /// Each panel: the mode, and the one word for what it gives up.
    static let modes: [(fit: ImageFit, name: String, cost: String)] = [
        (.stretch, ".stretch", "its proportions"),
        (.contain, ".contain", "part of the box"),
        (.cover, ".cover", "its own edges"),
    ]

    override func setup() {
        textFont(OutlineFont.system)
        paint()
    }

    override func draw() {
        background(paper)
        drawTitle()
        for (i, mode) in Fit.modes.enumerated() { panel(mode, at: i) }
        drawSource()
    }

    // MARK: The panels

    static let boxWidth = 280.0, boxHeight = 430.0, gap = 40.0, top = 250.0
    static var boxLeft: Double { (1080 - (boxWidth * 3 + gap * 2)) / 2 }

    func box(at index: Int) -> Rectangle {
        Rectangle(x: Fit.boxLeft + Double(index) * (Fit.boxWidth + Fit.gap),
                  y: Fit.top, width: Fit.boxWidth, height: Fit.boxHeight)
    }

    func panel(_ mode: (fit: ImageFit, name: String, cost: String), at index: Int) {
        let frame = box(at: index)

        // The box itself, drawn first, so a contained picture leaves it visible.
        noStroke()
        fill(Color(hex: 0xE2DACD))
        drawRect(corner: frame.corner, width: frame.width, height: frame.height)

        drawImage(picture, in: frame, fit: mode.fit)

        noFill()
        stroke(ink.withAlpha(0.35))
        strokeWeight(1.5)
        drawRect(corner: frame.corner, width: frame.width, height: frame.height)

        noStroke()
        fill(ink)
        textSize(30)
        textAlign(.center, .top)
        drawText(mode.name, frame.center.x, frame.y + frame.height + 26)
        fill(ink.withAlpha(0.5))
        textSize(21)
        drawText("gives up \(mode.cost)", frame.center.x, frame.y + frame.height + 64)
    }

    func drawTitle() {
        noStroke()
        fill(ink)
        textSize(44)
        textAlign(.center, .top)
        drawText("One picture, three ways into a tall box", 540, 120)
        fill(ink.withAlpha(0.45))
        textSize(23)
        drawText("the picture is 3:2 and every box is 2:3, so something has to give", 540, 180)
    }

    /// The source at its own shape, so the eye has something to compare against.
    func drawSource() {
        let wide = Rectangle(x: 540 - 150, y: 830, width: 300, height: 200)
        drawImage(picture, in: wide)
        noFill()
        stroke(ink.withAlpha(0.35))
        strokeWeight(1.5)
        drawRect(corner: wide.corner, width: wide.width, height: wide.height)
        noStroke()
        fill(ink.withAlpha(0.5))
        textSize(21)
        textAlign(.center, .top)
        drawText("the picture, 3:2", 540, wide.y + wide.height + 14)
    }

    // MARK: The picture

    /// A low sun over two ridges, with one tree well off to the right. The sun is
    /// round on purpose: it is the fastest way to see a stretch. The tree is off
    /// center on purpose: it is the fastest way to see a crop.
    func paint() {
        let w = picture.width, h = picture.height
        let sun = Vector2(Double(w) * 0.30, Double(h) * 0.33), sunRadius = 46.0

        for y in 0..<h {
            let v = Double(y) / Double(h - 1)
            let sky = Color.mix(Color(hex: 0x3E5C7E), Color(hex: 0xE8B478), t: pow(v, 0.7))
            for x in 0..<w {
                var c = sky
                let d = Vector2(Double(x), Double(y)).distance(to: sun)
                if d < sunRadius {
                    c = Color(hex: 0xFFF0C2)
                } else if d < sunRadius * 2.4 {
                    let glow = 1 - (d - sunRadius) / (sunRadius * 1.4)
                    c = Color.mix(c, Color(hex: 0xFFD98F), t: glow * 0.5)
                }
                picture[x, y] = c
            }
        }

        // Two ridges, the far one paler, laid over the sky.
        ridge(base: 0.62, amplitude: 26, frequency: 2.1, phase: 0.4, color: Color(hex: 0x5D6B77))
        ridge(base: 0.78, amplitude: 18, frequency: 1.3, phase: 2.2, color: Color(hex: 0x2E3A43))

        tree(at: 0.85, groundHeight: 0.78)
    }

    func ridge(base: Double, amplitude: Double, frequency: Double, phase: Double, color: Color) {
        let w = picture.width, h = picture.height
        for x in 0..<w {
            let u = Double(x) / Double(w - 1)
            let top = Double(h) * base + sin(u * .tau * frequency + phase) * amplitude
            for y in Int(top)..<h where y >= 0 { picture[x, y] = color }
        }
    }

    /// A trunk and a round crown, dark against the sky.
    func tree(at u: Double, groundHeight: Double) {
        let w = picture.width, h = picture.height
        let x0 = Double(w) * u
        let ground = Double(h) * groundHeight
        let crown = Vector2(x0, ground - 62), bark = Color(hex: 0x22282C)
        for y in 0..<h {
            for x in 0..<w {
                let p = Vector2(Double(x), Double(y))
                let inTrunk = abs(p.x - x0) < 5 && p.y > crown.y && p.y < ground
                if inTrunk || p.distance(to: crown) < 30 { picture[x, y] = bark }
            }
        }
    }
}
