#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Truchet tiling`</sup>

---

## Truchet tiling

Put the **same little tile** on every cell of a grid, but **spin each one to a random orientation**. Because the tile's marks always meet the cell edges at the same points, the random spins line up across borders, and a wall of identical parts reads as one flowing, connected pattern. It's the cheapest way to make a rich, non-repeating design: one tile, a coin flip per cell, all reproducible from a [`seed`](../Generators/Random.md#seed).

Two tiles are built in, each with two orientations:

```
  .arcs  (two quarter-circles              .diagonals  (one corner-to-corner
          joining edge midpoints)                       line)

   ╭─  ─╮        ╮  ╭                          ╲              ╱
   │    │   or   │  │                           ╲     or     ╱
   ╰─  ─╯        ╯  ╰                            ╲          ╱

  arcs meet across borders into           diagonals read as a maze of
  smooth loops and rings                  corridors (the one-line-program look)
```

The output is a set of open `Contour`s (the line-work), so it strokes, hatches, feeds the [shape booleans](./Geometry.md), or exports to SVG for a pen plotter.

### Contents

- [truchet](#truchet)
- [drawTruchet](#drawTruchet)
- [Tile styles](#tiles)

<a name="truchet"></a>

#### truchet

```swift
truchet(in bounds: Rectangle? = nil,
        columns: Int, rows: Int,
        tile: Truchet.Tile = .arcs) -> [Contour]
```

The line-work of a Truchet tiling over a `columns × rows` grid of `bounds` (the whole canvas by default). Each cell gets one tile spun to a random orientation drawn from the seeded `random`, so the same seed always lays out the same pattern. Returns open `Contour`s: two quarter-arcs per cell for `.arcs`, one diagonal per cell for `.diagonals`.

Iterate the contours to color each one (a flow of hue travels along the connected curves), or feed them to the booleans, hatching, or SVG export:

```swift
seed(3)
noFill(); strokeCap(.round); strokeWeight(11)
for arc in truchet(columns: 12, rows: 12, tile: .arcs) {
    let mid = arc.points[arc.points.count / 2]
    stroke(Color.mix(.teal, .orange, t: (signedNoise(mid.x * 0.003, mid.y * 0.003, time) + 1) * 0.5))
    drawPolyline(arc.points)
}
```

Use square cells (match `columns` to `rows` on a square canvas) so the arcs stay circular; on a non-square grid the arcs become elliptical but still connect. See the `Truchet` example.

<a name="drawTruchet"></a>

#### drawTruchet

```swift
drawTruchet(in bounds: Rectangle? = nil,
            columns: Int, rows: Int,
            tile: Truchet.Tile = .arcs)
```

Draw a Truchet tiling with the current `stroke`, in one call. For per-tile color, iterate the `truchet(…)` value's contours instead.

```swift
seed(1)
stroke(.white); strokeWeight(3); strokeCap(.round)
drawTruchet(columns: 20, rows: 20, tile: .diagonals)   // a maze
```

<a name="tiles"></a>

#### Tile styles

`Truchet.Tile` picks the tile:

- **`.arcs`** joins each cell's edge midpoints with two quarter-circles, so the arcs meet across borders into smooth meandering loops and rings (the classic Truchet look, after Cyril Stanley Smith).
- **`.diagonals`** draws one corner-to-corner diagonal per cell (`╲` or `╱`), so the cells read as a maze of connected corridors.

---

Related: [`Voronoi & Delaunay`](./Voronoi.md) (another way points become vector pattern), [`Blue noise`](../Generators/BlueNoise.md) (even scatter), [`Geometry`](./Geometry.md) (the `Grid`, `Contour`, and shape booleans the tiling rides on).
