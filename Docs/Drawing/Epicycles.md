#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Fourier epicycles`</sup>

---

## Fourier epicycles

Rebuild any closed outline as a **chain of spinning circles**. The discrete Fourier transform reads evenly spaced samples of a contour as points in the plane and rewrites them as a sum of circular motions: each term is a circle of fixed radius spinning a whole number of turns per lap. Chain the circles tip to tail, biggest first, and the last tip re-draws the outline; keep only the first few and it draws a smooth phantom of it. That is the whole trick, and it works on *any* closed contour: an [imported SVG](./SVG.md), a glyph from [`textToShapes`](./Text.md), points you computed.

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

Everything is deterministic (there is no randomness in the transform), so a fixed frame reproduces exactly, and one traced lap is inherently a perfect loop: declare the lap as [`loopDuration`](../Core/Sketch.md#loopDuration) and `--export-loop` renders a seamless cycle.

### Contents

- [Building a chain](#building)
- [Reading it: point, joints, path](#reading)
- [Drawing it: drawEpicycles](#drawing)
- [Terms, detail, and ringing](#terms)

<a name="building"></a>

#### Building a chain

```swift
Epicycles(_ contour: Contour, samples: Int = 256)
Epicycles(points: [Vector2])
```

The contour form resamples the outline to `samples` points an even walked-length apart first (the transform assumes even spacing; a raw glyph or SVG outline arrives dense on curves and sparse on straights), then runs the transform. An open contour is closed across its ends. The `points:` form skips the resampling for points that are already even.

The result holds a fixed `center` (the samples' average position) and `terms`, the rotating circles sorted largest first:

```swift
struct Epicycles.Term {
    var frequency: Int     // whole turns per lap; negative spins the other way
    var amplitude: Double  // the circle's radius
    var phase: Double      // the angle it starts from
}
```

The transform is the plain O(n²) DFT, run once at construction; at the default 256 samples it is a sub-millisecond, `setup()`-time cost. Build in `setup()` and keep the value; truncating later costs nothing (see [terms](#terms)).

<a name="reading"></a>

#### Reading it: point, joints, path

```swift
epicycles.point(at: t, terms: 64) -> Vector2     // the traced position
epicycles.joints(at: t, terms: 64) -> [Vector2]  // center, tips..., traced point
epicycles.path(samples: 512, terms: 64) -> Contour
```

`t` is the lap phase, `0...1`, one full trace per unit, so a looping sketch passes `loopProgress(over:)` straight in. It wraps: `point(at: -0.3)` equals `point(at: 0.7)`, which makes fixed-length trails that reach behind the lap start a one-liner.

`joints` is the chain itself: the fixed `center`, then each kept circle's tip in order. Joint `i` is the center of circle `i` (its radius is `terms[i].amplitude`), and the last joint equals `point(at:terms:)`. `path` samples a whole lap into a closed `Contour`, ready for `drawShape`, the [booleans](./Geometry.md), or [hatching](../Output/Export.md#hatching-solid-fills-for-a-pen-plotter).

With every term kept, the reconstruction is exact at the sample phases: `point(at: i / n)` lands back on input sample `i`.

<a name="drawing"></a>

#### Drawing it: drawEpicycles

```swift
drawEpicycles(_ epicycles: Epicycles, at: t, terms: 64)
```

The classic construction in one call: each kept circle as an unfilled outline in the current `stroke`, with a spoke from its center to the next joint. The current fill is untouched. For the trail the pen leaves behind, sample `point(at:terms:)` over recent phases and draw the polyline yourself (the `Motion/Epicycles` example fades one as it goes).

<a name="terms"></a>

#### Terms, detail, and ringing

Every read method takes `terms:`, a prefix count of the largest circles. Because the terms are amplitude-sorted, `terms: k` is always the best `k`-circle approximation, so one built chain serves every level of detail; put the count on a [`@Param`](../Helpers/Parameters.md) knob and scrub it live. A handful of terms gives a soft, dreamy phantom; more terms sharpen it; near-full terms trace the outline exactly. Around sharp corners a truncated chain overshoots in small ripples (the transform's ringing), which reads as a wobble near the corner: raise `terms:` or soften the corner if it bothers the piece.

---

Related: [`SVG import`](./SVG.md) (outlines to trace), [`Text`](./Text.md) (`textToShapes` glyph outlines), [`Geometry`](./Geometry.md) (`Contour` and `resampled`), [perfect loops](../Output/Export.md#perfect-loops) (exporting one traced lap). Example: [`Examples/Motion/Epicycles`](../../Examples/Motion/Epicycles/Sketch.swift).
