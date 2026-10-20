import Ollin

/// Six optical and print looks, one picker across them: a red-and-cyan
/// anaglyph of a 3D scene by its own depth, the plates of a print slipping
/// out of register, the shimmer of a heat mirage over a road, the knife-edge
/// shading of schlieren over a rising plume, a ramp over the wavelengths of
/// light fanned out like a prism's, and the rings a drop of ink leaves as it
/// spreads through paper. Each is one filter, one combine, one call on the
/// separations, one ramp, or one geometry emitter a sketch holds, and each
/// moves: the orbs orbit, the plates drift, the air shimmers, the plume
/// rises, the slit sweeps the spectrum, and the drops spread in.
@main
final class Phenomena: Sketch {
    enum Look: String, CaseIterable, ParamOption {
        case anaglyph, misregistration, mirage, schlieren, spectrum, chromatography
    }

    @Param(style: .segmented, icon: "eye") var look = Look.anaglyph
    @Param("Seed", 1 ... 99, icon: "dice") var seed = 7
    @Param("Amount", 0 ... 2, icon: "slider.horizontal.3") var amount = 1.0
    @Param("Knife angle", 0 ... 6.28, icon: "scissors") var knifeAngle = 0.0
    @Param("Outlines in ink", icon: "pencil.line") var drawsOutlines = false

    override var loopDuration: Double? { 12 }

    private var poster: PrintSeparation?
    private var posterSeed = -1
    private var misprint: Image?
    private var misprintKey = (0, 0)
    private var stain: Chromatography?
    private var stainSeed = -1

    override func draw() {
        let t = loopProgress(over: 12)
        switch look {
        case .anaglyph: drawAnaglyph(t)
        case .misregistration: drawMisregistration(t)
        case .mirage: drawMirage(t)
        case .schlieren: drawSchlieren(t)
        case .spectrum: drawSpectrum(t)
        case .chromatography: drawChromatography(t)
        }
    }

    // MARK: Anaglyph

