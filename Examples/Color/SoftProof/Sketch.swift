import Ollin

/// Seeing the print before you print it: proofing a poster against a press.
///
/// A screen makes color with light and a press makes it with ink on paper, and
/// the screen wins. The vivid cyan of a backlit pixel is simply not a color
/// four inks can lay down, so it arrives at the press and comes back as the
/// nearest thing the ink can do. A soft proof runs that trip on purpose: the
/// canvas is carried into the printer's profile and back out again, and what
/// comes home changed is exactly what the press is going to change.
///
/// The `view` knob shows the four ways to look at it. **Sweep** wipes the proof
/// across the poster so the two versions meet at a moving edge, which is the
/// quickest way to see what a press takes away. **Proof** is the whole canvas
/// under the printing condition. **Gamut** leaves the colors alone and flags
/// what will not survive, so a palette can be fixed before anything is
/// separated. **Plates** is what actually goes to the shop: one grayscale
/// plate per ink, black where that ink lands.
///
/// The proof itself runs on the GPU (`Filter.softProof`), so the intent and
/// paper knobs answer immediately. The plates are CPU work through the same
/// profile, done once and again whenever the intent changes. Write the print
/// files with:
///
///     --export-plates poster.png [--screen halftone]
enum ProofView: String, CaseIterable, ParamOption { case sweep, proof, gamut, plates }

@main
final class SoftProofSketch: Sketch {
    /// The press this poster is made for. A shop hands out its own profile for
    /// the actual press and paper; this generic four-ink one stands in, and is
    /// close enough to show which colors are in trouble.
    override var printProfile: ICCProfile? { .genericCMYK }

    @Param(style: .segmented, icon: "printer") var view: ProofView = .sweep
    @Param(icon: "arrow.triangle.merge") var intent: RenderingIntent = .relative
    @Param(icon: "doc.plaintext") var showPaperColor = false

    private let labelFont = OutlineFont.system
    private var artwork = Image(width: 1, height: 1)
    private var plates: ProcessSeparation?
    private var platesIntent: RenderingIntent?

    /// The printing condition the whole sketch reads from: press, canvas,
    /// intent, and whether the paper's own color is shown.
    private var proof: SoftProof {
        var condition = SoftProof(printProfile ?? .genericCMYK, intent: intent)
        condition.simulatesPaper = showPaperColor
        return condition
    }

    override func setup() {
        noStroke()
        textFont(labelFont)
        artwork = paint()
    }

    override func draw() {
        background(Color(hex: 0x0E0E12))
        switch view {
        case .sweep: drawSweep()
        case .proof: drawProofed(warning: nil, amount: 1)
        case .gamut: drawProofed(warning: Color(white: 0.55), amount: 0)
        case .plates: drawPlates()
        }
    }

    /// The poster with the proof wiped across it: ink on the left of the edge,
    /// light on the right. The edge travels, so the difference reads as
    /// movement rather than as two pictures to compare from memory.
    private func drawSweep() {
        let layer = makeRenderTarget()
        withTarget(layer) { drawImage(artwork, in: bounds) }
        drawImage(artwork, in: bounds)

        // The wipe starts closed and travels, so a frame exported at time zero
        // is the poster itself: `--export-plates` then separates the artwork
        // rather than a half already carried through the press.
        let edge = (0.5 - 0.5 * cos(time * 0.45)) * width
        let proofed = layer.filtered(.softProof(proof))
        withClip(Rectangle(x: 0, y: 0, width: edge, height: height)) {
            drawImage(proofed.image, in: bounds)
        }
        withState {
            stroke(Color(white: 1, alpha: 0.7))
            strokeWeight(2)
            drawLine(edge, 0, edge, height)
        }

        label("printed", at: Vector2(edge - 18, 34), align: .right)
        label("on screen", at: Vector2(edge + 18, 34), align: .left)
        drawCaption("the same poster on both sides of the line")
    }

