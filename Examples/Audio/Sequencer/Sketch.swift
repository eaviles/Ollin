import Ollin
import OllinAudio

/// A drum machine's grid, and an arpeggiator running over it.
///
/// Three lanes of a `StepSequencer`, sixteen steps each: a kick, a snare, and
/// a hat. Every step holds its own loudness, a chance of playing, and a
/// ratchet, and the whole bar swings. Click a cell to turn it on or off. Under
/// the drums an `Arpeggiator` climbs the chord of the bar, one note a step,
/// and the chord changes every bar from a `Progression`.
///
/// Every note is asked for before its time. The sketch reads the patterns up
/// to where the music will be at the end of the frame, and the synth waits
/// the rest, so a swung offbeat or a ratchet's strikes land on their own
/// samples rather than on the frame that asked. Nothing here has a clock of
/// its own: the beat comes from the sketch clock through one `Tempo`.
@main
final class Sequencer: Sketch {

    @Param(60 ... 160, icon: "metronome", group: "Time") var tempo: Tempo = 112
    @Param(0.5 ... 0.75, icon: "arrow.right.to.line", group: "Time") var swing = 0.58
    @Param(0 ... 1, icon: "die.face.3", group: "Drums") var chance = 0.6

    @Param(icon: "arrow.up.arrow.down", group: "Arpeggio") var figure: Arpeggio.Pattern = .upDown
    @Param(1 ... 3, icon: "square.stack", group: "Arpeggio") var octaves = 2
    @Param(icon: "music.note", group: "Arpeggio") var rate: NoteLength = .sixteenth

    /// One bar, in steps. Sixteen sixteenths.
    let steps = 16

    /// A drum is a struck body; a snare and a hat are bursts of noise, each
    /// through its own band.
    let kick = Synth(.drum, polyphony: 4)
    let snare = Synth(Voice(
        waveform: .noise,
        envelope: Envelope(attack: 0.001, decay: 0.12, sustain: 0, release: 0.05),
        filter: Voice.Filter(mode: .bandpass, cutoff: 1800, resonance: 0.4),
        gain: 0.7
    ), polyphony: 4)
    let hat = Synth(Voice(
        waveform: .noise,
        envelope: Envelope(attack: 0.001, decay: 0.04, sustain: 0, release: 0.03),
        filter: Voice.Filter(mode: .highpass, cutoff: 7000, resonance: 0.3),
        gain: 0.45
    ), polyphony: 8)
    let keys = Synth(.pluck, polyphony: 12)

    /// The three lanes, written out. The hat is filled in by hand in `setup`
    /// so its offbeats can carry a chance and two steps a ratchet.
    var lanes: [StepSequencer] = [
        "40 . . . 40 . . . 40 . . 40 . . 40 .",
        ". . . . 62 . . . . . . . 62 . . 62",
        StepSequencer(count: 16),
    ]
    let names = ["kick", "snare", "hat"]
    let colors = [Color(hex: 0xF2B134), Color(hex: 0xE56B6F), Color(hex: 0x67C9D9)]

    var arp = Arpeggiator(.upDown, octaves: 2)
    let homeKey = Scale(.minor, root: "A2")
    lazy var changes = Progression("i VI III VII", in: homeKey)
    var bar = -1

    /// Where each strike lands on the picture, and on which beat.
    var flashes: [(lane: Int, step: Int, beat: Double)] = []
    var played: [(pitch: Pitch, beat: Double)] = []

    override func setup() {
        noStroke()
        kick.gain = 0.9
        keys.gain = 0.4
        keys.reverb = Reverb(.room, mix: 0.2)

        lanes[0].gate = 0.6
        lanes[1].gate = 0.5
        lanes[2].gate = 0.25
        for step in 0..<steps {
            let offbeat = step % 2 == 1
            lanes[2][step] = StepSequencer.Step(Pitch(96), velocity: offbeat ? 0.45 : 0.8,
                                                probability: offbeat ? chance : 1)
        }
        lanes[2][7] = StepSequencer.Step(Pitch(96), velocity: 0.7, ratchet: 3)
        lanes[2][15] = StepSequencer.Step(Pitch(96), velocity: 0.7, ratchet: 4)
    }

