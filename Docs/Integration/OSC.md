#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `OSC`</sup>

---

## OSC

OSC (Open Sound Control) is a small protocol for sending messages over a network. TouchOSC, Max/MSP, TouchDesigner, Ableton, Resolume, and most lighting desks speak it, so a sketch can talk to the other tools in a performance rig. A sketch can read a fader from a phone, or send a value to a video mixer. The OSC support lives in a separate library, which keeps the drawing core free of networking. Add `import OllinOSC` beside `import Ollin` to reach it.

A message is an address (a slash path like `/synth/freq`) and a few typed values. You send messages with an [`OSCSender`](#oscsender) and read incoming ones with an [`OSCReceiver`](#oscreceiver). Both run over UDP on Apple's `Network.framework`. The OSC wire format is written from the spec, so nothing is vendored.

```text
  /synth/1/freq   440.0   "on"   true
  └─ address ─┘   └─── arguments ───┘
```

The usual pattern is to make the sender and the receiver in `setup()`, then send and read in `draw()`.

```swift
import Ollin
import OllinOSC

final class Wired: Sketch {
    let out = OSCSender(host: "127.0.0.1", port: 9000)
    let in_ = OSCReceiver(port: 8000)

    override func setup() { try? in_.start() }

    override func draw() {
        // read a fader coming in, send the cursor out
        let level = in_.number("/fader1", default: 0)
        out.send("/cursor", .float(Float(mouseX / width)))
        drawCircle(width / 2, height / 2, (40 + level * 300) * scale)
    }
}
```

### Contents

- [OSCMessage & arguments](#oscmessage--arguments) - the value you send and receive
- [OSCSender](#oscsender) - send messages and bundles
- [OSCReceiver](#oscreceiver) - read incoming messages two ways, or bind an address to a parameter
- [Binding to a `@Param`](#binding-to-a-param) - drive a parameter from an address
- [Bundles & time tags](#bundles--time-tags) - group messages
- [Testing without hardware](#testing-without-hardware) - loopback, monitors, and TouchOSC

<a name="oscmessage--arguments"></a>

### OSCMessage & arguments

```swift
OSCMessage("/light", 0.8, 1, "on", true)        // literals build arguments
OSCMessage("/x", .float(value), .int(count))     // a variable is wrapped by its case
```

An `OSCMessage` is an `address` and an array of `arguments`. A literal becomes an argument on its own, so the common case stays short. `0.8` is a float, `1` is an int, `"on"` is a string, and `true` is a bool. A value held in a variable is wrapped by its case, as `.float(x)`, `.int(n)`, or `.string(s)`. That step is needed because Swift does not convert a `Float` to an argument on its own.

`OSCArgument` covers the OSC 1.0 types. Those are `.int` at 32 bits, `.float`, `.string`, and `.blob` for raw bytes, plus `.double`, `.int64`, `.bool`, `.null`, and `.impulse` as a bare trigger. When you read a value back, the coercing accessors save you a `switch`. Those accessors are `.number`, `.int`, `.text`, and `.bool`, and they convert across the numeric types where that makes sense.

<a name="oscsender"></a>

### OSCSender

```swift
OSCSender(host: String, port: Int)
func send(_ message: OSCMessage)
func send(_ bundle: OSCBundle)
func send(_ address: String, _ arguments: OSCArgument...)   // build-and-send sugar
func close()
```

An `OSCSender` points at one destination and sends to it. The `host` is an IP address or a hostname. `127.0.0.1` is this Mac, and a phone on the same network is something like `192.168.1.42`. The one-line `send(address, args…)` form is the one you will use most often:

```swift
let out = OSCSender(host: "192.168.1.42", port: 9000)
out.send("/level", .float(level))
out.send("/note", 60, 100)          // two int literals
```

UDP does not acknowledge delivery, so `send` returns right away and never waits for the other end. That suits live control traffic, because a dropped frame of a continuous value is replaced by the next one a moment later.

<a name="oscreceiver"></a>

### OSCReceiver

```swift
OSCReceiver(port: Int)        // port 0 = let the system pick (read it from boundPort)
func start() throws
func stop()

// 1. Latest value per address (continuous controls)
func number(_ address: String) -> Double?
func int(_ address: String) -> Int?
func text(_ address: String) -> String?
func bool(_ address: String) -> Bool?
func number(_ address: String, default: Double) -> Double  // and int/bool variants
func message(_ address: String) -> OSCMessage?            // the whole message
func arguments(_ address: String) -> [OSCArgument]?

// 2. Everything since the last call, in order (discrete events)
func messages() -> [OSCMessage]
```

An `OSCReceiver` listens on a port, and the sketch reads what arrives. There are two main ways to read, and a third that binds an address to a parameter. The right one depends on what an address carries.

**The latest value** suits a continuous control like a fader. Read it fresh each frame:

```swift
let radius = osc.number("/fader1", default: 0) * 300
```

The typed getters read the *first* argument and coerce it, so `int("/fader1")` on a float message rounds the value. For a message with several arguments, read `arguments(_:)` instead.

**The event queue** suits discrete events like notes or triggers. `messages()` returns everything received since the last call, in arrival order, and then clears the queue. Call it once per frame:

```swift
for note in osc.messages() where note.address == "/note" {
    spawnRipple(pitch: note.int ?? 0)
}
```

```text
   network queue                main thread (draw)
   ┌────────────┐  latest[]     ┌──────────────────┐
   │ datagram → │ ───────────→  │ osc.number("/x") │   continuous
   │  decode +  │  inbox[]      │ osc.messages()   │   discrete
   │  stash     │ ───────────→  │                  │
   └────────────┘               └──────────────────┘
```

Datagrams arrive on a background queue while the sketch reads on the main thread. Everything the two sides share is held behind locks, so reading from `draw()` is safe.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(_ address: String, to param: Param<Double>, from input: ClosedRange<Double> = 0...1)
func unbind(_ address: String)
```

`to:` also takes a `Param<Tempo>`, the beats-per-minute slider a [tempo](../Helpers/Composition.md#tempo-and-note-lengths) declares, mapped into its range the same way. The beats per bar stay what the declaration gave them.

The third way to read is to bind an address to a [`@Param`](../Helpers/Parameters.md) parameter. An incoming value then drives the parameter the same way a slider in the live inspector does. The receiver maps the first value of each message from the `input` range into the parameter's own range. It then clamps that value and assigns it to the parameter:

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    try? osc.start()
    osc.bind("/radius", to: $radius)              // incoming 0…1 → 20…400
    osc.bind("/freq", to: $freq, from: 0...127)   // a 0…127 fader
}
```

A bound parameter updates on its own as messages arrive, so you do not need to read it each frame. The same parameter still works from the inspector slider and from code, and the most recent change is the one that takes effect.

<a name="bundles--time-tags"></a>

### Bundles & time tags

```swift
OSCBundle(_ timeTag: OSCTimeTag = .immediate, messages: [OSCMessage])
```

A bundle groups messages that belong together, and the group is sent as one datagram. It also carries a time tag that says when the messages take effect. That tag is usually `.immediate`. Send a bundle the same way you send a message:

```swift
out.send(OSCBundle(.immediate, messages: [
    OSCMessage("/x", 0.5),
    OSCMessage("/y", 0.5),
]))
```

On the receiving side, the messages in a bundle go into the same latest-value cache and event queue as loose messages. That means you read them in exactly the same way. If a downstream tool honors scheduling, `OSCTimeTag(_ date:)` builds a future time tag from a `Date`.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can test OSC with nothing but the Mac in front of you. Run a sender and a receiver in the same sketch, both on `127.0.0.1`. The **OSCLoopback** example (`Examples/Integration/OSCLoopback`) does exactly that. It sends an animated position to itself and draws the dot from what it reads back. What you see on screen is the value after the round trip.

To bring in real hardware, point a phone running TouchOSC at this Mac's IP address and the receiver's port. Any OSC source works, as long as it sends the addresses your sketch reads. The **OSCMonitor** example (`Examples/Integration/OSCMonitor`) listens on a port, then prints and draws every message it receives. That lets you discover the addresses each control sends just by touching them. To watch what a sketch emits, point a monitor like Protokol at the sender's port, or use `oscdump` from the command line.

---

See the **OSCLoopback** example for a sketch that sends and receives with no second app. Use the **OSCMonitor** example to inspect messages from a phone or a controller.
