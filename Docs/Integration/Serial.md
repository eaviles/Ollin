#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Serial`</sup>

---

## Serial

The classic physical-computing loop. A microcontroller (an Arduino, a Feather, an ESP32, most anything with a USB plug) shows up on the Mac as a serial device. A sketch reads the sensor values it prints and writes lines back to drive servos and LEDs. It lives in a separate library so the drawing core stays free of IOKit. Add `import OllinSerial` alongside `import Ollin` to reach it.

Devices are discovered through IOKit and driven through POSIX termios, so nothing is vendored. Framing stays at text lines and raw bytes, one sensor value per line being the classic shape. Higher protocols layer on top in sketch code or an [extension](../Tools/Extensions.md).

```swift
import Ollin
import OllinSerial

final class Dial: Sketch {
    let serial = SerialPort(matching: "usbmodem", baudRate: 9600)

    override func setup() { serial.open() }

    override func draw() {
        background(.white)
        // the board prints analogRead's 0...1023, one number per line
        let level = serial.number(default: 0) / 1023
        fill(.black)
        drawCircle(width / 2, height / 2, (40 + level * 400) * scale)
    }
}
```

### Contents

- [Finding a device](#finding-a-device) - list what's plugged in, or match by name
- [Opening, and staying open](#opening-and-staying-open) - reconnection is the default
- [Reading](#reading) - the latest value, or every line since last frame
- [Binding to a `@Param`](#binding-to-a-param) - a sensor drives a parameter
- [Writing](#writing) - lines and bytes back to the board
- [Testing without hardware](#testing-without-hardware) - the loopback and monitor examples

<a name="finding-a-device"></a>

### Finding a device

```swift
SerialPort.availableDevices() -> [SerialDevice]   // USB devices first
SerialDevice.path   // "/dev/cu.usbmodem101": what a port opens
SerialDevice.name   // "Feather M4", or the path's tail when USB has no name
```

`availableDevices()` lists every serial device on the Mac right now, USB devices sorted first, since those are almost always the ones a sketch wants. The built-in Bluetooth ports come along too; ignore them. Construct a port from a device, from its path, or, usually the most convenient, from a match:

```swift
SerialPort(matching: "usbmodem", baudRate: 9600)   // first device whose name or path contains it
SerialPort(device: devices[0], baudRate: 115200)
SerialPort(path: "/dev/cu.usbmodem101")            // baudRate defaults to 9600
```

The match is case-insensitive and re-runs on every connection attempt, which is what makes it the convenient form. The board can be plugged in after the sketch launches. One that re-enumerates under a new device number after a replug is still found. The `baudRate` must agree with what the board's firmware sets; USB-native boards ignore it entirely, so when in doubt leave the default.

<a name="opening-and-staying-open"></a>

### Opening, and staying open

```swift
func open()      // never gives up; retries every second until the device appears
func close()     // stops reading and stops reconnecting
var isOpen: Bool
```

`open()` returns immediately and keeps at it: a device that is missing, busy, or unplugged later is simply waited for. The port reconnects on its own the moment the device comes back. A cable bump or a firmware re-flash mid-performance heals without a restart. `isOpen` says where things stand, so a sketch can draw a waiting state.

The port holds the device exclusively, since two readers on one port each get half the bytes. So uploading new firmware needs the port free: `close()` first, or quit the sketch. The reconnection loop makes the reopen half automatic if you only `close()` for the upload.

<a name="reading"></a>

### Reading

```swift
// 1. Latest value (continuous controls)
var latestLine: String?
func number() -> Double?        // the latest line, parsed as a number
func int() -> Int?
func bool() -> Bool?            // "1"/"0", "true"/"false", "on"/"off"
func number(default: Double) -> Double // and int/bool variants

// 2. Everything since the last call, in order (discrete events)
func lines() -> [String]
func bytes() -> [UInt8]         // the raw stream, for binary protocols
```

Bytes arrive on a background queue while the sketch reads on the main thread. Everything shared is held behind locks, so the reads are safe from `draw()`.

**The latest value**, for a continuous sensor. Firmware that prints one number per line (`Serial.println(analogRead(A0))` and friends) reads directly:

```swift
let level = serial.number(default: 0) / 1023
```

**The event queue**, for discrete things. `lines()` hands you every complete line received since the last call, in arrival order, and clears the queue. Call it once per frame:

```swift
for line in serial.lines() where line == "pressed" { spawnRipple() }
```

Line endings are tolerated in every convention a device might use: LF, CRLF, or bare CR all end a line. A line split across reads still comes out whole. For a device that speaks a binary framing instead, `bytes()` drains the raw stream. It is independent of `lines()`, so draining one leaves the other alone.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(to param: Param<Double>, from input: ClosedRange<Double> = 0...1023)
func unbind()
```

The third way to read is to wire the stream straight onto a [`@Param`](../Helpers/Parameters.md). A sensor then drives the same parameter a live-inspector slider does. Each line that parses as a number is mapped from `input` into the parameter's own range and assigned. The default input range is the classic 10-bit analog read:

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    serial.open()
    serial.bind(to: $radius)                // 0...1023 → 20...400
    serial.bind(to: $level, from: 0...4095) // a 12-bit sensor
}
```

A bound parameter updates on its own as lines arrive. The same parameter still works from the inspector slider and from code, and whichever moved most recently wins.

<a name="writing"></a>

### Writing

```swift
func write(_ text: String)       // UTF-8, exactly as given
func writeLine(_ text: String)   // text plus a newline
func write(_ bytes: [UInt8])     // raw bytes
```

Writes go out on the port's background queue, so a frame never waits on the wire. `writeLine` uses the same framing `lines()` reads on the way in, which is the shape most firmware parses:

```swift
serial.writeLine("led:on")
serial.writeLine("servo:\(Int(angle))")
```

Bytes sent while the device is away are dropped rather than queued. A board that just reconnected wants current values, not a replay of everything it missed.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can exercise the whole loop with nothing but the Mac in front of you. The **SerialLoopback** example (`Examples/Integration/SerialLoopback`) runs both ends of the wire itself. A tiny fake device (one side of a pty pair) prints a sensor value thirty times a second. A `SerialPort` opens the other side exactly the way it would open a real board. The trace you see is drawn from what arrives over the port. Clicking writes a line back that flips the wave, so the write path is visible too.

With a real board, the **SerialMonitor** example (`Examples/Integration/SerialMonitor`) lists every serial device live, opens the first USB one it finds, and scrolls whatever the board prints. A numeric line also fills a value bar. Plug in, watch the lines, and you know exactly what your sketch will read.

---

See the **SerialLoopback** example for the full loop with no hardware, and **SerialMonitor** to discover what a real board sends.
