// figure: frame=0
//
// Guide diagram (Chapter 17): somebody else's shader. Left, a fragment shader
// as it arrives, written in GLSL against the values a shader site supplies.
// Right, what Ollin draws once `--from-shader` has translated it. One string
// feeds both panels, so the picture is the translator's own output rather than
// a result pasted in by hand.
import Ollin
import OllinProjects

final class ImportedShader: Sketch {
    override var canvasSize: CanvasSize { .size(920, 420) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)
    let paper = Color(hex: 0xF7F5F1)

    /// The shader as pasted. Written for this figure, so nobody else's terms
    /// travel with it. It centres its coordinates and then tiles them, so most
    /// of the plane sits left of and below the origin. That is the case `mod`
    /// decides: with Metal's truncating `fmod` the middle of the frame breaks
    /// into a seam, and with the flooring form the translation writes out, the
    /// rings stay even all the way across.
    let glsl = """
        void mainImage(out vec4 o, in vec2 fc) {
          vec2 p = (fc - 0.5 * iResolution.xy)
                 / iResolution.y;
          vec2 c = mod(p * 4.0, 1.0) - 0.5;
          float d = length(c) - 0.33;
          float k = smoothstep(0.04, 0.0, abs(d));
          float w = 0.5 + 0.5 * sin(iTime + length(p) * 7.0);
          o = vec4(mix(vec3(0.07, 0.09, 0.16),
                       vec3(0.96, 0.58, 0.24), k * w), 1.0);
        }
        """

    /// The translated shader, built by the same code `ollin new --from-shader`
    /// runs. If the translator stops working, this figure stops rendering.
    var translated: Shader?

    /// The left panel's text box, and the picture's on the right.
    let codeBox = Rectangle(x: 48, y: 78, width: 420, height: 300)
    let viewBox = Rectangle(x: 572, y: 78, width: 300, height: 300)

    override func setup() {
        translated = Shader(ShaderImport.translate(glsl: glsl).metalSource)
    }

    override func draw() {
        background(paper)
        drawSource()
        drawArrow()
        drawResult()
    }

    /// The GLSL, in the pixel font so the parentheses and the `mod` are
    /// countable. The size is measured rather than guessed, so the longest
    /// line fits the box whatever the font's advance turns out to be.
    private func drawSource() {
        noStroke()
        label("as it was pasted", at: Vector2(codeBox.x, 56))

        let lines = glsl.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let longest = lines.max { textWidth($0) < textWidth($1) } ?? ""

        textFont(BitmapFont.builtin)
        var size = 18.0
        textSize(size)
        while size > 8, textWidth(longest) > codeBox.width {
            size -= 1
            textSize(size)
        }

        // Sit the block against the middle of the picture, so the two panels
        // read as one row rather than as text with a gap under it.
        let step = size * 1.5
        let top = viewBox.y + viewBox.height / 2 - Double(lines.count) * step / 2 + step * 0.75

        textAlign(.left, .baseline)
        for (index, line) in lines.enumerated() {
            // The three names the translation has to do more than rename.
            let notable = line.contains("mod(") || line.contains("iTime")
                || line.contains("iResolution")
            fill(notable ? ink : faint)
            drawText(line, codeBox.x, top + Double(index) * step)
        }

        label("GLSL, against the values a shader site supplies", at: Vector2(codeBox.x, 396))
    }

    /// What the sketch runs: the translated shader, generated into a layer at
    /// the size of the panel it lands in.
    private func drawResult() {
        noStroke()
        label("running here", at: Vector2(viewBox.x, 56))

        if let translated {
            let picture = generate(translated, width: Int(viewBox.width), height: Int(viewBox.height))
            drawImage(picture.image, in: viewBox)
        }

        noFill()
        stroke(faint)
        strokeWeight(1)
        drawRect(corner: Vector2(viewBox.x, viewBox.y), width: viewBox.width, height: viewBox.height)

        noStroke()
        label("Metal, against ShaderInfo", at: Vector2(viewBox.x, 396))
    }

    /// The one turns into the other.
    private func drawArrow() {
        let y = viewBox.y + viewBox.height / 2
        stroke(faint)
        strokeWeight(1.5)
        drawLine(486, y, 550, y)
        drawLine(542, y - 6, 550, y)
        drawLine(542, y + 6, 550, y)

        noStroke()
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(12)
        textAlign(.center, .baseline)
        drawText("--from-shader", 518, y - 12)
    }

    private func label(_ text: String, at position: Vector2) {
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(13)
        textAlign(.left, .baseline)
        drawText(text, position.x, position.y)
    }
}
