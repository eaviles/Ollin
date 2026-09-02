import Foundation
import Ollin
import OllinLink
import OllinMIDI

/// Motion locked to a beat, from either of the two ways a beat arrives. The
/// `source` parameter picks which clock drives the picture: `midi` follows MIDI
/// clock (a background timer sends the standard sync messages, timing clock at
/// 24 pulses per quarter note plus transport start/stop, through a virtual
/// source, and a `TempoClock` reads them back), and `link` joins the local
/// network's shared tempo session through a `LinkClock`, so every app in the
/// session lands the same downbeat. Both clocks read the same way (beat, bar,
/// and ramp), so one visual serves both: the center disk throbs on each beat,
/// the dots step around the bar, and the comet rides a ramp that takes eight
/// beats per lap.
///
///   swift run Example-Integration-Tempo
///
/// Adjust the BPM parameter and the whole picture keeps step in either mode. On the
/// MIDI side, flip `playing` off and it freezes where the transport stopped;
/// leave it off and send MIDI clock from a DAW, a drum machine, or a DJ mixer
/// to this Mac, and the sketch follows that instead. On the Link side a BPM
/// move proposes the new tempo to the whole session (the latest change wins,
/// whoever makes it), `playing` flips the shared transport flag, and alone the
/// clock free-runs at its own tempo, so the sketch moves the same with nothing
/// to join; the status line says which is happening. Run a second copy on
/// another Mac, or any app in the session, and they pulse together. See
/// `Docs/Integration/MIDI.md` and `Docs/Integration/Link.md`.
@main
final class Tempo: Sketch {
    enum Source: String, CaseIterable, ParamOption { case midi, link }

    let midi = MIDIInput()
    lazy var clock = TempoClock(from: midi)
    var sender: InternalClock?
    let link = LinkClock(tempo: 120)

    @Param var source = Source.midi
    @Param(60...180) var bpm = 120.0
    @Param var playing = true

    // Last values pushed to each side, so parameter moves apply once and a change
    // arriving from a Link peer is not immediately overwritten.
    var sentBPM = 0.0
    var wasPlaying: Bool?
    var sentLinkBPM = 0.0
    var sentLinkPlaying: Bool?

    override func setup() {
        try? midi.start()
        sender = InternalClock()
        link.start()
        // Seed the Link side with the parameters as they stand, so joining a session
        // proposes nothing until a parameter actually moves.
        sentLinkBPM = bpm
        sentLinkPlaying = playing
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))
        driveInternalClock()
        applyLinkParameters()

        let accent = source == .midi
            ? Color(red: 0.55, green: 0.5, blue: 0.95)
            : Color(red: 0.2, green: 0.75, blue: 0.7)
        let center = Vector2(width / 2, height / 2 + 40 * scale)

        // One read surface, whichever clock is driving.
        let beat = source == .midi ? clock.beat : link.beat
        let perBar = source == .midi ? clock.beatsPerBar : link.beatsPerBar
        let barPhase = source == .midi ? clock.barPhase : link.barPhase

        // The MIDI clock counts beats, so its lit dot gates on the transport;
        // Link's shared grid is the bar phase, so two machines light the same
        // dot at the same moment.
        let litBeat: Int
        let litGate: Bool
        switch source {
        case .midi:
            litBeat = clock.beatCount % max(1, perBar)
            litGate = clock.isPlaying
        case .link:
            litBeat = Int(barPhase * Double(perBar)) % max(1, perBar)
            litGate = true
        }

        // The heartbeat: snaps up on each beat and eases back down.
        fill(accent)
        drawCircle(center: center, radius: (120 + 55 * beat) * scale)

        // One dot per beat of the bar; the beat we're on burns bright.
        for i in 0..<perBar {
            let angle = Double(i) / Double(perBar) * .tau - .tau / 4
            let spot = center + Vector2(angle: angle) * 260 * scale
            let lit = i == litBeat && litGate
            fill(lit ? Color(white: 0.98) : Color(white: 0.3))
            drawCircle(center: spot, radius: (lit ? 26 : 14) * scale)
        }

        // The bar hand: sweeps once around per bar.
        let sweep = barPhase * .tau - .tau / 4
        stroke(Color(white: 0.5))
        strokeWeight(4 * scale)
        drawLine(center, center + Vector2(angle: sweep) * 210 * scale)
        noStroke()

        // The comet: one lap every eight beats, with a trail hung on earlier
        // points of the same ramp.
        for i in 0..<10 {
            let lag = Double(i) * 0.12
            let lap = source == .midi
                ? clock.progress(over: 8, phase: -lag / 8)
                : link.progress(over: 8, phase: -lag / 8)
            let angle = lap * .tau - .tau / 4
            let spot = center + Vector2(angle: angle) * 380 * scale
            fill(accent.withAlpha(1 - Double(i) / 10))
            drawCircle(center: spot, radius: (16 - Double(i)) * scale)
        }

        // Labels, with each source's own readout.
        fill(Color(white: 0.95))
        textSize(30 * scale)
        drawText(source == .midi ? "Tempo: following MIDI clock"
                                 : "Tempo: one beat for the whole network",
                 40 * scale, 70 * scale)
        fill(Color(white: 0.55))
        textSize(20 * scale)
        let status: String
        switch source {
        case .midi:
            if clock.isReceiving {
                status = String(format: "%.1f BPM   bar %d, beat %d%@",
                                clock.tempo, clock.bar + 1, litBeat + 1,
                                clock.isPlaying ? "" : "   (stopped)")
            } else {
                status = "waiting for clock: press play, or send MIDI clock to this Mac"
            }
        case .link:
            if link.peerCount > 0 {
                status = String(format: "%.1f BPM   %d peer%@   bar %d%@",
                                link.tempo, link.peerCount, link.peerCount == 1 ? "" : "s",
                                link.bar + 1,
                                link.isPlaying ? "   playing" : "")
            } else {
                status = String(format: "%.1f BPM   alone, free-running: start a Link app on this network to lock in",
                                link.tempo)
            }
        }
        drawText(status, 40 * scale, 105 * scale)
    }

    /// Applies the parameters to the internal MIDI clock, once per change: `playing`
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

    /// Applies the parameters to the Link session, once per change: a BPM move
    /// proposes the new tempo, and `playing` flips the shared transport flag.
    func applyLinkParameters() {
        if bpm != sentLinkBPM {
            sentLinkBPM = bpm
            link.tempo = bpm
        }
        if playing != sentLinkPlaying {
            sentLinkPlaying = playing
            link.isPlaying = playing
        }
    }
}

/// The master side of the loopback: a virtual MIDI source and a background
/// timer sending the clock train, so the sketch has a beat to follow with no
/// gear attached. Real setups replace this whole class with hardware or a DAW.
final class InternalClock: @unchecked Sendable {

    private let output = MIDIOutput(name: "Ollin Tempo")
    private let queue = DispatchQueue(label: "Tempo.clock")
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