    override func draw() {
        background(Color(white: 0.05))

        // Where the music is now, and where it will be when this frame ends.
        // The patterns are read up to the second, and every note is played
        // from the first, so each lands on its own sample.
        let now = tempo.beats(at: time)
        let ahead = tempo.beats(at: time + deltaTime)

        for index in lanes.indices { lanes[index].swing = swing }
        for step in stride(from: 1, to: steps, by: 2) where lanes[2][step].ratchet == 1 {
            lanes[2][step].probability = chance
        }
        arp.pattern = figure
        arp.octaves = octaves
        arp.rate = rate
        arp.swing = swing

        // A new bar is a new chord. The held notes change and the figure
        // keeps its place in the ladder.
        let thisBar = Int((now / 4).rounded(.down))
        if thisBar != bar {
            bar = thisBar
            arp.notes = changes.pitches(at: bar)
        }

        for (index, synth) in [kick, snare, hat].enumerated() {
            let notes = lanes[index].events(upTo: ahead)
            synth.play(notes, tempo: tempo, from: now)
            for note in notes { flashes.append((index, note.step % steps, note.beat)) }
        }
        let figureNotes = arp.events(upTo: ahead)
        keys.play(figureNotes, tempo: tempo, from: now)
        for note in figureNotes { played.append((note.pitch, note.beat)) }

        drawGrid(now: now)
        drawLadder(now: now)
        drawCaption("\(tempo) · swing \(Int((swing * 100).rounded())) · \(figure.optionLabel) · \(rate)", edge: .top)
        drawCaption("Click a cell to turn it on or off. The hat's offbeats play by chance; two of its steps are ratchets.")
    }

    // MARK: The grid

    private var gridLeft: Double { Double(width) * 0.08 }
    private var gridTop: Double { Double(height) * 0.14 }
    private var cellWidth: Double { Double(width) * 0.84 / Double(steps) }
    private var cellHeight: Double { Double(height) * 0.1 }

    private func drawGrid(now: Double) {
        let seconds = tempo.secondsPerBeat
        flashes.removeAll { (now - $0.beat) * seconds > 0.4 }

        for (lane, sequencer) in lanes.enumerated() {
            let top = gridTop + Double(lane) * (cellHeight + 12 * scale)
            let color = colors[lane]

            for step in 0..<steps {
                let entry = sequencer[step]
                let x = gridLeft + Double(step) * cellWidth
                let inset = 3 * scale
                if entry.isRest {
                    fill(Color(white: step % 4 == 0 ? 0.16 : 0.11))
                    drawRect(x + inset, top + inset, cellWidth - 2 * inset, cellHeight - 2 * inset, cornerRadius: 4 * scale)
                    continue
                }
                // A struck step: as tall as its loudness, as solid as its
                // chance, and split into as many bars as its ratchet.
                let height = cellHeight * (0.35 + 0.65 * entry.velocity)
                let bars = entry.ratchet
                let gap = 2 * scale
                let barWidth = (cellWidth - 2 * inset - Double(bars - 1) * gap) / Double(bars)
                fill(color.withAlpha(0.3 + 0.7 * entry.probability))
                for bar in 0..<bars {
                    drawRect(x + inset + Double(bar) * (barWidth + gap), top + cellHeight - height,
                             barWidth, height - inset, cornerRadius: 3 * scale)
                }
            }

            fill(Color(white: 0.6))
            textFont(BitmapFont.builtIn)
            textSize(16 * scale)
            textAlign(.right)
            drawText(names[lane], gridLeft - 14 * scale, top + cellHeight * 0.62)
        }

        // The strikes as they land, brightest on their own beat.
        blendMode(.add)
        for flash in flashes {
            let age = max(0, (now - flash.beat) * seconds) / 0.4
            guard age <= 1 else { continue }
            let top = gridTop + Double(flash.lane) * (cellHeight + 12 * scale)
            let x = gridLeft + Double(flash.step) * cellWidth
            fill(Color.white.withAlpha((1 - age) * 0.35))
            drawRect(x, top, cellWidth, cellHeight, cornerRadius: 4 * scale)
        }
        blendMode(.normal)

        // The playhead sweeps evenly. The swing is in when the notes sound,
        // not in where the bar is.
        let position = now * 4 - Double(Int((now * 4 / Double(steps)).rounded(.down)) * steps)
        let x = gridLeft + position * cellWidth
        stroke(Color(white: 0.85))
        strokeWeight(1.5 * scale)
        drawLine(x, gridTop - 10 * scale, x, gridTop + 3 * cellHeight + 2 * 12 * scale + 10 * scale)
        noStroke()
    }

