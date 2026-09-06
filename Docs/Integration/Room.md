#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Room`</sup>

---

## Room

A room lets several machines draw one piece together. Two Macs on the same network find each other by the room's name alone. There is no server to run, no address to type, and nothing to configure. Values, `@Param` parameters, and one agreed clock travel between them. That is what makes a row of screens one piece rather than several copies of it. Rooms live in a separate library, so the drawing core stays free of MultipeerConnectivity. Add `import OllinRoom` alongside `import Ollin` to reach it.

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

Open that sketch on a second Mac and the two are in the same room. It still runs on a single machine, which is then the room's only seat.

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

`extend(room)` opens the room, and that is all a sketch needs. You can also open a room by hand with `start()` and close it with `stop()`. A sketch does that when it trades values but shares no parameters. A room closed by `stop()` leaves the others at once. So does a room dropped when a live reload builds a fresh sketch.

Who is here:

```swift
room.name              // what this machine goes by
room.peers             // the others, by name
room.everyone          // all of them, this machine included
room.isAlone           // nobody else yet
room.sketchName(of: peer)  // what that machine is running
room.problem           // what went wrong, when something did
```

Arrivals and departures drain as events, so a piece can respond to them:

```swift
for machine in room.arrivals()   { print("\(machine) joined") }
for machine in room.departures() { print("\(machine) left") }
```

<a name="sending-and-reading-values"></a>

### Sending and reading values

Send anything you want the others to know under a key:

```swift
room.send("beat", 1.0)                 // a number
room.send("count", 7)                  // a whole number
room.send("word", "hola")              // text
room.send("on", true)                  // a flag
room.send("at", Vector2(400, 200))     // a point
room.send("ink", Color.red)            // a color
room.send("raw", data)                 // bytes, for anything else
```

You read those values in the same three ways [OSC](./OSC.md) and [MIDI](./MIDI.md) offer.

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

Send a value the quick way when you send it every frame, because the next value matters more than one that goes missing:

```swift
room.send("pointer", mouse, reliable: false)
```

<a name="sharing-parameters"></a>

### Sharing parameters

A shared parameter lets you tune the whole room instead of one machine:

```swift
override func setup() {
    extend(room)
    room.share("speed", "hue")   // these parameters travel
    room.shareAll()              // or every @Param on the sketch
}
```

Every machine that shares a parameter both sends and follows it, so you can set it from whichever machine you stand at. If two people adjust one parameter at the same moment, the room's clock settles it and the later change wins everywhere. A parameter that nobody shares stays on its own machine.

Values from another machine land on the main thread between frames, before `draw()`. That is where the [inspector's](../Helpers/Parameters.md) own edits land too. They travel as the same persisted payloads, so a parameter accepts and clamps what the inspector would.

A machine that joins later receives the shared parameters as they stand. It then comes up showing the room's values rather than its own defaults.

Sharing needs `extend(room)`, because Ollin reads and applies the parameters on the frame boundary.

<a name="the-clock"></a>

### The clock everyone agrees on

Each machine starts its own clock when its sketch starts. Two machines running one piece are then out of step by the difference between their start times, and an audience sees that difference. `room.time` is the room's own clock, so read it for anything that moves:

```swift
let angle = room.time * speed     // in step everywhere
let angle = time * speed          // this machine's own clock, drifting from the rest
```

One machine owns the clock, and the others ask it for the time a few times a second. The owner is the machine whose name sorts first, so every machine picks the same one with no election. Each estimate allows for the time the answer spent on the wire. Ollin believes the quickest of several answers, because a slow answer is a delayed one.

```swift
room.ownsClock     // whether this machine keeps the clock
room.clockError    // how far room time can be off, in seconds, nil before the first answer
```

Between two sketches on one Mac, the first answer lands within a quarter second of joining. The two clocks then agree to within a tenth of a millisecond, which is the finest the measurement could see. Before that first answer, `room.time` is this machine's own clock and `clockError` is `nil`. A piece that must not start early can wait for the first answer.

When the machine that owns the clock leaves, the room picks the next owner. The room keeps the time it already had, rather than starting again from the new owner's own start. Across a real handover, the measured step was a tenth of a millisecond.

<a name="splitting-a-piece"></a>

### Splitting one piece across screens

A wall of screens draws one piece several times, and each machine slides its own part into view:

```swift
override func draw() {
    let wall = width * Double(room.seatCount)
    withState {
        translate(-Double(room.seat) * width, 0)
        drawWholePiece(across: wall)
    }
}
```

`room.seat` counts from zero, and `room.seatCount` says how many slices there are. Ask for a fixed seat when the machines stand in a known order (`Room(named: "wall", seat: 1)`). A machine that restarts then comes back to the same slice. Ask for no seat and the room hands seats out in name order, which is enough when the slices are interchangeable.

<a name="the-network-story"></a>

### The network story

The room name is the only thing needed to join, so anyone on the same network who knows it can join. Pass a `passcode` where that matters. The passcode never travels in the clear, only a hash of it does, and the connection itself is encrypted. Room is a studio and venue tool, like the [remote surface](./Remote.md). It is fine on your own Wi-Fi or a show network, and not something to leave open on a hostile one.

The machines reach each other over whatever the system has. That can be the same Wi-Fi, a cable, or the direct radio link the system sets up when there is no network at all. The first time a sketch opens a room, the system asks for permission to use the local network. A sketch run from a terminal inherits the terminal's answer, the same way [screen capture](./ScreenCapture.md) does.

The name a machine goes by is its computer's name plus a few characters. Two sketches on one Mac are therefore two members rather than one. Pass `as:` for a name an operator can read on a screen.

`Room` sits over a seam called `RoomTransport`, whose only job is to carry bytes to a named peer. A sketch or a test that wants two rooms inside one process supplies its own transport. The loopback example does exactly that.

<a name="trying-it"></a>

### Trying it

The **RoomCanvas** example (`Examples/Integration/RoomCanvas`) is the full one. Beads travel along a wall as wide as the room has seats, and every parameter travels with them. A readout shows the seat, who else is in the room, and how well the clocks agree. Open it on two Macs on the same network.

```sh
swift run --package-path Examples Example-Integration-RoomCanvas
```

The **RoomLoopback** example (`Examples/Integration/RoomLoopback`) needs no second machine. Two rooms inside one sketch trade values over a transport that never leaves the process. The left panel sends, and the right one draws only what arrived. Hold the space bar to break the connection.

```sh
swift run --package-path Examples Example-Integration-RoomLoopback
```

---

See [`@Param`](../Helpers/Parameters.md) for what a shared parameter can declare. See [`Remote`](./Remote.md) for the other way a second device reaches a sketch, with one machine drawing and a phone tuning it.
