#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `MQTT`</sup>

---

## MQTT

MQTT is the message bus a building speaks. A sensor publishes a reading to a topic, a switch subscribes to that topic, and a broker in the middle carries one to the other. Neither end knows the other exists. A sketch joins the same bus: you subscribe to `home/+/temperature` and the room's readings arrive, you publish to `home/lamp/set` and the lamp turns on. The support lives in a separate library, so the drawing core stays free of networking. Add `import OllinMQTT` beside `import Ollin` to use it.

The protocol is MQTT 3.1.1, written from its published specification over Network.framework, with nothing vendored. Reading works the way it does for [OSC](./OSC.md), [MIDI](./MIDI.md), [serial](./Serial.md), and [Bluetooth](./Bluetooth.md): the latest value on a topic, every message since the last frame, or a value bound onto a `@Param`.

```swift
import Ollin
import OllinMQTT

final class Room: Sketch {
    let bus = MQTTClient(host: "localhost")

    override func setup() {
        try? bus.connect()
        bus.subscribe(to: "home/+/temperature")
    }

    override func draw() {
        let warmth = bus.number("home/kitchen/temperature", default: 20)
        background(Color.blue.mixed(with: .red, (warmth - 15) / 15))
        if mouseIsPressed { bus.publish("home/lamp/set", "ON") }
    }
}
```

### Contents

