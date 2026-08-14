#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `OSC`</sup>

---

## OSC

Talk to the other tools in a performance rig. OSC (Open Sound Control) is a small networked-message protocol. TouchOSC, Max/MSP, TouchDesigner, Ableton, Resolume, and most lighting desks speak it. So a sketch can take a fader from a phone, or hand a value off to a video mixer. It lives in a separate library so the drawing core stays free of networking. Add `import OllinOSC` alongside `import Ollin` to reach it.

A message is an address (a slash path like `/synth/freq`) and a few typed values. You send messages with an [`OSCSender`](#oscsender) and read incoming ones with an [`OSCReceiver`](#oscreceiver). Both go over UDP, built on Apple's `Network.framework`, and the OSC wire format is written from the spec, so nothing is vendored.

```text
  /synth/1/freq   440.0   "on"   true
  └─ address ─┘   └─── arguments ───┘
```

The usual shape is to make the sender and receiver in `setup()`, then send and read in `draw()`.

```swift
import Ollin
import OllinOSC

final class Knob: Sketch {
    let out = OSCSender(host: "127.0.0.1", port: 9000)
    let in_ = OSCReceiver(port: 8000)

    override func setup() { try? in_.start() }

    override func draw() {
        // read a fader coming in, send the cursor out
        let level = in_.float("/fader1", default: 0)
        out.send("/cursor", .float(Float(mouseX / width)))
        drawCircle(width / 2, height / 2, (40 + Double(level) * 300) * scale)
    }
}
```

### Contents

- [OSCMessage & arguments](#oscmessage--arguments) - the value you send and receive
- [OSCSender](#oscsender) - send messages and bundles
- [OSCReceiver](#oscreceiver) - read incoming messages three ways
- [Binding to a `@Param`](#binding-to-a-param) - drive a knob from an address
- [Bundles & time tags](#bundles--time-tags) - group messages
- [Testing without hardware](#testing-without-hardware) - loopback, monitors, and TouchOSC

<a name="oscmessage--arguments"></a>

### OSCMessage & arguments

```swift
OSCMessage("/light", 0.8, 1, "on", true)        // literals build arguments
OSCMessage("/x", .float(value), .int(count))     // a variable is wrapped by its case
```

An `OSCMessage` is an `address` and an array of `arguments`. Literals turn into arguments on their own, so the common case stays terse. `0.8` is a float, `1` an int, `"on"` a string, and `true` a bool. A value held in a variable is wrapped by its case, as `.float(x)`, `.int(n)`, or `.string(s)`. Swift does not convert a `Float` to an argument on its own.

`OSCArgument` covers the OSC 1.0 types. Those are `.int` at 32 bits, `.float`, `.string`, and `.blob` for raw bytes, plus `.double`, `.int64`, `.bool`, `.null`, and `.impulse` as a bare trigger. Reading back, the coercing accessors save a `switch`, so `.asFloat`, `.asInt`, `.asString`, and `.asBool` convert across the numeric types where it makes sense.

<a name="oscsender"></a>

### OSCSender

```swift
OSCSender(host: String, port: Int)
func send(_ message: OSCMessage)
func send(_ bundle: OSCBundle)
func send(_ address: String, _ arguments: OSCArgument...)   // build-and-send sugar
func close()
```

Points at a destination and sends. The `host` is an IP or a hostname, where `127.0.0.1` is this Mac and a phone on the same network is something like `192.168.1.42`. The one-line `send(address, args…)` form is the one you'll reach for most:

```swift
let out = OSCSender(host: "192.168.1.42", port: 9000)
out.send("/level", .float(level))
out.send("/note", 60, 100)          // two int literals
```

Sending over UDP is fire-and-forget, so a `send` returns right away and delivery isn't acknowledged, which is what live control traffic wants. A dropped frame of a continuous value is replaced by the next one a moment later.

<a name="oscreceiver"></a>

### OSCReceiver

```swift
OSCReceiver(port: Int)        // port 0 = let the system pick (read it from boundPort)
func start() throws
func stop()

// 1. Latest value per address (continuous controls)
func float(_ address: String) -> Float?
func int(_ address: String) -> Int?
func string(_ address: String) -> String?
func bool(_ address: String) -> Bool?
func float(_ address: String, default: Float) -> Float    // and int/bool variants
func message(_ address: String) -> OSCMessage?            // the whole message
func arguments(_ address: String) -> [OSCArgument]?

// 2. Everything since the last call, in order (discrete events)
func messages() -> [OSCMessage]
```

Listen on a port, then read what arrives. There are two main ways to read, depending on what an address carries.

**The latest value**, for a continuous control like a fader. Read it fresh each frame:

```swift
let radius = Double(osc.float("/fader1", default: 0)) * 300
```

The typed getters read the *first* argument, coerced (so `int("/fader1")` on a float message rounds it). For a message with several arguments, reach into `arguments(_:)`.

**The event queue**, for discrete things like notes or triggers. `messages()` hands you everything received since the last call, in arrival order, and clears the queue. Call it once per frame:

```swift
for note in osc.messages() where note.address == "/note" {
    spawnRipple(pitch: note.int ?? 0)
}
```

```text
   network queue                main thread (draw)
   ┌────────────┐  latest[]     ┌──────────────────┐
   │ datagram → │ ───────────→  │ osc.float("/x")  │   continuous
   │  decode +  │  inbox[]      │ osc.messages()   │   discrete
   │  stash     │ ───────────→  │                  │
   └────────────┘               └──────────────────┘
```

Datagrams arrive on a background queue while the sketch reads on the main thread. Everything shared is held behind locks, so the reads are safe from `draw()`.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(_ address: String, to param: Param<Double>, from input: ClosedRange<Double> = 0...1)
func unbind(_ address: String)
```

The third way to read is to wire an address straight onto a [`@Param`](../Helpers/Parameters.md) knob. An incoming value then drives the same parameter a live-inspector slider does. Each message's first value is mapped from `input` into the parameter's own range and assigned (clamped):

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    try? osc.start()
    osc.bind("/radius", to: $radius)              // incoming 0…1 → 20…400
    osc.bind("/freq", to: $freq, from: 0...127)   // a 0…127 fader
}
```

A bound knob updates on its own as messages arrive, so you don't read it each frame. The same parameter still works from the inspector slider and from code, and whichever moved most recently wins.

<a name="bundles--time-tags"></a>

### Bundles & time tags

```swift
OSCBundle(_ timeTag: OSCTimeTag = .immediate, messages: [OSCMessage])
```

A bundle groups messages that belong together (sent as one datagram) and carries a time tag for when they take effect, usually `.immediate`. Send one the same way as a message:

```swift
out.send(OSCBundle(.immediate, messages: [
    OSCMessage("/x", 0.5),
    OSCMessage("/y", 0.5),
]))
```

On the receiving side a bundle's messages flow into the same latest-value cache and event queue as loose messages, so reading is unchanged. `OSCTimeTag(_ date:)` builds a future time tag from a `Date` if a downstream tool honors scheduling.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can exercise OSC with nothing but the Mac in front of you. Run both ends on `127.0.0.1`, a sender and a receiver in the same sketch. The **OSCLoopback** example (`Examples/Integration/OSCLoopback`) does exactly that. It sends an animated position to itself, and draws the dot from what it reads back. The picture you see is the round-trip itself.

To bring in real gear, point a phone running TouchOSC at this Mac's IP and the receiver's port. Any OSC source works, and it sends the addresses your sketch reads. The **OSCMonitor** example (`Examples/Integration/OSCMonitor`) listens on a port, and prints and draws every message it receives. So you can discover the addresses each control sends just by touching them. To watch what a sketch emits, aim a monitor like Protokol at the sender's port, or use `oscdump` from the command line.

---

See the **OSCLoopback** example for a sketch that sends and receives with no second app. Use **OSCMonitor** to inspect messages from a phone or controller.
