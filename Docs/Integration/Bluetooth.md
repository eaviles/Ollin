#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Bluetooth`</sup>

---

## Bluetooth

Bluetooth gives you the physical-computing loop with no wire. A heart rate strap, a weather sensor, a button, or a board of your own can all send values to a sketch. Anything that speaks Bluetooth Low Energy announces itself to the Mac, and a sketch reads its values in `draw()`. The support lives in a separate library, so the drawing core stays free of CoreBluetooth and of the permission it asks for. Add `import OllinBluetooth` beside `import Ollin` to use it.

Everything is Apple-native (CoreBluetooth), and nothing is vendored. The values the standard defines are read from their own published byte layouts. Reading works the same way as [OSC](./OSC.md), [MIDI](./MIDI.md), and [serial](./Serial.md). You read a value in one of three ways. You take the latest value each frame, every arrival since the last frame, or a value bound onto a `@Param`.

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
- [Finding a device](#finding-a-device) - scanning the room, and the ways to name a device
- [Connecting, and staying connected](#connecting) - waiting is the default
- [Reading](#reading) - the latest value, or every arrival since the last frame
- [Values and their formats](#values) - the bytes mean nothing until a characteristic says what they are
- [The catalog](#catalog) - the standard services and values, already named
- [Binding to a `@Param`](#binding) - a sensor drives a parameter
- [Asking and writing](#asking-and-writing) - reading on demand, polling, and writing back
- [Testing without gear](#testing-without-gear) - what runs with no gear of your own

<a name="permission"></a>

### Permission, and the first run

macOS asks the person once, per app, before a program may use Bluetooth. Until that question is answered, the radio reports **nothing at all**: not off, not refused, just no answer. So a first run reads nothing until the person answers, and the sketch has to say so instead of appearing to hang.

Every object in the library reports that state, and gives you one sentence to draw:

```swift
device.isAvailable            // false while anything is wrong with the radio
device.unavailableReason      // a sentence to draw, or nil when nothing is wrong
device.radioState             // .waiting / .unsupported / .unauthorized / .off / .on
```

Draw the reason. It names each of the four things that can go wrong, including the one that is hard to guess:

> Bluetooth has not answered in 12 seconds. macOS asks once, per app, before a program may use Bluetooth, and it cannot ask while the screen is locked. Unlock the screen and answer the question, or allow Bluetooth for the app running the sketch in System Settings.

Practical notes:

- **The question is asked of the app that started the sketch.** Under `swift run` that is the terminal, as it is for the microphone. Answer it once, and every sketch run the same way inherits the answer.
- **A locked screen cannot show the question.** So a sketch started on a locked Mac waits for as long as it is left there. This is the state most often mistaken for a broken sketch.
- **A packaged app says why it is asking.** `ollin new --kind mac-app --with bluetooth` writes the `NSBluetoothAlwaysUsageDescription` line into the app's `Info.plist`. A bundled app without that line is stopped by the system, and the person is never asked.

An export never asks. A headless run reports the radio as absent, because a device read live has nothing to add to a file being written.

<a name="finding-a-device"></a>

### Finding a device

`BluetoothScan` lists everything in range, strongest signal first, and you read the list every frame.

```swift
let scan = BluetoothScan()              // or BluetoothScan(service: .heartRate)
scan.start()

scan.peripherals        // [BluetoothPeripheral], strongest first
scan.forgetAfter    // seconds of silence before a device drops off the list (10)
scan.isScanning
```

A `BluetoothPeripheral` carries `id`, `name`, `signal` (in dBm, where closer to zero means nearer), the `services` it advertises, `isConnectable`, and `lastSeen`. The `id` is this Mac's own name for the device. It is the same on every run on this Mac and different on another Mac, so store it once you have found the right device.

You then name a device in one of three ways, or pass in one that a scan already found:

```swift
BluetoothDevice(named: "strap")        // any device whose advertised name contains this
BluetoothDevice(service: .heartRate)   // the first device offering a service, whatever it is called
BluetoothDevice(id: savedIdentifier)   // one exact device
BluetoothDevice(peripheral)            // one a scan already found
```

Prefer the service form for standard gear. It filters at the radio, which is cheaper, and it finds a device that advertises no useful name at all. Once a person has chosen a device, prefer the identifier form, so the sketch does not connect to a neighbor's device.

<a name="connecting"></a>

### Connecting, and staying connected

```swift
device.connect()      // starts looking, and keeps looking
device.disconnect()   // lets go and stops looking

device.isConnected    // draw a waiting state from this
device.name           // the connected device's own name
device.signal         // how strong the last advertisement was
```

`connect()` never fails and never gives up. If a device is out of range, switched off, or carried out of the room, the sketch waits for it. When the device comes back, it is picked up again with no call from you. If a connection fails halfway, the library looks for the device again in the same way. Call `connect()` once in `setup()`.

Once a device is connected, the library asks it about everything it offers. The library then subscribes to every value that announces itself, and reads every value the device holds one time. So the first frame that asks for a value usually has one.

<a name="reading"></a>

### Reading

There are three ways to read, and every other live input in Ollin uses the same three.

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

The latest value is a cache, not a queue, so reading it twice in a frame gives the same answer twice. `readings()` is a queue, so it hands each arrival over once. Use the cache for a value that moves (a rate, a temperature), and use `readings()` when every arrival matters.

The list of arrivals waiting for `readings()` has a cap, and the oldest arrivals are dropped first. So a sketch that never calls `readings()` does not grow a buffer forever.

<a name="values"></a>

### Values and their formats

Bluetooth sends a value as bytes and says nothing about what they mean. The meaning is part of the characteristic, so a characteristic carries its own format:

```swift
BluetoothCharacteristic("2A19", as: .uint8, name: "Battery")
BluetoothCharacteristic("6E400003-B5A3-F393-E0A9-E50E24DCCA9E", as: .text)
BluetoothCharacteristic(myUUID, as: .signed(bytes: 2, scale: 0.01))
```

The formats are `.raw`, `.uint8` / `.uint16` / `.uint32`, `.int8` / `.int16` / `.int32`, the general `.unsigned(bytes:scale:)` and `.signed(bytes:scale:)`, `.float32`, `.text`, and `.heartRate`. Numbers arrive smallest byte first, because that is the order Bluetooth always uses.

`.heartRate` is a format of its own, because a heart rate value says how wide it is. The first byte is a set of flags. The lowest bit of that byte decides whether the rate that follows is one byte or two, and more fields may follow the rate. If you read two bytes where the flags said one, a resting 114 becomes 626.

Two characteristics are **the same value** when they have the same identifier, whatever name a sketch gave one of them. So you can read the same stored value in a different format at the point of reading:

```swift
device.number(.heartRateMeasurement.read(as: .uint8))   // the flags byte, not the rate
```

Identifiers accept either spelling. The standard's short numbers (`"180D"`) and a device's own long ones (`"6E400001-B5A3-F393-E0A9-E50E24DCCA9E"`) compare equal to what they mean. Dashes, `0x`, and letter case are all optional. Text that is not an identifier is kept as it is and matches nothing. So a mistyped UUID gives you a device that never answers, not a wrong value.

<a name="catalog"></a>

### The catalog

The standard's own services and values already have names, and each value carries its own format.

| Service | Values |
| --- | --- |
| `.heartRate` | `.heartRateMeasurement`, `.bodySensorLocation` |
| `.battery` | `.batteryLevel` |
| `.environmentalSensing` | `.temperature`, `.humidity`, `.pressure` |
| `.deviceInformation` | `.manufacturerName`, `.modelNumber`, `.firmwareRevision` |
| `.uart` | `.uartIn`, `.uartOut` |

`.uart` is the de facto serial line over Bluetooth, and the one most maker boards speak. Read `.uartIn` as text, and write to `.uartOut`. With it, a wireless board reads almost exactly like [a wired one](./Serial.md).

Anything not in the catalog arrives as raw bytes under its own number, and `device.characteristics` lists what the connected device offers.

<a name="binding"></a>

### Binding to a `@Param`

```swift
@Param(20...400) var radius = 120.0

override func setup() {
    strap.connect()
    strap.bind(.heartRateMeasurement, to: $radius, from: 50...180)
}
```

Each reading is mapped from the given range into the parameter's own range. A reading past either end stops at that end, so it stays inside the range. A value with no number in it does not change the parameter. `unbind(_:)` removes the binding.

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

`poll` is for a value a device holds but never announces, which is what a battery level usually is. By default, every value that announces itself is subscribed to, so `subscribe` is only worth calling for a device that sends a lot.

Writes with nothing connected are dropped, not queued, for the same reason as on the serial port. A device that just came back wants current values, not a replay.

<a name="testing-without-gear"></a>

### Testing without gear

The **BluetoothRoom** example (`Examples/Integration/BluetoothRoom`) needs no gear of your own. A room is already full of devices announcing themselves several times a second, so the sketch draws them. The Mac sits at the center, and each device sits at the distance its signal suggests. A device moves when somebody walks past with a phone in a pocket. The example is also the way to find out what a device calls itself.

The **BluetoothSensor** example (`Examples/Integration/BluetoothSensor`) is the first step with a device you do own. Type part of its name into the `deviceName` parameter, and every value it offers appears as it arrives. If the device reports a heart rate, that rate drives the size of the disc the example draws.

Inside the library, the radio sits behind a small seam. That seam is how the whole reading path is tested with no radio switched on and no second device in the room. `OllinBluetoothTests` drives a stand-in radio through the shipped matching, connecting, subscribing, caching, draining, binding, polling, and reconnecting. Those tests do **not** cover CoreBluetooth itself, or a Mac's own radio hearing another device. Only real gear can check those two.

---

See the **BluetoothRoom** example to draw the room with no gear at all, and the **BluetoothSensor** example to read a device you own.