- [A broker to talk to](#broker) - the one piece that is not the sketch
- [Topics and filters](#topics) - `+` is one level, `#` is the rest, and `$` is the broker's own
- [Reading](#reading) - the latest value, or every message since the last frame
- [Payloads](#payloads) - what the devices actually write, and how to read it
- [Publishing](#publishing) - text, numbers, switches, and bytes
- [How hard to try](#qos) - at most once, at least once, and what each costs
- [Retained values](#retained) - starting up already knowing the room
- [The last will](#will) - how a piece announces its own failure
- [Staying up](#staying-up) - the heartbeat, the reconnection, and what survives a drop
- [Binding to a `@Param`](#binding) - a sensor drives a parameter
- [Testing without a broker](#testing) - what runs with nothing installed

<a name="broker"></a>

### A broker to talk to

Every MQTT network has a broker at the middle of it, and the sketch is a client of it, never the broker itself. On a Mac the usual one is mosquitto:

```sh
brew install mosquitto
mosquitto -v
```

That listens on port 1883, which is the default `MQTTClient` connects to. In a house that already runs Home Assistant, Zigbee2MQTT, Tasmota devices, or an ESPHome board, the broker is already there and its address is what goes in `host:`.

```swift
let bus = MQTTClient(host: "192.168.1.20", port: 1883,
                     username: "sketch", password: "…")
try? bus.connect()
```

`connect()` returns as soon as the attempt starts. `isConnected` turns true when the broker answers, usually within a frame or two on a local network, so a sketch reads it rather than waiting on it. If the broker refuses, `lastError` says why in a sentence worth printing, and nothing keeps trying: a refusal is an answer. `connect()` itself throws only `MQTTError.invalidPort`, for a port outside 0…65535, since everything after that is an answer from the broker rather than a mistake in the call.

Every client on a broker needs a name of its own, and two clients sharing one name push each other off. `clientID:` defaults to a fresh name each run for that reason, which is `MQTTClient.randomClientID()`: a fixed prefix and a random tail, inside the 23 characters every broker must accept. Pass your own only when the broker's rules ask for one.

<a name="topics"></a>

### Topics and filters

A topic is levels separated by `/`, such as `home/kitchen/temperature`. A published topic is always exact. A *subscription* is a filter, and a filter may hold two wildcards:

| Filter | Matches |
|---|---|
| `home/kitchen/temperature` | that topic alone |
| `home/+/temperature` | every room's temperature, one level each |
| `home/#` | everything under `home`, at any depth, and the bare topic `home` itself |
| `#` | the whole bus |

Two rules are easy to miss, and both are worth knowing before you write a filter. `#` covers the parent level, so `sport/#` matches `sport` as well as everything under it. And a filter beginning with a wildcard never reaches a topic beginning with `$`, which is where a broker keeps its own statistics: to read those you ask for `$SYS/#` by name.

`MQTTTopic.matches(_:filter:)` is the same rule as a public function, for a sketch that wants to sort what it has already drained, and `MQTTTopic.isValidFilter(_:)` says whether a filter is well formed before it is sent. `subscriptions` is what the client is subscribed to now.

<a name="reading"></a>

### Reading

A value that is published over and over is read at its latest, the same way a control surface is read:

```swift
let warmth = bus.number("home/kitchen/temperature", default: 20)
let lampIsOn = bus.bool("home/lamp/state", default: false)
let mode = bus.text("home/mode", default: "day")
```

Something that happens once is drained, in arrival order, once a frame:

```swift
for message in bus.messages() where message.topic.hasSuffix("/button") {
    lastPressAt = time            // a doorbell, not a reading
}
```

`messages()` takes everything and clears the queue. `messages(matching:)` takes only what a filter matches and leaves the rest, so two parts of a sketch can each drain their own topics without taking each other's. Draining does not touch the latest-value cache: the two ways of reading are separate, and a topic keeps its latest value after a drain.

`topics` lists every topic that has spoken, and `topics(matching:)` narrows that to a filter, which is how a sketch finds out which rooms are reporting rather than being told in advance.

<a name="payloads"></a>

### Payloads

MQTT says nothing at all about what a payload means. It is bytes. What the devices in the wild actually write is one of three things, and `MQTTMessage` reads all three.

A sensor writes a decimal number, so `number` and `int` parse one, ignoring whitespace a device left around it. A switch writes a word, so `bool` reads `ON`, `true`, `1`, `yes`, `open`, `online`, and `active` as true and their opposites as false, in any casing, and anything else as `nil`. A bridge writes a small JSON object, so `number(named:)`, `int(named:)`, `text(named:)`, and `bool(named:)` read one of its top-level fields:

```swift
for message in bus.messages(matching: "zigbee2mqtt/+") {
    let battery = message.int(named: "battery") ?? 100
    let warmth = message.number(named: "temperature")
}
```

`text` is the payload as UTF-8, and `payload` is the bytes themselves for anything else. A field written as a string of digits still reads as a number, because several bridges publish one that way.

<a name="publishing"></a>

### Publishing

```swift
bus.publish("home/lamp/set", "ON")            // text
bus.publish("home/sketch/level", 0.42)        // a number, as plain decimal
bus.publish("home/lamp/set", true)            // a switch, as ON or OFF
```

Anything else goes out as itself through `publish(_:payload:)`, which takes the `Data` you hand it. A number goes out as plain decimal text with no exponent and no trailing zeros, because that is what a device reading the topic parses. A `Bool` goes out as `ON` or `OFF`, which is what the lamps and relays expect. A topic with a wildcard in it is not a topic, so a publish to one does nothing rather than reaching the broker.

<a name="qos"></a>

### How hard to try

```swift
bus.publish("home/lamp/set", "ON", qos: .atLeastOnce)
bus.subscribe(to: "home/#", qos: .atLeastOnce)
```

`.atMostOnce` sends and forgets. It is the fastest, and the right level for a value that will be published again in a moment: a message published while the connection is down is simply gone, which is what at most once means.

`.atLeastOnce` is held until the far end acknowledges it, and goes out again after a reconnection, marked as a resend. It is what a command deserves, since a lamp that never hears `OFF` stays on. The cost is that a duplicate is possible, which is why `MQTTMessage.isDuplicate` is readable.

The protocol defines a third level, exactly once, which costs a four-packet handshake and stored state on both ends. A sketch reading a room does not need it: a sensor publishing every second is better served by the newest reading than by a guarantee that an old one arrived once. `MQTTQoS` has no case for it, so a broker never opens that handshake with a sketch.

<a name="retained"></a>

### Retained values

A retained publish is kept by the broker as that topic's stored value, and handed to anyone who subscribes afterwards:

```swift
bus.publish("home/sketch/state", "running", retains: true)
```

This is how a sketch starts up already knowing the room rather than waiting for every sensor to speak again. What arrives that way has `isRetained` set, so a sketch can tell a stored value from something that just happened, which matters when an arrival is meant to trigger something. Publishing an empty payload to a retained topic clears it.

<a name="will"></a>

### The last will

A will is a message the broker publishes on a client's behalf when that client vanishes without saying goodbye. It is the way a piece announces its own failure, and it costs nothing to set:

```swift
let bus = MQTTClient(host: "localhost",
                     will: MQTTWill(topic: "gallery/piece/status",
                                    text: "gone", retains: true))
```

Pull the power on the machine and `gallery/piece/status` reads `gone` a moment later, everywhere on the bus. Call `disconnect()` and the broker discards the will instead, because leaving is not the same as being cut off. That difference is the whole point of the feature, and it is what an installation's watchdog watches.

<a name="staying-up"></a>

### Staying up

The connection looks after itself, which is what a piece left running for a month needs.

A heartbeat goes out when the line has been quiet, so a broker does not hang up on a sketch that only ever reads. `keepAlive:` is how long quiet is allowed, in seconds, 30 by default. When the broker stops answering altogether, the client says so and reconnects.

A lost connection is reopened on its own, after a delay that starts at a quarter second and doubles to eight so a broker rebooting is waited out rather than hammered. Every subscription goes back up with it, and so does anything published at `.atLeastOnce` that was never acknowledged. `connectionCount` counts how many times the broker has accepted this client, so a sketch that wants to know the line dropped can watch that number rather than catching `isConnected` between frames. Pass `reconnects: false` to do it yourself.

<a name="binding"></a>

### Binding to a `@Param`

A topic can drive a parameter directly, which is the shortest path from a dial on a wall to a number in a sketch:

```swift
final class Wall: Sketch {
    let bus = MQTTClient(host: "localhost")
    @Param(20...400) var radius = 120.0
    @Param(0...1) var warmth = 0.5

    override func setup() {
        try? bus.connect()
        bus.subscribe(to: "home/#")
        bus.bind("home/dial/level", to: $radius)                        // 0…1 into 20…400
        bus.bind("home/kitchen/temperature", to: $warmth, from: 0...40)
    }
}
```

Each message's number is mapped from the incoming range into the parameter's own and assigned, clamped. `from:` says what the incoming range is; it defaults to `0...1`. `unbind(_:)` stops it, and the messages still arrive, they just drive nothing.

<a name="testing"></a>

### Testing without a broker

The **MQTTRoom** example (`Examples/Integration/MQTTRoom`) draws every topic it hears as a dial, and publishes a wave of its own, so a bare broker with nothing else on it already shows the round trip. Widen its `filter` parameter to `#` to watch a whole house at once.

Inside the library, `OllinMQTTTests` runs a broker of its own in the test process and drives a whole session against it over the loopback: connecting, both service levels, retained values, the will on a cut socket, the heartbeat, reconnection, and the resend that follows one. That broker exists because the interesting cases cannot be asked of a real one. A real broker will not cut a socket on request, sit on an acknowledgement, or refuse a connection with a chosen code. Those tests do **not** cover any particular broker's own behavior, which only a real one can check.

---

See the **MQTTRoom** example for the bus drawn as a wall of dials, and [Installations](../../Guide/32-Installations.md) in the Guide for the piece that reads a building and answers it.