    // MARK: The ladder

    private func drawLadder(now: Double) {
        let seconds = tempo.secondsPerBeat
        played.removeAll { (now - $0.beat) * seconds > 2.5 }

        let top = gridTop + 3 * cellHeight + 2 * 12 * scale + 50 * scale
        let bottom = Double(height) * 0.86
        let order = arp.figure.order
        guard !order.isEmpty else { return }
        let low = (order.min()?.midi ?? 48) - 2
        let high = (order.max()?.midi ?? 72) + 2
        func y(_ pitch: Pitch) -> Double {
            bottom - (pitch.midi - low) / max(1, high - low) * (bottom - top)
        }

        // The figure as the arpeggiator will play it, one column a step.
        let columns = Double(order.count)
        let columnWidth = Double(width) * 0.84 / columns
        stroke(Color(white: 0.18))
        strokeWeight(1 * scale)
        for pitch in Set(order) {
            drawLine(gridLeft, y(pitch), gridLeft + Double(width) * 0.84, y(pitch))
        }
        noStroke()
        for (index, pitch) in order.enumerated() {
            let x = gridLeft + (Double(index) + 0.5) * columnWidth
            let isNext = arp.next == pitch && index == order.firstIndex(of: pitch)
            fill(isNext ? Color.white : Color(hex: 0xB59CF2).withAlpha(0.7))
            drawCircle(x, y(pitch), (isNext ? 7 : 5) * scale)
        }

        // What was just played, drifting left as it ages.
        blendMode(.add)
        for note in played {
            let age = (now - note.beat) * seconds / 2.5
            guard age >= 0, age <= 1 else { continue }
            let x = gridLeft + Double(width) * 0.84 * (1 - age)
            fill(Color(hex: 0xB59CF2).withAlpha((1 - age) * 0.9))
            drawCircle(x, y(note.pitch), (3 + (1 - age) * 6) * scale)
        }
        blendMode(.normal)

        fill(Color(white: 0.6))
        textFont(BitmapFont.builtIn)
        textSize(16 * scale)
        textAlign(.right)
        drawText("keys", gridLeft - 14 * scale, (top + bottom) / 2)
        textAlign(.left)
        let chord = changes.pitches(at: bar).map { "\($0)" }.joined(separator: " ")
        drawText(chord, gridLeft, bottom + 26 * scale)
    }

    // MARK: The mouse

    override func mousePressed() {
        let column = Int(((mouse.x - gridLeft) / cellWidth).rounded(.down))
        guard column >= 0, column < steps else { return }
        for lane in lanes.indices {
            let top = gridTop + Double(lane) * (cellHeight + 12 * scale)
            guard mouse.y >= top, mouse.y < top + cellHeight else { continue }
            let pitches: [Pitch] = [40, 62, 96]
            if lanes[lane][column].isRest {
                lanes[lane][column] = StepSequencer.Step(pitches[lane], velocity: 0.8)
            } else {
                lanes[lane][column] = .rest
            }
        }
    }
}
