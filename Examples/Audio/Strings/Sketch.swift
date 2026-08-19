import Ollin
import OllinAudio

/// Six strings you pluck by clicking on them, wherever you click.
///
/// A `PluckedString` voice is not a wave being drawn. It is a delay line as
/// long as one period with a filtered loop round it, which is a disturbance
/// running up and down a string and losing a little at each end. Everything you
/// hear falls out of that rather than being dialed in.
///
/// Where you click along a string is the pick position, and it is the setting
/// that sounds least like a synthesizer. A string held at a point cannot move
/// there, so every harmonic with a node at that point goes missing. Click near
/// the middle for a hollow tone, near the end for a thin nasal one.
///
/// The shape drawn on each string is the same fact: it is the sum of the modes
/// a pluck at that point actually excites, which is the triangle your finger
/// left behind. The picture and the sound are one decision.
@main
final class Strings: Sketch {

    @Param(0 ... 1, icon: "hand.point.up.left", group: "Pluck") var hardness = 0.6
    @Param(0.2 ... 8, icon: "clock", group: "String") var ring = 3.2
    @Param(0 ... 1, icon: "square.3.layers.3d.down.right", group: "String") var damping = 0.5

    /// Standard tuning, lowest at the bottom of the picture.
    let tuning: [Pitch] = ["E2", "A2", "D3", "G3", "B3", "E4"]
    let synth = Synth(.steel, polyphony: 12)

    /// What each string is doing: where it was plucked and when.
    var plucked = [(pick: Double, start: Double, velocity: Double)?](repeating: nil, count: 6)
    /// When something last played, so the sketch plays itself until you do.
    var lastPluck = -2.0

    override func setup() {
        synth.gain = 0.45
        synth.reverb = Reverb(.hall, mix: 0.16)
    }

    override func draw() {
        background(Color(hex: 0x14110F))

        // A sketch that makes no sound until it is clicked looks broken, so it
        // plays itself while nobody is.
        if time - lastPluck > 1.0 {
            pluck(string: Int(random(0, 6)), at: random(0.1, 0.9))
        }

        for (index, pitch) in tuning.enumerated() {
            drawString(index: index, pitch: pitch)
        }
        drawTrace()

        drawCaption("Click a string where you want to pluck it. Near the middle is hollow, "
                    + "near the end is thin.", edge: .top)
        drawCaption("Six plucked strings. What you hear is a delay line with a filtered loop, "
                    + "not a wave.")
    }

    override func mousePressed() { pluck() }

    private func pluck() {
        let index = nearestString()
        guard index >= 0 else { return }
        pluck(string: index, at: mouseX / Double(width))
    }

    private func pluck(string index: Int, at position: Double) {
        guard tuning.indices.contains(index) else { return }
        let pick = min(max(0.02, position), 0.98)
        lastPluck = time

        // Changing the voice does not disturb notes already ringing, so each
        // pluck can have its own pick position and the previous ones carry on.
        synth.voice = Voice(
            string: PluckedString(pick: pick, hardness: hardness, decay: ring, damping: damping),
            gain: 0.85
        )
        // The note is held for as long as the string would ring, so the
        // envelope never cuts the string off before it has finished.
        synth.play(tuning[index], velocity: 0.9, for: ring)
        plucked[index] = (pick: pick, start: time, velocity: 0.9)
    }

    private func nearestString() -> Int {
        var best = -1
        var bestDistance = Double.infinity
        for index in tuning.indices {
            let distance = abs(mouseY - y(of: index))
            if distance < bestDistance { bestDistance = distance; best = index }
        }
        return bestDistance < spacing * 0.45 ? best : -1
    }

    // MARK: Drawing

    private var spacing: Double { Double(height) * 0.113 }
    private func y(of index: Int) -> Double {
        Double(height) * 0.19 + Double(index) * spacing
    }

    private func drawString(index: Int, pitch: Pitch) {
        let baseline = y(of: index)
        let left = Double(width) * 0.08
        let right = Double(width) * 0.92
        let span = right - left

        var amount = 0.0
        var pick = 0.5
        if let hit = plucked[index] {
            // The same fall the string itself takes, so the picture stops when
            // the sound does.
            let age = time - hit.start
            amount = hit.velocity * exp(-6.9078 * age / ring)
            pick = hit.pick
            if amount < 0.004 { plucked[index] = nil }
        }

        // The shape a pluck at that point leaves: every mode the pluck excites,
        // at the amplitude it excites it. The modes with a node under the
        // finger get nothing, which is exactly what the comb in the string
        // model takes out of the sound.
        let thickness = 1.2 + Double(5 - index) * 0.5
        // Drawn on a compressed scale. A real string's visible swing is gone
        // long before the sound is, and the picture is here to show where the
        // pluck was for as long as you can still hear it.
        let swing = pow(amount, 0.45) * spacing * 0.5
        let steps = 120

        func displacement(at along: Double) -> Double {
            var total = 0.0
            for mode in 1...24 {
                let harmonic = Double(mode)
                total += sin(harmonic * .pi * pick) / (harmonic * harmonic)
                    * sin(harmonic * .pi * along)
            }
            return total
        }

        // The shape is drawn to the same height whatever the pick position, so
        // what the picture shows is where the peak is and which modes are
        // missing rather than how big the sum happens to come out.
        let tallest = max(1e-6, abs(displacement(at: pick)))
        var top = [Vector2]()
        var bottom = [Vector2]()
        for step in 0...steps {
            let along = Double(step) / Double(steps)
            let x = left + along * span
            let offset = displacement(at: along) / tallest * swing
            top.append(Vector2(x, baseline - offset))
            bottom.append(Vector2(x, baseline + offset))
        }

        noFill()
        let glow = Colormap.magma.color(at: 0.42 + Double(index) * 0.07)
        stroke(Color(white: 0.42).withAlpha(0.9))
        strokeWeight(thickness * scale)
        drawLine(Vector2(left, baseline), Vector2(right, baseline))

        if amount > 0.004 {
            stroke(glow.withAlpha(0.85))
            strokeWeight(thickness * scale)
            drawPolyline(top)
            drawPolyline(bottom)

            noStroke()
            fill(glow)
            drawCircle(left + pick * span, baseline, 4.5 * scale)
        }

        noStroke()
        fill(Color(white: 0.5))
        textFont(OutlineFont.system)
        textSize(15 * scale)
        textAlign(.right, .middle)
        drawText("\(pitch)", left - 16 * scale, baseline)
    }

    /// What the synth is actually putting out, read back off its own playing.
    private func drawTrace() {
        let trace = synth.waveform
        guard !trace.isEmpty else { return }
        let baseline = Double(height) * 0.895
        let left = Double(width) * 0.08
        let span = Double(width) * 0.84

        noFill()
        stroke(Color(white: 0.3))
        strokeWeight(1.4 * scale)
        drawPolyline(trace.indices.map { index in
            Vector2(left + Double(index) / Double(trace.count - 1) * span,
                    baseline - Double(trace[index]) * spacing * 2.6)
        })
    }
}
