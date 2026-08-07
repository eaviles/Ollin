import Ollin
import OllinAudio

/// Numbers you can hear.
///
/// A line across a landscape is drawn as a profile and read out as a tune at
/// the same time, from the same numbers. The playhead is the note sounding, so
/// the picture and the sound are two views of one series rather than a chart
/// with a soundtrack bolted on.
///
/// Two things worth listening for. The pitches are snapped through a `Scale`,
/// so the reading stays in key however the ground moves: change the key with
/// the knob and the same hills come out in a different mood. And the pale line
/// across the middle is a *reference*: it sounds its own note every bar, so you
/// hear each hill as above or below something instead of having to know what
/// any one note means. It is the grid line of an ordinary chart, in sound.
///
/// Press `S` to read the picture instead of the ground, which is the same call
/// with a different source.
@main
final class Sonify: Sketch {

    enum Source: String, ParamOption { case terrain, picture }

    // Named `mode` rather than `key`, which is the keyboard's on a `Sketch`.
    @Param(icon: "waveform", group: "Reading") var source = Source.terrain
    @Param(icon: "music.note", group: "Reading") var mode = Scale.Mode.minorPentatonic
    @Param(40 ... 160, icon: "metronome", group: "Reading") var tempo = 96.0
    @Param(icon: "arrow.up.arrow.down", group: "Reading") var moreIsHigher = true

    let synth = Synth(.pluck, polyphony: 12)
    let marker = Synth(.sine, polyphony: 4)

    var land = Heightfield(columns: 2, rows: 2)
    var picture = Image(width: 1, height: 1, color: .black)
    var reading = Sonification([])
    var counter = StepCounter(perBeat: 2)
    var playhead = 0
    var lit: [Double] = []

    override func setup() {
        synth.gain = 0.5
        synth.reverb = Reverb(.hall, mix: 0.22)
        marker.gain = 0.16

        // The ground, and a picture made from it, so both readings are of the
        // same landscape and can be compared by ear.
        land = Heightfield(columns: 220, rows: 64) { u, v in
            fbm(u * 2.4, v * 2.4, octaves: 5)
        }.normalized()
        picture = Image(width: 220, height: 64, color: .black)
        for x in 0 ..< 220 {
            for y in 0 ..< 64 {
                picture[x, y] = Colormap.magma.color(at: land[x, y])
            }
        }
        rebuild()
    }

    /// The whole feature, in one call: a row of the landscape becomes a tune.
    private func rebuild() {
        built = Settings(source: source, mode: mode, moreIsHigher: moreIsHigher)
        let scale = Scale(mode, root: "A2")
        switch source {
        case .terrain:
            reading = Sonification(land, row: 32, in: scale,
                                   pitches: "A2"..."A5", length: 0.5)
        case .picture:
            reading = Sonification(picture, row: 32, in: scale,
                                   pitches: "A2"..."A5", length: 0.5)
        }
        if !moreIsHigher { reading = reading.inverted() }
        lit = [Double](repeating: 0, count: reading.count)
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))

        // The knobs rebuild the reading, so a change is heard on the next note.
        if built != Settings(source: source, mode: mode, moreIsHigher: moreIsHigher) {
            rebuild()
        }

        for step in counter.steps(upTo: time * tempo / 60) {
            let index = step % max(1, reading.count)
            playhead = index
            if index < lit.count { lit[index] = 1 }
            synth.play(reading, step: index, tempo: tempo)

            // The reference sounds once a bar, quietly, under the reading.
            if step % 8 == 0 {
                marker.play(reading.reference(at: referenceValue), tempo: tempo)
            }
        }

        drawProfile()
        drawCaption("A line across the landscape, drawn and read out at once. "
                    + "The pale line is the reference note.", edge: .top)
        drawCaption("S changes what is being read. The reading is snapped to a "
                    + "scale, so the ground always lands in key.")
    }

    /// The value the reference note sounds: the middle of the reading's range,
    /// which is the sea level of this landscape.
    private var referenceValue: Double {
        (reading.domain.lowerBound + reading.domain.upperBound) / 2
    }

    /// What the current reading was built from, so a knob turn rebuilds it and
    /// nothing else does.
    struct Settings: Equatable {
        var source: Source
        var mode: Scale.Mode
        var moreIsHigher: Bool
    }
    private var built = Settings(source: .terrain, mode: .major, moreIsHigher: true)

    private func drawProfile() {
        guard !reading.isEmpty else { return }
        let frame = Rectangle(x: width * 0.08, y: height * 0.28,
                              width: width * 0.84, height: height * 0.44)
        let right = frame.x + frame.width, bottom = frame.y + frame.height

        // The profile itself, as a filled area under the line.
        let low = reading.domain.lowerBound, high = reading.domain.upperBound
        let span = max(1e-9, high - low)
        func point(_ index: Int) -> Vector2 {
            let t = Double(index) / Double(max(1, reading.count - 1))
            let value = (reading.values[index] - low) / span
            return Vector2(frame.x + frame.width * t,
                           bottom - frame.height * value)
        }

        // Through the shape builder rather than drawPolygon: a profile is
        // concave wherever the ground dips, and a polygon fill is a fan from
        // the first point, which would bridge straight across every valley.
        noStroke()
        fill(Color(hex: 0x1B2A3A))
        drawShape { path in
            path.move(to: Vector2(frame.x, bottom))
            for index in 0 ..< reading.count { path.line(to: point(index)) }
            path.line(to: Vector2(right, bottom))
            path.close()
        }

        stroke(Color(hex: 0x6FB8E0))
        strokeWeight(2 * scale)
        noFill()
        drawPolyline((0 ..< reading.count).map(point))

        // The reference, drawn where it sounds.
        let referenceY = bottom - frame.height * ((referenceValue - low) / span)
        stroke(Color(white: 0.55, alpha: 0.5))
        strokeWeight(1 * scale)
        drawLine(frame.x, referenceY, right, referenceY)

        // Each reading lights as it is played and fades, so the playhead leaves
        // a trail of what has just been heard.
        noStroke()
        for index in lit.indices where lit[index] > 0.01 {
            lit[index] *= pow(0.02, deltaTime)
            let at = point(index)
            fill(Colormap.magma.color(at: 0.35 + reading.values[index] * 0.5)
                .withAlpha(lit[index]))
            drawCircle(at.x, at.y, (3 + lit[index] * 7) * scale)
        }

        // The note sounding now.
        let head = point(playhead)
        stroke(Color(white: 0.9, alpha: 0.7))
        strokeWeight(1.5 * scale)
        drawLine(head.x, frame.y, head.x, bottom)
        noStroke()
        fill(.white)
        drawCircle(head.x, head.y, 5 * scale)

        // What is sounding, named, so the mapping is legible.
        if let note = reading.note(at: playhead) {
            fill(Color(white: 0.75))
            textSize(20 * scale)
            textAlign(.center)
            drawText("\(note.pitch)", at: Vector2(width / 2, bottom + 46 * scale))
        }
    }

    override func keyPressed() {
        guard key == "s" || key == "S" else { return }
        source = source == .terrain ? .picture : .terrain
    }
}
