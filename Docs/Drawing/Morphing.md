#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Shape morphing`</sup>

---

## Shape morphing

Tween one `Shape` into another. A `ShapeMorph` works out once which point of the first outline becomes which point of the second. After that, reading the in-between at any fraction is a straight blend. Every in-between is a vector `Shape`, so you can fill it, stroke it, run it through the [booleans](./Geometry.md), [hatch it](../Output/Export.md#hatching-solid-fills-for-a-pen-plotter), or export it. That is why a morph runs on a pen plotter instead of being a pixel effect.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/MorphSteps-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/MorphSteps.jpg" alt="Five panels of a solid orange star turning into a ring with a hole, the star's points retracting and the hole opening from nothing in the middle" width="680">
</picture>

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

Nothing in a morph is random. The same pair of shapes always morphs the same way, so a given frame reproduces exactly. Declare a there-and-back cycle, or a closed chain of morphs, as [`loopDuration`](../Core/Sketch.md#loopDuration), and it exports seamlessly with `--export-loop`.

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

Build it in `setup()`, or whenever the pair changes, and keep the value. The correspondence work happens once, right there, which is what keeps the per-frame read cheap. `from` and `to` are stored untouched, so a read at `0` or `1` gives them back unchanged.

`spacing` limits how far apart correspondence points may sit along either outline. Left `nil`, it comes from each outline's own length, taking 1/128 of it. That spreads the added points at matching fractions along both sides of a pair, which suits most shapes. Pass a smaller spacing when a long straight edge has to follow a tightly curved partner more closely. Extra points are only ever *added* along segments, so every original corner survives. The point count is capped, so a tiny spacing cannot run away.

<a name="reading"></a>

#### Reading the in-between

```swift
morph.shape(at: t) -> Shape
```

`t` runs `0...1` and clamps. `0` and `1` give back the exact originals, and every value between them gives the pointwise blend. Set the timing outside the read. You can pass an [`Easing`](../Helpers/Animation.md) of your phase, `pingPong(over:)` for there-and-back, or a [`Timeline`](../Helpers/Animation.md#timeline)'s progress.

When the two shapes fill by different [winding rules](./Geometry.md), the in-betweens use `from`'s rule up to the halfway mark and `to`'s after it.

<a name="matching"></a>

#### How the matching works

Contours pair up first, closed outlines with closed outlines and open line-work with open line-work. The largest pairs with the largest, measured by enclosed area for closed contours and by walked length for open ones. Each remaining contour takes the unused partner whose center is nearest. Each pair is then prepared like this:

- Both sides get the same number of points. The added points go on segments longer than the spacing, so corners are kept rather than resampled away.
- Windings are lined up, so a clockwise outline never blends toward a counter-clockwise one. That pairing would fold the shape through itself halfway.
- For a closed contour, the starting point of one ring rotates to wherever the total travel is shortest. For an open contour, the direction flips if that travels less.

A contour with no partner scales down to its own center, or grows out of it. Shapes with different contour counts cross-fade instead of popping. Holes count as contours here, so when you morph a disc into a donut the hole grows from the middle.

There are two limits worth knowing. First, a closed contour never pairs with an open one, so the leftover rule above handles the mix. Second, the correspondence follows outline distance rather than meaning, so a morph from one hand to another does not know a thumb from a finger. When a morph looks muddled, add a `spacing`, or split the shape and morph the parts separately.

<a name="tweening"></a>

#### Tweening geometry

`Shape` and `Contour` are `Tweenable`, so a [`Timeline`](../Helpers/Animation.md#timeline) sequences geometry like any other value:

```swift
let tween = Timeline(star).to(blob, in: 2).hold(for: 1).to(star, in: 2)
// each frame:
drawShape(tween.value)
```

These conveniences rebuild the correspondence on every read, which is fine for simple outlines. When the shapes are heavy, such as a dense SVG or a glyph, hold a `ShapeMorph` and read `shape(at:)` instead. The one-off form below rebuilds it on every call in the same way:

```swift
star.morphed(toward: blob, 0.5)            // one blended shape, no held state
star.morphed(toward: blob, 0.5, spacing: 4)
```

---

Related: [`Geometry`](./Geometry.md) (`Shape`, `Contour`, winding), [`SVG import`](./SVG.md) (outlines worth morphing), [`Animation`](../Helpers/Animation.md) (`Timeline`, `Easing`), [perfect loops](../Output/Export.md#perfect-loops). Example: [`Examples/Motion/Morphing`](../../Examples/Motion/Morphing/Sketch.swift).
