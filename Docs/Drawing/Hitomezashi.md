#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Hitomezashi stitching`</sup>

---

## Hitomezashi stitching

The one-stitch sashiko pattern. Every line of a grid carries a row of **unit dashes** over alternating cells. **One bit per line** decides whether its dashes start on the edge or one cell in (the phase of that alternation). Neighboring lines shift against each other, so the dashes join at the grid's crossings into steps, staircases, and closed loops. A handful of coin flips reads as a woven cloth. The whole design *is* those bits: one per horizontal line, one per vertical line, all reproducible from a [`seed`](../Generators/Random.md#seed).

One design has **two faces**. The `stitches` are the line-work, one open two-point `Contour` per dash. They stroke, hatch, feed the [shape booleans](./Geometry.md), or export to SVG for a pen plotter. The `parities` two-color the cells. Every hitomezashi design splits the cloth into regions that exactly two tones can fill, and `parities` is that coloring.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/07-Tiles/HitomezashiFaces-dark.jpg">
  <img src="../../Guide/Images/07-Tiles/HitomezashiFaces.jpg" alt="Two dark panels: cream dashes joining into stepped loops on indigo cloth, and the same design with its regions filled in two blues, every tone boundary sitting under a stitch" width="680">
</picture>

### Contents

- [hitomezashi](#hitomezashi)
- [drawHitomezashi](#drawHitomezashi)
- [The two faces](#faces)
- [Explicit bits](#bits)

<a name="hitomezashi"></a>

#### hitomezashi

```swift
hitomezashi(in bounds: Rectangle? = nil,
            columns: Int, rows: Int,
            probability: Double = 0.5) -> Hitomezashi
```

A stitch design over a `columns × rows` grid of `bounds` (the whole canvas by default). Every line's bit is flipped by the seeded `random` with `probability`, so the same seed always stitches the same design. At `0.5` the classic balanced weave; biased toward 0 or 1 the design drifts into long diagonal staircases.

```swift
seed(5)
let design = hitomezashi(columns: 24, rows: 24)
stroke(.white); strokeWeight(4); strokeCap(.round)
for dash in design.stitches { drawPolyline(dash.points) }
```

<a name="drawHitomezashi"></a>

#### drawHitomezashi

```swift
drawHitomezashi(in bounds: Rectangle? = nil,
                columns: Int, rows: Int,
                probability: Double = 0.5)
```

Draw a stitch design with the current `stroke`, in one call. For the two-tone fill or per-stitch color, hold the `hitomezashi(…)` value and draw its faces yourself.

<a name="faces"></a>

#### The two faces

```swift
design.stitches   // [Contour], one open two-point contour per dash
design.parities   // [Bool], row-major, zips with design.grid.cells
```

`stitches` is the thread. On any one line, dashes cover alternating cells, so two stitches on the same line never touch. The meetings at the crossings are the design.

`parities` is the cloth. Two side-by-side cells get different values exactly when a stitch separates them, so filling by parity paints the design's regions in two tones with no seams:

```swift
let design = hitomezashi(columns: 24, rows: 24)
for (cell, tone) in zip(design.grid.cells, design.parities) {
    fill(tone ? Color(hex: 0x2C4A7F) : Color(hex: 0x18264A))
    drawRect(cell.frame)
}
```

Draw the fill first and the stitches over it and every tone boundary lands exactly under a stitch. See the `Hitomezashi` example.

<a name="bits"></a>

#### Explicit bits

```swift
Hitomezashi(grid: Grid,
            rowBits: [Bool], columnBits: [Bool])
```

The building block under the sugar, for hand-authored or encoded designs. `rowBits` is one bit per horizontal line, top to bottom: `rows + 1` lines. `columnBits` is one per vertical line, left to right: `columns + 1`. **Shorter arrays repeat**, so a small motif tiles a large cloth. An empty array reads as all `false`. A favorite encoding turns a word into bits, a vowel as a 1, so a name becomes a design.

```swift
// A woven twill from a two-bit motif on both axes.
let design = Hitomezashi(grid: Grid(in: bounds, columns: 30, rows: 30),
                         rowBits: [true, false], columnBits: [false, false, true])
```

---

Related: [`Truchet tiling`](./Truchet.md) is the other one-bit-per-element pattern; [`Geometry`](./Geometry.md) covers the `Grid` and `Contour` the stitching rides on; [`Tiling`](./Tiling.md) has the hex and triangle grids.
