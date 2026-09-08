#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `TUIO`</sup>

---

## TUIO

TUIO is the protocol tangible surfaces speak. A table with a camera under it reads printed markers. A touch wall reports fingers. A phone app sends the contacts on its screen. All of them send TUIO, and a sketch reads it as touches, tagged pieces, and shapes. Trackers that speak it include reacTIVision, Community Core Vision, the TUIO Simulator, and the TUIO apps for phones and tablets.

TUIO rides on [OSC](./OSC.md), so it lives in the same library. Add `import OllinOSC` beside `import Ollin` to reach it, and nothing else changes.

A surface sends three messages per frame, all at one address:

```text
  /tuio/2Dcur set 12 0.5 0.25 0.0 0.1 0.02    one item, this is its state now
  /tuio/2Dcur alive 12 13                     everything on the surface, by id
  /tuio/2Dcur fseq 4218                       the frame those two belong to
```

Only what moved gets a `set`, so the alive list is what says a touch has left. Ollin reads that frame for you and hands back three lists.

```swift
import Ollin
import OllinOSC

final class Table: Sketch {
    let surface = TUIOReceiver()

    override func setup() { try? surface.start() }

    override func draw() {
        background(.white)
        for touch in surface.cursors {
            drawCircle(center: touch.position(in: bounds), radius: 40)
        }
    }
}
```

### Contents

