#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `DMX`</sup>

---

## DMX

Drive stage lights from `draw()`. DMX is the protocol behind theatrical dimmers, LED pars, and moving heads, and it carries 512 channels per universe. On a network it travels over ordinary Ethernet as **Art-Net** or **sACN** (ANSI E1.31). Those are the two wire protocols that lighting nodes and consoles speak. A sketch fills a universe of channels every frame and puts it on the network. An [`LEDMap`](#ledmap) goes further and sends the canvas's own pixels to LED strips and matrices. The same path in reverse lets a lighting console drive a sketch. The DMX code lives in a separate library, so the drawing core stays free of networking. Add `import OllinDMX` beside `import Ollin` to reach it.

Both wire formats are written from their published specifications on top of Apple's `Network.framework`, so nothing is vendored. Those specifications are the Art-Net 4 protocol document and ANSI E1.31-2018. Art-Net™ Designed by and Copyright Artistic Licence.

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

The usual pattern is to make the sender (or receiver) once, then fill and send a `DMXUniverse` in `draw()`. Send every frame at the display rate. The sender handles the packet timing that the specs ask for, so you do not have to.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/32-Installations/LampsAndBytes-dark.jpg">
  <img src="../../Guide/Images/32-Installations/LampsAndBytes.jpg" alt="A diagram in two rows: six colored pars hanging over a dark stage throwing red through violet light, and below them the same universe's first eighteen channels as meter bars bracketed into fixtures, with the fourth par dim in both views" width="680">
</picture>

### Contents

- [DMXUniverse](#dmxuniverse) - the 512-channel value you fill and send
- [DMXFixture](#dmxfixture) - patch by name instead of raw channel numbers
- [DMXSender](#dmxsender) - put universes on the wire, Art-Net or sACN
- [LEDMap](#ledmap) - send the canvas's own pixels to LED strips and matrices
- [DMXReceiver](#dmxreceiver) - let a console drive the sketch
- [Binding to a `@Param`](#binding-to-a-param) - a console fader as a parameter
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

A `DMXUniverse` is a plain value of 512 bytes, one byte per channel. The channels are numbered 1 to 512, which is how every console and fixture manual numbers them. Reading a channel outside that range returns 0. Writing outside it does nothing, so an off-by-one error never crashes the sketch during a performance.

`set(_:level:)` takes a level in the 0…1 range that the rest of a sketch already works in and scales it to the wire's 0…255. `set(_:color:)` writes a `Color`'s red, green, and blue to three consecutive channels, and `color(_:)` reads three channels back as a `Color`.

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

A fixture is a start address plus the roles of its channels, in order. Take those roles from the channel-mode table in the fixture's manual. The roles are `.dimmer`, `.red`, `.green`, `.blue`, `.white`, `.amber`, `.uv`, `.pan`, `.tilt`, `.strobe`, and `.unused` for a slot the sketch does not drive. The presets cover the common pars: `.dimmer`, `.rgb`, `.rgbw`, and `.drgb`, each at an address. `nextAddress` places the next fixture directly after the last one.

`set(_:color:dimmer:)` writes a color through the fixture's layout. On an RGBW fixture the part shared by red, green, and blue moves to the white channel, which is the classic RGBW split. A pale wash then comes from the white emitter instead of from all three color emitters at once. A fixture with a `.dimmer` channel takes the `dimmer` value on that channel. A fixture without one has its color scaled by `dimmer` instead, so `dimmer` means brightness either way.

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
var maxRate: Double                  // transmit ceiling, 44 packets/s per universe
```

Plain `DMXSender()` needs no configuration. It uses sACN, which multicasts each universe to that universe's standard group address. Any sACN node on the network that listens to that universe picks it up, so you name no address at all. Art-Net 4 sends DMX as unicast, so there the node's IP address is the one thing you name. The two protocols also number universes differently. On sACN the numbers run 1 to 63999. On Art-Net the universe number is the 15-bit port-address, 1 to 32767, which packs the net, sub-net, and universe switches into one number.

Call `send` every frame with whatever the sketch computed. The sender handles the packet timing that both specs ask for. Changed data goes out at once, capped at `maxRate` so the sender never exceeds what a DMX gateway can output. Unchanged data is re-sent a few times, so a receiver that missed one packet still reaches the same values. After that, a keep-alive packet goes out about every 0.9 s, so nodes know the source is still there. The sender also handles sequence numbers, sACN's source identity (the CID), and priorities.

`close()` on an sACN sender ends each stream cleanly before it shuts the connection. It sends three stream-terminated packets per universe, which is the ending the standard defines. Receivers then drop that source's output at once instead of waiting for a timeout.

The first time a sketch sends to hardware on the local network, macOS asks for **Local Network** permission, and it asks only once. The permission is attributed to the terminal that launched the sketch, because a `swift run` sketch has no bundle identity of its own. Permission for screen recording is attributed the same way, and for the same reason. Loopback to `127.0.0.1` needs no permission.

<a name="ledmap"></a>

### LEDMap

```swift
let dmx = DMXSender()                            // or unicast to your controller
let leds = LEDMap(sender: dmx)

override func setup() {
    leds.addStrip(from: Vector2(100, 540), to: Vector2(980, 540), leds: 144)
    leds.addMatrix(in: Rectangle(x: 390, y: 150, width: 300, height: 300),
                   columns: 16, rows: 16, universe: 2)
    extend(leds)                                 // it runs itself after every frame
}
```

An `LEDMap` sends regions of the canvas to addressable LEDs. You lay strips and matrices over the picture, register the map as an extension, and draw as usual. Every frame, the map samples the *rendered* pixels under each LED on the GPU. That sampling is a small compute pass over a few hundred points, not a readback of the full frame. The map then sends the sampled pixels as universes through its `DMXSender`, and the sender keeps the packet timing within the specs. The byte sent is the display byte, so the lamp gets the same value you see at that pixel.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/32-Installations/LEDWall-dark.jpg">
  <img src="../../Guide/Images/32-Installations/LEDWall.jpg" alt="A diagram in two rows: a colorful gradient picture with a wavy strip of small rings and a bracketed grid of rings mapped over it, and below, the same LEDs lit for real: the strip laid out straight in wire order and the panel beside it, each labeled with the universe it occupies" width="680">
</picture>

```swift
func addStrip(along points: [Vector2], leds: Int, closed: Bool = false,
              universe: Int = 1, address: Int = 1,
              layout: [DMXFixture.Role] = [.red, .green, .blue],
              sampleRadius: Double? = nil) -> Fixture
func addStrip(from: Vector2, to: Vector2, leds: Int, ...) -> Fixture
func addMatrix(in rect: Rectangle, columns: Int, rows: Int,
               serpentine: Bool = false, ...) -> Fixture
func addPoints(_ points: [Vector2], ...) -> Fixture

var brightness: Double               // master level, 0…1, over every LED
var positions: [Vector2]             // every sample point, wire order
var colors: [Color]                  // what each LED read last frame
var universes: [Int]                 // every universe the map writes
```

Each call places its LEDs in a different way.

- A **strip** spaces its LEDs evenly by the distance walked along the polyline, endpoints included, so a corner does not bunch them. `closed: true` spaces them around the closed loop instead, which suits an LED ring. `addStrip(from:to:)` is the shorthand for a straight run.
- A **matrix** reads one LED per cell, at the center of the cell, in straight rows from the top left. `serpentine: true` reverses every other row, which suits a zigzag-wired panel that you address directly. The default is straight rows, because a pixel controller usually knows the panel's wiring and expects straight rows on the wire.
- `addPoints` maps loose lamps at any positions you give, in the order you give them.

Each LED averages a small patch of the canvas around its point, **in linear light**. So a patch that is half black and half white reads as the gray that looks halfway to the eye. The default `sampleRadius` covers the patch the LED stands for. That is half the LED spacing on a strip, and half the cell on a matrix, kept between 1 and 32 pixels. Pass an explicit radius to override it.

On the wire, a universe holds **whole LEDs** only. An LED's channels never cross a universe boundary, so 170 RGB pixels (or 128 RGBW) fill a universe. The channels left over at the end of a universe stay dark, and a longer run continues on the next universe number. That is the layout pixel controllers expect, so patch the controller to the numbers that `universes` reports. The channels of each LED follow `layout`, and colors are written through the fixture path. So an `[.red, .green, .blue, .white]` layout gets the RGBW white split, and `brightness` scales the light for RGB and RGBW layouts alike. The returned `Fixture` tells you where everything landed. It carries its `positions` and its `universes`. It also carries `address(ofLED:)`, which reads one LED back off the wire, and the drawn preview in the LEDMapping example uses that.

The map drives lights, so it runs only in a live window. A headless export renders no frames to a window, so the map sends nothing. Frame-sharing behaves the same way in an export. The **LEDMapping** example (`Examples/Integration/LEDMapping`) runs the whole path on loopback. It lights a drawn strip and panel from what a receiver reads back.

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
func color(_ channel: Int, universe: Int = 1) -> Color     // three channels
func universeNumbers() -> [Int]                                   // what's been heard
```

The receiver lets the sketch act as a fixture. A lighting console, or another sketch, fades a channel, and `draw()` reads that channel like any other input. DMX carries continuous levels rather than events, so the read methods give the latest value only. Read it again each frame.

```swift
let dmx = DMXReceiver()
override func setup() { try? dmx.start(universes: [1]) }
override func draw() {
    background(dmx.color(1))                 // the console paints the canvas
    let size = dmx.level(4) * 400                // channel 4 runs a radius
    drawCircle(width / 2, height / 2, size)
}
```

Consoles usually multicast sACN. Pass the universes you want to `start(universes:)`, and the receiver joins their standard multicast groups. Plain `start()` hears only unicast sent to this Mac's IP address, which is all that loopback needs.

The receiver applies the standard's rules for you.

- When several sources drive one universe, the source with the highest priority wins.
- Packets that arrive out of order are dropped by their sequence number.
- The receiver ignores data flagged as preview and packets with an alternate START code.
- A source's stream-terminated packet clears that source's universe.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(channel: Int, universe: Int = 1, to param: Param<Double>)
func unbind(channel: Int, universe: Int = 1)
```

Bind a channel directly to a [`@Param`](../Helpers/Parameters.md), so a console fader drives the same parameter that a slider in the live inspector does. Each arriving value is mapped from the wire's 0…255 into the parameter's own range:

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    try? dmx.start(universes: [1])
    dmx.bind(channel: 1, to: $radius)            // fader 1 drives the radius parameter
}
```

A bound parameter updates on its own as data arrives. The same parameter still works from the inspector and from code, and the most recent change wins, whichever source made it.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can test the whole path on your Mac alone. Run both ends on `127.0.0.1`. The **DMXLoopback** example (`Examples/Integration/DMXLoopback`) does exactly that. It fills universe 1 with a color chase for a row of RGB pars and sends it to itself as sACN. It then lights the drawn stage from what the receiver reads back, so the picture shows the whole round trip.

To reach real hardware, replace the loopback sender with `DMXSender()` (multicast), or point it at your node's IP address. Patch the fixtures at the addresses your rig uses, and the same universe then drives real lights. Free sACN and Art-Net monitor apps, such as sACNView and DMX-Workshop, show every universe on the wire. That is a quick way to confirm what a sketch is sending.

The library covers the streaming level only. That means ArtDmx output and input on the Art-Net side, and E1.31 data packets on the sACN side. Art-Net's discovery layer (ArtPoll/ArtPollReply) is out of scope for now. sACN's universe discovery packets, its synchronization packets, and RDM are also out of scope. A node that needs only a stream of universes works without any of those, and nearly all nodes need only that.

---

Credits: this implementation is written from the published specifications. Art-Net™ Designed by and Copyright Artistic Licence. sACN is ANSI E1.31, published by ESTA's Technical Standards Program.

See the **DMXLoopback** example for a self-contained sketch that sends and receives. It needs no console or hardware to run. See **LEDMapping** for the canvas sampled onto a drawn strip and panel in the same way.
