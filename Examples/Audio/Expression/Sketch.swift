import Foundation
import Ollin
import OllinAudio
import OllinMIDI

/// A note under the finger. Each note a polyphonic-expression controller
/// holds is bent, pressed, and slid on its own, and the synth follows each
/// one: across the surface is pitch, up it is slide (the filter opening), and
/// how long a note has been held stands in for pressure when the mouse plays.
/// The mouse plays through a virtual MIDI source, so what the sketch draws
/// and plays has crossed Core MIDI the way a real controller's notes do; plug
/// one in (a polyphonic-expression controller, or a phone app that speaks
/// MPE) and its notes join the same picture. Left alone, a hand of the
/// sketch's own plays a phrase, straight into the instrument.
///
///   swift run Example-Audio-Expression
///
/// Press and drag on the surface to play: moving across bends the note from
/// where it was struck, moving up and down slides it, and holding presses it
/// harder. Switch `bowed` on for the cello, where pressure is the bow and a
/// note pressed to nothing goes quiet. See `Docs/Helpers/Synthesis.md` and
/// `Docs/Integration/MIDI.md`.
@main
final class Expression: Sketch {

    /// Everything a note on the surface is, whoever is playing it.
    struct Ribbon: Equatable {
        let id: Int
        let note: Int
        let pitch: Double
        let velocity: Double
        let pressure: Double
        let slide: Double

        init(_ held: HeldNote) {
            id = held.id
            note = held.note
            pitch = held.pitch
            velocity = held.velocity
            pressure = held.pressure
            slide = held.slide
        }

        init(id: Int, note: Int, pitch: Double, velocity: Double, pressure: Double, slide: Double) {
            self.id = id
            self.note = note
            self.pitch = pitch
            self.velocity = velocity
            self.pressure = pressure
            self.slide = slide
        }
    }

    /// A lead whose filter opens with the slide and whose level rises with
    /// pressure: the two things a wave can do with a finger, beside the bend.
    static let lead = Voice(
        waveform: .sawtooth,
        envelope: Envelope(attack: 0.02, decay: 0.3, sustain: 0.7, release: 0.5),
        filter: Voice.Filter(mode: .lowpass, cutoff: 500, resonance: 0.35, keyTracking: 0.6, slideAmount: 2),
        detune: 0.06
    )

    let midi = MIDIInput()
    let out = MIDIOutput(name: "Ollin Expression")
    let synth = Synth(Expression.lead, polyphony: 12)

    @Param var bowed = false
    var wasBowed = false

    /// The notes the synth is playing, by the surface's own identity for them.
    var playing: [Int: PlayingNote] = [:]

    /// The mouse's note while it is down: the channel it went out on, and
    /// where and when it was struck, so a drag bends from there.
    struct Finger {
        let channel: Int
        let note: Int
        let struckX: Double
        let since: Double
    }
    var finger: Finger?
    var nextChannel = 2
    var lastTouch = -10.0
    var wireNotesSeen = 0

    let lowest = 48.0          // C3
    let octaves = 2.0

    var surface: Rectangle {
        Rectangle(x: 60 * scale, y: 160 * scale, width: width - 120 * scale, height: height - 300 * scale)
    }

