#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Fourier epicycles`</sup>

---

## Fourier epicycles

Rebuild any closed outline as a **chain of spinning circles**. The discrete Fourier transform reads evenly spaced samples of a contour as points in the plane. It rewrites those points as a sum of circular motions. Each term is a circle of fixed radius, and it spins a whole number of turns per lap. Chain the circles tip to tail, biggest first, and the last tip re-draws the outline. Keep only the first few circles and that tip draws a smooth, loose version of the outline instead. This works on any closed contour, so the input can be an [imported SVG](./SVG.md), a glyph from [`textToShapes`](./Text.md), or points you computed yourself.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/EpicycleTerms-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/EpicycleTerms.jpg" alt="Three panels rebuilding the letter g from spinning circles: with three circles it is a wobbly loop, with twelve it is recognizably the letter, and with sixty-four it is exact, with the faint construction circles visible in each" width="680">
</picture>

```swift
var epicycles = Epicycles(points: [])

override func setup() {
    guard let art = loadSVG("whale.svg") else { return }
    let outline = art.fitted(in: bounds.inset(by: .all(140))).contours[0]
    epicycles = Epicycles(outline, samples: 320)
}

override func draw() {
    background(.black)
    let phase = loopProgress(over: 12)              // one traced lap per 12 s
    stroke(.white)
    drawEpicycles(epicycles, at: phase, terms: 64)  // the spinning machine
    fill(.yellow)
    drawCircle(center: epicycles.point(at: phase, terms: 64), radius: 5)
}
```

The transform has no randomness in it, so everything here is deterministic and a fixed frame reproduces exactly. One traced lap is also a perfect loop on its own. Declare the lap as [`loopDuration`](../Core/Sketch.md#loopDuration), and `--export-loop` then renders a seamless cycle.

### Contents

- [Building a chain](#building)
- [Reading a chain](#reading)
- [Drawing a chain](#drawing)
- [Terms, detail, and ringing](#terms)

<a name="building"></a>

#### Building a chain

```swift
Epicycles(_ contour: Contour, samples: Int = 256)
Epicycles(points: [Vector2])
```

The contour form first resamples the outline to `samples` points an even walked-length apart, then runs the transform. It resamples because the transform assumes even spacing, and a raw glyph or SVG outline arrives dense on curves and sparse on straights. An open contour is closed across its ends. The `points:` form skips the resampling, so use it when your points are already evenly spaced.

The result holds a fixed `center` and a list of `terms`. The `center` is the average position of the samples, and `terms` holds the rotating circles sorted largest first:

```swift
struct Epicycles.Term {
    var frequency: Int     // whole turns per lap; negative spins the other way
    var amplitude: Double  // the circle's radius
    var phase: Double      // the angle it starts from
}
```

The transform is the plain O(n²) DFT, and it runs once at construction. At the default 256 samples that costs under a millisecond, paid in `setup()`. Build the chain there and keep the value, because truncating it later costs nothing (see [terms](#terms)).

<a name="reading"></a>

#### Reading a chain

```swift
epicycles.point(at: t, terms: 64) -> Vector2     // the traced position
epicycles.joints(at: t, terms: 64) -> [Vector2]  // center, tips..., traced point
epicycles.path(samples: 512, terms: 64) -> Contour
```

`t` is the lap phase and runs `0...1`, one full trace per unit, so a looping sketch can pass `loopProgress(over:)` straight in. The phase also wraps, so `point(at: -0.3)` equals `point(at: 0.7)`. Because the phase wraps, you can write a fixed-length trail that reaches behind the lap start in one line.

`joints` returns the chain itself: the fixed `center`, then each kept circle's tip in order. Joint `i` is the center of circle `i`, and that circle's radius is `terms[i].amplitude`. The last joint equals `point(at:terms:)`. `path` samples a whole lap into a closed `Contour`, ready for `drawShape`, the [booleans](./Geometry.md), or [hatching](../Output/Export.md#hatching-solid-fills-for-a-pen-plotter).

When you keep every term, the reconstruction is exact at the sample phases, so `point(at: i / n)` lands back on input sample `i`.

<a name="drawing"></a>

#### Drawing a chain

```swift
drawEpicycles(_ epicycles: Epicycles, at: t, terms: 64)
```

This draws the classic construction in one call. Each kept circle appears as an unfilled outline in the current `stroke`, with a spoke from its center to the next joint. The current fill is untouched. To draw the trail behind the traced point, sample `point(at:terms:)` over recent phases and draw the polyline yourself. The `Motion/Epicycles` example fades that trail as the traced point moves.

<a name="terms"></a>

#### Terms, detail, and ringing

Every read method takes `terms:`, the number of circles to keep from the front of the list. The terms are sorted by amplitude, so `terms: k` is always the best `k`-circle approximation, and one built chain serves every level of detail. Put the count on a [`@Param`](../Helpers/Parameters.md) parameter and scrub it live. A few terms give a soft, loose shape, more terms sharpen it, and a near-full count traces the outline exactly. Around a sharp corner a truncated chain overshoots in small ripples. That overshoot is the transform's ringing, and it reads as a wobble near the corner. Raise `terms:` or soften the corner if that wobble bothers the piece.

---

Related: [`SVG import`](./SVG.md) (outlines to trace), [`Text`](./Text.md) (`textToShapes` glyph outlines), [`Geometry`](./Geometry.md) (`Contour` and `resampled`), [perfect loops](../Output/Export.md#perfect-loops) (exporting one traced lap). Example: [`Examples/Motion/Epicycles`](../../Examples/Motion/Epicycles/Sketch.swift).
