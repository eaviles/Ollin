#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Parquet deformations`</sup>

---

## Parquet deformations

A tiling whose **tile changes shape as you read across it**. Every piece still meets its neighbors exactly. There are no gaps, no overlaps, and nothing to line up by hand. Yet a square at one edge of the sheet has become an interlocking key at the other. Between them runs a line of shapes, each only a little unlike the one beside it. The pattern is the *change*, not the motif.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/07-Tiles/ParquetRun-dark.jpg">
  <img src="../../Guide/Images/07-Tiles/ParquetRun.jpg" alt="A sheet of interlocking tiles running from plain squares on the left to notched keys on the right, with five of the tiles lifted out below and shown on their own" width="680">
</picture>

The whole thing rests on one decision. **The geometry lives on the edges of the lattice, not on the tiles.** A tile is never drawn and then fitted to its neighbors. It is read off the four edges around it. The tile on the far side of any edge reads that same curve backwards. So the tiling holds however far the shape drifts, and the drift is free to be anything you can write down.

The output is typed geometry: closed `Contour`s for the tiles, and open ones for the line work. So it feeds stroking, filling, the [shape booleans](./Geometry.md), hatching, and SVG export for a pen plotter.

### Contents

- [parquetDeformation](#parquetDeformation)
- [drawParquetDeformation](#drawParquetDeformation)
- [Profiles](#profiles)
- [Sweeps, and driving the run yourself](#sweeps)
- [The two faces](#faces)

<a name="parquetDeformation"></a>

#### parquetDeformation

```swift
parquetDeformation(in bounds: Rectangle? = nil,
                   columns: Int, rows: Int,
                   from start: ParquetDeformation.Profile,
                   to end: ParquetDeformation.Profile,
                   sweep: ParquetDeformation.Sweep = .horizontal) -> ParquetDeformation
```

A sheet of `columns × rows` tiles over `bounds` (the whole canvas by default), running from the `start` profile to the `end` profile across it.

```swift
let sheet = parquetDeformation(columns: 14, rows: 14,
                               from: .straight, to: .tooth(depth: 0.3))
stroke(.black); strokeWeight(2)
for edge in sheet.edges { drawPolyline(edge.points, closed: false) }
```

Use square cells when the profiles should read the same in both directions. A profile's sideways offsets are fractions of *its own edge's* length. So on a lattice of tall cells the vertical edges deform further than the horizontal ones. Matching `columns` to `rows` on a square canvas keeps the two equal.

The tiles on the sheet's rim carry their deformed outer edges, so the sheet's own boundary is fringed rather than straight. For a clean border, intersect the tiles with the bounds through the [shape booleans](./Geometry.md).

<a name="drawParquetDeformation"></a>

#### drawParquetDeformation

```swift
drawParquetDeformation(in bounds: Rectangle? = nil,
                       columns: Int, rows: Int,
                       from start: ParquetDeformation.Profile,
                       to end: ParquetDeformation.Profile,
                       sweep: ParquetDeformation.Sweep = .horizontal)
```

Stroke the line work in one call, with the current `stroke`. For filled tiles or per-tile color, hold the `parquetDeformation(…)` value and draw its faces yourself.

<a name="profiles"></a>

#### Profiles

A `Profile` is the shape of **one lattice edge**, given in that edge's own frame. `x` runs from `0` at one lattice corner to `1` at the other. `y` is the sideways offset, as a fraction of the edge's length. Every profile starts at `(0, 0)` and ends at `(1, 0)`. That is what holds the lattice's corners in place while everything between them moves.

| Profile | What it is |
|---|---|
| `.straight` | A plain segment, the undeformed lattice. |
| `.tooth(depth:width:)` | A square tooth of `depth` standing on the middle `width` of the edge, the classic interlocking key. A negative depth cuts a notch instead. `.tooth(depth:)` alone stands it on the middle half. |
| `.zigzag(count:depth:)` | `count` alternating peaks of `depth`, the first to the positive side. `.zigzag(depth:)` gives two. |
| `.wave(count:depth:)` | `count` full sine waves of amplitude `depth`. `.wave(depth:)` gives one. |
| `.bump(depth:)` | A circular arc bulging `depth` to one side at its middle. |
| `.custom([Vector2])` | A profile written out by hand. The ends are pinned to `(0, 0)` and `(1, 0)` however they were given, so only the shape between them counts. |

A profile is a polyline and may double back on itself. A tooth's vertical sides are as legal as a wave's slopes.

**The blend is exact at both ends.** Each edge blends `start` into `end` by the amount read at its midpoint. Both profiles are reparameterized by arc length, and the blend's vertices sit at the *union* of the two profiles' vertices. Between any two of those both inputs are straight, so their blend is straight too. The result is the exact interpolation rather than a sampling of it. That is why a square tooth arrives with square corners rather than rounded ones.

<a name="sweeps"></a>

#### Sweeps, and driving the run yourself

A `Sweep` says which way the run goes. `.horizontal` is the default, with `start` at the left. `.vertical` runs down the sheet, `.diagonal` puts `start` at the top-left corner, and `.radial` puts it at the center with `end` at the corners.

The general form takes a closure instead. It is handed a point in canvas coordinates, and it answers how far along the run that point sits, `0`…`1`. Anything outside is clamped. This is where the interesting sheets come from, because the drift can follow noise, an image's tone, a distance, or a moving front:

```swift
let field = bounds.inset(by: .all(70))
let front = 0.5 + sin(time * 0.25) * 0.55
let sheet = ParquetDeformation(grid: Grid(in: field, columns: 15, rows: 15),
                               from: .wave(depth: 0.22),
                               to: .tooth(depth: 0.3, width: 0.42)) { point in
    smoothstep(front - 0.28, front + 0.28, (point.x - field.x) / field.width)
}
```

See the `ParquetDeformation` example, which is that sheet with the front sliding back and forth.

<a name="faces"></a>

#### The two faces

`tiles` is the interlocking pieces, row-major so they zip with `grid.cells`. Each `Tile` carries its `column` and `row`, the `amount` it was built at, the `center` of its lattice cell, its closed `contour`, and that contour as a fillable `shape`. The `amount` runs `0`…`1`, so it colors the drift directly. The outline is walked clockwise from the tile's top-left lattice corner.

```swift
for tile in sheet.tiles {
    fill(Color.mix(.teal, .orange, tile.amount))
    drawShape(tile.shape)
}
```

`edges` is the line work: every lattice edge exactly **once**, as an open `Contour`. Stroking the tiles instead would draw every interior edge twice. That shows as a doubled line under a translucent stroke, and it costs a pen plotter a second pass over each one. The horizontal edges come first, top line to bottom and left to right within a line, then the vertical ones.

### Where this comes from

The form is William S. Huff's. He set it as a design exercise in his basic-design studio from the 1960s on. Douglas Hofstadter gave it a wider audience in his *Scientific American* column of July 1983, collected in *Metamagical Themas*. The computational treatment follows Craig S. Kaplan's Bridges papers, which read a deformation as a curve interpolated across a tiling rather than as a drawing made by hand. Implemented from the published technique, credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

### Go deeper

- [Tiling & layout](./Tiling.md) - hex and triangle grids, recursive subdivision, mazes
- [Truchet tiling](./Truchet.md) - one tile, spun at random, that still connects
- [Aperiodic tilings](./AperiodicTilings.md) - Penrose, girih, Wang tiles, the spectre
- [Geometry](./Geometry.md) - `Contour`, `Shape`, and the shape booleans
- [SVG export](./SVG.md) - taking the line work to a pen plotter
