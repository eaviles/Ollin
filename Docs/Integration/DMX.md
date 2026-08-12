#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `DMX`</sup>

---

## DMX

Drive stage lights from `draw()`. DMX is the 512-channels-per-universe protocol behind theatrical dimmers, LED pars, and moving heads, and it travels over ordinary Ethernet as **Art-Net** or **sACN** (ANSI E1.31), the two wire protocols lighting nodes and consoles speak. A sketch fills a universe of channels every frame and puts it on the network; the same machinery in reverse lets a lighting console drive a sketch. It lives in a separate library so the drawing core stays free of networking. Add `import OllinDMX` alongside `import Ollin` to reach it.

Both wire formats are written from their published specifications (the Art-Net 4 protocol document and ANSI E1.31-2018) over Apple's `Network.framework`, so nothing is vendored. Art-Net™ Designed by and Copyright Artistic Licence.

```swift
import Ollin
import OllinDMX

final class Chase: Sketch {
    let dmx = DMXSender()                        // sACN multicast: zero config
    let par = DMXFixture.rgb(at: 1)              // an RGB par on channels 1-3

    override func draw() {
        var rig = DMXUniverse()
        rig.set(par, color: Color(hue: fract(time * 0.1), saturation: 1, brightness: 1))
        dmx.send(rig)                            // universe 1, every frame
    }
}
```

The usual shape is to make the sender (or receiver) once, then fill and send a `DMXUniverse` in `draw()`. Send every frame at the display rate; the sender handles the wire cadence the specs ask for on its own.

### Contents

