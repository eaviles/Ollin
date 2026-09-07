import Ollin
import OllinAudio

/// A wave you can draw, and a note that moves through a row of them.
///
/// An oscillator traces one shape. A wavetable holds several side by side
/// and a note reads the blend of the two its `position` lands between, so the
/// sound has a shape that can change while it sounds. The frames of the
/// chosen table are stacked on the left, faintest to brightest, and the cycle
/// the next note will read is drawn over them in color. The sweep is what
/// moves that position over each note: strike bright and settle, or open up
/// slowly, depending on its sign and its envelope.
///
/// Pick a table. `basic` is the four plain shapes, `pulse` a square narrowing
/// to a spike, `vowels` five mouth shapes a note sings through, and `drawn` a
/// sine bent a little more in every frame, built from one line of code. Every
/// frame is kept at eleven strengths and a note reads the one that fits its
/// pitch, which is why the sawtooth stays clean at the top of the pattern.
@main
final class WavetableSketch: Sketch {

    enum Table: String, ParamOption { case basic, pulse, vowels, drawn }
    @Param(icon: "square.stack.3d.up", group: "Table") var table = Table.basic
    @Param(0 ... 1, icon: "slider.horizontal.below.rectangle", group: "Table") var position = 0.25
    @Param(-1 ... 1, icon: "arrow.left.arrow.right", group: "Scan") var sweep = 0.7
    @Param(0.02 ... 2, icon: "timer", group: "Scan") var settle = 0.6
    @Param(60 ... 160, icon: "metronome", group: "Playing") var tempo: Tempo = 92

    let synth = Synth(polyphony: 12)
    let pentatonic = Scale(.minorPentatonic, root: "C3")
    var counter = StepCounter(perBeat: 2)
    var trace: [Double] = []
    var built = ""
    var step = 0

    /// A sine bent harder in every frame: the whole table in one closure.
    static let drawn = Wavetable(name: "drawn", frameCount: 6) { phase, frame in
        sin(2 * .pi * pow(phase, 1 + 2.5 * frame))
    }

    override func setup() {
        synth.gain = 0.55
        synth.effects = [.reverb(Reverb(.hall, mix: 0.22))]
        rebuild()
    }

    private var recipe: String { "\(table)-\(position)-\(sweep)-\(settle)" }

    private var current: Wavetable {
        switch table {
        case .basic: return .basic
        case .pulse: return .pulse
        case .vowels: return .vowels
        case .drawn: return Self.drawn
        }
    }

    /// The whole feature in two lines: which table, and where in it a note
    /// reads. They are set apart because a table is far too large to travel
    /// inside a note.
    private func rebuild() {
        synth.wavetable = current
        synth.voice = Voice(
            wavetable: WavetableScan(position: position, sweep: sweep,
                                     envelope: Envelope(attack: 0.01, decay: settle,
                                                        sustain: 0.1, release: 0.3)),
            envelope: Envelope(attack: 0.01, decay: 0.4, sustain: 0.6, release: 0.5),
            gain: 0.75)
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        if built != recipe { rebuild() }

        for next in counter.steps(upTo: tempo.beats(at: time)) {
            step = next
            // Degrees past the end of the scale carry on into the next
            // octave, so every other bar sits five degrees up.
            let degree = [0, 2, 4, 3, 1, 5, 4, 2][next % 8] + (next / 8 % 2 == 0 ? 0 : 5)
            synth.play(pentatonic[degree], velocity: 0.8, for: 0.45)
        }
        if mouseIsPressed { slidePosition() }

        trace.append(Double(synth.amplitude))
        if trace.count > 320 { trace.removeFirst() }

        drawFrames()
        drawTrace()
        drawCaption("A row of cycles, read by position. The colored one is what the next note reads.",
                    edge: .top)
        drawCaption("Drag the position, or let the sweep move it over every note. "
                    + "Every frame is kept clean at every pitch.")
    }

    /// The frames stacked up the left, faint to full, and the cycle at the
    /// position drawn over them in color at the place it reads from.
    private func drawFrames() {
        let table = current
        let left = width * 0.12, right = width * 0.62
        let top = height * 0.2, bottom = height * 0.72
        let rows = table.frameCount
        let lane = (bottom - top) / Double(max(1, rows))

        for index in 0..<rows {
            let cycle = table.frame(index)
            let middle = bottom - (Double(index) + 0.5) * lane
            let along = rows > 1 ? Double(index) / Double(rows - 1) : 0
            noFill()
            stroke(Color(white: 0.35 + 0.55 * along))
            strokeWeight(1.4 * scale)
            drawCycle(cycle, left: left, right: right, middle: middle, height: lane * 0.42)
        }

        // Where the position sits between the frames, and the blend it reads.
        let middle = bottom - (position * Double(max(1, rows - 1)) + 0.5) * lane
        noFill()
        stroke(Color(hex: 0xE8A33D))
        strokeWeight(2.6 * scale)
        drawCycle(table.cycle(at: position), left: left, right: right,
                  middle: middle, height: lane * 0.42)

        noStroke()
        fill(Color(hex: 0xE8A33D))
        drawCircle(left - 14 * scale, middle, 5 * scale)
        fill(Color(white: 0.55))
        textSize(13 * scale)
        textAlign(.right)
        drawText(table.name, at: Vector2(left - 26 * scale, middle + 5 * scale))
        textAlign(.left)
        drawText(String(format: "position %.2f", position),
                 at: Vector2(right + 14 * scale, middle + 5 * scale))
    }

    private func drawCycle(_ cycle: [Double], left: Double, right: Double,
                           middle: Double, height: Double) {
        let stride = max(1, cycle.count / 256)
        let points = Swift.stride(from: 0, to: cycle.count, by: stride).map { index in
            Vector2(left + (right - left) * Double(index) / Double(cycle.count),
                    middle - cycle[index] * height)
        }
        drawPolyline(points)
    }

    /// What came out, so the shape and the sound are on one screen.
    private func drawTrace() {
        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.8))
        strokeWeight(2 * scale)
        let frame = Rectangle(x: width * 0.7, y: height * 0.22,
                              width: width * 0.22, height: height * 0.5)
        guard trace.count > 2 else { return }
        drawPolyline(trace.enumerated().map { index, value in
            Vector2(frame.x + frame.width * Double(index) / Double(max(1, trace.count - 1)),
                    frame.y + frame.height * (1 - min(value * 4, 1)))
        })
    }

    /// Slide the position by hand over the stack; the next note reads from there.
    private func slidePosition() {
        let left = width * 0.12, right = width * 0.62
        guard mouseX >= left - 40, mouseX <= right + 40 else { return }
        let top = height * 0.2, bottom = height * 0.72
        position = min(max(0, (bottom - mouseY) / (bottom - top)), 1)
    }
}
