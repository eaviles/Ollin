#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Laser`</sup>

---

## Laser

A show laser draws with a single moving dot. Two mirrors on galvanometers steer the beam, and a fixed clock decides how often they are told where to point. At each of those points the beam is lit or dark, so there is no picture in the machine anywhere. What you see is one dot going round a path fast enough that your eye holds the whole loop.

That suits the geometry Ollin already works in, because a `Contour` is close to a beam path already. The gap between the two is what this library covers. It turns line work into a point list a real machine can scan, and it does that safely. Add `import OllinLaser` alongside `import Ollin` to reach it.

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

Both wire formats here are written from their published specifications, so nothing is vendored. The [ILDA Image Data Transfer Format](https://www.ilda.com/resources/StandardsDocs/ILDA_IDTF14_rev011.pdf) covers files, and the [Ether Dream](https://ether-dream.com/protocol.html) DAC protocol covers the network.

### Contents

- [Line work, not pictures](#line-work-not-pictures) - what a laser can and cannot draw
- [The projector's square](#the-projectors-square) - where the canvas ends up
- [Making the points](#making-the-points) - spacing, corners, blanking, order, budget
- [Seeing it without a laser](#seeing-it-without-a-laser) - the preview, and what it shows
- [Safety](#safety) - the arm gate and the rules under it
- [Sending it](#sending-it) - finding a DAC, connecting, streaming
- [Writing a file](#writing-a-file) - ILDA, for the software that already drives your rig
- [What is not here](#what-is-not-here) - what this version does not do

<a name="line-work-not-pictures"></a>

### Line work, not pictures

A `LaserFrame` holds the paths to trace. They are measured in canvas coordinates, the same numbers every drawing call takes.

```swift
var frame = LaserFrame(canvas: bounds)
frame.add(contour, color: .cyan)                 // a Contour, open or closed
frame.add(shape, color: .white)                  // every contour of a Shape
frame.add(textToShapes("hello", …), color: .red) // several shapes at once
frame.add(points, color: .green, closed: true)   // bare points
frame.addLine(from: a, to: b, color: .white)
```

A laser draws lines, so a `Shape` contributes its **outlines** and its fill rule plays no part. To shade a region, first hatch it into line work with [`Hatching`](../Output/GCode.md). The pen plotter takes the same step.

Color can change along a path. Pass one color per point, and the optimizer cross-fades between them as it fills in the segments:

```swift
frame.add(points, colors: points.indices.map { Color(hue: …, saturation: 1, brightness: 1) })
```

<a name="the-projectors-square"></a>

### The projector's square

A projector throws into a square field. Its own coordinates run `-1…1` on both axes from the center, with **y up**. The canvas grows downward instead, so one of the two has to be flipped. `ProjectorSpace` does that flip once, at the edge of the optimizer.

The canvas rectangle is **fitted** into the field, so its longer side reaches the edge and nothing lands outside. A point drawn off the canvas is clamped rather than dropped. A sketch can never ask the mirrors for a swing they do not have.

```swift
ProjectorSpace.transform(from: canvas)   // canvas point -> field point
ProjectorSpace.inverse(to: canvas)       // field point  -> canvas point
```

The optimizer measures everything in field units rather than pixels. Every distance it cares about is a distance the mirrors actually move, so a setting means the same thing whatever the size of the canvas.

<a name="making-the-points"></a>

### Making the points

`LaserOptimizer` turns a frame into a `LaserStream`. That stream is the list of positions, each one lit in a color or blanked.

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

Five things happen here, and each one is something a laser needs rather than something a renderer would do:

- **Spacing.** Points are laid evenly along every segment, so the beam moves at a steady speed and the line is evenly bright. A long line drawn with two points is scanned fast, so it reads faint. Segments are **subdivided** rather than resampled end to end, so every point the sketch gave stays exactly where it put it. That is what keeps a corner a corner.
- **Corner dwell.** The mirrors have mass. If they are asked to turn sharply at speed, they overshoot and round the corner off. A few points are held at the turn to let them arrive.
- **Blanking.** Between two shapes the beam goes off and the mirrors travel. Points are held at **each end** of that jump as well. Without them the beam lights while the mirrors are still moving, and it drags a faint tail between the shapes.
- **Order.** Dark travel takes time and draws nothing, so paths are visited near to near rather than in the order they arrived. The walk may enter a closed path at any of its points, or walk an open one backwards. It changes the route, never the picture. It is the same greedy tour the [G-code](../Output/GCode.md) path uses to shorten pen-up travel.
- **The budget.** `pointsPerSecond / refreshRate` is the number of points a frame may hold. `stream.pointBudget` reports that number, and `stream.isOverBudget` reports whether the frame went past it.

**Nothing is dropped when a frame goes over budget.** The frame plays whole and repeats more slowly, which the eye reads as flicker. `stream.refreshRate` tells you the rate it will actually run at. Thinning the line work in silence would give you a wrong picture instead of a flickering one, so the choice is left to you. Draw less, or raise `spacing`.

The stream also reports what the frame cost: `points.count`, `litCount`, `blankedCount`, `drawnLength` and `travelLength` in field units, and `duration` in seconds.

<a name="seeing-it-without-a-laser"></a>

### Seeing it without a laser

```swift
drawLaserPreview(laser.stream, showsTravel: true, showsPoints: true)
```

The preview draws the stream the way the beam will trace it. Lit runs appear in their own colors, the dark travel as faint lines, and each point the beam passes through as a dot. It shows things the drawn picture cannot. Where the dots bunch up, the beam is slow and the line is bright, and where they spread out the line is faint. Every travel line is time spent drawing nothing.

The **LaserPreview** example (`Examples/Integration/LaserPreview`) is that view with the parameters attached, and it runs with no hardware.

<a name="safety"></a>

### Safety

A projector is not a screen. The light is collimated, and the mirrors are the only thing that spreads it. While the mirrors sweep, the power lands along a whole line, and while they sit still it lands on one spot. So a laser sketch goes wrong in two ways: a beam that stops moving, and a beam brighter than the room can take.

**A projector will not emit until it is armed.** That is the one rule the library keeps for you rather than trusting to a sketch:

```swift
laser.arm()        // a line somebody had to write on purpose
laser.disarm()     // dark again, connection kept, rig still live
```

Below that gate, `LaserSafety` guards every stream on its way out:

```swift
laser.safety.maximumBrightness = 0.5   // a ceiling on every channel
laser.safety.stationaryRadius = 0.004  // how far counts as moving
laser.safety.stationaryLimit = 24      // lit points allowed to stand still
laser.safety.stallTimeout = 0.5        // seconds before a stale frame is blanked
```

The stopped-beam guard blanks a run of lit points that stays inside `stationaryRadius`. That catches a beam effect, a shape far smaller than it looks, and a frame that turned out to be a single point. Its limit sits well above `cornerDwell`, which holds points at a corner on purpose. The stall timeout covers the case a sketch cannot cover itself. The sketch stopped or crashed, and the projector is still playing the last thing it was given.

The defaults are careful, including a brightness ceiling of half. `LaserSafety.unguarded` turns every guard off, for a bench where the beam goes into a meter rather than a room. Nothing in the framework selects it for you.

<a name="sending-it"></a>

### Sending it

A DAC on the network takes the point stream and clocks it out to the projector.

```swift
let laser = LaserProjector(etherDream: "192.168.1.50")
laser.connect()
```

To find a DAC instead of naming it, listen for the announcement each one broadcasts once a second:

```swift
let finder = EtherDreamFinder()
try finder.start()
// a moment later
if let dac = finder.devices.first { laser.connect(to: dac) }
```

A DAC that announced itself also says how big its buffer is and how fast it will scan. Those numbers are taken from it rather than assumed. Listening on the local network makes macOS ask for its Local Network permission once. The request is attributed to whatever launched the sketch.

Then `send` a frame each `draw()`:

```swift
laser.send(frame)      // optimize, guard, and put it on the wire
laser.stream           // the same stream, for the preview and the numbers
laser.status           // what the DAC last said about itself
```

The projector is not handed one frame and then left to wait for the next. The DAC holds a small buffer and plays it at a fixed rate. If that buffer empties, the mirrors stop where they stood, so the stream is topped up continuously from whatever frame is in hand. A new frame takes over at the **end** of the one going out, so a picture is never cut in half. Every command gets one reply that carries the buffer's fullness, and that reply is what asks for the next batch. The stream therefore clocks itself against the hardware.

A projector with no DAC is still useful. It optimizes, guards, and keeps the stream, so you can write, preview, and measure a sketch with nothing plugged in. Connect the DAC later and the sketch does not change.

<a name="writing-a-file"></a>

### Writing a file

Laser software has traded frames as ILDA files since 1986. A file is the way into a rig this library does not talk to directly.

```swift
try ILDAFile.write([stream], to: url, name: "RING")     // one still frame
try ILDAFile.write(frames, to: url)                     // an animation
```

Frames are written in **format 5**, the 2D true-color record, because a sketch's colors are its own rather than numbers into a palette. Coordinates use the full signed range of the format, so a frame fills whatever the receiving software calls its canvas.

<a name="what-is-not-here"></a>

### What is not here

These limits are stated plainly, because a laser is not a thing to be surprised by:

- **No hardware has ever been on the other end.** The wire is verified end to end on the loopback. The stand-in DAC there speaks the same published protocol, and the files are read back by a parser written from the same specification. That is not the same as a projector in a room. Treat the first run with real hardware as a first run: low power, a wall, and nobody in the beam.
- **Discovery is best-effort.** The announcement a DAC broadcasts is decoded and tested, but no real DAC has ever announced itself here. If nothing shows up, name the address instead.
- **One DAC family.** Other DACs speak their own protocols, and the network standard that unifies them is not implemented.
- **True color only in files.** The older indexed ILDA formats, which name colors by number into a palette, are not written.
- **No geometric correction.** Keystone, size and position, and the mapping onto a surface are the job of the projector or the rig. The sketch does not do them.
- **No point-rate feedback.** The optimizer trusts the rate you tell it. A projector asked to scan faster than it can does not complain. It distorts the picture instead, so start below the rate it is rated for.

---

See the **LaserPreview** example to watch the optimizer at work, with no hardware needed. For the other machine that draws with lines, see [G-code](../Output/GCode.md). For vector output on paper, see [Export](../Output/Export.md).
