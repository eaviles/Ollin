#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Celtic knotwork`</sup>

---

## Celtic knotwork

This is the [kolam line](./Kolam.md) given width, plus a rule about which cord passes over which.

A plait is one line, or a few lines, running at 45 degrees between the dots of a field. The edge of the field turns the line, and so does any wall placed between two dots. Wherever two passes meet, one goes over and the other goes under. The whole design holds together because that choice **alternates**. Follow any cord and it goes over, under, over, under, the whole way around. A knot drawn that way is called alternating, and that is what the eye reads as woven rather than as a heap of lines.

```
  the two rules, and nothing else:

  over/under alternates along every cord  ->  it reads as woven
  a wall turns the line where it stands   ->  the plait becomes a knot
```

The bands come back **already broken where they dive under**, so stroking them draws the weave. You have nothing to mask, and there is no draw order to get right.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/07-Tiles/KnotworkWeave-dark.jpg">
  <img src="../../Guide/Images/07-Tiles/KnotworkWeave.jpg" alt="Three dark panels. A thin gold lattice of crossing diagonal lines; the same lattice as thick gold bands outlined in near-black, woven over and under; and the same weave with the middle reorganized into a knot by two pairs of walls" width="680">
</picture>

### Contents

- [knotwork](#knotwork)
- [drawKnotwork](#drawKnotwork)
- [The faces](#faces)
- [Walls](#walls)

<a name="knotwork"></a>

#### knotwork

```swift
knotwork(in bounds: Rectangle? = nil,
         columns: Int, rows: Int,
         mirrors: [Kolam.Mirror] = []) -> Knotwork
```

This returns a knot woven over a `columns × rows` field of dots that fills `bounds`, which is the whole canvas by default. Nothing here is random, so the same field always weaves the same knot.

```swift
let knot = knotwork(columns: 7, rows: 5)
strokeCap(.round); strokeJoin(.round)
for band in knot.bands(gap: 30) {
    let line = band.smoothed(iterations: 3)
    withState {
        stroke(.black); strokeWeight(22)          // the outline
        drawPolyline(line.points, closed: line.isClosed)
        stroke(.white); strokeWeight(15)          // the cord inside it
        drawPolyline(line.points, closed: line.isClosed)
    }
}
```

The `withState` around each band keeps the second color from becoming the next band's outline. Drawing one band at a time, outline first and then cord, matters too. It lets the next band's outline cut the last one cleanly where it passes over.

<a name="drawKnotwork"></a>

#### drawKnotwork

```swift
drawKnotwork(in bounds: Rectangle? = nil,
             columns: Int, rows: Int,
             mirrors: [Kolam.Mirror] = [],
             weight: Double = 18,
             cordColor: Color = .white,
             rounding: Int = 3)
```

This draws the two-tone band above in one call. The current `stroke` is the outline at `weight`, `cordColor` fills it, and the gap is sized to the band.

<a name="faces"></a>

#### The faces

- **`bands(gap:)`** gives the visible pieces, one open `Contour` per piece, already broken where the cord dives under. `gap` is how much cord is taken out at each dive, in canvas points. Left to itself it is a little over half the distance between two crossings, which suits a band about as wide as that gap. A cord that dives nowhere comes back whole and closed, because a single dot's loop has nothing to cross.
- **`cords`** gives the whole cords, unbroken, one closed `Contour` each. This is the same line work the [kolam](./Kolam.md) gives, so draw it when you do not want the weave.
- **`crossings`** gives the points where two passes meet. A plain field of `rows` by `columns` dots has `2 × rows × columns - rows - columns` of them. That is every point of the field except the ones on the outside edge, where the line turns and only one pass ever arrives. Each wall takes one more away.

<a name="walls"></a>

#### Walls

Walls are `Kolam.Mirror` values, and they work exactly as they do for a [kolam](./Kolam.md#walls). Each one is a short wall between two neighboring dots, and the line turns at it. Walls are what turn a plait into a knot with a shape. A wall joins or splits a cord, and it also takes away the crossing that would have been there.

```swift
let knot = knotwork(columns: 6, rows: 6,
                    mirrors: [.rightOf(column: 2, row: 2), .below(column: 2, row: 2),
                              .rightOf(column: 2, row: 3), .below(column: 3, row: 2)])
```

---

Related: [`Kolam and sona`](./Kolam.md) is the same walk drawn as a single line. For the `Grid`, `Contour`, and shape booleans that the bands use, see [`Geometry`](./Geometry.md). To take the bands to a pen plotter, see [`Fabrication`](../Output/Fabrication.md).
