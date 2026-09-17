#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Widget`</sup>

---

## A sketch as a widget

A widget sits on the desktop and in the notification panel, next to the weather and the calendar. Putting a sketch there gives the piece a place in the day rather than a window you open.

```sh
ollin new Ripple --kind widget
cd Ripple && ./build.sh --install
```

Open the app once, so the system sees what is inside it. Then right-click the desktop, choose Edit Widgets, and look for **Ripple**.

### A widget is not a window

This is the one surface that changes what a sketch *is*, so it is worth being plain about before anything else.

The system asks for a handful of pictures at a time, keeps them, and puts each one up when its moment comes. Nothing runs in between. There is no frame rate here and no sixty draws a second: there are four or five draws an hour, and the viewer sees the difference between two of them rather than the motion between them.

So a piece here is one that **changes** rather than one that moves. A dial that turns through the day works. A slow drift through a color works. A ball bouncing does not: by the time the next picture goes up, the ball has been somewhere else a thousand times and nobody saw any of it.

### What you get

```
Ripple/
  Package.swift              three targets: the sketch, the app, the widget
  Info.plist                 the app's name tag
  Widget-Info.plist          the extension's, saying what kind it is
  Widget.entitlements        the sandbox line an extension is refused without
  build.sh                   builds the app and packs the widget inside it
  Sources/Ripple/
    Sketch.swift             an ordinary sketch
    Piece.swift              one public line, the door the two programs use
  Sources/RippleApp/
    Main.swift               the app the widget is packed inside
  Sources/RippleWidget/
    Widget.swift             the run, and the view that shows one picture
```

Three targets, which is more than any other kind writes. The reason is structural: the system finds a widget through the app it is packed inside, so there are two programs here, and two programs cannot share a folder of sources. The sketch therefore lives in a library both of them depend on.

That would normally mean making the sketch `public`, and a public class makes every `override func draw()` in it public too, which is a sketch written differently from every other kind's. So the library exposes one line instead, and the sketch stays ordinary:

```swift
public enum RipplePiece {
    @MainActor public static func make() -> Sketch { Ripple() }
}
```

### The clock is the time of day

`time` is seconds since midnight of the moment being drawn. `time / 3600` is the hour, `time` runs from 0 to 86400, and the piece reads the same at four this afternoon as at four tomorrow.

An elapsed clock could not do that. The system throws a run away and asks for a new one whenever it feels like it, and a piece counting from zero would jump back to the beginning every time it did. Reading the day instead means two runs that cover the same moment draw the same picture, which is the whole contract of this surface.

The rest of the frame's clock follows from that:

| The sketch reads | In a widget |
|---|---|
| `time` | Seconds since midnight of this picture's moment, 0 to 86400. |
| `deltaTime` | The spacing: what really passed since the picture before this one. |
| `date` | The moment itself, for anything the day of the week or the month decides. |
| `frameCount` | 1. Every picture is the first frame of its own sketch. |

`date` is worth one more line. A widget's pictures are drawn *before* their moments come, so a piece that asks `Date()` is asking about the wrong time, sometimes by an hour. `date` is the moment being drawn, and at a desk it is simply now, so a piece written against it reads correctly on both. [A day schedule](./Installation.md) reads it too.

### How far apart the pictures sit

The sketch says:

```swift
override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }
```

Four pictures a quarter of an hour apart, which covers the next hour. `.every(hours:count:)` is the same call at the other scale, and `WidgetTimeline(spacing:count:)` takes plain seconds.

Two things about it are honest rather than convenient:

- **The spacing is a wish, not a promise.** The system decides when it comes back for more pictures, and it will not come back every minute for anybody. A quarter of an hour is the shortest spacing worth asking for, and a piece that would look wrong a few minutes late should not be a widget.
- **The whole run is held at once.** Every picture is drawn before any of them is shown, so `count` is a handful and not a hundred.

`span` is how long one pass covers, which is the last picture's moment minus the first's. `moments(from:)` is the whole list a pass draws for, `gridMoment(atOrBefore:)` the grid step a moment falls on, and `WidgetTimeline.timeOfDay(at:)` the seconds since midnight of one. The moments land on a grid counted from midnight rather than from whenever the system happened to ask. A quarter-hour piece therefore steps at the quarter hours, and the next run carries on the same grid instead of starting one of its own. A spacing that does not divide the day has one short step at midnight.

One consequence follows from the grid: a piece whose own period divides the spacing is caught in the same place every time, so it never appears to move at all. A run every fifteen minutes cannot show you anything that repeats every fifteen minutes.

### Seeing the run without waiting for it

Waiting a quarter of an hour to judge a change is no way to work. Two faster ways, and the second is the one that matters:

```sh
ollin Sources/Ripple/Sketch.swift                               # a window, reloading as you save
swift run RippleApp --export-widget frames --size 720x720       # the whole run, as files
```

`--export-widget <dir>` writes one picture per moment into a folder, named by the moment (`widget-141500.png`). It is exactly what the widget will show, drawn by exactly the same call. `--size WxH` is the widget's own size in pixels; left out, the sketch's declared canvas is used. `--frames N` overrides how many pictures the run holds.

The flag works on any sketch, not only a generated widget project, so a piece can be tried on this surface before it is wrapped for it.

### The same call, from your own code

```swift
let frames = OllinApp.widgetFrames(size: .square(720)) { Ripple() }
for frame in frames {
    print(frame.date, frame.image.width)
}
```

Each of those is a `WidgetFrame(date:image:)`, the moment and the picture drawn for it. Each picture gets a sketch of its own, made fresh and drawn once. Nothing carries from one to the next, which is what makes a moment draw the same picture whether it opened a run or closed one.

### Building it

`build.sh` is the [Mac app](./App.md) wrapper with one more step: it puts the extension inside the app, at `Contents/PlugIns/RippleWidget.appex`, and signs that before it signs the app. The order is load-bearing. Signing the app seals what is inside it, so anything signed afterwards breaks the seal.

The extension is signed with `Widget.entitlements`, which declares the sandbox. App extensions on this system run sandboxed, and one signed without that declaration is refused rather than sandboxed.

`--install` puts the app in /Applications, which is where the system looks. Open it once after that, so the extension is registered. As with every other bundle here, the plain build is signed for this machine alone; handing it to somebody else needs a Developer ID signature and a trip through notarization.

---

## See also

- [Menu bar](./MenuBar.md) - the other small surface, live rather than stepped
- [Wallpaper](./Wallpaper.md) - the whole desktop, drawn at the display's own rate
- [Sketch as an app](./App.md) - the wrapper this kind extends, and how to hand an app over
- [Installation](./Installation.md) - a day schedule, which reads the same `date` this surface pins
- [The project generator](../Tools/ProjectGenerator.md) - the kinds of project `ollin new` writes, this one among them