    override func setup() {
        do {
            try out.openVirtual(named: "Ollin Expression")
            try midi.start()
        } catch {
            print("could not open the MIDI loopback: \(error)")
        }
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.07))
        announceZone()
        applyVoice()
        playMouse()

        // Whoever is playing: the surface and any controller through the
        // wire, and the sketch's own hand when nobody has touched it lately.
        let wired = midi.heldNotes
        if !wired.isEmpty { wireNotesSeen = frameCount; lastTouch = time }
        var ribbons = wired.map(Ribbon.init)
        let idle = time - lastTouch > 2.5
        if idle { ribbons += hand(at: time) }
        follow(ribbons)

        drawSurface()
        for ribbon in ribbons { drawRibbon(ribbon) }
        drawLabels(ribbons: ribbons, idle: idle)
    }

    // MARK: The wire

    /// The zone is announced until the input has it: the input connects to
    /// the new virtual source a moment after it opens, and anything sent
    /// before that is lost.
    func announceZone() {
        guard midi.mpeZones.isEmpty, frameCount % 30 == 0 else { return }
        out.send(mpeZone: .lower())
    }

    func applyVoice() {
        guard bowed != wasBowed || frameCount == 1 else { return }
        wasBowed = bowed
        synth.voice = bowed ? .cello : Expression.lead
        synth.pressure = 0.7
    }

    /// The mouse as a polyphonic-expression controller: each press takes the
    /// next member channel, says where the finger is, then puts it down.
    func playMouse() {
        if mouseIsPressed, finger == nil, surface.contains(Vector2(mouseX, mouseY)) {
            let note = Int(pitch(atX: mouseX).rounded())
            let channel = nextChannel
            nextChannel = nextChannel == 16 ? 2 : nextChannel + 1
            out.pitchBend(8192, channel: channel)
            out.controlChange(74, value: Int(slide(atY: mouseY) * 127), channel: channel)
            out.channelPressure(Int(0.25 * 127), channel: channel)
            out.noteOn(note, velocity: 100, channel: channel)
            finger = Finger(channel: channel, note: note, struckX: mouseX, since: time)
            lastTouch = time
        }
        guard let finger else { return }
        lastTouch = time
        if !mouseIsPressed {
            out.noteOff(finger.note, channel: finger.channel)
            self.finger = nil
            return
        }
        // Where the finger is now: bent from where it struck, slid by height,
        // and pressed harder the longer it stays.
        let semitones = (mouseX - finger.struckX) / (surface.width / (12 * octaves))
        let bend = Int((8192 + semitones / 48 * 8192).rounded())
        out.pitchBend(min(max(0, bend), 16383), channel: finger.channel)
        out.controlChange(74, value: Int(slide(atY: mouseY) * 127), channel: finger.channel)
        let pressure = min(1, 0.25 + 0.75 * (time - finger.since) / 1.5)
        out.channelPressure(Int(pressure * 127), channel: finger.channel)
    }

    // MARK: The instrument

    /// Starts each note as it appears, lets it go as it leaves, and every
    /// frame hands each held note what the surface says about it.
    func follow(_ ribbons: [Ribbon]) {
        for ribbon in ribbons where playing[ribbon.id] == nil {
            playing[ribbon.id] = synth.noteOn(Pitch(Double(ribbon.note)), velocity: ribbon.velocity)
        }
        for (id, note) in playing where !ribbons.contains(where: { $0.id == id }) {
            synth.noteOff(note)
            playing[id] = nil
        }
        for ribbon in ribbons {
            guard let note = playing[ribbon.id] else { continue }
            synth.bend(note, semitones: ribbon.pitch - Double(ribbon.note))
            synth.press(note, ribbon.pressure)
            synth.slide(note, ribbon.slide)
        }
    }

    /// A phrase the sketch plays itself: four notes, each sliding a little
    /// from where it was struck, pressed hardest in its middle, the finger
    /// drifting up the key as it goes.
    func hand(at t: Double) -> [Ribbon] {
        let cycle = 9.6
        let phrase: [(start: Double, length: Double, note: Int, rise: Double)] = [
            (0.0, 3.2, 55, 5), (1.6, 3.2, 62, 3), (4.8, 3.6, 59, 7), (6.4, 2.6, 67, -2),
        ]
        let local = t.truncatingRemainder(dividingBy: cycle)
        var ribbons: [Ribbon] = []
        for (index, step) in phrase.enumerated() where local >= step.start && local < step.start + step.length {
            let u = (local - step.start) / step.length
            let eased = u * u * (3 - 2 * u)
            ribbons.append(Ribbon(id: 1000 + index, note: step.note,
                                  pitch: Double(step.note) + step.rise * eased,
                                  velocity: 0.8, pressure: sin(u * .pi),
                                  slide: 0.25 + 0.6 * u))
        }
        return ribbons
    }

    // MARK: The picture

    func pitch(atX x: Double) -> Double {
        lowest + (x - surface.x) / surface.width * 12 * octaves
    }

    func x(ofPitch pitch: Double) -> Double {
        surface.x + (pitch - lowest) / (12 * octaves) * surface.width
    }

    func slide(atY y: Double) -> Double {
        min(max(0, 1 - (y - surface.y) / surface.height), 1)
    }

    func drawSurface() {
        fill(Color(white: 0.11))
        drawRect(surface.x, surface.y, surface.width, surface.height)
        // A line per semitone, the C of each octave brighter.
        for semitone in 0...Int(12 * octaves) {
            let x = x(ofPitch: lowest + Double(semitone))
            fill(Color(white: semitone % 12 == 0 ? 0.32 : 0.17))
            drawRect(x - scale, surface.y, 2 * scale, surface.height)
        }
        for octave in 0...Int(octaves) {
            fill(Color(white: 0.45))
            textSize(16 * scale)
            textAlign(.center, .top)
            drawText("C\(3 + octave)", x(ofPitch: lowest + Double(12 * octave)), surface.bottomRight.y + 10 * scale)
        }
    }

    /// A held note as a ribbon standing on the surface: at its pitch, as tall
    /// as its slide, as wide and as bright as its pressure.
    func drawRibbon(_ ribbon: Ribbon) {
        let x = x(ofPitch: ribbon.pitch)
        let top = surface.y + (1 - ribbon.slide) * surface.height
        let widthNow = (14 + 44 * ribbon.pressure) * scale
        let hue = (ribbon.pitch - lowest) / (12 * octaves)
        let color = Color(hue: 0.55 + 0.35 * hue, saturation: 0.7, brightness: 0.55 + 0.45 * ribbon.pressure)
        fill(color.withAlpha(0.28))
        drawRect(x - widthNow, top, 2 * widthNow, surface.bottomRight.y - top)
        fill(color)
        drawRect(x - widthNow / 2, top, widthNow, surface.bottomRight.y - top)
        drawCircle(x, top, widthNow * 0.7)

        fill(Color(white: 0.92))
        textSize(15 * scale)
        textAlign(.center, .bottom)
        let bend = ribbon.pitch - Double(ribbon.note)
        let name = Pitch(Double(ribbon.note)).description
        drawText(abs(bend) < 0.05 ? name : String(format: "%@ %+.1f", name, bend), x, top - widthNow * 0.7 - 6 * scale)
    }

    func drawLabels(ribbons: [Ribbon], idle: Bool) {
        fill(Color(white: 0.95))
        textAlign(.left, .top)
        textSize(30 * scale)
        drawText("Expression: each note bent, pressed, and slid on its own", 40 * scale, 44 * scale)
        fill(Color(white: 0.55))
        textSize(19 * scale)
        let who = idle ? "the sketch's own hand" : finger != nil ? "the mouse, through the virtual source" : "a controller, through the wire"
        let zone = midi.mpeZones.first.map { "zone: channel \($0.masterChannel) master, \($0.memberChannels.lowerBound) to \($0.memberChannels.upperBound) for notes" } ?? "waiting for the zone to cross the wire"
        drawText("\(ribbons.count) note\(ribbons.count == 1 ? "" : "s") held, played by \(who)   \(zone)", 40 * scale, 92 * scale)
        drawText("across is pitch, up is slide, holding presses; `bowed` makes pressure the bow", 40 * scale, 122 * scale)
    }
}