    /// Orbs at every depth, drawn into a layer whose own depth drives the
    /// parallax: a near orb's copies land one way, a far orb's the other.
    private func drawAnaglyph(_ t: Double) {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.white)
            perspective(eye: Vector3(0, 2.4, 18), target: Vector3(0, 0, -3),
                        fieldOfView: .pi / 4, near: 5, far: 34)
            let count = 9
            for i in 0 ..< count {
                let u = Double(i) / Double(count - 1)
                let z = 6 - u * 24
                let x = sin(u * .tau * 1.5 + t * .tau) * 3.6
                withState {
                    translate(x, 0, z)
                    rotateY(t * .tau + Double(i))
                    fill(Color(hue: 0.02 + u * 0.6, saturation: 0.7, brightness: 0.92))
                    specular(0.5)
                    specularSharpness(48)
                    drawSphere(radius: 1.6)
                }
            }
        }
        background(.white)
        let print = scene.combined(with: scene.depth, .anaglyph(separation: 36 * amount, focus: 0.45))
        drawImage(print.image, 0, 0)
    }

    // MARK: Misregistration

    /// A flat poster in three inks, separated once, and the plates slipping a
    /// few pixels each as the loop turns, resampled only when they move.
    private func drawMisregistration(_ t: Double) {
        if poster == nil || posterSeed != seed {
            poster = paintPoster().separated(into: [.black, .blue, .fluorescentPink])
            posterSeed = seed
            misprint = nil
        }
        guard let poster else { return }
        let a = t * .tau
        let slip = 9 * amount
        let key = (Int((cos(a) * slip).rounded()), Int((sin(a * 2) * slip * 0.6).rounded()))
        if misprint == nil || key != misprintKey {
            let blue = Vector2(Double(key.0), Double(key.1))
            let pink = Vector2(-Double(key.0) * 0.5, Double(key.1) * 0.5 - 3 * amount)
            misprint = poster.misregistered(offsets: [.zero, blue, pink],
                                            rotations: [0, 0.004 * amount * sin(a), 0]).preview()
            misprintKey = key
        }
        if let misprint { drawImage(misprint, in: canvasRectangle) }
        if drawsOutlines, let misprint {
            // The masters beside the print, the slip plain on each.
            let w = width / 6
            for (i, layer) in poster.layers.enumerated() {
                drawImage(layer.master, in: Rectangle(x: width - w * 1.1, y: height * 0.05 + Double(i) * w * 1.15,
                                                      width: w, height: w))
            }
            _ = misprint
        }
    }

    /// A poster of flat shapes in the inks' colors, painted on the CPU at
    /// half size so the separation is exact and quick: a sun ringed in black,
    /// a blue ridge, and a navy ground the blue and the black plates both
    /// print, so a slip shows as a fringe of ink and not only as paper.
    private func paintPoster() -> Image {
        let side = 540
        let image = Image(width: side, height: side)
        let black = Ink.black.color, blue = Ink.blue.color, pink = Ink.fluorescentPink.color
        let navy = Color(red: blue.red * black.red, green: blue.green * black.green, blue: blue.blue * black.blue)
        var r = SplitMix64(seed: UInt64(seed))
        let sun = Vector2(Double.random(in: 150 ... 390, using: &r), Double.random(in: 120 ... 240, using: &r))
        for y in 0 ..< side {
            for x in 0 ..< side {
                let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                var c = Color.white
                let d = (p - sun).length
                if d < 110 { c = pink }
                if d > 110 && d < 121 { c = black }
                let ridge = 330 + 40 * sin(p.x * 0.013 + 1.1) + 18 * sin(p.x * 0.031)
                if p.y > ridge { c = blue }
                if p.y > 400 + 30 * sin(p.x * 0.02 + 3) { c = navy }
                let stripe = Int(p.x / 36)
                if p.y > 455 && stripe % 2 == 0 { c = .white }
                image[x, y] = c
            }
        }
        return image
    }

    // MARK: Mirage

    /// A road to the horizon under a hot sky, and the air over it shimmering,
    /// the sky mirrored onto the road below the line.
    private func drawMirage(_ t: Double) {
        let horizon = 0.6
        let layer = makeRenderTarget()
        withTarget(layer) {
            let sky = Ramp([Color(hex: 0x3B6FBF), Color(hex: 0xA9CBEA), Color(hex: 0xF3D9A6)])
            noStroke()
            for row in stride(from: 0.0, to: height * horizon, by: 4) {
                fill(sky.color(at: row / (height * horizon)))
                drawRect(0, row, width, 5)
            }
            fill(Color(hex: 0xFFE9A8)); drawCircle(width * 0.68, height * 0.22, width * 0.07)
            fill(Color(hex: 0xC9A66B)); drawRect(0, height * horizon, width, height * (1 - horizon))
            // The road, to a vanishing point on the horizon.
            let vanish = Vector2(width * 0.5, height * horizon)
            fill(Color(hex: 0x3A3A40))
            drawPolygon([Vector2(width * 0.2, height), Vector2(width * 0.8, height),
                         vanish + Vector2(6, 0), vanish - Vector2(6, 0)])
            fill(Color(hex: 0xF2E27A))
            for i in 0 ..< 7 {
                let u = pow(Double(i) / 7, 1.8), v = pow((Double(i) + 0.5) / 7, 1.8)
                let y0 = height * horizon + (height - height * horizon) * u
                let y1 = height * horizon + (height - height * horizon) * v
                drawPolygon([Vector2(width * 0.5 - 2 - 4 * u, y0), Vector2(width * 0.5 + 2 + 4 * u, y0),
                             Vector2(width * 0.5 + 2 + 5 * v, y1), Vector2(width * 0.5 - 2 - 5 * v, y1)])
            }
            // Posts along the road, nearer ones taller, and a far ridge.
            fill(Color(hex: 0x2A2A2E))
            for i in 0 ..< 7 {
                let u = pow((Double(i) + 1) / 7, 1.6)
                let y = height * horizon + (height * 0.36) * u
                let h = 14 + 150 * u
                drawRect(width * (0.8 + 0.17 * u), y - h, 3 + 9 * u, h)
            }
            fill(Color(hex: 0x6E5A8E))
            drawPolygon([Vector2(0, height * horizon), Vector2(width * 0.3, height * 0.5),
                         Vector2(width * 0.55, height * horizon)])
        }
        let shimmer = layer.filtered(.mirage(horizon: horizon, faults: 0.5, amount: 16 * amount, phase: t * .tau))
        drawImage(shimmer.image, 0, 0)
    }

    // MARK: Schlieren

    /// A plume of warm air rising from a burner, drawn as soft blobs the
    /// knife-edge reads as density: light on one side of every curl, dark on
    /// the other, and the knife on a parameter.
    private func drawSchlieren(_ t: Double) {
        let layer = makeRenderTarget()
        withTarget(layer) {
            background(Color(white: 0.15))
            noStroke()
            // Many faint puffs make one smooth density, the way warm air does.
            for i in 0 ..< 420 {
                let u = Double(i) / 420
                let rise = (u + t).truncatingRemainder(dividingBy: 1)
                let sway = sin(rise * 9 + Double(i) * 0.7) * width * (0.02 + 0.14 * rise)
                let x = width * 0.5 + sway + noise(Double(i) * 3.1, rise * 2) * width * 0.22 - width * 0.11
                let y = height * (0.95 - 0.9 * rise) + noise(Double(i) * 1.7 + 50, rise) * height * 0.06 - height * 0.03
                let r = width * (0.012 + 0.07 * rise)
                fill(Color(white: 1, alpha: 0.28 * (1 - rise * 0.6)))
                drawCircle(x, y, r)
            }
        }
        let density = layer.filtered(.gaussianBlur(radius: 12 * scale))
        drawImage(density.filtered(.schlieren(angle: knifeAngle, amount: 4 * amount)).image, 0, 0)
    }

    // MARK: The spectrum

    /// The wavelengths of light fanned from a slit, the ramp's own colors, and
    /// a bright band sweeping it as the loop turns.
    private func drawSpectrum(_ t: Double) {
        background(Color(hex: 0x0A0B10))
        let spectrum = Ramp.wavelengths(from: 400, to: 700)
        let slit = Vector2(width * 0.12, height * 0.5)
        let bands = 120
        noStroke()
        for i in 0 ..< bands {
            let u = (Double(i) + 0.5) / Double(bands)
            let a0 = -0.42 + 0.84 * Double(i) / Double(bands)
            let a1 = -0.42 + 0.84 * Double(i + 1) / Double(bands)
            let reach = width * 1.3
            let sweep = exp(-pow((u - t) * 9, 2))
            fill(spectrum.color(at: u).withAlpha(0.55 + 0.45 * sweep))
            drawPolygon([slit, slit + Vector2(angle: a0, length: reach), slit + Vector2(angle: a1, length: reach)])
        }
        // The slit itself, and the three wavelengths a label names.
        fill(.white); drawRect(slit.x - 4, slit.y - 40, 8, 80)
        textFont(.system); textSize(22 * scale); textAlign(.center, .middle)
        for nm in [450.0, 550.0, 650.0] {
            let u = (nm - 400) / 300
            let a = -0.42 + 0.84 * u
            let p = slit + Vector2(angle: a, length: width * 0.78)
            fill(Color(white: 0.05, alpha: 0.6)); drawCircle(p.x, p.y, 34 * scale)
            fill(.white); drawText("\(Int(nm)) nm", p.x, p.y)
        }
    }

    // MARK: Chromatography

    /// Drops of a felt-tip ink spreading into paper, each pigment stopping at
    /// its own ring, the fronts yielding where they meet, grown in over the
    /// loop; the ink switch strokes every ring and fiber.
    private func drawChromatography(_ t: Double) {
        if stain == nil || stainSeed != seed {
            stain = Chromatography.scatter(in: Rectangle(x: width * 0.1, y: height * 0.1, width: width * 0.8, height: height * 0.8), count: 8,
                                           radius: (width * 0.14) ... (width * 0.27), rings: 5, seed: seed)
            stainSeed = seed
        }
        guard let stain else { return }
        background(Color(hex: 0xF4EFE3))
        let inks = Ramp([Color(hex: 0x1B1A2E), Color(hex: 0x24449A), Color(hex: 0x3F86B8),
                         Color(hex: 0xC43E7A), Color(hex: 0xE9B84A)])
        for (i, drop) in stain.drops.enumerated() {
            let start = Double(i) / Double(stain.drops.count) * 0.35
            let grow = smoothstep(start, start + 0.3, t)
            let scaled = Chromatography.Drop(
                center: drop.center, radius: drop.radius,
                rings: drop.rings.map { ring in
                    Chromatography.Ring(points: ring.points.map { drop.center + ($0 - drop.center) * (0.15 + 0.85 * grow) },
                                        fraction: ring.fraction, tone: ring.tone)
                },
                fibers: grow > 0.99 ? drop.fibers : [])
            noStroke()
            for (band, ring) in zip(scaled.bands, scaled.rings) {
                fill(inks.color(at: ring.tone).withAlpha(0.55 + 0.35 * (1 - ring.tone)))
                drawShape(band)
            }
            noFill()
            stroke(Color(hex: 0x1B1A2E).withAlpha(drawsOutlines ? 0.8 : 0.35))
            strokeWeight((drawsOutlines ? 1.4 : 0.8) * scale)
            for line in scaled.fibers { drawPolyline(line) }
            if drawsOutlines {
                for ring in scaled.rings { drawPolygon(ring.points) }
            }
        }
    }
}
