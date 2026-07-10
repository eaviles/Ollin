import Foundation
import Ollin
import OllinMIDI

/// Motion locked to a beat, no gear required. A background timer sends the
/// standard MIDI sync messages (timing clock at 24 pulses per quarter note,
/// plus transport start/stop) through a virtual source, and a `TempoClock`
/// reading them back drives everything that moves: the center disk throbs on
/// each beat, the dots step around the bar, and the comet rides a ramp that
/// takes eight beats per lap.
///
///   swift run Example-Integration-TempoSync
///
/// Turn the BPM knob and the whole picture keeps step; flip `playing` off and
/// it freezes where the transport stopped. To follow real gear instead (a DAW,
/// a drum machine, a DJ mixer), leave `playing` off and send MIDI clock to this
/// Mac: the sketch follows whatever arrives. See `Docs/Integration/MIDI.md`.
@main
final class TempoSync: Sketch {

    let midi = MIDIInput()
    lazy var clock = TempoClock(from: midi)
    var sender: InternalClock?

    @Param(60...180) var bpm = 120.0
    @Param var playing = true

    // Last values pushed to the internal clock, so knob moves apply once.
    var sentBPM = 0.0
    var wasPlaying: Bool?

    override func setup() {
        try? midi.start()
        sender = InternalClock()
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))
        driveInternalClock()

        let accent = Color(red: 0.55, green: 0.5, blue: 0.95)
        let center = Vector2(width / 2, height / 2 + 40 * scale)

        // The heartbeat: snaps up on each beat and eases back down.
        fill(accent)
        drawCircle(center: center, radius: (120 + 55 * clock.beat) * scale)

        // One dot per beat of the bar; the beat we're on burns bright.
        let perBar = clock.beatsPerBar
        let litBeat = clock.beatCount % max(1, perBar)
        for i in 0..<perBar {
            let angle = Double(i) / Double(perBar) * .tau - .tau / 4
            let spot = center + Vector2(cos(angle), sin(angle)) * 260 * scale
            let lit = i == litBeat && clock.isPlaying
            fill(lit ? Color(white: 0.98) : Color(white: 0.3))
            drawCircle(center: spot, radius: (lit ? 26 : 14) * scale)
        }

        // The bar hand: sweeps once around per bar.
        let sweep = clock.barPhase * .tau - .tau / 4
        stroke(Color(white: 0.5))
        strokeWeight(4 * scale)
        drawLine(center, center + Vector2(cos(sweep), sin(sweep)) * 210 * scale)
        noStroke()

        // The comet: one lap every eight beats, with a trail hung on earlier
        // points of the same ramp.
        for i in 0..<10 {
            let lag = Double(i) * 0.12
            let lap = clock.progress(over: 8, phase: -lag / 8)
            let angle = lap * .tau - .tau / 4
            let spot = center + Vector2(cos(angle), sin(angle)) * 380 * scale
            fill(accent.withAlpha(1 - Double(i) / 10))
            drawCircle(center: spot, radius: (16 - Double(i)) * scale)
        }

        // Labels.
        fill(Color(white: 0.95))
        textSize(30 * scale)
        drawText("Tempo sync: following MIDI clock", 40 * scale, 70 * scale)
        fill(Color(white: 0.55))
        textSize(20 * scale)
        let status: String
        if clock.isReceiving {
            status = String(format: "%.1f BPM   bar %d, beat %d%@",
                            clock.tempo, clock.bar + 1, litBeat + 1,
                            clock.isPlaying ? "" : "   (stopped)")
        } else {
            status = "waiting for clock: press play, or send MIDI clock to this Mac"
        }
        drawText(status, 40 * scale, 105 * scale)
    }

    /// Applies the knobs to the internal clock, once per change: `playing`
    /// starts/stops its transport, and a BPM move retimes the running train.
    func driveInternalClock() {
        if playing != wasPlaying {
            wasPlaying = playing
            if playing {
                sender?.play(bpm: bpm)
                sentBPM = bpm
            } else {
                sender?.stop()
            }
        } else if playing, bpm != sentBPM {
            sentBPM = bpm
            sender?.setTempo(bpm)
        }
    }
}

/// The master side of the loopback: a virtual MIDI source and a background
/// timer sending the clock train, so the sketch has a beat to follow with no
/// gear attached. Real setups replace this whole class with hardware or a DAW.
final class InternalClock: @unchecked Sendable {

    private let output = MIDIOutput(name: "Ollin Tempo")
    private let queue = DispatchQueue(label: "TempoSync.clock")
    private var timer: DispatchSourceTimer?   // touched only on `queue`

    init?() {
        do { try output.openVirtual(named: "Ollin Tempo") } catch { return nil }
    }

    /// Sends a transport start and begins the clock train at `bpm`.
    func play(bpm: Double) {
        queue.async { [self] in
            output.send(MIDIMessage(.start))
            schedule(bpm: bpm)
        }
    }

    /// Retimes the running train without restarting the transport.
    func setTempo(_ bpm: Double) {
        queue.async { [self] in
            guard timer != nil else { return }
            schedule(bpm: bpm)
        }
    }

    /// Halts the train and sends a transport stop.
    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            output.send(MIDIMessage(.stop))
        }
    }

    /// (On `queue`.) Replaces the timer with one ticking 24 times per beat.
    private func schedule(bpm: Double) {
        timer?.cancel()
        let tick = DispatchSource.makeTimerSource(queue: queue)
        let interval = 60 / (bpm * 24)
        tick.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        tick.setEventHandler { [output] in output.send(MIDIMessage(.clock)) }
        tick.resume()
        timer = tick
    }

    deinit {
        timer?.cancel()
        output.close()
    }
}