- [DMXUniverse](#dmxuniverse) - the 512-channel value you fill and send
- [DMXFixture](#dmxfixture) - patch by name instead of raw channel numbers
- [DMXSender](#dmxsender) - put universes on the wire, Art-Net or sACN
- [DMXReceiver](#dmxreceiver) - let a console drive the sketch
- [Binding to a `@Param`](#binding-to-a-param) - a console fader as a knob
- [Testing without hardware](#testing-without-hardware) - loopback and monitors

<a name="dmxuniverse"></a>

### DMXUniverse

```swift
var rig = DMXUniverse()              // 512 channels, all at 0
rig[1] = 255                         // channel 1 to full (channels are 1-based)
rig.set(2, level: 0.5)               // a 0…1 level, the unit animations live in
rig.set(10, color: .red)             // channels 10, 11, 12 = R, G, B
rig.clear()                          // all dark
```

A `DMXUniverse` is a plain value: 512 bytes, one per channel, numbered 1 to 512 the way every console and fixture manual numbers them. Reading outside that range returns 0 and writing outside it does nothing, so an off-by-one never traps mid-performance.

`set(_:level:)` takes the 0…1 range the rest of a sketch already works in and scales it to the wire's 0…255. `set(_:color:)` lays a `Color`'s red, green, and blue across three consecutive channels, and `color(at:)` reads three back.

<a name="dmxfixture"></a>

### DMXFixture

```swift
let par = DMXFixture.rgb(at: 1)                  // channels 1-3
let wash = DMXFixture.rgbw(at: par.nextAddress)  // channels 4-7
let head = DMXFixture(at: 20, .pan, .tilt, .dimmer, .red, .green, .blue)

rig.set(par, color: .red)                        // color lands on its RGB channels
rig.set(wash, color: .white, dimmer: 0.5)        // dimmer on its dimmer channel
rig.set(head, .pan, level: 0.25)                 // one role directly
```

A fixture is a start address plus the ordered roles of its channels, spelled from the fixture manual's channel-mode table: `.dimmer`, `.red`, `.green`, `.blue`, `.white`, `.amber`, `.uv`, `.pan`, `.tilt`, `.strobe`, and `.unused` for slots the sketch doesn't drive. The presets cover the common pars (`.dimmer`, `.rgb`, `.rgbw`, `.drgb` at an address), and `nextAddress` patches the next fixture right behind the last one.

`set(_:color:dimmer:)` writes a color through the layout. On an RGBW fixture the shared part of the color moves to the white channel (the classic split, so a pale wash uses the white emitter instead of faking it with all three colors). A fixture with a `.dimmer` channel takes `dimmer` there; one without gets its color scaled instead, so `dimmer` means brightness either way.

<a name="dmxsender"></a>

### DMXSender

```swift
DMXSender()                              // sACN multicast: any listening node receives it
DMXSender(sACN: "192.168.1.20")          // sACN unicast to one node
DMXSender(artNet: "192.168.1.60")        // Art-Net unicast to a node

func send(_ data: DMXUniverse, universe: Int = 1)
func send(channels: [UInt8], universe: Int = 1)
func close()

var sourceName: String                   // what sACN monitors show, "Ollin" by default
var priority: Int                        // sACN source priority 0…200, 100 by default
var maximumRate: Double                  // transmit ceiling, 44 packets/s per universe
```

The zero-config form is plain `DMXSender()`: sACN multicasts each universe to its standard group address, so any sACN node on the network listening to that universe picks it up with no addressing at all. Art-Net 4 sends DMX unicast, so there the node's IP is the one thing to name. Universe numbers run 1 to 63999 on sACN; on Art-Net the number is the 15-bit port-address (net, sub-net, and universe switches packed together), 1 to 32767.

Call `send` every frame with whatever the sketch computed; the sender takes care of the wire cadence both specs ask for. Changed data goes out immediately (capped at `maximumRate`, matching what a DMX gateway can physically output), unchanged data is re-sent a few times so a receiver that missed a packet still converges, and after that a keep-alive goes out every ~0.9 s so nodes know the source is alive. Sequence numbers, sACN's source identity (CID), and priorities are handled for you.

`close()` on an sACN sender says goodbye first: three stream-terminated packets per universe, the standard's clean ending, so receivers drop the look immediately instead of waiting out a timeout.

Sending to hardware on the local network makes macOS ask for **Local Network** permission once. Like screen recording, the permission is attributed to the launching terminal (a `swift run` sketch has no bundle identity of its own); loopback to `127.0.0.1` needs nothing.

<a name="dmxreceiver"></a>

### DMXReceiver

```swift
DMXReceiver()                            // sACN on its standard port 5568
DMXReceiver(.artNet)                     // Art-Net on 6454
func start() throws                      // hear unicast sent to this Mac
func start(universes: [Int]) throws      // also join those sACN multicast groups
func stop()

func universe(_ number: Int = 1) -> DMXUniverse?
func channel(_ channel: Int, universe: Int = 1) -> UInt8
func level(_ channel: Int, universe: Int = 1) -> Double     // 0…1
func color(at channel: Int, universe: Int = 1) -> Color     // three channels
func universes() -> [Int]                                   // what's been heard
```

The receiver turns the sketch into a fixture: a lighting console (or another sketch) fades a channel, and `draw()` reads it like any other input. DMX is continuous levels rather than events, so the read surface is the latest-value kind only; read fresh each frame.

```swift
let dmx = DMXReceiver()
override func setup() { try? dmx.start(universes: [1]) }
override func draw() {
    background(dmx.color(at: 1))                 // the console paints the canvas
    let size = dmx.level(4) * 400                // channel 4 runs a radius
    drawCircle(width / 2, height / 2, size)
}
```

Consoles usually multicast sACN, so pass the universes you care about to `start(universes:)` and the receiver joins their standard groups; plain `start()` hears unicast aimed at this Mac's IP (and is all loopback needs). The standard's receiver rules are applied for you: when several sources drive one universe the highest priority wins, out-of-order stragglers are dropped by sequence number, preview-flagged data and alternate START codes are ignored, and a source's stream-terminated goodbye clears its universe.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(channel: Int, universe: Int = 1, to param: Param<Double>)
func unbind(channel: Int, universe: Int = 1)
```

Wire a channel straight onto a [`@Param`](../Helpers/Parameters.md) knob, so a console fader drives the same parameter a live-inspector slider does. Each arriving value is mapped from the wire's 0…255 into the parameter's own range:

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    try? dmx.start(universes: [1])
    dmx.bind(channel: 1, to: $radius)            // fader 1 becomes the radius knob
}
```

A bound knob updates on its own as data arrives. The same parameter still works from the inspector and from code, and whichever moved most recently wins.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can exercise the whole path with nothing but the Mac in front of you by running both ends on `127.0.0.1`. The **DMXLoopback** example (`Examples/Integration/DMXLoopback`) does exactly that: it fills universe 1 with a color chase for a row of RGB pars, sends it to itself as sACN, and lights the drawn stage from what the receiver reads back, so the picture is the round trip itself.

To reach real hardware, swap the loopback sender for `DMXSender()` (multicast) or point it at your node's IP, patch the fixtures at the addresses your rig uses, and the same universe drives real lights. Free sACN/Art-Net monitor apps (sACNView, DMX-Workshop, and friends) show every universe on the wire, which is the quickest way to confirm what a sketch is emitting.

What's covered, and what deliberately isn't: this is the streaming-level tier (ArtDmx output and input on the Art-Net side; E1.31 data packets on the sACN side). Art-Net's discovery layer (ArtPoll/ArtPollReply) and sACN's universe discovery and synchronization packets are out of scope for now, as is RDM; nodes that need only a stream of universes, which is nearly all of them, work without any of it.

---

Credits: this implementation is written from the published specifications. Art-Net™ Designed by and Copyright Artistic Licence. sACN is ANSI E1.31, published by ESTA's Technical Standards Program.

See the **DMXLoopback** example for a self-contained send-and-receive sketch that needs no console or hardware to run.
