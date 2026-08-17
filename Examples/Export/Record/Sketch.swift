import Ollin
import OllinAudio

/// Record a run while you play it.
///
/// The offline exporters re-render a sketch on a fixed clock, which is how a
/// file reproduces exactly. A performance is the opposite kind of thing: the
/// mouse, the knobs, and the sound happen once, in real time. This sketch
/// keeps that once. Press **R** and play; press **R** again and the take is a
/// movie in `~/Movies/Ollin/`, picture and sound together, stamped with the
/// wall clock so a slow frame lasts longer instead of stretching time.
///
/// The sound needs no wiring: the recorder finds the instruments the sketch
/// is holding, the same way the offline exporters do. In the live hosts the
/// same recording is on ⌘⇧R, and there it even survives an evaluate.
@main
final class Record: Sketch {
    override var canvasSize: CanvasSize { .square(900) }

    let strings = Synth(.nylon, polyphony: 8)
    let tuning = Scale(.minorPentatonic, root: "A2")

    var ripples: [(x: Double, y: Double, born: Double)] = []
    var nextPluck = 0.0

    override func setup() {
        strings.gain = 0.6
        strings.reverb = Reverb(.hall, mix: 0.3)
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x101318))

        // A quiet pulse of its own, so a hands-off take still has a heartbeat.
        if time >= nextPluck {
            nextPluck = time + 1.5
            strings.play(tuning[0], velocity: 0.35, for: 1.2)
            ripples.append((width / 2, height / 2, time))
        }

        // Dragging plays: height picks the note, the ripple marks it.
        if mouseIsPressed, time >= lastStroke + 0.12 {
            lastStroke = time
            let step = Int((1 - mouseY / height) * 9)
            strings.play(tuning[step], velocity: 0.8, for: 0.8)
            ripples.append((mouseX, mouseY, time))
        }

        ripples.removeAll { time - $0.born > 2 }
        for ripple in ripples {
            let age = time - ripple.born
            let radius = 20 + age * 150
            fill(Color(hue: 0.55 + age * 0.1, saturation: 0.5, brightness: 0.9,
                       alpha: (1 - age / 2) * 0.8))
            drawRing(ripple.x, ripple.y, radius, radius + 4)
        }

        // The level, drawn: the same loudness the recording is hearing.
        fill(Color(white: 0.9, alpha: 0.8))
        let level = Double(strings.amplitude) * 500
        drawRect(width / 2 - level / 2, height - 60, level, 6)
    }

    override func keyPressed() {
        guard key == "r" || key == "R" else { return }
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private var lastStroke = 0.0
}
