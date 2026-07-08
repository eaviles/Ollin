#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Shape morphing`</sup>

---

## Shape morphing

Tween one `Shape` into another. A `ShapeMorph` works out, once, which point of the first outline becomes which point of the second; after that, reading the in-between at any fraction is a straight blend. Every in-between is a real vector `Shape`: fill it, stroke it, run it through the [booleans](./Geometry.md), [hatch it](../Output/Export.md#hatching-solid-fills-for-a-pen-plotter), or export it, which is what makes the morph plotter-friendly rather than a pixel effect.

```swift
var morph = ShapeMorph(from: Shape([]), to: Shape([]))

override func setup() {
    let star = Shape((0 ..< 10).map { i in
        let angle = Double(i) / 10 * .tau
        return center + Vector2(angle: angle, length: i.isMultiple(of: 2) ? 300 : 130)
    })
    let ring = Shape(outer: (0 ..< 64).map { center + Vector2(angle: Double($0) / 64 * .tau, length: 280) },
                     holes: [(0 ..< 48).map { center + Vector2(angle: Double($0) / 48 * .tau, length: 140) }])
    morph = ShapeMorph(from: star, to: ring)
}

override func draw() {
    background(.white)
    fill(.black)
    drawShape(morph.shape(at: pingPong(over: 6)))   // there and back every 6 s
}
```

There is no randomness anywhere: the same pair of shapes always morphs the same way, a fixed frame reproduces exactly, and a there-and-back cycle (or a closed chain of morphs) declared as [`loopDuration`](../Core/Sketch.md#loopDuration) exports seamlessly with `--export-loop`.

### Contents

- [Preparing a morph](#preparing)
- [Reading it: shape(at:)](#reading)
- [How the matching works](#matching)
- [Tweening geometry: Timeline and morphed(toward:)](#tweening)

<a name="preparing"></a>

#### Preparing a morph

```swift
ShapeMorph(from: Shape, to: Shape, spacing: Double? = nil)
```

Build it in `setup()` (or whenever the pair changes) and keep the value; the correspondence work happens here, so the per-frame read stays cheap. `from` and `to` are stored untouched, and the reads at `0` and `1` return them verbatim.

`spacing` bounds how far apart correspondence points may sit along either outline. Left `nil`, it derives from each outline's own length (1/128 of it), which spreads the added points at matching fractions along both sides of a pair and suits most shapes. Pass a smaller spacing when a long straight edge must follow a tightly curved partner more faithfully; extra points are only ever *added* along segments, so every original corner survives, and the point count is capped so a tiny spacing cannot run away.

<a name="reading"></a>

#### Reading it: shape(at:)

```swift
morph.shape(at: t) -> Shape
```

`t` runs `0...1` and clamps. `0` and `1` are the exact originals; everything between is the pointwise blend. Shape the timing outside the read: pass an [`Easing`](../Helpers/Animation.md) of your phase, `pingPong(over:)` for there-and-back, or a [`Timeline`](../Helpers/Animation.md#timeline)'s progress.

When the two shapes fill by different [winding rules](./Geometry.md), the in-betweens use `from`'s rule up to the halfway mark and `to`'s after it.

<a name="matching"></a>

#### How the matching works

Contours pair up first: closed outlines with closed outlines, open line-work with open line-work. The largest pairs with the largest (by enclosed area for closed contours, walked length for open ones), and each remaining contour takes the unused partner whose center sits nearest. Then, per pair:

- Both sides get the same number of points, added along segments longer than the spacing, so corners are kept, not resampled away.
- Windings are lined up (a clockwise outline never blends toward a counter-clockwise one, which would fold through itself halfway).
- For closed contours, the starting point of one ring rotates to wherever the total travel is shortest; for open ones the direction flips if that travels less.

A contour with no partner scales down to its own center, or grows out of one, so shapes with different contour counts cross-fade instead of popping. That includes holes: morph a disc into a donut and the hole grows from the middle.

Two limits worth knowing. A closed contour never pairs with an open one (the leftover rule above handles the mix), and the correspondence is by outline distance, not by meaning: morphing a hand into another hand does not know a thumb from a finger. When a morph reads muddled, add a `spacing`, or split the shape and morph the parts separately.

<a name="tweening"></a>

#### Tweening geometry: Timeline and morphed(toward:)

`Shape` and `Contour` are `Tweenable`, so a [`Timeline`](../Helpers/Animation.md#timeline) sequences geometry like any other value:

```swift
let tween = Timeline(star).to(blob, in: 2).hold(for: 1).to(star, in: 2)
// each frame:
drawShape(tween.value)
```

The conveniences rebuild the correspondence on each read, which is fine for simple outlines; when the shapes are heavy (a dense SVG, a glyph), hold a `ShapeMorph` and read `shape(at:)` instead. The same trade holds for the one-off form:

```swift
star.morphed(toward: blob, 0.5)            // one blended shape, no held state
star.morphed(toward: blob, 0.5, spacing: 4)
```

---

Related: [`Geometry`](./Geometry.md) (`Shape`, `Contour`, winding), [`SVG import`](./SVG.md) (outlines worth morphing), [`Animation`](../Helpers/Animation.md) (`Timeline`, `Easing`), [perfect loops](../Output/Export.md#perfect-loops). Example: [`Examples/Motion/Morphing`](../../Examples/Motion/Morphing/Sketch.swift).
