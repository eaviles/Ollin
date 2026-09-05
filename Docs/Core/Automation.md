#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Automation`</sup>

---

## Keyframed parameters

A [`@Param`](../Helpers/Parameters.md) gives a sketch a parameter you can adjust. An `Automation` moves that parameter for you. You place one value at one moment and another value later, and a curve carries the first value into the second. So you do not have to tune the parameter by hand, because the automation sets it for you as the sketch runs.

The tracks read the sketch clock, and every export drives that clock at a fixed step. So an automated run renders exactly as it plays.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/03-MotionAndTime/TimelineCurve-dark.jpg">
  <img src="../../Guide/Images/03-MotionAndTime/TimelineCurve.jpg" alt="A timeline's value plotted over 2.8 seconds: an eased rise to 1, a flat hold, then an easeOutBounce drop to 0.25, keyframes marked as dots" width="680">
</picture>

### Contents

- [Writing tracks in code](#writing-tracks-in-code)
- [Curves](#curves)
- [What blends, and what steps](#what-blends-and-what-steps)
- [How a pass plays](#how-a-pass-plays)
- [Reading a track back](#reading-a-track-back)
- [A track that is a rule](#a-track-that-is-a-rule)
- [The file](#the-file)
- [How it sits beside the rest](#how-it-sits-beside-the-rest)

---

### Writing tracks in code

Call `automate(_:_:)` in `setup()`, once for each parameter. Inside the closure you place the keys, and each key takes a value of the parameter's own type:

```swift
final class Breathing: Sketch {
    @Param(20...400) var radius = 120.0
    @Param var tint = Color.coral

    override func setup() {
        automate($radius) { track in
            track.key(at: 0, 40)
            track.key(at: 2, 320, curve: .easeInOut)
            track.key(at: 4, 40)
        }
        automate($tint) { track in
            track.key(at: 0, .coral, curve: .linear)
            track.key(at: 4, Color(hex: 0x2E6BE6), curve: .linear)
        }
        automation?.loops = true
    }

    override func draw() {
        background(.white)
        fill(tint)
        drawCircle(center: center, radius: radius)   // both parameters are on their curves
    }
}
```

The `$radius` form passes the parameter itself rather than its value, and that is how the track learns the property name. You can write the keys in any order, because a track sorts them by time. If you call `automate` again for the same parameter, the new track replaces the old one.

Every frame, before the sketch draws, each track reads the sketch clock and sets its parameter to the value its curve holds at that time.

### Curves

A key carries the curve that *leaves* it and runs to the next key, so the curve on the last key is never read.

| Curve | What it does |
|---|---|
| `.hold` | stay at this value until the next key, then jump |
| `.linear` | a straight line |
| `.easeIn` | start slowly, arrive fast |
| `.easeOut` | start fast, arrive slowly |
| `.easeInOut` | slow at both ends, fast through the middle (the default) |
| `.bezier(x1:y1:x2:y2:)` | a cubic Bezier through two handle points |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/ParameterOnACurve-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/ParameterOnACurve.jpg" alt="Four panels, each with the same two keys read by a different curve: a straight line, an S, a flat line that jumps at the end, and a hard snap. A red line marks one moment on each, and the circle above shows the size the parameter holds there" width="680">
</picture>

The Bezier is the curve you shape yourself. Its two handles change the timing as well as the value, the same way a curve you draw by hand does. The `x` of each handle stays inside `0...1`, so the curve always reads from left to right. The `y` may go outside that range, and then the value overshoots and comes back.

```swift
track.key(at: 0, 40, curve: .bezier(x1: 0.85, y1: 0, x2: 0.15, y2: 1))   // a hard snap
```

`track.hold(at:_:)` is a shorter way to write a key whose curve is `.hold`.

### What blends, and what steps

Numbers, colors, points, rectangles, insets, and ranges have values in between any two settings, so they travel along the curve. Colors blend along the same even path that [`Color.mix`](../Drawing/Color.md) uses, so a fade between two keys stays even from end to end.

A switch, a menu choice, and a piece of text have no values in between. So they *step* instead, and the parameter holds the setting of the key it left until the next key takes over. Two keys of different kinds step in the same way, which happens when a parameter changed its type after its keys were written.

Outside its own span, a track is a constant. Before the first key it holds the first key's value, and after the last key it holds the last key's value.

### How a pass plays

The automation reads its position from the sketch clock as `start + time * speed`:

```swift
automation?.speed = 2                       // twice as fast
automation?.loops = true                    // wrap at the duration
automation?.length = 8                      // hold past the last key, then wrap
automation?.speed = -1                      // and run it backwards,
automation?.start = automation?.duration ?? 0   // starting from the end
```

`duration` is the time of the last key on the longest track, unless `length` sets a different value. With `loops` off, a pass holds its last key once it runs past the end.

### Reading a track back

An automation is plain data, so a sketch can read its own curves and draw them:

```swift
if case .number(let value)? = automation?.track(named: "radius")?.value(at: 1.5) {
    // what the radius parameter will hold one and a half seconds in
}
```

`value(of:at:)` does the same, but it takes a sketch time rather than a position, so it applies `speed`, `start`, and the loop first. The [Automation example](../../Examples/Motion/Automation/Sketch.swift) uses this to plot each of its own tracks under the stage.

### A track that is a rule

Keys set a parameter's value at a few moments. A [`Formula`](../Helpers/Formula.md) sets it at every moment, and you write that rule as text rather than as Swift source:

```swift
drive($radius, "190 + sin(time * tau / 6) * 80")
```

A formula fills the same kind of track, so `loops`, `speed`, `start`, and `length` shape it the same way. A formula is also saved in the same file, where it appears as the text itself:

```json
{ "name": "radius", "formula": "190 + sin(time * tau / 6) * 80" }
```

Inside a formula, `time` is the position in the automation. A formula can also read `frame`, the canvas, the pointer, and the sketch's other number and switch parameters by name. The [`Formula`](../Helpers/Formula.md) page lists the whole vocabulary and the two rules to know before you type one.

A parameter that holds more than one number takes one rule for each part. A part with no rule is left alone:

```swift
drive($eye, x: "frame.x + frame.width / 2", y: "height / 2")
```

```json
{ "name": "eye", "parts": { "x": "frame.x + frame.width / 2", "y": "height / 2" } }
```

`Automation.parts(of:)` names the parts that a stored value carries. `Automation.applying(_:to:)` puts the worked-out numbers back into a stored value, and that is how a track of parts becomes a whole value again. See [a parameter of more than one number](../Helpers/Formula.md#a-parameter-of-more-than-one-number).

### The file

An `Automation` is codable, so it reads and writes as JSON:

```swift
try automation?.write(to: url)
sketch.automation = try Automation.load(from: url)
```

The `--automation <file>` flag attaches a file to a standalone run or to any export:

```sh
swift run Example-Motion-Automation --automation slow.json --export-video out.mp4 --seconds 12
```

A file is loaded before `setup()` runs. So when the sketch also writes a track for the same parameter, the sketch's track replaces the one from the file. Ollin refuses a file written in a *newer* format than this version understands, rather than guessing at what it means. An older file still reads, because each layout so far has only added to the one before it.

Standalone runs, every export path, and OllinLive all read the flag. When no flag names a file, OllinLive also looks for the sketch's sibling file, `Sketch.automation.json` beside `Sketch.swift`. The live host installs the file's tracks again after every reload. Its [timeline panel](../Tools/Timeline.md) lets you edit those tracks by hand and writes them back to the same file.

### How it sits beside the rest

- **Smoothing.** A track sets its parameter directly rather than easing it in. So a `@Param` that carries `smoothing:` does not glide twice, because the curve already does the easing.
- **The inspector.** A parameter under a track returns to its curve at the next frame. So dragging its slider only nudges the value for a frame instead of changing it. To tune by hand, take the track off with `automation = nil`.
- **Takes.** A run recorded with [`--record-take`](Replay.md) writes down the values the curves held. So the take replays the same run whether or not the automation is attached.
- **Exports.** Every export flag drives the clock at a fixed step, so an automated piece renders frame for frame. `--export-video --seconds` decides how many passes the file holds.

---

### See also

- [`Parameters`](../Helpers/Parameters.md) - the `@Param` parameters themselves, and the controls that edit them by hand
- [`Replay`](Replay.md) - a run written down as it happened, in a sibling file format that keys its values by parameter name
- [`Export`](../Output/Export.md) - the flags an automated run renders through, `--automation` among them
- [`Formula`](../Helpers/Formula.md) - the other way to fill a track: a rule worked out every frame, read from text
- [`Animation`](../Helpers/Animation.md) - `Timeline`, the in-code sibling that sequences one value rather than a sketch's parameters
