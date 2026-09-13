import Ollin
import OllinSamplePhotos

/// A look from a `.cube` file: the bundled warm print over a photograph, with
/// the amount on a parameter, beside the identity table and a look written in
/// code. Drop any `.cube` file onto the window and it becomes a choice too.
///
/// A `.cube` file is what a grading tool hands over when a colorist is done: a
/// table that says, for every color, which color to show instead. Ollin reads
/// one into a `ColorLUT` and applies it with `Filter.lut(_:amount:)`, on a
/// layer or on the whole frame. The **look** parameter picks the table:
/// **warm** is the bundled look, **identity** the table that changes nothing
/// (the control), **code** a cool, contrasty look built from a closure in
/// `setup()`, and **dropped** whatever `.cube` file was last dropped on the
/// window, which is the way to try one exported from Resolve or downloaded from
/// a colorist. **amount** fades the look in.
///
/// The wipe runs the look across the picture so the two versions meet at a
/// moving edge, the quickest way to see what a look does. Turn it off to see the
/// whole picture under the look.
enum LookChoice: String, CaseIterable, ParamOption { case warm, identity, code, dropped }

@main
final class LookSketch: Sketch {
    @Param(style: .segmented, icon: "camera.filters") var look: LookChoice = .warm
    @Param("Amount", 0 ... 1, icon: "slider.horizontal.below.rectangle") var amount = 1.0
    @Param(icon: "rectangle.lefthalf.filled") var wipes = true

    private let labelFont = OutlineFont.system
    private var photograph = Image(width: 1, height: 1)

    /// A look written in code: cool shadows, a hard S, and the reds pulled
    /// toward orange. `write(to:)` would hand it to any other tool.
    private var written = ColorLUT.identity(size: 2)
    /// The last `.cube` file dropped on the window, once there is one.
    private var dropped: ColorLUT?
    private var droppedName = ""

    override func setup() {
        textFont(labelFont)
        photograph = SamplePhoto.portrait.load()
        written = ColorLUT(size: 17, title: "Cool Contrast") { c in
            func curve(_ x: Double) -> Double {
                let s = x * x * (3 - 2 * x)
                return 0.02 + 0.96 * (0.6 * s + 0.4 * x)
            }
            let luminance = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
            let cool = 1 - luminance * 0.8
            return Color(red: curve(c.red) * (1 - 0.10 * cool) + 0.06 * c.red * (1 - c.green),
                         green: curve(c.green),
                         blue: min(1, curve(c.blue) * (1 + 0.14 * cool)))
        }
    }

    override func filesDropped() {
        for path in droppedFiles() where path.lowercased().hasSuffix(".cube") {
            do {
                dropped = try ColorLUT(contentsOf: path)
                droppedName = path.split(separator: "/").last.map(String.init) ?? path
                look = .dropped
            } catch {
                // The reader names the line that stopped it.
                print("Ollin: could not read \(path): \(error)")
            }
        }
    }

    /// The table the `look` parameter names.
    private var table: ColorLUT {
        switch look {
        case .warm: return .warmPrint
        case .identity: return .identity()
        case .code: return written
        case .dropped: return dropped ?? .identity()
        }
    }

    override func draw() {
        background(Color(hex: 0x0E0E12))
        let plain = makeRenderTarget()
        withTarget(plain) { drawImage(photograph, in: canvasRectangle, fit: .cover) }
        let graded = plain.filtered(.lut(table, amount: amount))

        if wipes {
            drawImage(plain.image, in: canvasRectangle)
            let edge = (0.5 - 0.5 * cos(time * 0.45)) * width
            withClip(Rectangle(x: 0, y: 0, width: edge, height: height)) {
                drawImage(graded.image, in: canvasRectangle)
            }
            withState {
                stroke(Color(white: 1, alpha: 0.7))
                strokeWeight(2)
                drawLine(edge, 0, edge, height)
            }
        } else {
            drawImage(graded.image, in: canvasRectangle)
        }

        let name: String
        switch look {
        case .warm: name = "\(ColorLUT.warmPrint.title), the bundled look"
        case .identity: name = "the identity table, which changes nothing"
        case .code: name = "\(written.title), written in code"
        case .dropped: name = dropped == nil ? "drop a .cube file on the window" : droppedName
        }
        withState {
            noStroke()
            fill(Color(white: 0, alpha: 0.55))
            drawRect(0, height - 64, width, 64)
            fill(.white)
            textSize(22)
            textAlign(.center, .middle)
            drawText(name, width / 2, height - 32)
        }
    }
}
