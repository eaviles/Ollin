#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Shape morphing`</sup>

---

## Shape morphing

Tween one `Shape` into another. A `ShapeMorph` works out, once, which point of the first outline becomes which point of the second. After that, reading the in-between at any fraction is a straight blend. Every in-between is a real vector `Shape`. Fill it, stroke it, run it through the [booleans](./Geometry.md), [hatch it](../Output/Export.md#hatching-solid-fills-for-a-pen-plotter), or export it. That is what makes the morph plotter-friendly rather than a pixel effect.

<img src="../../Guide/Images/15-ShapesAsMaterial/MorphSteps.jpg" alt="Five panels of a solid orange star turning into a ring with a hole, the star's points retracting and the hole opening from nothing in the middle" width="680">

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

There is no randomness anywhere. The same pair of shapes always morphs the same way, and a fixed frame reproduces exactly. A there-and-back cycle, or a closed chain of morphs, declared as [`loopDuration`](../Core/Sketch.md#loopDuration) exports seamlessly with `--export-loop`.

### Contents

- [Preparing a morph](#preparing)
- [Reading the in-between](#reading)
- [How the matching works](#matching)
- [Tweening geometry](#tweening)

<a name="preparing"></a>

#### Preparing a morph

```swift
ShapeMorph(from: Shape, to: Shape, spacing: Double? = nil)
```

Build it in `setup()` (or whenever the pair changes) and keep the value, because the correspondence work happens here, which keeps the per-frame read cheap. `from` and `to` are stored untouched, and the reads at `0` and `1` return them verbatim.

`spacing` bounds how far apart correspondence points may sit along either outline. Left `nil`, it derives from each outline's own length, taking 1/128 of it. That spreads the added points at matching fractions along both sides of a pair, which suits most shapes. Pass a smaller spacing when a long straight edge must follow a tightly curved partner more faithfully. Extra points are only ever *added* along segments, so every original corner survives. The point count is capped, so a tiny spacing cannot run away.

<a name="reading"></a>

#### Reading the in-between

```swift
morph.shape(at: t) -> Shape
```

`t` runs `0...1` and clamps. `0` and `1` are the exact originals, and everything between is the pointwise blend. Shape the timing outside the read. Pass an [`Easing`](../Helpers/Animation.md) of your phase, `pingPong(over:)` for there-and-back, or a [`Timeline`](../Helpers/Animation.md#timeline)'s progress.

When the two shapes fill by different [winding rules](./Geometry.md), the in-betweens use `from`'s rule up to the halfway mark and `to`'s after it.

<a name="matching"></a>

#### How the matching works

Contours pair up first: closed outlines with closed outlines, open line-work with open line-work. The largest pairs with the largest, measured by enclosed area for closed contours and walked length for open ones. Each remaining contour takes the unused partner whose center sits nearest. Then, per pair:

- Both sides get the same number of points, added along segments longer than the spacing, so corners are kept, not resampled away.
- Windings are lined up (a clockwise outline never blends toward a counter-clockwise one, which would fold through itself halfway).
- For closed contours, the starting point of one ring rotates to wherever the total travel is shortest. For open ones, the direction flips if that travels less.

A contour with no partner scales down to its own center, or grows out of one. Shapes with different contour counts cross-fade instead of popping. That includes holes, so morph a disc into a donut and the hole grows from the middle.

Two limits worth knowing. A closed contour never pairs with an open one, and the leftover rule above handles the mix. The correspondence is by outline distance rather than by meaning, so morphing one hand into another does not know a thumb from a finger. When a morph reads muddled, add a `spacing`, or split the shape and morph the parts separately.

<a name="tweening"></a>

#### Tweening geometry

`Shape` and `Contour` are `Tweenable`, so a [`Timeline`](../Helpers/Animation.md#timeline) sequences geometry like any other value:

```swift
let tween = Timeline(star).to(blob, in: 2).hold(for: 1).to(star, in: 2)
// each frame:
drawShape(tween.value)
```

The conveniences rebuild the correspondence on each read, which is fine for simple outlines. When the shapes are heavy (a dense SVG, a glyph), hold a `ShapeMorph` and read `shape(at:)` instead. The same trade holds for the one-off form:

```swift
star.morphed(toward: blob, 0.5)            // one blended shape, no held state
star.morphed(toward: blob, 0.5, spacing: 4)
```

---

Related: [`Geometry`](./Geometry.md) (`Shape`, `Contour`, winding), [`SVG import`](./SVG.md) (outlines worth morphing), [`Animation`](../Helpers/Animation.md) (`Timeline`, `Easing`), [perfect loops](../Output/Export.md#perfect-loops). Example: [`Examples/Motion/Morphing`](../../Examples/Motion/Morphing/Sketch.swift).
