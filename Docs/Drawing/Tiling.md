#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Tiling & layout`</sup>

---

## Tiling & layout

Beyond the square grid there are several more ways to divide a canvas: **hexagon** and **triangle** grids (the other two regular tilings, as `Grid` siblings), **recursive subdivision** (uneven panels, the grid-painting look), **mazes** (perfect labyrinths as clean line-work), and the **Apollonian gasket** (a circle filled with an endless foam of kissing circles). They're all geometry rather than draw calls, since each hands back typed cells, contours, or circles that feed the same drawing, boolean, hatching, and SVG paths as everything else, and everything random rides the seeded `random`, so a [`seed`](../Generators/Random.md#seed) reproduces the layout. The tilings that never repeat (Penrose, Wang, girih star patterns, the spectre) have [their own page](./AperiodicTilings.md).

<img src="../../Guide/Images/06-GridsAndRepetition/OtherGrids.jpg" alt="Four panels: a honeycomb tinted by ring distance from one cell, a field of alternating up and down triangles, a rectangle split recursively into unequal panels, and a carved maze" width="680">

### Contents

- [hexGrid / HexGrid](#hexGrid)
- [triangleGrid / TriangleGrid](#triangleGrid)
- [subdivide / Subdivision](#subdivide)
- [maze / Maze](#maze)
- [apollonianGasket](#apollonianGasket)

<a name="hexGrid"></a>

#### hexGrid / HexGrid

```swift
hexGrid(columns: Int, rows: Int,
        orientation: HexGrid.Orientation = .pointy,
        padding: Insets = .zero, gutter: Double = 0) -> HexGrid
```

A `columns × rows` honeycomb over the canvas (or `HexGrid(in: someRectangle, …)` for a sub-region). Hexagons can't stretch the way a `Grid` cell can, so the block keeps its true aspect, sized to fit the padded bounds and centered. `orientation` picks pointy-top (`.pointy`, rows shift by half a hex) or flat-top (`.flat`, columns shift), and `gutter` opens a gap between neighbors.

Loop over `cells`, where each `HexGrid.Cell` carries its `column`/`row`, its `center`, and its six ready-to-draw `corners` (also available as a `contour`):

```swift
let hexes = hexGrid(columns: 12, rows: 10, padding: 40, gutter: 6)
for cell in hexes.cells {
    fill(Color(hue: Double(cell.row) / 10, saturation: 0.5, brightness: 0.9))
    drawPolygon(cell.corners)
}
```

What makes a hex grid worth the trade is the *hex-native math*, and every cell carries the axial coordinates (`q`, `r`) it runs on:

- `distance(from:to:)` counts neighbor steps, so equal distances make true concentric rings (the honeycomb falloff square grids can't fake).
- `neighbors(of:)` is the up-to-six adjacent cells, and `ring(around:radius:)` walks the cells at an exact distance.
- `cell(at: point)` is exact hex picking (mouse to hexagon in one call), and `cell(q:r:)` looks up by axial address.

```swift
let focus = hexes.cell(at: Vector2(mouseX, mouseY)) ?? hexes.cell(column: 6, row: 5)
for cell in hexes.cells {
    let rings = Double(hexes.distance(from: focus, to: cell))
    fill(Color.mix(.teal, .black, t: min(1, rings / 6)))
    drawPolygon(cell.corners)
}
```

See the `Patterns/HexGrid` example (a radiating pulse with mouse picking).

<a name="triangleGrid"></a>

#### triangleGrid / TriangleGrid

```swift
triangleGrid(columns: Int, rows: Int,
             padding: Insets = .zero, gutter: Double = 0) -> TriangleGrid
```

This is the third regular tiling, rows of equilateral triangles alternating up- and down-pointing (cell `(column, row)` points up when `column + row` is even). `columns` counts triangles per row, and each advances half an edge, so neighbors share alternating edges. Like the hex grid, the block keeps its true shape and centers in the padded bounds, and `gutter` shrinks each triangle toward its center so neighbors part evenly.

Each `TriangleGrid.Cell` carries `column`/`row`, `pointsUp`, its `center`, and its three `vertices`, and `neighbors(of:)` is the up-to-three cells across each edge:

```swift
for cell in triangleGrid(columns: 21, rows: 10, padding: 40, gutter: 4).cells {
    fill(cell.pointsUp ? .white : .black)
    drawPolygon(cell.vertices)
}
```

See the `Patterns/TriangleGrid` example (a two-palette weave over the parity).

<a name="subdivide"></a>

#### subdivide / Subdivision

```swift
subdivide(in bounds: Rectangle? = nil,
          minSize: Double, maxDepth: Int = 6, chance: Double = 1,
          fraction: ClosedRange<Double> = 0.3...0.7,
          style: Subdivision.Style = .binary) -> [Subdivision.Cell]
```

Recursively split a rectangle into leaf panels. `.binary` (the default) cuts across the longer side at a random fraction drawn from `fraction`, giving the uneven, painterly panels of the classic grid-painting composition. `.quad` cuts into four equal quadrants instead, for the quadtree look. A cell splits while it can and the coin allows: never below `minSize` on either side of a cut, never past `maxDepth`, and (past the root, which always splits when it can) only with probability `chance`, so `chance: 0.7` leaves a mix of large and small panels. Each returned `Subdivision.Cell` is a `frame` plus the `depth` it stopped at, handy for tinting by scale. Driven by the seeded `random`.

```swift
seed(5)
stroke(.black); strokeWeight(8)
for cell in subdivide(minSize: 90, chance: 0.75) {
    fill(random(0, 1) < 0.2 ? randomChoice([.red, .yellow, .blue]) : .white)
    drawRect(cell.frame)
}
```

The typed core is `Subdivision.cells(in:minSize:maxDepth:chance:fraction:style:using:)` over any `RandomNumberGenerator`. See the `Patterns/Subdivision` example.

<a name="maze"></a>

#### maze / Maze

```swift
maze(columns: Int, rows: Int,
     algorithm: Maze.Algorithm = .backtracker) -> Maze
drawMaze(_ maze: Maze, in rect: Rectangle? = nil)
```

Carve a *perfect maze* (every cell reachable, no loops, one path between any two cells) and read it as geometry. The algorithm is a texture knob as much as an algorithmic one:

- **`.backtracker`** (randomized depth-first search): long winding corridors, few dead ends.
- **`.kruskal`** (randomized Kruskal's over union-find): many short dead ends, an even all-over texture.
- **`.wilson`** (loop-erased random walks): a uniform sample over *every* possible maze of the grid, so there's no bias at all.

The geometry reads:

- `walls(in: rect)` is the stroke-ready line-work, with collinear wall segments merged into single long runs (clean for stroking, hatching, and plotter SVG). `drawMaze` strokes it in one call.
- `solution(fromColumn:fromRow:toColumn:toRow:)` is the unique path between two cells, and `longestPath()` is the maze's diameter, the natural entrance-and-exit pair.
- `contour(of:in:)` lays a cell path over a rectangle as a polyline through the cell centers, and `isOpen(_:atColumn:row:)` reads a single passage.

```swift
seed(9)
let m = maze(columns: 24, rows: 24)
stroke(.white); strokeWeight(4); strokeCap(.round)
drawMaze(m)
stroke(.orange)
drawPolyline(m.contour(of: m.longestPath(), in: bounds).points)
```

For the *look* of the classic one-line BASIC maze (random `╱`/`╲` diagonals, corridors implied rather than carved), see [Truchet tiling](./Truchet.md)'s `.diagonals` tile. See the `Patterns/Maze` example (all three algorithms, with the longest path tracing itself through).

<a name="apollonianGasket"></a>

#### apollonianGasket

```swift
apollonianGasket(in circle: Circle, minRadius: Double,
                 rotation: Double = 0, maxCount: Int = 20_000) -> [Circle]
```

Fill a circle with the classic fractal foam. Three equal circles kiss inside the rim, and every three-way gap gets the one circle that exactly touches all three of its parents, down to `minRadius`. The construction is a closed form with no randomness (the Descartes circle theorem pins each new circle), so the same inputs always build the same foam. Circles come back in generation order, so the index doubles as an age for tinting, and `rotation` spins the three seeds around the center.

```swift
let foam = apollonianGasket(in: Circle(center: bounds.center, radius: 480), minRadius: 3)
noStroke()
for (i, c) in foam.enumerated() {
    fill(Colormap.viridis.color(at: Double(i) / Double(foam.count)))
    drawCircle(c)
}
```

See the `Patterns/Apollonian` example.

---

Related: [`Geometry`](./Geometry.md) (the square `Grid` these extend, `Contour`, shape booleans), [`Truchet tiling`](./Truchet.md) (one tile per grid cell at random spins), [`Voronoi & Delaunay`](./Voronoi.md) (cells from scattered points instead of a lattice), [`Classic curves`](./Curves.md) (the closed-form curve canon).
