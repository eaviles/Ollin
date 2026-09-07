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
- [Tempo sync (TempoClock)](#tempo-sync-tempoclock) - lock motion to the beat of whatever is playing
- [MIDIOutput](#midioutput) - send notes and control changes
- [Testing without hardware](#testing-without-hardware) - loopback and the monitor

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

The convenience accessors cover the common reads, so you rarely need to switch on `kind` directly:

```swift
message.note         // Int?  (note and poly-pressure messages)
message.velocity     // Int?  (note messages)
message.controller   // Int?  (the CC number)
message.value        // Int?  (CC value, program, pressure, or bend)
message.isNoteOn     // Bool
```

<a name="midiinput"></a>

### MIDIInput

```swift
MIDIInput(name: String = "Ollin")
func start() throws
func stop()
var sources: [MIDIEndpoint]    // the connected devices, by name

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
let swell = Timeline(0.0).to(1.0, in: 3, ease: .easeOut).to(0.0, in: 1)   // durations in beats

override func draw() {
    swell.loops = true
    swell.seek(to: clock.beats)   // now it cycles every 4 beats, locked to the music
}
```

The **Tempo** example (`Examples/Integration/Tempo`) shows this with no hardware. An internal timer sends clock through a virtual source, and the visuals lock to it. Connect real gear to the Mac, and the same sketch follows that clock instead.

<a name="midioutput"></a>

### MIDIOutput

```swift
MIDIOutput(name: String = "Ollin")
func open(matching: String? = nil) throws     // a hardware destination (first matching name)
func openVirtual(named: String? = nil) throws  // a virtual source other apps receive from
var destinations: [MIDIEndpoint]
func send(_ message: MIDIMessage)
func noteOn(_ note: Int, velocity: Int = 100, channel: Int = 1)
func noteOff(_ note: Int, velocity: Int = 0, channel: Int = 1)
func controlChange(_ controller: Int, value: Int, channel: Int = 1)
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

See the **MIDILoopback** example for a sketch that sends and receives with no hardware. Use **MIDIMonitor** to inspect messages from a real controller, and **Tempo** for visuals locked to MIDI clock.
