#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Kolam and sona`</sup>

---

## Kolam and sona

One line, launched between a field of dots at 45 degrees. It runs straight until it meets the edge of the field, turns, and carries on, and it always comes back to where it started. The drawing is the path it took.

The tradition belongs to more than one place. In south India a **kolam** is chalked on the doorstep at dawn around a grid of pulli (dots). In Angola a **sona** is drawn in the sand with one finger while the story that goes with it is told. The mathematics under both is the same object, and it is exact: over a plain field the line closes into **gcd(rows, columns)** loops. A 7 by 5 field is one unbroken line. A 6 by 4 field is two.

```
  dots:      ·   ·   ·        the line never touches a dot; it passes
                              between them and turns at the edge
      \  /\  /\  /\  /
       \/  \/  \/  \/         7 by 5 dots  ->  1 loop   (gcd 7,5 = 1)
       /\  /\  /\  /\         6 by 4 dots  ->  2 loops  (gcd 6,4 = 2)
      /  \/  \/  \/  \        5 by 5 dots  ->  5 loops
```

A **wall** placed between two neighboring dots turns the line there as well. Each wall inside the field either cuts one loop in two or joins two into one, never more, so walls are how a drawing is steered toward a single line. That is how the figures of a sona are built.

The line-work is geometry, not a picture: `loops` hands back closed `Contour`s, so it strokes, feeds the [shape booleans](./Geometry.md), hatches, and exports to SVG for a pen plotter. A kolam is drawn with square corners by this walk; [`Contour.smoothed(_:)`](./Curves.md) rounds them into the drawn form.

### Contents

- [kolam](#kolam)
- [drawKolam](#drawKolam)
- [The two faces](#faces)
- [Walls](#walls)

<a name="kolam"></a>

#### kolam

```swift
kolam(in bounds: Rectangle? = nil,
      columns: Int, rows: Int,
      mirrors: [Kolam.Mirror] = []) -> Kolam
```

A kolam over a `columns × rows` field of dots filling `bounds` (the whole canvas by default). Nothing here is random, so no seed is involved: the same field always draws the same line.

```swift
let design = kolam(columns: 7, rows: 5)
noFill(); stroke(.white); strokeWeight(6); strokeJoin(.round)
for loop in design.loops { drawPolyline(loop.smoothed(iterations: 3).points, closed: true) }
```

<a name="drawKolam"></a>

#### drawKolam

```swift
drawKolam(in bounds: Rectangle? = nil,
          columns: Int, rows: Int,
          mirrors: [Kolam.Mirror] = [],
          rounding: Int = 2)
```

Draw the line-work with the current `stroke`, rounded by `rounding` passes of corner cutting (2 is the drawn look, 0 the square lattice path). The dots are not drawn: a kolam shows them and a sona does not, so that choice stays yours.

<a name="faces"></a>

#### The two faces

- **`loops`** one closed `Contour` per loop, in canvas coordinates. However the walls are placed, the loops always hold `4 × rows × columns` segments between them: four in every cell, one against each of its four sides.
- **`dots`** the field itself, row-major, for marking the pulli a kolam is drawn around.
- **`loopCount`** how many closed loops the line makes. One is the single unbroken line, which is what most traditional drawings are after.

The `grid` the design was built on is kept, so `design.grid.cells` and `design.grid.bounds` are there when a piece needs to place something else against the same field. The grid's `gutter` does not apply: the line needs an even field to bounce in.

<a name="walls"></a>

#### Walls

A `Kolam.Mirror` is a short wall between two neighboring dots, named after the dot it sits against, counting from the top-left dot:

```swift
Kolam.Mirror.rightOf(column: 2, row: 1)   // standing between this dot and its right neighbor
Kolam.Mirror.below(column: 3, row: 2)     // lying between this dot and the one below
```

```swift
let design = kolam(columns: 7, rows: 5,
                   mirrors: [.rightOf(column: 2, row: 1), .below(column: 3, row: 2)])
```

A wall asked for on the outside edge is dropped rather than counted, since the edge already turns the line. Every other wall moves `loopCount` by exactly one, up or down.

---

Related: [`Hitomezashi stitching`](./Hitomezashi.md) is the other grid pattern whose whole design is a handful of bits; [`Geometry`](./Geometry.md) covers the `Grid`, `Contour`, and shape booleans the line-work rides on; [`Curves`](./Curves.md) has the corner cutting that rounds it; [`Fabrication`](../Output/Fabrication.md) takes it to a pen plotter.
