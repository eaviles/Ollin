#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Truchet tiling`</sup>

---

## Truchet tiling

Put the **same little tile** on every cell of a grid, and **spin each one to a random orientation**. The tile's marks always meet the cell edges at the same points, so the random spins still line up across borders. A wall of identical parts then reads as one flowing, connected pattern. The whole thing costs one tile and one coin flip per cell, which is a cheap way to get a rich, non-repeating design. The layout is reproducible from a [`seed`](../Generators/Random.md#seed).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/07-Tiles/TruchetTiles-dark.jpg">
  <img src="../../Guide/Images/07-Tiles/TruchetTiles.jpg" alt="Two panels of white line work on dark squares: quarter-circle arcs joining into meandering loops, and corner-to-corner diagonals forming a maze" width="680">
</picture>

Two tiles are built in, `.arcs` and `.diagonals`, and each one has two orientations (see [Tile styles](#tiles)). The output is a set of open `Contour`s, which are the line-work. You can stroke them, hatch them, feed them to the [shape booleans](./Geometry.md), or export them to SVG for a pen plotter.

### Contents

- [truchet](#truchet)
- [drawTruchet](#drawTruchet)
- [Tile styles](#tiles)
- [Single tiles](#single-tiles)

<a name="truchet"></a>

#### truchet

```swift
truchet(in bounds: Rectangle? = nil,
        columns: Int, rows: Int,
        tile: Truchet.Tile = .arcs) -> [Contour]
```

Returns the line-work of a Truchet tiling over a `columns × rows` grid of `bounds`, which is the whole canvas by default. Each cell gets one tile, spun to a random orientation drawn from the seeded `random`, so the same seed always lays out the same pattern. The result is open `Contour`s: two quarter-arcs per cell for `.arcs`, and one diagonal per cell for `.diagonals`.

Iterate the contours to color each one, so a flow of hue travels along the connected curves. You can also feed them to the booleans, to hatching, or to SVG export:

```swift
seed(3)
noFill(); strokeCap(.round); strokeWeight(11)
for arc in truchet(columns: 12, rows: 12, tile: .arcs) {
    let mid = arc.midpoint
    stroke(Color.mix(.teal, .orange, (signedNoise(mid.x * 0.003, mid.y * 0.003, time) + 1) * 0.5))
    drawPolyline(arc.points)
}
```

Use square cells to keep the arcs circular, so match `columns` to `rows` on a square canvas. On a non-square grid the arcs become elliptical, but they still connect. See the `Truchet` example.

<a name="drawTruchet"></a>

#### drawTruchet

```swift
drawTruchet(in bounds: Rectangle? = nil,
            columns: Int, rows: Int,
            tile: Truchet.Tile = .arcs)
```

Draws a Truchet tiling with the current `stroke`, in one call. To color each tile separately, iterate the contours that `truchet(…)` returns instead.

```swift
seed(1)
stroke(.white); strokeWeight(3); strokeCap(.round)
drawTruchet(columns: 20, rows: 20, tile: .diagonals)   // a maze
```

<a name="tiles"></a>

#### Tile styles

`Truchet.Tile` picks the tile:

- **`.arcs`** joins each cell's edge midpoints with two quarter-circles. The arcs meet across borders and form smooth meandering loops and rings. This is the classic Truchet look, after Cyril Stanley Smith.
- **`.diagonals`** draws one corner-to-corner diagonal per cell (`╲` or `╱`), so the cells read as a maze of connected corridors.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/07-Tiles/TruchetJoins-dark.jpg">
  <img src="../../Guide/Images/07-Tiles/TruchetJoins.jpg" alt="The arc tile's two spins, with dots marking where arcs end at edge midpoints; beside them, six randomly spun tiles whose arcs meet exactly at every shared edge midpoint" width="680">
</picture>

<a name="single-tiles"></a>

#### Single tiles

```swift
Truchet.contours(in rect: Rectangle,
                 tile: Truchet.Tile = .arcs,
                 flipped: Bool = false) -> [Contour]
```

Returns one tile's line-work in `rect`, at a spin you choose instead of a random one. `flipped: false` gives the `╲`-leaning orientation, and `true` gives the `╱`. This is the building block that the grid form places in each cell. Use it to hand-author a layout, such as weighted spins, symmetric arrangements, or one specific pattern. You can also use it to draw a single tile on its own:

```swift
// A tiling whose spins follow a checkerboard instead of a coin flip.
for cell in grid(columns: 12, rows: 12).cells {
    for arc in Truchet.contours(in: cell.frame, flipped: (cell.column + cell.row) % 2 == 0) {
        drawPolyline(arc.points)
    }
}
```

---

Related: [`Voronoi & Delaunay`](./Voronoi.md) (another way to turn points into vector pattern), [`Blue noise`](../Generators/BlueNoise.md) (even scatter), [`Geometry`](./Geometry.md) (the `Grid`, `Contour`, and shape booleans this tiling is built on).
