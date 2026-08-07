import Ollin
import OllinAudio

/// Shapes you can hit, that sound like the shape they are.
///
/// A flat thing held at its edge rings at frequencies decided entirely by its
/// outline. Working them out is a matter of asking which standing waves fit
/// inside the shape, which is what `StruckShape` does: measure the outline
/// once, then strike it anywhere.
///
/// Nothing here chooses a sound. The round one comes out with the ratios a real
/// drumhead has, the square one with a square membrane's, and the blob with
/// whatever its own outline implies. The bars under each shape are those
/// ratios, drawn where they fall.
///
/// Click a shape to strike it where you clicked. Where you hit it decides which
/// of its tones answer, because a tone that holds still under your finger gets
/// nothing, which is why the bars move when you move the click.
@main
final class StruckShapes: Sketch {

    @Param(0.2 ... 8, icon: "clock", group: "Body") var ring = 2.6
    @Param(0 ... 2.5, icon: "square.3.layers.3d.down.right", group: "Body") var damping = 0.9
    @Param(0 ... 1, icon: "hammer", group: "Strike") var hardness = 0.7

    struct Piece {
        var name: String
        var outline: Shape
        var measured: StruckShape?
        var center: Vector2
        var pitch: Pitch
        /// Where it was last struck, and when.
        var hit: (at: Vector2, start: Double)?
        var gains: [Double] = []
    }

    let synth = Synth(.chime, polyphony: 12)
    var pieces: [Piece] = []
    var lastStrike = -3.0

    override func setup() {
        synth.gain = 0.42
        synth.reverb = Reverb(.hall, mix: 0.22)

        let radius = Double(width) * 0.115
        let outlines: [(String, Shape, Pitch)] = [
            ("circle", Self.polygon(sides: 96, radius: radius), "C4"),
            ("square", Self.polygon(sides: 4, radius: radius * 1.05, turn: .pi / 4), "E4"),
            ("triangle", Self.polygon(sides: 3, radius: radius * 1.2), "G4"),
            ("ring", Self.ring(outer: radius, inner: radius * 0.45), "A3"),
            ("oblong", Self.oblong(width: radius * 2.3, height: radius * 1.1), "D4"),
            ("blob", Self.blob(radius: radius), "F4"),
        ]

        // Measured once, here, because it is real arithmetic. Striking one
        // afterwards costs nothing.
        for (index, entry) in outlines.enumerated() {
            let column = index % 3
            let row = index / 3
            let center = Vector2(Double(width) * (0.24 + Double(column) * 0.26),
                                 Double(height) * (0.28 + Double(row) * 0.35))
            pieces.append(Piece(name: entry.0, outline: entry.1,
                                measured: StruckShape(entry.1, modes: 10),
                                center: center, pitch: entry.2))
        }
    }

    override func draw() {
        background(Color(hex: 0x111318))

        // It plays itself until somebody plays it, so it never looks broken.
        if time - lastStrike > 1.5, !pieces.isEmpty {
            let index = Int(random(0, Double(pieces.count)))
            let spread = Double(width) * 0.09
            let offset = Vector2(random(-spread, spread), random(-spread, spread))
            strike(index, at: pieces[index].center + offset)
        }

        for index in pieces.indices { drawPiece(index) }

        drawCaption("Click a shape to strike it where you clicked.", edge: .top)
        drawCaption("Nothing here picks a sound. Each shape rings at the frequencies "
                    + "its own outline allows.")
    }

    override func mousePressed() {
        let point = Vector2(mouseX, mouseY)
        for index in pieces.indices {
            let local = point - pieces[index].center
            if pieces[index].outline.contains(local) { strike(index, at: point); return }
        }
    }

    private func strike(_ index: Int, at point: Vector2) {
        guard let measured = pieces[index].measured else { return }
        let local = point - pieces[index].center
        let body = measured.body(struckAt: local, decay: ring,
                                 damping: damping, hardness: hardness)

        synth.voice = Voice(body: body, gain: 0.9)
        synth.play(pieces[index].pitch, velocity: 0.9, for: ring)

        pieces[index].hit = (at: local, start: time)
        pieces[index].gains = body.modes.map(\.gain)
        lastStrike = time
    }

    // MARK: Drawing

    private func drawPiece(_ index: Int) {
        let piece = pieces[index]
        var glow = 0.0
        if let hit = piece.hit {
            glow = max(0, 1 - (time - hit.start) / max(0.2, ring))
            if glow < 0.01 { pieces[index].hit = nil }
        }

        withState {
            translate(piece.center)
            // The outline swells a little where it was struck, so the picture
            // says where the sound came from.
            let swell = 1 + pow(glow, 0.5) * 0.035
            scale(swell, swell)

            noStroke()
            fill(Color(white: 0.16))
            drawShape(piece.outline)

            noFill()
            stroke(Colormap.magma.color(at: 0.35 + glow * 0.45)
                .withAlpha(0.45 + glow * 0.55))
            strokeWeight((1.4 + glow * 2.2) * scale)
            drawShape(piece.outline)

            if let hit = piece.hit, glow > 0.01 {
                noStroke()
                fill(Color(white: 1).withAlpha(glow))
                drawCircle(center: hit.at, radius: (3 + glow * 5) * scale)
            }
        }

        // What it rings at, drawn where those tones fall. The height of each is
        // how much the last strike put into it, which is why the picture
        // changes when you hit the same shape somewhere else.
        let ratios = piece.measured?.ratios ?? []
        let baseline = piece.center.y + Double(height) * 0.15
        let span = Double(width) * 0.19
        let widest = ratios.max() ?? 1
        noStroke()
        for (mode, ratio) in ratios.enumerated() {
            let x = piece.center.x - span / 2 + ratio / widest * span
            let gain = mode < piece.gains.count ? piece.gains[mode] : 0.25
            let tall = (5 + gain * 26 * (0.25 + 0.75 * glow)) * scale
            fill(Color(white: 0.75).withAlpha(0.25 + glow * 0.6))
            drawRect(corner: Vector2(x - 1.2 * scale, baseline - tall),
                     width: 2.4 * scale, height: tall)
        }

        fill(Color(white: 0.45))
        textFont(OutlineFont.system)
        textSize(14 * scale)
        textAlign(.center, .top)
        drawText(piece.name, piece.center.x, baseline + 8 * scale)
    }

    // MARK: Shapes to strike

    private static func polygon(sides: Int, radius: Double, turn: Double = 0) -> Shape {
        Shape((0..<sides).map { step in
            let angle = Double(step) / Double(sides) * .tau - .pi / 2 + turn
            return Vector2(cos(angle), sin(angle)) * radius
        })
    }

    private static func ring(outer: Double, inner: Double) -> Shape {
        Shape(outer: polygon(sides: 96, radius: outer).contours[0].points,
              holes: [polygon(sides: 72, radius: inner).contours[0].points])
    }

    private static func oblong(width: Double, height: Double) -> Shape {
        Shape([Vector2(-width / 2, -height / 2), Vector2(width / 2, -height / 2),
               Vector2(width / 2, height / 2), Vector2(-width / 2, height / 2)])
    }

    /// A shape with no name, to make the point that any outline works.
    private static func blob(radius: Double) -> Shape {
        Shape((0..<120).map { step in
            let angle = Double(step) / 120 * .tau
            let wobble = 1 + 0.26 * sin(angle * 3 + 0.7) + 0.13 * sin(angle * 5 - 1.9)
            return Vector2(cos(angle), sin(angle)) * radius * wobble
        })
    }
}
