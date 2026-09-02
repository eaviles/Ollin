#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Bluetooth`</sup>

---

## Bluetooth

The physical-computing loop with no wire. A heart rate strap, a weather sensor, a button, a board of your own. Anything that speaks Bluetooth Low Energy announces itself to the Mac, and a sketch reads its values in `draw()`. It lives in a separate library so the drawing core stays free of CoreBluetooth, and free of the permission it asks for. Add `import OllinBluetooth` alongside `import Ollin` to reach it.

Everything is Apple-native (CoreBluetooth) and nothing is vendored. The values the standard defines are read from their own published byte layouts. Reading is the same shape as [OSC](./OSC.md), [MIDI](./MIDI.md), and [serial](./Serial.md): the latest value each frame, every arrival since the last frame, or a value bound onto a `@Param`.

```swift
import Ollin
import OllinBluetooth

final class Pulse: Sketch {
    let strap = BluetoothDevice(service: .heartRate)

    override func setup() { strap.connect() }

    override func draw() {
        background(.white)
        let beats = strap.number(.heartRateMeasurement, default: 60)
        fill(.black)
        drawCircle(width / 2, height / 2, beats * 2)
    }
}
```

### Contents

- [Permission, and the first run](#permission) - the one thing to know before anything works
- [Finding a device](#finding-a-device) - the room, and the three ways to name one
- [Connecting, and staying connected](#connecting) - waiting is the default
- [Reading](#reading) - the latest value, or every arrival since last frame
- [Values and their formats](#values) - bytes mean nothing until a characteristic says so
- [The catalog](#catalog) - the standard services and values, already named
- [Binding to a `@Param`](#binding) - a sensor drives a parameter
- [Asking and writing](#asking-and-writing) - reading on demand, polling, writing back
- [Testing without gear](#testing-without-gear) - what runs with nothing of your own

<a name="permission"></a>

### Permission, and the first run

macOS asks the person once, per app, before a program may use Bluetooth. Until that question is answered the radio reports **nothing at all**: not off, not refused, simply no answer. So a first run stops before it starts, and the sketch has to say so rather than sit there.

Every object here reports that in one sentence:

```swift
device.isAvailable            // false while anything is wrong with the radio
device.unavailableReason      // a sentence to draw, or nil when nothing is wrong
device.radioState             // .waiting / .unsupported / .unauthorized / .off / .on
```

Draw the reason. It names the four things that go wrong, including the one that is hard to guess:

> Bluetooth has not answered in 12 seconds. macOS asks once, per app, before a program may use Bluetooth, and it cannot ask while the screen is locked. Unlock the screen and answer the question, or allow Bluetooth for the app running the sketch in System Settings.

Two practical notes:

- **The question is asked of the app that started the sketch**, which under `swift run` is the terminal, exactly as the microphone works. Answer it once and every sketch run the same way inherits it.
- **A locked screen cannot show the question**, so a sketch started on a locked Mac waits for as long as it is left there. This is the state most often mistaken for a broken sketch.
- **A packaged app says why it is asking.** `ollin new --kind mac-app --with bluetooth` writes the `NSBluetoothAlwaysUsageDescription` line into the app's `Info.plist`; a bundled app without it is stopped by the system instead of asked about.

An export never asks. A headless run reports the radio as absent, since a device read as it moves has nothing to say to a file being written.

<a name="finding-a-device"></a>

### Finding a device

`BluetoothScan` is the room: everything in range, strongest signal first, read every frame.

```swift
let scan = BluetoothScan()              // or BluetoothScan(service: .heartRate)
scan.start()

scan.peripherals        // [BluetoothPeripheral], strongest first
scan.forgetAfter    // seconds of silence before a device drops off the list (10)
scan.isScanning
```

A `BluetoothPeripheral` carries `id`, `name`, `signal` (dBm, closer to zero is nearer), the `services` it advertises, `isConnectable`, and `lastSeen`. The `id` is this Mac's own name for the device. It is the same on every run here and different on another Mac, so it is worth storing once you have found the right device.

A device is then named in one of three ways:

```swift
BluetoothDevice(named: "strap")        // any device whose advertised name contains this
BluetoothDevice(service: .heartRate)   // the first device offering a service, whatever it is called
BluetoothDevice(id: savedIdentifier)   // one exact device
BluetoothDevice(peripheral)            // one a scan already found
```

Prefer the service form for standard gear. It filters at the radio, which is cheaper, and it finds a device that advertises no useful name at all. Prefer the identifier form once a person has chosen a device, so the sketch does not connect to a neighbor's.

<a name="connecting"></a>

### Connecting, and staying connected

```swift
device.connect()      // starts looking, and keeps looking
device.disconnect()   // lets go and stops looking

device.isConnected    // draw a waiting state from this
device.name           // the connected device's own name
device.signal         // how strong the last advertisement was
```

`connect()` never fails and never gives up. A device out of range, switched off, or carried out of the room is simply waited for. It is picked up again by itself when it comes back. A connection that fails halfway is looked for again the same way. Call it once in `setup()`.

Once a device is connected it is asked about everything it offers. It is told about every value that announces itself, and read once for every value it holds. So the first frame that asks for a value usually has one.

<a name="reading"></a>

### Reading

Three ways, the same three every other live input here has.

```swift
// 1. The latest value, read fresh each frame.
device.number(.heartRateMeasurement)            // Double?
device.number(.heartRateMeasurement, default: 60)
device.int(.batteryLevel)                       // Int?
device.text(.manufacturerName)                  // String?
device.bool(myButton)                           // Bool?
device.bytes(myOwnValue)                        // [UInt8]?
device.data(myOwnValue)                         // Data?
device.latest(.temperature)                     // BluetoothReading?

// 2. Every arrival since the last frame, oldest first, then cleared.
for reading in device.readings() {
    print(reading.characteristic.name, reading.number ?? 0, reading.time)
}
```

The cache is not a queue: reading it twice in a frame gives the same answer twice. The drain is a queue: it hands each arrival over once. Use the cache for a value that moves (a rate, a temperature), and the drain when every single arrival matters.

An undrained list is capped, and the oldest go first, so a sketch that never calls `readings()` does not grow a buffer forever.

<a name="values"></a>

### Values and their formats

Bluetooth sends a value as bytes and says nothing about what they mean. What the bytes mean is part of the characteristic, so a characteristic carries its own format:

```swift
BluetoothCharacteristic("2A19", as: .uint8, name: "Battery")
BluetoothCharacteristic("6E400003-B5A3-F393-E0A9-E50E24DCCA9E", as: .text)
BluetoothCharacteristic(myUUID, as: .signed(bytes: 2, scale: 0.01))
```

The formats are `.raw`, `.uint8` / `.uint16` / `.uint32`, `.int8` / `.int16` / `.int32`, the general `.unsigned(bytes:scale:)` and `.signed(bytes:scale:)`, `.float32`, `.text`, and `.heartRate`. Numbers arrive smallest byte first, which is what Bluetooth always uses.

`.heartRate` is a format of its own, because a heart rate says how wide it is. The first byte is a set of flags. Its lowest bit decides whether the rate that follows is one byte or two, and more fields may follow it. Reading two bytes where the flags said one turns a resting 114 into 626.

Two characteristics are **the same value** when they have the same identifier, whatever a sketch chose to call one of them. So the same stored value can be read a different way at the point of reading:

```swift
device.number(.heartRateMeasurement.read(as: .uint8))   // the flags byte, not the rate
```

Identifiers accept either spelling. The standard's short numbers (`"180D"`) and a device's own long ones (`"6E400001-B5A3-F393-E0A9-E50E24DCCA9E"`) compare equal to what they mean. Dashes, `0x`, and letter case are all optional. Text that is not an identifier keeps itself and matches nothing, so a mistyped UUID is a device that never answers rather than the wrong value arriving.

<a name="catalog"></a>

### The catalog

The standard's own services and values are named already, each knowing how to read itself.

| Service | Values |
| --- | --- |
| `.heartRate` | `.heartRateMeasurement`, `.bodySensorLocation` |
| `.battery` | `.batteryLevel` |
| `.environmentalSensing` | `.temperature`, `.humidity`, `.pressure` |
| `.deviceInformation` | `.manufacturerName`, `.modelNumber`, `.firmwareRevision` |
| `.uart` | `.uartIn`, `.uartOut` |

`.uart` is the de facto serial line over Bluetooth, the one most maker boards speak: read `.uartIn` as text, write `.uartOut`. It makes a wireless board read almost exactly like [a wired one](./Serial.md).

Anything not in the catalog arrives as raw bytes under its own number, and `device.characteristics` lists what the connected device actually offers.

<a name="binding"></a>

### Binding to a `@Param`

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    strap.connect()
    strap.bind(.heartRateMeasurement, to: $radius, from: 50...180)
}
```

Each reading is mapped from the range given into the parameter's own range. A reading past either end stops at the parameter's end rather than running out of it. A value with no number in it adjusts no parameter. `unbind(_:)` removes it.

<a name="asking-and-writing"></a>

### Asking and writing

```swift
device.read(.batteryLevel)                 // ask once, now
device.poll(.batteryLevel, every: 10)      // ask again every ten seconds
device.subscribe(to: .heartRateMeasurement)   // be told about this value only
device.unsubscribe(from: .batteryLevel)

device.write("led on\n", to: .uartOut)     // text, as UTF-8
device.write([0x01, 0x02], to: .uartOut)   // bytes
```

`poll` is for a value a device holds but never announces, which is what a battery level usually is. `subscribe` is only worth naming for a device that talks a lot: with nothing named, every value that announces itself is subscribed to.

Writes with nothing connected are dropped rather than queued, on the serial port's reasoning. A device that just came back wants current values, not a replay.

<a name="testing-without-gear"></a>

### Testing without gear

The **BluetoothRoom** example (`Examples/Integration/BluetoothRoom`) needs nothing of your own. A room is already full of devices announcing themselves several times a second, so the sketch draws them. The Mac sits at the center and each device sits at the distance its signal suggests, moving as somebody walks past with a phone in a pocket. It is also the way to find out what a device calls itself.

The **BluetoothSensor** example (`Examples/Integration/BluetoothSensor`) is the introduction ritual for a device you do own. Type part of its name into the `deviceName` parameter and every value it offers appears as it arrives, with a heart rate driving the disc.

Inside the library, the radio sits behind a small seam. That is how the whole reading path is proved with no radio switched on and no second device in the room. `OllinBluetoothTests` drives a stand-in radio through the shipped matching, connecting, subscribing, caching, draining, binding, polling, and reconnecting. Note what that does **not** cover, and what only real gear can: CoreBluetooth itself, and a Mac's own radio hearing another device.

---

See the **BluetoothRoom** example for the room with no gear at all, and **BluetoothSensor** to read a device you own.
