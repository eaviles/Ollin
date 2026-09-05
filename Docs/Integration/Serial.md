#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Serial`</sup>

---

## Serial

Serial is the classic physical-computing loop. A microcontroller shows up on the Mac as a serial device. That covers an Arduino, a Feather, an ESP32, and most anything with a USB plug. Your sketch reads the sensor values the board prints, and it writes lines back to drive servos and LEDs. Serial lives in a separate library, so the drawing core stays free of IOKit. Add `import OllinSerial` alongside `import Ollin` to reach it.

Ollin finds devices through IOKit and drives them through POSIX termios, so it vendors no third-party code. The framing stays at text lines and raw bytes, and the classic shape is one sensor value per line. Any higher protocol goes on top of that, in sketch code or in an [extension](../Tools/Extensions.md).

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
- [Reading](#reading) - the latest value, or every line since the last frame
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

`availableDevices()` lists every serial device on the Mac right now. USB devices are sorted first, because those are almost always the ones a sketch wants. The built-in Bluetooth ports appear in the list too, and you can ignore them. You build a port from a device, from its path, or from a match, and the match is usually the most convenient form:

```swift
SerialPort(matching: "usbmodem", baudRate: 9600)   // first device whose name or path contains it
SerialPort(device: devices[0], baudRate: 115200)
SerialPort(path: "/dev/cu.usbmodem101")            // baudRate defaults to 9600
```

The match is case-insensitive, and it runs again on every connection attempt. That is what makes it convenient, because you can plug the board in after the sketch launches. A board that re-enumerates under a new device number after a replug is still found. The `baudRate` must agree with what the board's firmware sets. USB-native boards ignore it entirely, so leave the default when you are unsure.

<a name="opening-and-staying-open"></a>

### Opening, and staying open

```swift
func open()      // never gives up; retries every second until the device appears
func close()     // stops reading and stops reconnecting
var isOpen: Bool
```

`open()` returns immediately and then keeps trying. A device that is missing, busy, or unplugged later is simply waited for. The port reconnects on its own the moment the device comes back. A cable bump or a firmware re-flash in the middle of a performance therefore recovers without a restart. `isOpen` tells you where things stand, so a sketch can draw a waiting state.

The port holds the device exclusively, because two readers on one port would each get half the bytes. Uploading new firmware therefore needs the port free, so call `close()` first or quit the sketch. If you only `close()` for the upload, the reconnection loop reopens the port for you afterwards.

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

Bytes arrive on a background queue while the sketch reads on the main thread. Locks guard everything the two share, so these reads are safe to call from `draw()`.

**The latest value** suits a continuous sensor. Firmware that prints one number per line, such as `Serial.println(analogRead(A0))` and similar calls, reads directly:

```swift
let level = serial.number(default: 0) / 1023
```

**The event queue** suits discrete things. `lines()` returns every complete line received since the last call, in arrival order, and then clears the queue. Call it once per frame:

```swift
for line in serial.lines() where line == "pressed" { spawnRipple() }
```

Ollin accepts every line-ending convention a device might use, so LF, CRLF, and a bare CR all end a line. A line split across two reads still comes out whole. For a device that uses a binary framing instead, `bytes()` drains the raw stream. That stream is independent of `lines()`, so draining one leaves the other alone.

<a name="binding-to-a-param"></a>

### Binding to a `@Param`

```swift
func bind(to param: Param<Double>, from input: ClosedRange<Double> = 0...1023)
func unbind()
```

The third way to read is to wire the stream straight onto a [`@Param`](../Helpers/Parameters.md). A sensor then drives the same parameter that a slider in the live inspector drives. Every line that parses as a number is mapped from `input` into the parameter's own range, then assigned to it. The default input range is the classic 10-bit analog read:

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    serial.open()
    serial.bind(to: $radius)                // 0...1023 → 20...400
    serial.bind(to: $level, from: 0...4095) // a 12-bit sensor
}
```

A bound parameter updates on its own as lines arrive. You can still change the same parameter from the inspector slider and from code, and whichever moved most recently wins.

<a name="writing"></a>

### Writing

```swift
func write(_ text: String)       // UTF-8, exactly as given
func writeLine(_ text: String)   // text plus a newline
func write(_ bytes: [UInt8])     // raw bytes
```

Writes go out on the port's background queue, so a frame never waits on the wire. `writeLine` uses the same framing that `lines()` reads on the way in, and that is the shape most firmware parses:

```swift
serial.writeLine("led:on")
serial.writeLine("servo:\(Int(angle))")
```

Bytes you send while the device is away are dropped rather than queued. A board that has just reconnected needs current values, not a replay of everything it missed.

<a name="testing-without-hardware"></a>

### Testing without hardware

You can run the whole loop with nothing but the Mac in front of you. The **SerialLoopback** example (`Examples/Integration/SerialLoopback`) runs both ends of the wire itself. A small fake device, one side of a pty pair, prints a sensor value thirty times a second. A `SerialPort` opens the other side exactly the way it would open a real board. The sketch draws its trace from what arrives over that port. Clicking writes a line back that flips the wave, so you can see the write path too.

With a real board, use the **SerialMonitor** example (`Examples/Integration/SerialMonitor`). It lists every serial device and keeps that list up to date, opens the first USB device it finds, and scrolls whatever the board prints. A numeric line also fills a value bar. Plug the board in and watch the lines, and you will know exactly what your sketch will read.

---

See the **SerialLoopback** example for the full loop with no hardware, and the **SerialMonitor** example to find out what a real board sends.
