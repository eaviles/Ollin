#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Hitomezashi stitching`</sup>

---

## Hitomezashi stitching

Hitomezashi is the one-stitch sashiko pattern. Every line of a grid carries a row of **unit dashes** over alternating cells. Each line has **one bit** of its own, and that bit sets the phase of the alternation. It decides whether the dashes on that line start on the edge or one cell in. Neighboring lines shift against each other, which makes the dashes join at the grid's crossings into steps, staircases, and closed loops. That is how a handful of coin flips reads as a woven cloth. The whole design *is* those bits, one per horizontal line and one per vertical line, so a [`seed`](../Generators/Random.md#seed) reproduces all of it.

One design has **two faces**. The `stitches` are the line-work, one open two-point `Contour` per dash. You can stroke them, hatch them, feed them to the [shape booleans](./Geometry.md), or export them to SVG for a pen plotter. The `parities` two-color the cells instead. Every hitomezashi design splits the cloth into regions that exactly two tones can fill, and `parities` is that coloring.

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

A stitch design over a `columns × rows` grid of `bounds` (the whole canvas by default). The seeded `random` flips every line's bit with `probability`, so the same seed always stitches the same design. At `0.5` you get the classic balanced weave. Biased toward 0 or 1, the design drifts into long diagonal staircases.

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

Draw a stitch design with the current `stroke`, in one call. For the two-tone fill or for per-stitch color, keep the `hitomezashi(…)` value instead and draw its faces yourself.

<a name="faces"></a>

#### The two faces

```swift
design.stitches   // [Contour], one open two-point contour per dash
design.parities   // [Bool], row-major, zips with design.grid.cells
```

`stitches` is the thread. On any one line the dashes cover alternating cells, so two stitches on the same line never touch. The design is what happens where they meet at the crossings.

`parities` is the cloth. Two side-by-side cells get different values exactly when a stitch separates them. Filling by parity therefore paints the design's regions in two tones with no seams:

```swift
let design = hitomezashi(columns: 24, rows: 24)
for (cell, tone) in zip(design.grid.cells, design.parities) {
    fill(tone ? Color(hex: 0x2C4A7F) : Color(hex: 0x18264A))
    drawRect(cell.frame)
}
```

Draw the fill first and the stitches over it, and every tone boundary lands exactly under a stitch. See the `Hitomezashi` example.

<a name="bits"></a>

#### Explicit bits

```swift
Hitomezashi(grid: Grid,
            rowBits: [Bool], columnBits: [Bool])
```

The building block under the two calls above, for hand-authored or encoded designs. `rowBits` is one bit per horizontal line, top to bottom, so it holds `rows + 1` bits. `columnBits` is one bit per vertical line, left to right, so it holds `columns + 1`. **Shorter arrays repeat**, so a small motif tiles a large cloth. An empty array reads as all `false`. A favorite encoding turns a word into bits, taking each vowel as a 1, so a name becomes a design.

```swift
// A woven twill from a two-bit motif on both axes.
let design = Hitomezashi(grid: Grid(in: bounds, columns: 30, rows: 30),
                         rowBits: [true, false], columnBits: [false, false, true])
```

---

Related: [`Truchet tiling`](./Truchet.md) is the other one-bit-per-element pattern. For the `Grid` and the `Contour` the stitching is built from, see [`Geometry`](./Geometry.md). The hex and triangle grids are in [`Tiling`](./Tiling.md).
