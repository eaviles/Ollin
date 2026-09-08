import Foundation
import Ollin
import OllinMIDI

/// A sketch that chases a timeline. MIDI Time Code is how a video deck, a show
/// controller, a lighting desk, or a DAW locked to picture tells everything
/// else where it is, as hours, minutes, seconds, and frames, and a
/// `TimecodeClock` reads it back so the picture can land its cues on the
/// frame. A background timer here plays the part of the deck: it sends the
/// quarter-frame messages through a virtual source at four a frame, and a
/// full-frame message when it stops, and the clock follows them. Point any
/// timecode sender at this Mac and the sketch follows that instead.
///
///   swift run Example-Integration-Timecode
///
/// The readout is the position as the clock has it. The strip below it is the
/// timeline scrolling under a playhead, one tick a second, and the marks on
/// it are cues: each flashes as the playhead passes it. `rate` picks the
/// frame rate the internal deck counts at (a real sender declares its own),
/// `playing` rolls and stops it, and `cueEvery` spaces the cues. See
/// `Docs/Integration/MIDI.md`.
@main
final class TimecodeChase: Sketch {
    enum Rate: CaseIterable, ParamOption {
        case fps24, fps25, fps30Drop, fps30

        var frameRate: Timecode.FrameRate {
            switch self {
            case .fps24: .fps24
            case .fps25: .fps25
            case .fps30Drop: .fps30Drop
            case .fps30: .fps30
            }
        }

        var optionLabel: String { frameRate.name }
    }

    let midi = MIDIInput()
    lazy var clock = TimecodeClock(from: midi)
    var deck: InternalDeck?

    @Param var rate = Rate.fps25
    @Param var playing = true
    @Param(2 ... 30, icon: "flag") var cueEvery = 5.0

    var sentRate: Rate?
    var wasPlaying: Bool?
    /// The last cue passed, so each flashes once.
    var lastCue = -1
    var flashAt = -1.0

    override func setup() {
        try? midi.start()
        deck = InternalDeck()
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.07))
        driveDeck()

        let accent = Color(red: 0.95, green: 0.62, blue: 0.25)
        let seconds = clock.seconds

        // The readout, the way the deck's own display would show it.
        fill(clock.isPlaying ? Color(white: 0.97) : Color(white: 0.6))
        textSize(118 * scale)
        textAlign(.center, .middle)
        drawText(clock.timecode.map { "\($0)" } ?? "--:--:--:--", width / 2, height * 0.36)

        // The timeline: one tick a second, numbers every ten, scrolling so the
        // playhead stays put.
        let baseline = height * 0.62
        let pixelsPerSecond = 90 * scale
        let cue = max(1.0, cueEvery)
        textSize(20 * scale)
        for tick in Int(seconds) - 8 ... Int(seconds) + 8 where tick >= 0 {
            let x = width / 2 + (Double(tick) - seconds) * pixelsPerSecond
            let isCue = tick % Int(cue) == 0
            let passed = Double(tick) <= seconds
            fill(isCue ? (passed ? accent : accent.withAlpha(0.5)) : Color(white: 0.4))
            let tall = (isCue ? 46 : 22) * scale
            drawRect(x - 1.5 * scale, baseline - tall, 3 * scale, tall)
            if tick % 10 == 0 {
                fill(Color(white: 0.6))
                drawText(String(format: "%d:%02d", tick / 60, tick % 60), x, baseline + 24 * scale)
            }
        }
        fill(Color(white: 0.25))
        drawRect(0, baseline, width, 2 * scale)

        // The playhead, and the flash when it passes a cue.
        let cueIndex = Int(seconds / cue)
        if cueIndex != lastCue, clock.isPlaying {
            lastCue = cueIndex
            flashAt = time
        }
        let flash = max(0, 1 - (time - flashAt) / 0.5)
        fill(accent.withAlpha(0.25 * flash))
        drawCircle(width / 2, baseline - 24 * scale, 120 * scale * (1 + flash))
        fill(Color(white: 0.97))
        drawRect(width / 2 - 2 * scale, baseline - 70 * scale, 4 * scale, 90 * scale)

        // The status line: the rate the sender declares, and whether it rolls.
        fill(Color(white: 0.55))
        textSize(22 * scale)
        textAlign(.left, .top)
        let status: String
        if let frameRate = clock.frameRate, clock.isReceiving {
            status = "\(frameRate.name) fps   " + (clock.isPlaying
                ? (clock.isReversed ? "rolling backward" : "rolling")
                : "stopped")
        } else {
            status = "waiting for timecode: press play, or send MIDI Time Code to this Mac"
        }
        drawText(status, 40 * scale, 40 * scale)
        fill(Color(white: 0.95))
        textSize(30 * scale)
        drawText("Timecode: chasing a timeline", 40 * scale, 70 * scale)
    }

    /// Applies the parameters to the internal deck, once per change.
    func driveDeck() {
        if rate != sentRate {
            sentRate = rate
            deck?.setRate(rate.frameRate)
        }
        if playing != wasPlaying {
            wasPlaying = playing
            if playing { deck?.play() } else { deck?.stop() }
        }
    }
}

/// The deck side of the loopback: a virtual MIDI source and a background timer
/// sending quarter frames at four a frame, so the sketch has a timeline to
/// chase with no gear attached. Stopping sends the position as a full frame,
/// the way a deck reports where it parked.
final class InternalDeck: @unchecked Sendable {

    private let output = MIDIOutput(name: "Ollin Timecode")
    private let queue = DispatchQueue(label: "Timecode.deck")
    // Touched only on `queue`.
    private var timer: DispatchSourceTimer?
    private var frameRate = Timecode.FrameRate.fps25
    private var quarter = 0          // the next piece to send, 0…7
    private var frame = 0            // the frame the current set spells
    private var rolling = false

    init?() {
        do { try output.openVirtual(named: "Ollin Timecode") } catch { return nil }
    }

    func play() {
        queue.async { [self] in
            rolling = true
            schedule()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            rolling = false
            output.send(timecode: Timecode(frameNumber: frame, frameRate: frameRate))
        }
    }

    /// Changes the rate the deck counts at, keeping its place on the wall clock.
    func setRate(_ rate: Timecode.FrameRate) {
        queue.async { [self] in
            let seconds = Double(frame) * frameRate.secondsPerFrame
            frameRate = rate
            frame = Int(seconds / rate.secondsPerFrame)
            quarter = 0
            if rolling { schedule() }
        }
    }

    /// (On `queue`.) Replaces the timer with one firing four times a frame.
    private func schedule() {
        timer?.cancel()
        let tick = DispatchSource.makeTimerSource(queue: queue)
        tick.schedule(deadline: .now(), repeating: frameRate.secondsPerFrame / 4, leeway: .milliseconds(1))
        tick.setEventHandler { [self] in
            // Each set spells the frame it started on; the pieces go out over
            // the next two frames.
            let code = Timecode(frameNumber: frame, frameRate: frameRate)
            output.send(MIDIMessage(.timecodeQuarterFrame(piece: quarter, value: code.quarterFrameValue(piece: quarter))))
            quarter += 1
            if quarter == 8 {
                quarter = 0
                frame += 2
            }
        }
        tick.resume()
        timer = tick
    }

    deinit {
        timer?.cancel()
        output.close()
    }
}
