import Ollin
import OllinAudio

/// A piece that carries its own sound out of the window.
///
/// Everything else in this folder makes sound you have to be there to hear.
/// This one exports:
///
/// ```sh
/// swift run --package-path Examples Example-Audio-SoundInAnExport --export-video piece.mp4 --frames 480
/// ```
///
/// and the file has the music in it. There is no recording step. The exporters
/// drive a sketch on a fixed clock with nothing playing, so the notes it asks
/// for are written down instead, and the soundtrack is rendered at the end
/// through the same code that would have fed the speakers. That works because
/// the renderer takes events and gives back samples and has no clock of its
/// own: an export is that same code with the waiting taken out.
///
/// Which also means the file reproduces. Export it twice and you get the same
/// music, because the notes come from a seeded chain over a Euclidean rhythm
/// and nothing here reads a clock it does not own.
@main
final class SoundInAnExport: Sketch {
    override var canvasSize: CanvasSize { .square(720) }
    /// Eight bars at 96 beats a minute, so `--export-loop` closes cleanly.
    override var loopDuration: Double? { tempo.seconds(bars: 8) }

    let tempo: Tempo = 96
    let steps = 16

    let bass = Synth(.nylon, polyphony: 6)
    let bells = Synth(.chime, polyphony: 10)

    let pulse = Rhythm(3, in: 16)
    let sparkle = Rhythm(7, in: 16)
    let tuning = Scale(.minorPentatonic, root: "A2")

    var counter = StepCounter(perBeat: 4)
    var melody = MarkovChain<Int>(seed: 9)
    var marks: [(x: Double, y: Double, start: Double, tone: Double, big: Bool)] = []

    override func setup() {
        seed(4321)
        noStroke()
        bass.gain = 0.5
        bells.gain = 0.3
        bells.reverb = Reverb(.hall, mix: 0.32)
        melody.learn([0, 2, 4, 2, 0, -3, 0, 5], loops: true)
        melody.start(at: 0)
    }

    override func draw() {
        background(Color(hex: 0x0D0F14))

        for step in counter.steps(upTo: tempo.beats(at: time)) {
            play(step)
        }

        marks.removeAll { time - $0.start > 2.4 }
        blendMode(.add)
        for mark in marks {
            let age = (time - mark.start) / 2.4
            let radius = (mark.big ? 26.0 : 9.0) * (1 + age * 2.6) * scale
            fill(Colormap.magma.color(at: 0.3 + mark.tone * 0.55)
                .withAlpha(pow(1 - age, 1.6) * 0.8))
            drawCircle(mark.x, mark.y, radius)
        }
        blendMode(.normal)

        drawCaption("Export it and the file has the music in it.")
    }

    private func play(_ step: Int) {
        let across = Double(width)
        let down = Double(height)

        if pulse[step] {
            let degree = melody.next() ?? 0
            bass.play(tuning[degree], velocity: 0.9, for: 0.5)
            marks.append((x: across * 0.5 + Double(degree) * across * 0.055,
                          y: down * 0.66, start: time,
                          tone: Double((degree + 6) % 8) / 8, big: true))
        }

        if sparkle[step] {
            let inBar = ((step % steps) + steps) % steps
            let pitch = tuning[6 + inBar % 5]
            bells.play(pitch, velocity: 0.5, for: 1.6)
            marks.append((x: across * (0.12 + Double(inBar) / Double(steps) * 0.76),
                          y: down * 0.34, start: time,
                          tone: (pitch.midi - 45) / 40, big: false))
        }
    }
}
