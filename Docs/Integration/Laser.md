#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Laser`</sup>

---

## Laser

A show laser draws with a single moving dot. Two mirrors on galvanometers steer the beam. A fixed clock decides how often they are told where to point, and at each of those points the beam is lit or dark. There is no picture in it anywhere. What you see is one dot going round a path fast enough that your eye holds the whole loop.

That makes a laser a natural sink for the kind of geometry Ollin already speaks. A `Contour` is nearly a beam path already. What stands between them is the part this library is mostly about. It turns line work into a point list a real machine can scan, and it does that safely. Add `import OllinLaser` alongside `import Ollin` to reach it.

```swift
import Ollin
import OllinLaser

final class Ring: Sketch {
    let laser = LaserProjector(etherDream: "192.168.1.50")

    override func setup() {
        laser.connect()
        laser.arm()                       // nothing goes out before this
    }

    override func draw() {
        background(.black)
        var frame = LaserFrame(canvas: bounds)
        frame.add(Contour(ring, closed: true), color: .green)
        laser.send(frame)
        drawLaserPreview(laser.stream)    // watch it on screen too
    }
}
```

Both wire formats here are written from their published specifications, so nothing is vendored: the [ILDA Image Data Transfer Format](https://www.ilda.com/resources/StandardsDocs/ILDA_IDTF14_rev011.pdf) for files, and the [Ether Dream](https://ether-dream.com/protocol.html) DAC protocol for the network.

### Contents

- [Line work, not pictures](#line-work-not-pictures) - what a laser can and cannot draw
- [The projector's square](#the-projectors-square) - where the canvas ends up
- [Making the points](#making-the-points) - spacing, corners, blanking, order, budget
- [Seeing it without a laser](#seeing-it-without-a-laser) - the preview, and what it shows
- [Safety](#safety) - the arm gate and the rules under it
- [Sending it](#sending-it) - finding a DAC, connecting, streaming
- [Writing a file](#writing-a-file) - ILDA, for the software that already drives your rig
- [What is not here](#what-is-not-here) - the edges of this version

<a name="line-work-not-pictures"></a>

### Line work, not pictures

A `LaserFrame` holds the paths to trace, measured in canvas coordinates: the same numbers every drawing call takes.

```swift
var frame = LaserFrame(canvas: bounds)
frame.add(contour, color: .cyan)                 // a Contour, open or closed
frame.add(shape, color: .white)                  // every contour of a Shape
frame.add(textToShapes("hello", …), color: .red) // several shapes at once
frame.add(points, color: .green, closed: true)   // bare points
frame.addLine(from: a, to: b, color: .white)
```

A laser draws lines. A `Shape` contributes its **outlines**, and its fill rule plays no part. To shade a region, hatch it into line work first with [`Hatching`](../Output/GCode.md). That is the step the pen plotter takes as well.

Color can change along a path. Pass one color per point and the optimizer cross-fades between them as it fills the segments in:

```swift
frame.add(points, colors: points.indices.map { Color(hue: …, saturation: 1, brightness: 1) })
```

<a name="the-projectors-square"></a>

### The projector's square

A projector throws into a square field. Its own coordinates run `-1…1` on both axes from the center, with **y up**. The canvas grows downward, so something has to turn over. `ProjectorSpace` is where that happens, once, at the optimizer's edge.

The canvas rectangle is **fitted** into the field: its longer side reaches the edge, and nothing lands outside. A point drawn off the canvas is clamped rather than dropped. A sketch can never ask the mirrors for a swing they do not have.

```swift
ProjectorSpace.transform(from: canvas)   // canvas point -> field point
ProjectorSpace.inverse(to: canvas)       // field point  -> canvas point
```

Everything the optimizer measures is in field units rather than pixels. Every distance it cares about is a distance the mirrors actually move, so a setting means the same thing whatever size the canvas is.

<a name="making-the-points"></a>

### Making the points

`LaserOptimizer` turns a frame into a `LaserStream`: the list of positions, each lit in a color or blanked.

```swift
var optimizer = LaserOptimizer()
optimizer.pointsPerSecond = 30_000   // what the projector is rated for
optimizer.refreshRate = 30           // how often the frame should repeat
optimizer.spacing = 0.02             // field units between lit points
optimizer.travelSpacing = 0.08       // and between blanked ones
optimizer.cornerAngle = .pi / 6      // a turn sharper than this is held
optimizer.cornerDwell = 3            // for this many points
optimizer.blankingDwell = 4          // held at each end of a dark jump
optimizer.reordersPaths = true       // visit shapes near to near
let stream = optimizer.stream(frame)
```

Five things are happening, and each of them is something a laser needs rather than something a renderer would do:

- **Spacing.** Points are laid evenly along every segment, so the beam moves at a steady speed and the line is evenly bright. A long line drawn with two points is scanned fast and reads faint. Segments are **subdivided**, not resampled end to end. Every point the sketch gave stays exactly where it put it, which is what keeps a corner a corner.
- **Corner dwell.** The mirrors have mass. Asked to turn sharply at speed they overshoot and round the corner off, so a few points are held at the turn to let them arrive.
- **Blanking.** Between two shapes the beam goes off and the mirrors travel. Points are held at **each end** of that jump as well. Otherwise the beam lights while the mirrors still move, and drags a faint tail between the shapes.
- **Order.** Dark travel is time that buys nothing, so paths are visited by a near walk rather than in the order they arrived. The walk may enter a closed path at any of its points, or walk an open one backwards. It changes the route, never the picture. It is the same greedy tour the [G-code](../Output/GCode.md) path uses to shorten pen-up travel.
- **The budget.** `pointsPerSecond / refreshRate` is all the points a frame may hold. `stream.pointBudget` says how many that is, and `stream.isOverBudget` says whether the frame passed it.

**Nothing is dropped when a frame goes over budget.** The frame plays whole and repeats more slowly, which the eye reads as flicker. `stream.refreshRate` tells you what it will actually run at. Silently thinning the line work would make a picture that is wrong instead of one that flickers. The choice is left to you: draw less, or raise `spacing`.

The stream also reports what the frame cost: `points.count`, `litCount`, `blankedCount`, `drawnLength` and `travelLength` in field units, and `duration` in seconds.

<a name="seeing-it-without-a-laser"></a>

### Seeing it without a laser

```swift
drawLaserPreview(laser.stream, showsTravel: true, showsPoints: true)
```

The preview draws the stream the way the beam will trace it: lit runs in their own colors, the dark travel as faint lines, and the beam's own footsteps as dots. It shows things the drawn picture cannot. Where the dots bunch up the line is bright and slow; where they spread it is faint. Every travel line is time spent drawing nothing.

The **LaserPreview** example (`Examples/Integration/LaserPreview`) is that view with the parameters attached, and it runs with no hardware at all.

<a name="safety"></a>

### Safety

A projector is not a screen. The light is collimated, and the mirrors are the only thing spreading it. While they sweep, the power lands along a whole line. While they sit still, it lands on one spot. So the two ways a laser sketch goes wrong are a beam that stops moving, and a beam brighter than the room can take.

**A projector will not emit until it is armed.** That is the one rule kept for you rather than trusted to a sketch:

```swift
laser.arm()        // a line somebody had to write on purpose
laser.disarm()     // dark again, connection kept, rig still live
```

Under it, `LaserSafety` guards every stream on its way out:

```swift
laser.safety.maximumBrightness = 0.5   // a ceiling on every channel
laser.safety.stationaryRadius = 0.004  // how far counts as moving
laser.safety.stationaryLimit = 24      // lit points allowed to stand still
laser.safety.stallTimeout = 0.5        // seconds before a stale frame is blanked
```

The stopped-beam guard blanks a run of lit points that stays inside `stationaryRadius`. That catches a beam effect, a shape far smaller than it looks, and a frame that turned out to be a single point. Its limit sits well above `cornerDwell`, which holds points at a corner on purpose. The stall timeout covers the case a sketch cannot. It stopped, or it crashed, and the projector is still playing the last thing it was given.

The defaults are careful, including a brightness ceiling of half. `LaserSafety.unguarded` turns everything off, for a bench where the beam goes into a meter rather than a room. Nothing in the framework selects it for you.

<a name="sending-it"></a>

### Sending it

A DAC on the network takes the point stream and clocks it out to the projector.

```swift
let laser = LaserProjector(etherDream: "192.168.1.50")
laser.connect()
```

To find one instead of naming it, listen for the announcement a DAC broadcasts once a second:

```swift
let finder = EtherDreamFinder()
try finder.start()
// a moment later
if let dac = finder.devices.first { laser.connect(to: dac) }
```

A DAC that announced itself also says how big its buffer is and how fast it will scan. Those are taken from it rather than assumed. Listening on the local network makes macOS ask for its Local Network permission once, attributed to whatever launched the sketch.

Then `send` a frame each `draw()`:

```swift
laser.send(frame)      // optimize, guard, and put it on the wire
laser.stream           // the same stream, for the preview and the numbers
laser.status           // what the DAC last said about itself
```

The projector does not send a frame and wait for the next one. The DAC holds a small buffer and plays it at a fixed rate. If that buffer empties, the mirrors stop where they stood, so the stream is topped up continuously from whatever frame is in hand. A new frame takes over at the **end** of the one going out, so a picture is never cut in half. Every command gets one reply carrying the buffer's fullness, and that reply is what asks for the next batch. The stream therefore clocks itself against the hardware.

A projector with no DAC is still worth having. It optimizes, guards, and keeps the stream, so a sketch can be written, previewed and measured with nothing plugged in. Connect it later, unchanged.

<a name="writing-a-file"></a>

### Writing a file

An ILDA file is how laser software has traded frames since 1986, and it is the way into a rig this library does not talk to directly.

```swift
try ILDAFile.write([stream], to: url, name: "RING")     // one still frame
try ILDAFile.write(frames, to: url)                     // an animation
```

Frames are written in **format 5**, the 2D true-color record, because a sketch's colors are its own rather than numbers into a palette. Coordinates use the format's full signed range. A frame fills whatever the receiving software calls its canvas.

<a name="what-is-not-here"></a>

### What is not here

Stated plainly, because a laser is not a thing to be surprised by:

- **No hardware has ever been on the other end.** The wire is verified end to end against a stand-in DAC speaking the same published protocol on the loopback. The files are read back by a parser written from the same specification. That is not the same as a projector in a room. Treat the first run with real hardware as a first run: low power, a wall, nobody in the beam.
- **Discovery is best-effort.** The announcement a DAC broadcasts is decoded and tested, but no real DAC has ever announced itself here. If nothing shows up, name the address instead.
- **One DAC family.** Other DACs speak their own protocols, and the network standard that unifies them is not implemented.
- **True color only in files.** The older indexed ILDA formats, which name colors by number into a palette, are not written.
- **No geometric correction.** Keystone, size and position, and the mapping onto a surface are the projector's or the rig's job here, not the sketch's.
- **No point-rate feedback.** The optimizer trusts the rate you tell it. A projector asked to scan faster than it can does not complain, it distorts. Start below what it is rated for.

---

See the **LaserPreview** example for the optimizer made visible, with no hardware needed. For the other machine that draws with lines, see [G-code](../Output/GCode.md); for vector output on paper, see [Export](../Output/Export.md).
