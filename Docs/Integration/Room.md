#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Room`</sup>

---

## Room

Several machines drawing one piece. Two Macs on the same network find each other by the room's name alone: no server to run, no address to type, nothing to configure. Values, `@Param` parameters, and one agreed clock travel between them. That is what turns a row of screens into one piece rather than several copies of it. It lives in a separate library, so the drawing core stays free of MultipeerConnectivity. Add `import OllinRoom` alongside `import Ollin` to reach it.

```swift
import Ollin
import OllinRoom

final class Wall: Sketch {
    let room = Room(named: "wall")

    override func setup() {
        extend(room)
    }

    override func draw() {
        background(.black)
        // The room's clock, so every machine turns together.
        let angle = room.time
        drawCircle(540 + cos(angle) * 300, 540 + sin(angle) * 300, 60)
    }
}
```

Open that sketch on a second Mac and the two are in the same room. With one machine it still runs, as one seat of one.

### Contents

- [Joining a room](#joining-a-room) - the name, the seat, the passcode
- [Sending and reading values](#sending-and-reading-values) - the three ways to read, as with OSC and MIDI
- [Sharing parameters](#sharing-parameters) - one person adjusts a parameter for the whole room
- [The clock everyone agrees on](#the-clock) - why `room.time` and not `time`
- [Splitting one piece across screens](#splitting-a-piece) - seats
- [The network story](#the-network-story) - who can join, and what the system asks
- [Trying it](#trying-it) - the two examples

<a name="joining-a-room"></a>

### Joining a room

```swift
let room = Room(named: "wall")                       // the name is the whole address
let room = Room(named: "wall", seat: 1)              // this machine draws slice 1
let room = Room(named: "wall", as: "left projector") // a name people can read
let room = Room(named: "gallery", passcode: "cempoalli")
```

`extend(room)` opens it, which is all a sketch needs. A room can also be opened by hand with `start()` and closed with `stop()`. That is what a sketch does when it trades values but shares no parameters. A room closed by `stop()` leaves the others at once, and so does one dropped when a live reload builds a fresh sketch.

Who is here:

```swift
room.name              // what this machine goes by
room.peers             // the others, by name
room.everyone          // all of them, this machine included
room.isAlone           // nobody else yet
room.sketchName(of: peer)  // what that machine is running
room.problem           // what went wrong, when something did
```

Arrivals and departures drain like events, so a piece can answer them:

```swift
for machine in room.arrivals()   { print("\(machine) joined") }
for machine in room.departures() { print("\(machine) left") }
```

<a name="sending-and-reading-values"></a>

### Sending and reading values

Anything a sketch wants the others to know goes out under a key:

```swift
room.send("beat", 1.0)                 // a number
room.send("count", 7)                  // a whole number
room.send("word", "hola")              // text
room.send("on", true)                  // a flag
room.send("at", Vector2(400, 200))     // a point
room.send("ink", Color.red)            // a color
room.send("raw", data)                 // bytes, for anything else
```

Reading follows the same three ways [OSC](./OSC.md) and [MIDI](./MIDI.md) do.

**The latest value**, for anything continuous:

```swift
let beat = room.number("beat", default: 0)
let pointer = room.point("at", default: Vector2(0, 0))
```

**Everything that arrived**, for events where each one counts:

```swift
for message in room.messages() {
    if message.key == "note" { play(message.int ?? 0) }
}
```

**Bound to a parameter**, so another machine drives a `@Param` the way an external fader does:

```swift
room.bind("dial", to: $radius)                 // 0...1 into the parameter's own range
room.bind("dial", to: $radius, from: 0...127)  // or another range
```

A value sent every frame can travel the quick way, where the next one matters more than the one that went missing:

```swift
room.send("pointer", mouse, reliable: false)
```

<a name="sharing-parameters"></a>

### Sharing parameters

A parameter that travels is the difference between tuning one machine and tuning the room:

```swift
override func setup() {
    extend(room)
    room.share("speed", "hue")   // these parameters travel
    room.shareAll()              // or every @Param on the sketch
}
```

Every machine that shares a parameter both sends and follows, so it can be set wherever the person is standing. Two people adjusting one parameter at the same moment is settled by the room's clock: the later change wins everywhere. A parameter nobody shares stays home.

Values from another machine land on the main thread between frames, before `draw()`, which is exactly where the [inspector's](../Helpers/Parameters.md) own edits land. They ride the same persisted payloads, so a parameter accepts and clamps what the inspector would.

A machine that joins later is sent the shared parameters as they stand, so it comes up showing the room's values rather than its own defaults.

Sharing needs `extend(room)`, because the parameters are read and applied on the frame boundary.

<a name="the-clock"></a>

### The clock everyone agrees on

Each machine starts its own clock when its sketch starts. Two machines running one piece are then out of step by the difference between their start times, and that difference is the thing an audience sees. `room.time` is the room's own clock, and it is what motion should read:

```swift
let angle = room.time * speed     // in step everywhere
let angle = time * speed          // this machine's own clock, drifting from the rest
```

One machine owns the clock, and the others ask it what time it is a few times a second. The owner is the machine whose name sorts first, so every machine picks the same one with no election. The estimate allows for the time the answer spent on the wire. Of several answers the quickest is believed, because a slow answer is a delayed one.

```swift
room.ownsClock     // whether this machine keeps the clock
room.clockError    // how far room time can be off, in seconds, nil before the first answer
```

Measured between two sketches on one Mac: the first answer lands within a quarter second of joining. The two clocks then agree to within a tenth of a millisecond, which is the finest the measurement could see. Before that first answer, `room.time` is this machine's own clock and `clockError` is `nil`. A piece that must not start early can wait for it.

When the machine that owns the clock leaves, the room picks the next one. It keeps the time it already had, rather than starting again from the new owner's own start. Measured across a real handover: a step of a tenth of a millisecond.

<a name="splitting-a-piece"></a>

### Splitting one piece across screens

A wall of screens is one piece drawn several times, each machine sliding its own part into view:

```swift
override func draw() {
    let wall = width * Double(room.seatCount)
    withState {
        translate(-Double(room.seat) * width, 0)
        drawWholePiece(across: wall)
    }
}
```

`room.seat` counts from zero and `room.seatCount` says how many slices there are. Ask for a fixed seat when the machines stand in a known order (`Room(named: "wall", seat: 1)`). A machine that restarts then comes back to the same slice. Ask for none and the room hands seats out in name order, which is enough when the slices are interchangeable.

<a name="the-network-story"></a>

### The network story

The room name is the only thing needed to join. Anyone on the same network who knows it can. Pass a `passcode` where that matters: it never travels in the clear, only a hash of it does, and the connection itself is encrypted. This is a studio and venue tool, like the [remote surface](./Remote.md). It is fine on your own Wi-Fi or a show network, and not something to leave open on a hostile one.

The machines reach each other over whatever the system has: the same Wi-Fi, a cable, or the direct radio link it sets up when there is no network at all. The first time a sketch opens a room, the system asks for permission to use the local network. A sketch run from a terminal inherits the terminal's answer, the same way [screen capture](./ScreenCapture.md) does.

The name a machine goes by is its computer's name plus a few characters, so two sketches on one Mac are two members rather than one. Pass `as:` for something an operator can read on a screen.

`Room` sits over a seam, `RoomTransport`, which is only asked to carry bytes to a named peer. A sketch or a test that wants two rooms inside one process supplies its own. That is what the loopback example does.

<a name="trying-it"></a>

### Trying it

The **RoomCanvas** example (`Examples/Integration/RoomCanvas`) is the real thing. Beads travel along a wall as wide as the room has seats, every parameter travels, and a readout shows the seat, the company, and how well the clocks agree. Open it on two Macs on the same network.

```sh
swift run --package-path Examples Example-Integration-RoomCanvas
```

The **RoomLoopback** example (`Examples/Integration/RoomLoopback`) needs no second machine. Two rooms inside one sketch trade values over a transport that never leaves the process. The left panel sends, and the right one draws only what arrived. Hold the space bar to cut the wire.

```sh
swift run --package-path Examples Example-Integration-RoomLoopback
```

---

See [`@Param`](../Helpers/Parameters.md) for what a shared parameter can declare, and [`Remote`](./Remote.md) for the other way a second device reaches a sketch: one machine drawing, a phone tuning it.
