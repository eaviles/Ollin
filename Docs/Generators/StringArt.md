#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `String art`</sup>

---

## String art

**`StringArt`** winds one continuous thread between pins on a circular rim until the crossings reproduce a picture. Dark regions collect many crossings and light regions collect few, so a shaded image builds up out of straight chords alone. Petros Vrellis made the craft widely known with his knitted portraits in 2016. Each chord here comes from the standard greedy step. Starting at the pin the thread is on, the solver scores every allowed next pin by the darkness its chord still covers. It takes the best one, then subtracts that much ink from the picture so later chords look elsewhere. The code is written independently from the published descriptions.

The winding is deterministic, so the same picture and the same settings always wind the same thread, and there is no seed to set. The helper produces geometry only, and you draw the chords yourself. The thread can therefore be ink on paper, glowing light, or anything else a line can be.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/WoundFromThread-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/WoundFromThread.jpg" alt="Three panels: a bold crescent picture, the first 350 chords of its winding crowding into the crescent, and the finished winding where the crescent is dense thread and the rest a light veil" width="680">
</picture>

### Contents

- [StringArt](#winding)
- [The chords and the thread](#chords)
- [Practical notes](#notes)

<a name="winding"></a>

#### StringArt

```swift
StringArt(of: Image, center: Vector2, radius: Double,
          pins: Int = 200, chords: Int = 4000, ink: Double = 0.055,
          minSpan: Int? = nil, inverted: Bool = false,
          resolution: Int = 300)
```

`StringArt` is a stateful stepper that you hold across frames. The circle of `pins` reads the picture's largest centered square, with pin `0` at the top and the rest running clockwise. Tone is the linear-light darkness `(1 - luminance) * alpha`, so transparency reads as paper. The winding stops at `chords`. It also stops earlier if no allowed chord still covers enough darkness to be worth its ink.

```swift
let art = StringArt(of: picture, center: Vector2(540, 540), radius: 470)

override func setup() { noClear() }

override func draw() {
    if frameCount == 1 { background(.white) }
    stroke(Color.black.withAlpha(0.35))
    for chord in art.step(8) {
        drawLine(chord.from, chord.to)
    }
}
```

The canvas never clears, so each frame adds a few more chords to the ones already there. The picture knits itself over the first seconds of the run.

- **`ink`** is how much darkness one pass of thread takes out of the picture (`0...1`), and it sets how dense the winding gets. Lower ink winds more chords, and finer ones, before a region counts as done. Match it to the stroke alpha you draw with, so the solver's idea of one pass is close to what a drawn chord darkens.
- **`minSpan`** is the shortest chord allowed, counted in pins around the rim, and it defaults to a tenth of the pins. It keeps the thread crossing the picture instead of running along the rim.
- **`inverted`** winds the light areas instead of the dark ones, which gives you a bright thread on a dark ground.
- **`resolution`** is the side of the internal grid that the scoring runs on. The default suits canvas-sized work. Raise it for fine detail, which costs more time in setup and more time per chord.

<a name="chords"></a>

#### The chords and the thread

```swift
art.step()           // wind one chord; nil once finished
art.step(_ count:)   // wind up to `count` more, collected

art.pins             // the rim, in canvas coordinates
art.sequence         // the pin visit order so far
art.thread           // the whole winding as one open Contour
art.chordCount       // chords wound so far
art.isFinished       // the cap is reached, or nothing left worth winding
```

Each `Chord` carries the pins it spans (`fromPin`, `toPin`) and their canvas positions (`from`, `to`), which you pass straight to `drawLine`. `thread` is the same winding as one open polyline through the pins. `sequence` is the pin order on its own. That order is the whole piece if you ever wind it by hand on a real rim.

<a name="notes"></a>

#### Practical notes

- **Bold tonal masses read best.** A strong silhouette or a deep shadow against open paper knits into a clear figure. A soft gradient across the whole frame reads as fuzz. If the picture is low in contrast, raise its contrast first.
- **Accumulate, don't redraw.** The look comes from thousands of translucent chords piling up, so all you need is `noClear()` plus a one-time `background`. See `Examples/Images/StringArt`.
- **The thread is one line, which suits a pen plotter.** Draw `art.thread` with `drawPolyline` in a clearing sketch. The [SVG export](../Output/Export.md) then writes the whole piece as a single continuous line.
- **`chords` sets the length of the thread.** A few hundred chords stay open and diagrammatic, and a few thousand read as continuous tone. The winding also stops on its own once nothing left is worth its ink, so `chords` is a ceiling rather than a target.
- **A texture-backed image has no CPU pixels.** Read a video frame through its `snapshot()` first. This is the same rule the other picture renderings follow.

---

Related: [`Single line`](./SingleLine.md) and [`Spanning tree`](./SpanningTree.md), the other generators that turn a picture into line work. See also [`Halftone`](../Drawing/Halftone.md) for tone as dots instead of chords, and [`Export`](../Output/Export.md) for SVG and the plotter path.
