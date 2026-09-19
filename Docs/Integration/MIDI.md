#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `MIDI`</sup>

---

## MIDI

MIDI is the protocol that knob boxes, keyboards, pad grids, and sequencers speak. Because those devices speak it, you can connect one to a sketch. A hardware fader can then drive a parameter, and a key can trigger an event. A sketch can also send notes and control changes back out. MIDI support lives in a separate library, so the drawing core stays free of Core MIDI. Add `import OllinMIDI` beside `import Ollin` to use it.

You read incoming MIDI with a [`MIDIInput`](#midiinput) and send it with a [`MIDIOutput`](#midioutput). Both run over Apple's Core MIDI. A message is a *kind*, such as a note, a control change, or a clock tick. Each message arrives on a *channel* (1 to 16). Ollin parses and encodes the MIDI 1.0 format from the specification, so no third-party code is vendored.

```text
   ch 1   controlChange   controller 7   value 64
   └ channel ┘  └─ kind ─┘  └──────── data ────────┘
```

The usual pattern is to create the input in `setup()` and read it in `draw()`.

```swift
import Ollin
import OllinMIDI

final class Wired: Sketch {
    let midi = MIDIInput()

    override func setup() { try? midi.start() }

    override func draw() {
        // a knob on CC 7 (0…127) sets the radius
        let level = midi.controlValue(7, default: 0)
        drawCircle(width / 2, height / 2, (40 + Double(level) / 127 * 300) * scale)
    }
}
```

### Contents

- [MIDIMessage & kinds](#midimessage--kinds) - the value you read and send
- [MIDIInput](#midiinput) - read incoming MIDI three ways
- [Binding to a `@Param`](#binding-to-a-param) - drive a parameter from a controller
- [Per-note expression (MPE)](#per-note-expression-mpe) - a controller that bends, presses, and slides each note on its own
- [Tempo sync (TempoClock)](#tempo-sync-tempoclock) - lock motion to the beat of whatever is playing
- [Timecode (TimecodeClock)](#timecode-timecodeclock) - chase a timeline sent as MIDI Time Code
- [MIDIOutput](#midioutput) - send notes and control changes
- [Testing without hardware](#testing-without-hardware) - loopback and the monitor
- [Files, not cables](#files-not-cables) - where a `.mid` file is read and written

<a name="midimessage--kinds"></a>

### MIDIMessage & kinds

A `MIDIMessage` holds a `kind` and the `channel` (1 to 16) it arrived on. The `kind` carries its own data:

```swift
switch message.kind {
case .noteOn(let note, let velocity):     trigger(note, velocity)
case .noteOff(let note, _):               release(note)
case .controlChange(let cc, let value):   knobs[cc] = value
case .pitchBend(let value):               bend = value          // 0…16383, 8192 center
default: break
}
```

The common kinds are `.noteOn` / `.noteOff` (a key or pad), `.controlChange` (a knob, fader, or pedal), and `.pitchBend`. The other kinds are `.programChange`, `.channelPressure`, `.polyPressure`, and the system sync messages `.clock` / `.start` / `.stop` / `.continue` / `.songPosition`. The sync messages carry no channel, so they report `0`, and the [tempo clock](#tempo-sync-tempoclock) reads them for you. A note-on with velocity 0 becomes `.noteOff`, because many devices send that form for a release.

A `.timecodeQuarterFrame(piece:value:)` is one piece of a MIDI Time Code position; a `TimecodeClock` reads those for you.

The convenience accessors cover the common reads, so you rarely need to switch on `kind` directly:

```swift
message.note         // Int?  (note and poly-pressure messages)
message.velocity     // Int?  (note messages)
message.controller   // Int?  (the CC number)
message.value        // Int?  (CC value, program, pressure, or bend)
message.isNoteOn     // Bool
message.isNoteOff    // Bool  (a note-off, or a note-on at velocity 0)
```

To **send** one, build it: `MIDIMessage(_:channel:)` from a kind, or `MIDIMessage(status:data1:data2:)` from the raw bytes, or `MIDIMessage(umpWord:)` from a MIDI 2.0 Universal MIDI Packet word. `umpWord` writes it back out in that form, which is what the timecode walk steps through.

<a name="midiinput"></a>

### MIDIInput

```swift
MIDIInput(name: String = "Ollin")
func start() throws                          // MIDIError.coreMIDI(status) if Core MIDI refuses
func stop()
func availableSources() -> [MIDIEndpoint]    // the connected devices: `name`, `manufacturer`, and an `id`

// 1. Latest value of a controller (continuous knobs/faders)
func controlValue(_ controller: Int, channel: Int? = nil) -> Int?
func controlValue(_ controller: Int, default: Int, channel: Int? = nil) -> Int

// 2. State of a note right now (held keys/pads)
func isNoteOn(_ note: Int, channel: Int? = nil) -> Bool

// 3. Everything since the last call, in order (discrete events)
func messages() -> [MIDIMessage]
```

`start()` connects to every MIDI device on the system. A device plugged in later connects automatically. Then you read what arrives in one of three ways, depending on what you need. Omit `channel` to read across all channels, or pass `1…16` to read one channel only.

**The latest value of a controller**, for a continuous knob or fader. Read it again each frame:

```swift
let radius = Double(midi.controlValue(7, default: 0)) / 127 * 300
```

**The state of a note**, for a held key or pad:

```swift
if midi.isNoteOn(60) { sustain() }
```

**The event queue**, for discrete events such as struck notes, transport, and clock. `messages()` returns everything received since the last call, in arrival order, and then clears the queue. Call it once per frame:

```swift
for message in midi.messages() where message.isNoteOn {
    spawnRipple(pitch: message.note ?? 0, force: message.velocity ?? 0)
}
```

```text
   Core MIDI thread             main thread (draw)
   ┌────────────┐  controls[]   ┌────────────────────┐
   │ packet →   │ ───────────→  │ midi.controlValue  │   continuous
   │  parse +   │  held notes   │ midi.isNoteOn      │   state
   │  stash     │  inbox[]      │ midi.messages()    │   discrete
   └────────────┘ ───────────→  └────────────────────┘
```

MIDI arrives on a Core MIDI thread, and the sketch reads it on the main thread. Every shared value is held behind a lock, so you can read them safely from `draw()`.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(controlChange controller: Int, to param: Param<Double>,
          channel: Int? = nil, from input: ClosedRange<Double> = 0...127)
func unbind(controlChange controller: Int, channel: Int? = nil)
```

`to:` also takes a `Param<Tempo>`, the beats-per-minute slider a [tempo](../Helpers/Composition.md#tempo-and-note-lengths) declares, mapped into its range the same way. The beats per bar stay what the declaration gave them.

The fourth way to read is to bind a control-change knob directly to a [`@Param`](../Helpers/Parameters.md). A hardware fader then drives the same parameter that the inspector slider does. Ollin maps each incoming value from `input`, a controller's `0…127` by default, into the parameter's own range, then assigns it:

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    try? midi.start()
    midi.bind(controlChange: 7, to: $radius)   // CC 0…127 → 20…400
}
```

A bound parameter updates on its own as messages arrive, so you do not read it each frame. The same parameter still works from the inspector slider and from code. Whichever source moved it most recently sets the value.

**Smoothing the moves.** Give the `@Param` a `smoothing:`, and the value glides to each new position instead of jumping. Smoothing is a property of the parameter, so it applies whether the value comes from MIDI, OSC, or a drag of the inspector slider:

```swift
@Param(20...400, smoothing: .eased(0.3)) var radius = 120.0   // 0.3s glide
@Param(0...1, smoothing: .smoothed) var mix = 0.5             // adaptive 1€ filter
```

`.eased` glides to each value over a fixed time along an `Easing` curve. `.smoothed` passes the value through a `OneEuroFilter`, which holds steady while the knob is still and responds faster as the knob moves. That response usually feels better than `.eased` for a hand on live hardware. Both are documented in [Animation](../Helpers/Animation.md), together with the `Easing` curves and the `@Smoothed` 1€ filter.

<a name="per-note-expression-mpe"></a>

### Per-note expression (MPE)

```swift
var heldNotes: [HeldNote]           // every held note, oldest first, its expression resolved
var mpeZones: [MPEZone]             // the zones in force: what the controller announced, or what you set

struct HeldNote {
    let note: Int                   // the key, 0…127
    let channel: Int                // 1…16
    let velocity: Double            // how hard it was struck, 0…1
    let pitchBend: Double           // semitones, the channel's range applied
    var pitch: Double               // note + pitchBend, the MIDI number sounding
    let pressure: Double            // 0…1, zero until the controller says
    let slide: Double               // 0…1, controller 74, half way until the controller says
    var id: Int                     // the note and its channel together
}

MPEZone.lower(members: Int = 15)    // channel 1 is the master, 2 up to 16 carry notes
MPEZone.upper(members: Int = 15)    // channel 16 is the master, 15 down carry notes
```

A keyboard bends every note at once, because its wheel speaks for the whole channel. A polyphonic-expression surface (a Seaboard, a LinnStrument, a phone app that speaks MPE) puts each note on a channel of its own. The channel's pitch bend, pressure, and controller 74 then belong to that one note. `heldNotes` reads it that way: every note that is down, with what the controller has said about it since, resolved for the channel it arrived on.

```swift
for note in midi.heldNotes {
    drawCircle(x(note.pitch), y(note.slide), 20 + 60 * note.pressure)
}
```

On a plain keyboard the same read gives the wheel and the aftertouch, shared by every note on the channel. A key's own pressure (polyphonic aftertouch) counts where the keyboard sends it. Nothing changes in the sketch.

**Zones.** MPE divides the sixteen channels into a lower zone running up from channel 1 and an upper zone running down from 16. Most controllers use the lower one alone. The channel at the edge is the *master*. What arrives there (a bend, a pressure, a slide) applies to every note in the zone, on top of each note's own. A controller announces its zone with a configuration message on the master channel, and the input lays itself out from it. So `mpeZones` is usually nothing to set. For a controller that does not announce, set it by hand: `midi.mpeZones = [.lower()]`, or build one field by field with `MPEZone(masterChannel:memberChannels:…)`. A zone reads back what it is: `masterChannel` is the channel the shared messages arrive on, `memberChannels` the range the notes arrive on and `memberCount` how many that is, `isLower` says which end of the sixteen it runs from, and `isMember(channel:)` answers whether a channel carries notes, with `contains(channel:)` counting the master too.

**Bend ranges.** A member channel's bend spans 48 semitones and the master's 2, the specification's defaults, held on the zone as `memberPitchBendRange` and `masterPitchBendRange`. A quarter of the wheel on a member channel is then twelve semitones. A controller that says otherwise (the pitch bend range as a registered parameter) is believed. On a member channel it sets every member's range, on the master the master's. On a channel outside any zone it sets that channel's, which is 2 semitones until told.

**Playing an instrument from it.** Start each note as it appears, let it go as it leaves, and every frame hand each held note the three values. That is the whole wiring; [`Synth`](../Helpers/Synthesis.md#expression) does the rest.

```swift
var playing: [Int: PlayingNote] = [:]

override func draw() {
    let held = midi.heldNotes
    for note in held where playing[note.id] == nil {
        playing[note.id] = synth.noteOn(Pitch(Double(note.note)), velocity: note.velocity)
    }
    for (id, note) in playing where !held.contains(where: { $0.id == id }) {
        synth.noteOff(note)
        playing[id] = nil
    }
    for note in held {
        guard let playing = playing[note.id] else { continue }
        synth.bend(playing, semitones: note.pitchBend)
        synth.press(playing, note.pressure)
        synth.slide(playing, note.slide)
    }
}
```

A strike shorter than a frame is not in `heldNotes` by the time `draw()` reads it. A pad played that way is a discrete event, which is what `messages()` is for.

`controlValue(74)` with no channel is whichever channel moved last, which on a surface is whichever finger moved last. The per-note value is on the held note.

The **Expression** example (`Examples/Audio/Expression`) is a surface the mouse plays through a virtual source, so a bend, a press, and a slide cross Core MIDI the way a controller's do. A real controller plugged in joins the same picture.

<a name="tempo-sync-tempoclock"></a>

### Tempo sync (TempoClock)

```swift
TempoClock(from: MIDIInput)
var tempo: Double          // received BPM (smoothed); 0 until measured
var isPlaying: Bool        // the position is advancing
var isReceiving: Bool      // a clock tick arrived within the last second
var beats: Double          // musical time in quarter notes: 2.5 is halfway through beat 3
var beatCount: Int         // whole beats, from 0
var phase: Double          // 0…1 through the current beat
var beat: Double           // 0…1 pulse: snaps to 1 on each beat, decays over ~0.25 s
var timeSinceBeat: Double  // seconds since the last beat landed
var beatsPerBar: Int       // the meter you declare for the bar reads (default 4)
var bar: Int               // whole bars, from 0
var barPhase: Double       // 0…1 through the current bar
func progress(over length: Double, phase: Double = 0) -> Double   // 0…1 ramp across any beat span
```

A `TempoClock` locks a sketch's motion to whatever is playing, so the visuals follow the music the way a VJ set does. Anything that sends MIDI clock can lead: a DAW, a drum machine, a hardware sequencer, or a DJ mixer. The clock reads the sync messages from a `MIDIInput` and turns them into musical time that you read in `draw()`. So animation lands on the beat instead of near it.

```swift
let midi = MIDIInput()
lazy var clock = TempoClock(from: midi)

override func setup() { try? midi.start() }

override func draw() {
    background(.black)
    drawCircle(width / 2, height / 2, (120 + 50 * clock.beat) * scale)   // throbs on the beat
    let angle = clock.progress(over: 8) * .tau                           // one lap every 8 beats
    drawCircle(width / 2 + cos(angle) * 300, height / 2 + sin(angle) * 300, 20 * scale)
}
```

`beat` is the ready-made pulse. It has the same shape as the audio analyzer's `beat`. A beat-reactive sketch can therefore switch between the audio it hears in the room and the MIDI clock it receives. `phase` is the position inside the current beat. `progress(over:)` is the musical-time counterpart of `loopProgress(over:)`. It is a `0…1` ramp across any number of beats, for a move that spans a phrase rather than a single beat.

**How it handles a real-world clock.** MIDI clock ticks 24 times per beat. The *position* comes from counting those ticks, so the beat grid cannot drift however much the tempo varies. The *tempo* is a mean over a sliding window of recent tick intervals. The window holds about two beats of ticks, which is enough to flatten the millisecond-scale jitter that is typical of a MIDI connection. The tempo is used only to glide `phase` between ticks. That glide is clamped, so the position never runs backward when a tick is late. A large tempo jump clears the window, so the new tempo locks in within a beat.

**Transport.** `start` resets the position to zero, and the next tick is the downbeat. `stop` freezes the position, but the tempo keeps updating if clock keeps arriving. `continue` resumes from where the position froze, or from a received song position. A master that sends only clock and no transport messages (common on DJ gear) free-runs, and its first tick counts as beat zero. MIDI clock carries no meter, so you declare `beatsPerBar` (default 4), and bar zero is wherever the count began.

**Keyframes on musical time.** A [`Timeline`](../Helpers/Animation.md) whose durations are written in *beats* runs on the clock, and one line is enough to set that up. It follows `clock.beats` instead of advancing in seconds.

```swift
let swell = Timeline(0.0).to(1.0, in: 3, curve: .easeOut).to(0.0, in: 1)   // durations in beats

override func draw() {
    swell.loops = true
    swell.seek(to: clock.beats)   // now it cycles every 4 beats, locked to the music
}
```

The **Tempo** example (`Examples/Integration/Tempo`) shows this with no hardware. An internal timer sends clock through a virtual source, and the visuals lock to it. Connect real gear to the Mac, and the same sketch follows that clock instead.

<a name="timecode-timecodeclock"></a>

### Timecode (TimecodeClock)

```swift
TimecodeClock(from: MIDIInput)
var timecode: Timecode?             // the frame the timeline is on; nil until any arrives
var seconds: Double                 // the position in seconds, gliding between frames
var frameRate: Timecode.FrameRate?  // 24, 25, 29.97 drop, or 30, once the sender has said
var isPlaying: Bool                 // quarter frames arrived within the last half second
var isReceiving: Bool               // any timecode arrived within the last second
var isReversed: Bool                // the pieces run backward: a deck shuttling in reverse

Timecode(hours:minutes:seconds:frames:frameRate:)
Timecode(frameNumber:frameRate:)    // and Timecode(seconds:frameRate:)
var frameNumber: Int                // frames from zero, the dropped numbers not counted
var totalSeconds: Double            // the same on the wall clock
var fullFrameSysEx: [UInt8]         // the whole position as one system-exclusive message
func advanced(by frames: Int) -> Timecode
cueIn < cueOut                      // Comparable, by the moment it names
(cueIn...cueOut).contains(code)     // so a cue window is a range
"\(code)"                           // "01:02:03:04", or "00:10:00;02" for drop frame

rate.framesPerSecond                // 24, 25, 29.97, or 30
rate.secondsPerFrame                // one frame's length on the wall clock
rate.isDropFrame                    // true for 29.97 drop, where two numbers a minute go unused
```

Where a tempo clock says how fast, timecode says where. A video deck, a show controller, a lighting desk, or a DAW locked to picture sends its position as MIDI Time Code. That is hours, minutes, seconds, and frames, at one of four frame rates. A `TimecodeClock` reads it, so a sketch can chase the same timeline and land a cue on the frame:

```swift
let midi = MIDIInput()
lazy var timecode = TimecodeClock(from: midi)

override func setup() { try? midi.start() }

override func draw() {
    background(.black)
    let t = timecode.seconds                                   // 90.48 when the deck reads 00:01:30:12 at 25
    fill(t >= 90 && t < 92 ? .white : Color(white: 0.3))      // a cue at a minute and a half
    drawCircle(width / 2, height / 2, 120 * scale)
    drawText(timecode.timecode.map { "\($0)" } ?? "--:--:--:--", 40 * scale, 60 * scale)
}
```

**How it reads the wire.** A running sender spells its position in eight *quarter-frame* messages, four to a frame, so a whole time arrives every two frames. The clock counts every message as a quarter of a frame in the direction the pieces run, and re-anchors on each completed set. A deck shuttling backward sends them in reverse, and the position runs backward with it. `seconds` is therefore exact at every message and glides at the frame rate between them. The glide stops just short of the next message, so a late one never runs it backward. A *full-frame* message, the one a deck sends when it locates or stops, sets the position outright. Half a second of silence means the transport stopped, and the position holds where it was.

**Cue points are comparisons.** A `Timecode` is `Comparable`, so a cue test is `<` and a window is a range, with no detour through `totalSeconds`:

```swift
let cueIn = Timecode(hours: 0, minutes: 1, seconds: 30, frames: 0, frameRate: .fps25)
let cueOut = cueIn.advanced(byFrames: 50)                  // two seconds later at 25

if let now = timecode.timecode, (cueIn..<cueOut).contains(now) { drawTitle() }
cues.sorted()                                        // in the order they play
```

The comparison runs on the wall clock, so two timecodes counted at different rates still answer honestly about which came first, even where the larger frame number is the earlier moment. Two that name the very same moment at different rates are ordered by rate, which is what keeps the order total: `<` and `==` never disagree.

**Frame rates.** `Timecode.FrameRate` is the four the protocol names: `.fps24`, `.fps25`, `.fps30Drop`, and `.fps30`. Drop frame counts thirty frames a second over video that runs at 29.97. It skips frame numbers 0 and 1 at the top of every minute except each tenth, so the labels stay on the wall clock. `frameNumber` and `totalSeconds` account for that, and a drop-frame timecode prints with a semicolon before the frames, the way a broadcast display does.

**Sending it.** `MIDIOutput.send(timecode:)` sends a position whole as a full-frame message. `send(.timecodeQuarterFrame(piece:value:))` with `Timecode.quarterFrameValue(piece:)` spells one out, and `send(sysEx:)` under both sends any system exclusive. The **Timecode** example (`Examples/Integration/Timecode`) plays the deck itself. An internal timer sends the quarter frames through a virtual source, a `TimecodeClock` follows them, and cues flash under a scrolling timeline. Point a real sender at the Mac and the same sketch chases that.

<a name="midioutput"></a>

### MIDIOutput

```swift
MIDIOutput(name: String = "Ollin")
func open(matching: String? = nil) throws     // a hardware destination (first matching name)
func openVirtual(named: String? = nil) throws  // a virtual source other apps receive from
func availableDestinations() -> [MIDIEndpoint]
func send(_ message: MIDIMessage)
func noteOn(_ note: Int, velocity: Int = 100, channel: Int = 1)
func noteOff(_ note: Int, velocity: Int = 0, channel: Int = 1)
func controlChange(_ controller: Int, value: Int, channel: Int = 1)
func pitchBend(_ value: Int, channel: Int = 1)                   // 0…16383, 8192 at rest
func channelPressure(_ pressure: Int, channel: Int = 1)          // aftertouch for the channel
func polyPressure(_ note: Int, pressure: Int, channel: Int = 1)  // one key's pressure
func registeredParameter(_ parameter: Int, value: Int, fine: Int = 0, channel: Int = 1)
func send(mpeZone: MPEZone)          // announce a zone the way a controller does
func send(sysEx body: [UInt8])       // a system exclusive, the bytes between its start and end
func send(timecode: Timecode)         // a position whole, as a full-frame timecode message
func close()
```

`open(matching:)` connects to a hardware destination. It takes the first destination whose name contains the text you pass, or the first available destination when you pass nothing. Then you send from `draw()`:

```swift
let out = MIDIOutput()
override func setup() { try? out.open(matching: "Grid") }      // first destination matching "Grid"
override func draw() { out.controlChange(7, value: Int(level * 127)) }
```

`openVirtual(named:)` instead publishes a virtual source that other apps can receive from. A `MIDIInput` in the same process can receive from it too, which is how the loopback below runs with no hardware.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can test MIDI with nothing but the Mac in front of you. The **MIDILoopback** example (`Examples/Integration/MIDILoopback`) opens a virtual source, sends control changes to itself, and draws the value it reads back. What you see on screen is the round trip. It also shows parameter smoothing. The incoming value arrives in jumps, and the circle glides toward each new value.

To bring in real gear, connect a controller and run the **MIDIMonitor** example (`Examples/Integration/MIDIMonitor`). It listens to every device and prints and draws each message, so you can find out what a knob or pad sends by touching it. You can reconfigure many controllers, especially the endless-encoder kind, in their own editor software. The monitor shows what yours is set to.

---

### Files, not cables

This page is about gear playing live. A `.mid` file on disk is the other thing the word MIDI names, and it lives one library over, in [`MIDI files`](../Helpers/MIDIFiles.md): `MIDIFile` reads a Standard MIDI File into notes a sketch plays or draws, and writes one back out, so a phrase a sketch worked out opens in a sequencer.

It sits in `OllinAudio` because a file arrives as music rather than as messages. Its notes are `ScheduledNote` values, which is what a `Synth` plays and what every pattern type in [`Composition`](../Helpers/Composition.md) hands back, so nothing has to be translated in between.

---

See the **MIDILoopback** example for a sketch that sends and receives with no hardware. Use **MIDIMonitor** to inspect messages from a real controller, **Tempo** for visuals locked to MIDI clock, and **Timecode** for a sketch that chases a timeline.
