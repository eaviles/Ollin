import Ollin
import OllinAudio

/// Playing along with the room.
///
/// A `BeatFollower` listens to the microphone and turns detected onsets into
/// musical time: a tempo, a beat position, and how much to trust both. Clap or
/// play a steady pulse and watch it lock: the ring starts breathing on the
/// beat, the tempo appears in the middle, and once `isFollowing` comes on the
/// sketch joins in, playing a note on every beat it believes in.
///
/// The picture separates what is heard from what is inferred. The small disc
/// flashes on every raw onset the analyzer detects; the ring pulses on the
/// *musical* beat the follower has settled on, which carries on between onsets
/// and survives a missed one. The outer arc is `steadiness`, how much the
/// recent gaps agree with each other: a machine reads near one, a hand reads
/// lower, and a guessing detector reads low enough to ignore.
///
/// The dots around the ring are `rhythm(steps: 16)`, the room's own pattern
/// built from where the onsets actually fell, so a pattern with a gap in it
/// comes back with that gap.
///
/// Until the microphone is allowed, a generated pulse stands in: the sketch
/// gates an oscillator at a parameter tempo and the follower follows *that*, so the
/// whole mechanism is visible before any permission is granted. Allow the
/// microphone and the room takes over. On speakers the sketch's own note lands
/// on the beat it heard and reinforces it; headphones keep the lock honest.
///
/// Press `R` to make it forget everything, for when the music changes.
@main
final class PlayAlong: Sketch {

    @Param(70 ... 140, icon: "metronome", group: "Stand-in") var practiceTempo = 96.0
    @Param(0 ... 1, icon: "speaker.wave.2", group: "Playing") var replyLevel = 0.5

    let mic = AudioInput()
    let pulse = Tone(frequency: 220, amplitude: 0, waveform: .sawtooth)
    lazy var micRoom = BeatFollower(mic)
    lazy var pulseRoom = BeatFollower(pulse)

    let synth = Synth(.pluck, polyphony: 8)
    let pentatonic = Scale(.minorPentatonic, root: "A3")
    var counter = StepCounter(perBeat: 1)

    var pulsePlaying = false
    var onsetFlash = 0.0
    var lastRawCount = 0

    override func setup() {
        synth.gain = 0.5
        synth.reverb = Reverb(.room, mix: 0.2)
        try? mic.start()
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))

        // The microphone the moment it is allowed; the generated pulse until
        // then. Each source has its own follower, so switching never mixes
        // one clock into the other.
        let live = mic.isRunning
        if live, pulsePlaying { pulse.stop(); pulsePlaying = false }
        if !live, !pulsePlaying { pulse.play(); pulsePlaying = true }
        if !live { drivePulse() }

        let room = live ? micRoom : pulseRoom
        room.update(at: time)

        // The raw onsets, kept apart from the inferred beat on purpose.
        let source: any AudioSource = live ? mic : pulse
        if source.beatCount > lastRawCount { onsetFlash = 1 }
        lastRawCount = source.beatCount
        onsetFlash *= pow(0.02, deltaTime)

        // Once it is following, play along: one note per beat it believes in.
        if room.isFollowing {
            for step in counter.steps(upTo: room.beats) {
                synth.play(pentatonic[[0, 4, 2, 3][step % 4]],
                           velocity: 0.35 + replyLevel * 0.5, for: 0.22)
            }
        }

        drawFollower(room)
        drawCaption("Playing along with the room: onsets in, musical time out.",
                    edge: .top)
        drawCaption(status(live: live, room: room))
    }

    /// Gates the stand-in oscillator at the parameter tempo: silence, then a short
    /// decaying burst on each beat, which is exactly the kind of arrival the
    /// onset detector listens for. Two alternating pitches keep it musical.
    private func drivePulse() {
        let beat = time * practiceTempo / 60
        let phase = beat - beat.rounded(.down)
        let within = phase * 60 / practiceTempo
        pulse.frequency = Int(beat) % 2 == 0 ? 220 : 165
        pulse.amplitude = within < 0.16 ? 0.22 * (1 - within / 0.16) : 0
    }

    private func drawFollower(_ room: BeatFollower) {
        let middle = Vector2(width / 2, height * 0.5)
        let radius = shortSide * 0.24

        // Where the beat is, carried forward between onsets. The kick eases
        // out from each whole beat, so the ring lands rather than sweeps.
        let beats = room.beats
        let phase = beats - beats.rounded(.down)
        let kick = room.isFollowing ? pow(1 - phase, 3) : 0.1 + 0.05 * sin(time * 2)

        // The outer arc: steadiness, the number that says how much to trust
        // the rest of the picture.
        noFill()
        stroke(Color(white: 0.2))
        strokeWeight(5 * scale)
        drawCircle(center: middle, radius: radius * 1.35)
        if room.steadiness > 0 {
            stroke(Colormap.viridis.color(at: room.steadiness).withAlpha(0.9))
            strokeWeight(7 * scale)
            drawArc(center: middle, radiusX: radius * 1.35, radiusY: radius * 1.35,
                    start: -Double.pi / 2,
                    stop: -Double.pi / 2 + room.steadiness * .tau, mode: .open)
        }

        // The room's own pattern: sixteen steps, lit where onsets fell.
        let heard = room.rhythm(steps: 16)
        for step in 0 ..< heard.length {
            let angle = -Double.pi / 2 + Double(step) / Double(heard.length) * .tau
            let at = middle + Vector2(angle: angle) * radius * 1.18
            noStroke()
            fill(heard[step] ? Color(hex: 0xE4B34C) : Color(white: 0.22))
            drawCircle(center: at, radius: (heard[step] ? 7 : 3.5) * scale)
        }

        // The beat ring: the inferred pulse, breathing once per beat.
        noFill()
        stroke(Color(white: 0.9).withAlpha(0.35 + kick * 0.65))
        strokeWeight((3 + kick * 11) * scale)
        drawCircle(center: middle, radius: radius * (1 + kick * 0.05))

        // The raw onset disc: what the detector heard, before any inference.
        noStroke()
        fill(Color(hex: 0xE4572E).withAlpha(0.25 + onsetFlash * 0.75))
        drawCircle(center: middle, radius: (26 + onsetFlash * 40) * scale)

        // The numbers, spelled out.
        fill(Color(white: 0.9))
        textSize(44 * scale)
        textAlign(.center)
        drawText(room.isFollowing ? "\(Int(room.tempo.rounded())) bpm" : "...",
                 at: Vector2(middle.x, middle.y - radius * 0.5))
        fill(Color(white: 0.55))
        textSize(16 * scale)
        drawText(room.isFollowing
                 ? "steadiness \(Int((room.steadiness * 100).rounded()))%"
                 : "not following yet",
                 at: Vector2(middle.x, middle.y - radius * 0.5 + 30 * scale))
    }

    private func status(live: Bool, room: BeatFollower) -> String {
        if !live {
            return "A generated pulse stands in; allow the microphone and clap a steady beat."
        }
        if !room.isFollowing {
            return "Listening. Clap or play a steady pulse; three good gaps and it follows."
        }
        return "Following, and playing a note on every beat it believes. Press R to reset."
    }

    override func keyPressed() {
        guard key == "r" || key == "R" else { return }
        micRoom.reset()
        pulseRoom.reset()
        counter = StepCounter(perBeat: 1)
    }
}
