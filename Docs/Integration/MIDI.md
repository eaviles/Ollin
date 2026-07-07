#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `MIDI`</sup>

---

## MIDI

Wire a controller into a sketch. MIDI is the protocol every knob box, keyboard, pad grid, and sequencer speaks, so a hardware fader can drive a parameter, a key can trigger an event, and a sketch can send notes and control changes back out. It lives in a separate library so the drawing core stays free of Core MIDI. Add `import OllinMIDI` alongside `import Ollin` to reach it.

You read incoming MIDI with a [`MIDIInput`](#midiinput) and send it with a [`MIDIOutput`](#midioutput), both over Apple's Core MIDI. A message is a *kind* (a note, a control change, a clock tick) on a *channel* (1 to 16); the MIDI 1.0 format is parsed and encoded from the spec, so nothing is vendored.

```text
   ch 1   controlChange   controller 7   value 64
   └ channel ┘  └─ kind ─┘  └──────── data ────────┘
```

The usual shape: make the input in `setup()`, read it in `draw()`.

```swift
import Ollin
import OllinMIDI

final class Knob: Sketch {
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

- [MIDIMessage & kinds](#midimessage--kinds) — the value you read and send
- [MIDIInput](#midiinput) — read incoming MIDI three ways
- [Binding to a `@Param`](#binding-to-a-param) — drive a knob from a controller
- [MIDIOutput](#midioutput) — send notes and control changes
- [Testing without hardware](#testing-without-hardware) — loopback and the monitor

<a name="midimessage--kinds"></a>

### MIDIMessage & kinds

A `MIDIMessage` is a `kind` and the `channel` (1 to 16) it arrived on. The `kind` carries its own data:

```swift
switch message.kind {
case .noteOn(let note, let velocity):     trigger(note, velocity)
case .noteOff(let note, _):               release(note)
case .controlChange(let cc, let value):   knobs[cc] = value
case .pitchBend(let value):               bend = value          // 0…16383, 8192 center
default: break
}
```

The everyday kinds are `.noteOn` / `.noteOff` (a key or pad), `.controlChange` (a knob, fader, or pedal), and `.pitchBend`; the set is rounded out by `.programChange`, `.channelPressure`, `.polyPressure`, and the system real-time `.clock` / `.start` / `.stop` / `.continue` (these last carry no channel, so they report `0`). A note-on with velocity 0 — what a lot of gear sends for a release — is normalized to `.noteOff`.

The convenience accessors keep the common reads terse, so you rarely switch on `kind` directly:

```swift
message.note         // Int?  — for note / poly-pressure messages
message.velocity     // Int?  — for note messages
message.controller   // Int?  — the CC number
message.value        // Int?  — CC value, program, pressure, or bend
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

`start()` connects to every MIDI device on the system; ones plugged in afterward connect automatically. Then read what arrives — three ways, depending on what you're after. Omit `channel` to read across all channels, or pass `1…16` to pin one.

**The latest value of a controller**, for a continuous knob or fader. Read it fresh each frame:

```swift
let radius = Double(midi.controlValue(7, default: 0)) / 127 * 300
```

**The state of a note**, for a held key or pad:

```swift
if midi.isNoteOn(60) { sustain() }
```

**The event queue**, for discrete things — notes struck, transport, clock. `messages()` hands you everything received since the last call, in arrival order, and clears the queue. Call it once per frame:

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

MIDI arrives on a Core MIDI thread while the sketch reads on the main thread; everything shared is held behind locks, so the reads are safe from `draw()`.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(controlChange controller: Int, to param: Param,
          channel: Int? = nil, from input: ClosedRange<Double> = 0...127)
func unbind(controlChange controller: Int, channel: Int? = nil)
```

The fourth way to read: wire a control-change knob straight onto a [`@Param`](../Helpers/Parameters.md) knob, so a hardware fader drives the same parameter the inspector slider does. Each incoming value is mapped from `input` (a controller's `0…127` by default) into the parameter's own range and assigned:

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    try? midi.start()
    midi.bind(controlChange: 7, to: $radius)   // CC 0…127 → 20…400
}
```

A bound knob updates on its own as messages arrive, so you don't read it each frame. The same parameter still works from the inspector slider and from code; whichever moved most recently wins.

**Softening the moves.** Give the `@Param` a `smoothing:` and the hardware glides instead of jumping — the same softening applies whether the value comes from MIDI, OSC, or a drag of the inspector slider, because it's a property of the knob:

```swift
@Param(20...400, smoothing: .eased(0.3)) var radius = 120.0   // 0.3s glide
@Param(0...1, smoothing: .smoothed) var mix = 0.5             // adaptive 1€ filter
```

`.eased` glides to each value over a fixed time on an `Easing` curve; `.smoothed` runs it through a `OneEuroFilter`, which stays steady while the knob is still and opens up as it moves — the better feel for a hand on live hardware. Both are documented in [Animation](../Helpers/Animation.md) (the `Easing` curves and the `@Smoothed` 1€ filter).

<a name="midioutput"></a>

### MIDIOutput

```swift
MIDIOutput(name: String = "Ollin")
func open(to match: String? = nil) throws     // a hardware destination (first matching name)
func openVirtual(named: String? = nil) throws  // a virtual source other apps receive from
var destinations: [MIDIEndpoint]
func send(_ message: MIDIMessage)
func noteOn(_ note: Int, velocity: Int = 100, channel: Int = 1)
func noteOff(_ note: Int, velocity: Int = 0, channel: Int = 1)
func controlChange(_ controller: Int, value: Int, channel: Int = 1)
func close()
```

`open(to:)` points at a hardware destination — the first one whose name contains the text you pass, or the first available when you pass nothing — then send from `draw()`:

```swift
let out = MIDIOutput()
override func setup() { try? out.open(to: "Grid") }      // first destination matching "Grid"
override func draw() { out.controlChange(7, value: Int(level * 127)) }
```

`openVirtual(named:)` instead publishes a virtual source other apps — and a `MIDIInput` in this same process — can receive from, which is how the loopback below runs with no hardware.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can exercise MIDI with nothing but the Mac in front of you. The **MIDILoopback** example (`Examples/Integration/MIDILoopback`) opens a virtual source, sends control changes to itself, and draws the value it reads back — so the picture you see is the round-trip. It also shows the param softening: the incoming value steps like a knob jumping, but the circle glides toward each step.

To bring in real gear, connect a controller and run the **MIDIMonitor** example (`Examples/Integration/MIDIMonitor`): it listens to every device and prints and draws each message, so you can discover what a knob or pad sends just by touching it. Many controllers (the endless-encoder kind especially) are reconfigurable in their own editor — the monitor is how you see what yours is set to.

---

See the **MIDILoopback** example for a self-contained send-and-receive sketch that needs no hardware, and **MIDIMonitor** for inspecting messages from a real controller.