    /// The whole canvas under the printing condition. At `amount: 0` the colors
    /// are left as drawn and only the warning shows, which is the mode for
    /// checking a palette without living inside the proof.
    private func drawProofed(warning: Color?, amount: Double) {
        let layer = makeRenderTarget()
        withTarget(layer) { drawImage(artwork, in: bounds) }
        let proofed = layer.filtered(.softProof(proof, warning: warning, amount: amount))
        drawImage(proofed.image, in: bounds)

        if warning == nil {
            let paper = showPaperColor ? ", on its own paper" : ""
            drawCaption("\(proof.destination.name), \(intent.rawValue) intent\(paper)")
        } else {
            drawCaption("gray marks the colors this press cannot make")
        }
    }

    /// What goes to the shop: one plate per ink, black where the ink lands.
    private func drawPlates() {
        ensurePlates()
        guard let plates, !plates.plates.isEmpty else {
            return drawStatus("this profile could not be read")
        }

        let tile = 440.0, gutter = 36.0
        let origin = (width - tile * 2 - gutter) / 2
        textSize(16)
        textAlign(.left, .middle)

        for (index, plate) in plates.plates.enumerated() {
            let x = origin + Double(index % 2) * (tile + gutter)
            let y = origin - 40 + Double(index / 2) * (tile + gutter + 40)
            drawImage(plate.master, in: Rectangle(x: x, y: y, width: tile, height: tile))
            fill(.white)
            let coverage = Int((plate.averageInk * 100).rounded())
            drawText("\(plate.name.lowercased())  \(coverage)% ink", x, y + tile + 21)
        }

        let peak = Int((plates.peakTotalInk * 100).rounded())
        drawCaption("four plates, \(peak)% ink at the heaviest spot")
    }

    /// Separate the poster, once per intent. This is per-pixel CPU work through
    /// the profile, so it runs when the answer would change and not before.
    private func ensurePlates() {
        guard plates == nil || platesIntent != intent else { return }
        plates = artwork.separated(into: proof)
        platesIntent = intent
    }

    private func label(_ text: String, at position: Vector2, align: HorizontalTextAlign) {
        withState {
            noStroke()
            fill(Color(white: 1, alpha: 0.85))
            textSize(18)
            textAlign(align, .middle)
            drawText(text, position.x, position.y)
        }
    }

    /// A poster in the colors a screen is good at and a press is not: an
    /// electric sea, a fluorescent hill, a sun on a hot gradient. The strip of
    /// neutrals along the bottom is the control, since ink handles those
    /// perfectly well and they should come through the proof untouched.
    private func paint() -> Image {
        let w = 1080, h = 1080
        let image = Image(width: w, height: h)
        let dusk = Color(hex: 0x2B1B6B)
        let heat = Color(hex: 0xFF2D55)
        let sun = Color(hex: 0xFFD400)
        let sea = Color(hex: 0x00E5FF)
        let hill = Color(hex: 0x00FF66)

        for y in 0..<h {
            let v = Double(y) / Double(h - 1)
            for x in 0..<w {
                let u = Double(x) / Double(w - 1)

                var c = Color.mix(dusk, heat, smoothstep(0.05, 0.62, v))
                let disk = dist(u, v, 0.62, 0.30)
                c = Color.mix(c, sun, 1 - smoothstep(0.145, 0.152, disk))
                c = Color.mix(c, sun, clamp(1 - disk * 2.6, 0, 1) * 0.35)

                // The sea starts at a flat horizon and carries a few bands.
                if v > 0.62 {
                    let bands = 0.5 + 0.5 * sin((v - 0.62) * 90 + sin(u * 6) * 1.4)
                    c = Color.mix(sea, dusk, bands * 0.35 * smoothstep(0.62, 0.95, v))
                }
                // A fluorescent headland cuts in from the left.
                let ridge = 0.78 + 0.10 * sin(u * 3.4 + 2.1)
                if v > ridge {
                    c = Color.mix(hill, dusk, smoothstep(ridge, 1.15, v) * 0.5)
                }
                // The control strip: neutrals a press reproduces exactly. The
                // margin under it is the poster's own, and keeps the caption
                // off the light end of the ramp.
                if v > 0.86 { c = Color(white: 0.12 + (u * 8).rounded(.down) / 7 * 0.8) }
                if v > 0.95 { c = Color(hex: 0x0E0E12) }
                image[x, y] = c
            }
        }
        return image
    }
}
