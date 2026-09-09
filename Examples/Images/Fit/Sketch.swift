import Ollin
import OllinSamplePhotos

/// A picture and a box rarely have the same shape, and `fit:` says what to do
/// about it. The same city goes into the same three tall boxes: `.stretch`
/// squashes it, which the round dome reports at once; `.contain` keeps its
/// proportions and leaves the box showing above and below; `.cover` keeps them
/// too and fills the box, paying for it with the left and right edges, so the
/// people walking up the street go over the side.
///
/// The picture is a bundled photograph, wide because `cropped(toAspect:)` takes
/// a 3:2 slice out of the square it ships as. The panel at the foot is that
/// slice, at the shape it really is.
///
/// See Docs/Drawing/Images.md.
@main
final class Fit: Sketch {
    private var picture = Image(width: 1, height: 1)

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
        picture = SamplePhoto.city.load().cropped(toAspect: 3.0 / 2)
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
}
