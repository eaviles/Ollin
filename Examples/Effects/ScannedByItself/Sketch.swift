import Ollin

/// A sketch that reads its own drawing: a slit scan of the shapes it moves,
/// and a glyph mosaic of the word it writes.
///
/// Until now the picture techniques that read pixels (`SlitScan`, the glyph
/// mosaic, a dither, a stipple) took a photograph, a camera, or an image
/// painted on the CPU, because a layer lives on the GPU. Two routes bring a
/// layer to them. `Filter.slitScan(_:delay:)` keeps the picture on the GPU: a
/// `LayerHistory` made once holds the layer's last frames in a ring, and the
/// filter composes every pixel from the frame its delay names, the left edge
/// now and the right edge the oldest frame held. `layer.snapshot()` brings
/// the layer's pixels to the CPU a frame late, so anything that reads a
/// picture can read the sketch; here the glyph mosaic takes a layer straight
/// (a reduction on the GPU averages its cells, a frame late), and the small
/// panel is the snapshot drawn back as a plain image.
///
/// Hold the mouse to switch the scan's delay from across to radial, where
/// the center is now and the corners are the past.
@main
final class ScannedByItself: Sketch {
    override var loopDuration: Double? { 8 }

    @Param("Reach (frames)", 12...180) var reach = 90
    @Param("Columns", 24...96) var columns = 54

    private var history: LayerHistory?
    private var reachHeld = 0

    override func setup() {
        textFont(OutlineFont.systemBold)
        textAlign(.center, .middle)
    }

    override func draw() {
        if history == nil || reachHeld != reach {
            history = makeLayerHistory(capacity: reach)
            reachHeld = reach
        }
        guard let history else { return }
        background(Color(hex: 0x0B0E14))

        // The scene the scan reads: three discs on orbits that close each lap,
        // over bands of hue drifting up, so slow motion stretches into ribbons
        // and the bands shear into curves.
        let scene = makeRenderTarget(width: Int(width), height: Int(height * 0.62))
        withTarget(scene) {
            paintScene(height: height * 0.62)
        }

        // The scan, filling the upper band of the canvas.
        let delay: SlitScanDelay = mouseIsPressed ? .radial : .across
        drawImage(scene.filtered(.slitScan(history, delay: delay)).image, 0, 0)

        // The live scene, inset at the lower right, from its snapshot: the
        // picture of the frame before, now ordinary CPU pixels.
        let inset = Rectangle(x: width - 300, y: height * 0.62 + 44, width: 256, height: 256 * 0.62)
        if let picture = scene.snapshot() {
            drawImage(picture, in: inset)
        }
        noFill()
        stroke(Color(white: 1, alpha: 0.6))
        strokeWeight(2)
        drawRect(inset)

        // The word, written into its own layer and read back as a mosaic of
        // glyphs: each cell's tone is averaged on the GPU and the character
        // whose measured ink matches it is drawn as text.
        let band = Rectangle(x: 44, y: height * 0.62 + 44, width: width - 388, height: 256 * 0.62)
        let word = makeRenderTarget(width: Int(band.width), height: Int(band.height))
        withTarget(word) {
            paintWord(width: band.width, height: band.height)
        }
        noStroke()
        fill(Color(hex: 0xF2E8D5))
        drawGlyphMosaic(word.image, columns: columns, characters: GlyphSet.classic, in: band)

        drawCaption(mouseIsPressed
            ? "the center is now, the corners the past; the word is read as glyphs a frame late"
            : "left is now, right is a second and a half ago; hold the mouse for radial time")
    }

    /// Three discs on closed orbits over bands of hue drifting upward.
    private func paintScene(height h: Double) {
        let phase = loopProgress(over: 8) * .tau
        noStroke()
        for i in 0..<6 {
            let t = Double(i) / 6
            fill(Color(hue: 0.55 + t * 0.25, saturation: 0.55,
                       brightness: 0.42 + 0.1 * sin(phase + t * .tau)))
            // Each band drawn at its place and a lap above and below it, so
            // the one crossing an edge still covers it.
            let y = fract(t + loopProgress(over: 8)) * h
            for wrap in [-h, 0, h] { drawRect(0, y + wrap - h / 12, width, h / 6) }
        }
        let orbits: [(Double, Double, Double)] = [(1, 0.32, 0.2), (2, 0.18, 0.34), (3, 0.26, 0.12)]
        for (k, (laps, rx, ry)) in orbits.enumerated() {
            let a = phase * laps + Double(k) * 2.1
            let x = width * (0.5 + rx * sin(a))
            let y = h * (0.5 + ry * sin(a * 2 + Double(k)))
            fill(Color(white: 1))
            drawCircle(x, y, 26 + 10 * Double(k))
            fill(Color(hue: Double(k) / 3, saturation: 0.8, brightness: 1))
            drawCircle(x, y, 12 + 5 * Double(k))
        }
    }

    /// The word, swinging across its layer once a lap.
    private func paintWord(width w: Double, height h: Double) {
        let phase = loopProgress(over: 8) * .tau
        background(.clear)
        noStroke()
        fill(.white)
        textSize(h * 0.72)
        withState {
            translate(w / 2 + sin(phase) * w * 0.12, h / 2)
            rotate(sin(phase * 2) * 0.08)
            drawText("OLLIN", 0, 0)
        }
    }
}