- [The three things a surface reports](#what-it-reports) - touches, tagged pieces, shapes
- [TUIOReceiver](#tuioreceiver) - listening, and what it hands back
- [Onto the canvas](#onto-the-canvas) - the surface measured like the canvas
- [Following one touch](#following) - session ids, and what to do when one leaves
- [Sharing a port with your own OSC](#sharing) - one socket, two readers
- [What Ollin reads and what it skips](#what-is-read) - the profiles, sources, and frame numbers
- [Testing without a table](#testing) - the example runs both ends

<a name="what-it-reports"></a>

### The three things a surface reports

A tracker reports up to three kinds of thing, and Ollin gives each its own list.

| Read | Type | What it is |
| --- | --- | --- |
| `surface.cursors` | `TUIOCursor` | A touch: a fingertip, a contact, a pointer |
| `surface.objects` | `TUIOObject` | A tagged piece: a printed marker the tracker can name and measure |
| `surface.blobs` | `TUIOBlob` | An untagged shape: a hand, a sleeve, a cup |

Every one of them carries an `id`, a `point`, and a `velocity`. A piece adds the `symbol` printed on its marker and the `angle` it is turned to. A shape adds its `size` and the `area` it covers. Turning and speed are there too, as `angularVelocity`, `acceleration`, and `angularAcceleration`, in case a sketch wants to throw something rather than drag it.

```swift
for piece in surface.objects {
    withState {
        translate(piece.position(in: bounds))
        rotate(piece.angle)                    // radians, clockwise, like rotate(_:)
        drawRect(center: .zero, width: 120, height: 120)
    }
    if piece.symbol == 7 { playTheSeventhSound() }
}
```

<a name="tuioreceiver"></a>

### TUIOReceiver

`TUIOReceiver` opens a socket and keeps the surface up to date behind it.

```swift
let surface = TUIOReceiver()              // port 3333, what trackers use by default
let surface = TUIOReceiver(port: 3334)    // when the tracker was told otherwise
try surface.start()
```

| Member | What it gives you |
| --- | --- |
| `start()` / `stop()` | Opens and closes the socket. `start()` throws if the port is taken |
| `isRunning`, `boundPort` | Whether it is listening, and on what. Pass port `0` to be given a free one |
| `cursors`, `objects`, `blobs` | What is on the surface right now, ordered by session id |
| `framesReceived` | How many frames have arrived, across the three profiles |
| `sourceName` | What the tracker calls itself, once it has said so |
| `receive(_:)` | Hands it a message or a packet you read yourself |

The three lists are what is there right now, not a history. A tracker sends the whole surface many times a second, and an id that stops appearing has left. `framesReceived` is how a sketch says a tracker is connected. An idle table still sends a frame every tick while `cursors` stays empty.

Datagrams arrive on a background thread and the sketch reads on the main one. The surface is held behind a lock, so reading it in `draw()` is safe.

<a name="onto-the-canvas"></a>

### Onto the canvas

A surface measures itself from 0 to 1 across and down, with the origin at the top left. That is the canvas's own direction, so nothing has to be flipped. `position(in:)` puts a report where it belongs:

```swift
let at = touch.position(in: bounds)             // the whole canvas
let at = touch.position(in: table)              // or any rectangle in it
```

Velocities are in surface widths per second, so a touch crossing the whole table in a second reads `1`. Multiply by the canvas size to draw one:

```swift
let ahead = Vector2(touch.velocity.x * width, touch.velocity.y * height) * 0.25
drawLine(at, at + ahead)                        // where it will be in a quarter second
```

A shape also knows its own box, which is the easy way to draw it:

```swift
for shape in surface.blobs {
    let box = shape.bounds(in: bounds)
    drawEllipse(center: box.center, radiusX: box.width / 2, radiusY: box.height / 2)
}
```

<a name="following"></a>

### Following one touch

The `id` is the tracker's session id. It holds from the moment something appears until it leaves. That is what lets a sketch keep a stroke, a color, or a sound with one finger:

```swift
var trails: [Int: [Vector2]] = [:]

override func draw() {
    for touch in surface.cursors {
        trails[touch.id, default: []].append(touch.position(in: bounds))
    }
    // A touch that left is no longer in the list, so its trail can go.
    let here = Set(surface.cursors.map(\.id))
    trails = trails.filter { here.contains($0.key) }
}
```

That last line is also how a sketch notices a touch ending. Compare the ids you saw last frame with the ids you see now: what is missing has lifted, and what is new has landed.

<a name="sharing"></a>

### Sharing a port with your own OSC

A receiver opens its own socket, so a sketch that also reads other OSC on the same port should use one socket for both. Leave the surface unstarted and pour your inbox into it. Anything that is not TUIO is ignored:

```swift
let osc = OSCReceiver(port: 3333)
let surface = TUIOReceiver()      // never started, so it opens nothing

override func draw() {
    for message in osc.messages() { surface.receive(message) }
    let level = osc.number("/level", default: 0)
}
```

<a name="what-is-read"></a>

### What Ollin reads and what it skips

Ollin reads the three 2D profiles of TUIO 1.1: `/tuio/2Dcur`, `/tuio/2Dobj`, and `/tuio/2Dblb`. The 2.5D and 3D profiles and the newer TUIO 2.0 addresses are ignored rather than half read. A message that is not TUIO at all passes through untouched.

Two details of the protocol are worth knowing, because they are what keeps a surface steady:

- **A frame is taken whole.** The `set` messages and the alive list are held aside until the frame number arrives, so a sketch never reads half a frame with one finger moved and another not.
- **A late datagram is dropped.** UDP can deliver out of order, and a frame numbered below the last one would drag a touch back to where it was. A number far below the last one is a tracker that started counting again, and that one is taken. A tracker that sends no frame numbers still works, one frame behind, because the next frame opening is what closes the last one.

A tracker that names itself with a `source` message sets `sourceName`. Ollin does not separate two trackers sending to one port, so point them at different ports if you run more than one.

<a name="testing"></a>

### Testing without a table

The **TUIOSurface** example (`Examples/Integration/TUIOSurface`) runs both ends, so it works with no hardware at all. A stand-in tracker sends real TUIO frames to `127.0.0.1`, and everything the sketch draws comes back off the wire. Turn its `simulate` parameter off and point a real tracker at this Mac on port 3333 to drive it instead.

To try it with a phone, use one of the TUIO apps for iOS and Android. They send finger positions to an address and port you type in. A marker table needs its tracker running and pointed here. Both look the same from the sketch's side.

---

See the **TUIOSurface** example for a table you can watch with nothing plugged in, and the [OSC](./OSC.md) page for the protocol underneath.
