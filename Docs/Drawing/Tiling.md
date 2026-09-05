#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Tiling & layout`</sup>

---

## Tiling & layout

There are several more ways to divide a canvas beyond the square grid. The **hexagon** and **triangle** grids are the other two regular tilings, built as `Grid` siblings. **Recursive subdivision** gives the uneven panels of a grid painting. A **maze** is a perfect labyrinth drawn as clean line work. The **Apollonian gasket** fills a circle with a foam of circles that touch. All of them are geometry rather than draw calls, because each one returns typed cells, contours, or circles. Those values feed the same drawing, boolean, hatching, and SVG paths as everything else. Everything random uses the seeded `random`, so a [`seed`](../Generators/Random.md#seed) reproduces the layout. The tilings that never repeat (Penrose, Wang, girih star patterns, the spectre) have [their own page](./AperiodicTilings.md).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/06-GridsAndRepetition/OtherGrids-dark.jpg">
  <img src="../../Guide/Images/06-GridsAndRepetition/OtherGrids.jpg" alt="Four panels: a honeycomb tinted by ring distance from one cell, a field of alternating up and down triangles, a rectangle split recursively into unequal panels, and a carved maze" width="680">
</picture>

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

This builds a `columns × rows` honeycomb over the canvas. Use `HexGrid(in: someRectangle, …)` for a sub-region. A hexagon cannot stretch the way a `Grid` cell can, so the block keeps its true aspect ratio. The block is sized to fit the padded bounds and centered in them. `orientation` picks pointy-top or flat-top. With `.pointy`, each row shifts by half a hex. With `.flat`, each column shifts. `gutter` opens a gap between neighbors.

Each `HexGrid.Cell` carries its `column` and `row`, its `center`, and its six `corners`, ready to draw. The corners are also available as a `contour`. Loop over `cells` to draw the grid:

```swift
let hexes = hexGrid(columns: 12, rows: 10, padding: 40, gutter: 6)
for cell in hexes.cells {
    fill(Color(hue: Double(cell.row) / 10, saturation: 0.5, brightness: 0.9))
    drawPolygon(cell.corners)
}
```

A hex grid costs you something a square grid gives you for free, since its cells cannot stretch. The hex-native math is what makes that trade worth it, and every cell carries the axial coordinates (`q`, `r`) that this math runs on:

- `distance(from:to:)` counts steps between neighbors, so cells at equal distances form true concentric rings. A square grid cannot produce that honeycomb falloff.
- `neighbors(of:)` returns the adjacent cells, up to six of them, and `ring(around:radius:)` walks the cells at an exact distance.
- `cell(at: point)` picks the exact hexagon under a point, so one call turns a mouse position into a hexagon. `cell(q:r:)` looks a cell up by its axial address.

```swift
let focus = hexes.cell(at: Vector2(mouseX, mouseY)) ?? hexes.cell(column: 6, row: 5)
for cell in hexes.cells {
    let rings = Double(hexes.distance(from: focus, to: cell))
    fill(Color.mix(.teal, .black, min(1, rings / 6)))
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

This is the third regular tiling: rows of equilateral triangles that alternate between pointing up and pointing down. Cell `(column, row)` points up when `column + row` is even. `columns` counts the triangles in a row. Each triangle advances half an edge past the one before it, so neighbors share alternating edges. Like the hex grid, the block keeps its true shape and is centered in the padded bounds. `gutter` shrinks each triangle toward its center, so neighbors separate evenly.

Each `TriangleGrid.Cell` carries `column` and `row`, `pointsUp`, its `center`, and its three `vertices`. `neighbors(of:)` returns the cells across each edge, up to three of them:

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

This splits a rectangle into leaf panels, recursively. `.binary` (the default) cuts across the longer side at a random fraction drawn from `fraction`. That gives the uneven, painterly panels of the classic grid-painting composition. `.quad` cuts into four equal quadrants instead, which gives the quadtree look. A cell splits while there is room for a cut and while the random draw allows it. It never splits when a cut would leave either side below `minSize`, and it never splits past `maxDepth`. The root always splits when it can. Below the root, a cell splits only with probability `chance`, so `chance: 0.7` leaves a mix of large and small panels. Each returned `Subdivision.Cell` is a `frame` plus the `depth` at which it stopped, which is useful for tinting by scale. The randomness comes from the seeded `random`.

```swift
seed(5)
stroke(.black); strokeWeight(8)
for cell in subdivide(minSize: 90, chance: 0.75) {
    fill(random(0, 1) < 0.2 ? randomChoice([.red, .yellow, .blue]) : .white)
    drawRect(cell.frame)
}
```

The typed core is `Subdivision.cells(in:minSize:maxDepth:chance:fraction:style:using:)`, which works over any `RandomNumberGenerator`. See the `Patterns/Subdivision` example.

<a name="maze"></a>

#### maze / Maze

```swift
maze(columns: Int, rows: Int,
     algorithm: Maze.Algorithm = .backtracker) -> Maze
drawMaze(_ maze: Maze, in bounds: Rectangle? = nil)
```

This carves a *perfect maze* and reads it back as geometry. In a perfect maze every cell is reachable, there are no loops, and there is one path between any two cells. The algorithm you choose changes how the maze looks, not only how it is built:

- **`.backtracker`** (randomized depth-first search) gives long winding corridors and few dead ends.
- **`.kruskal`** (randomized Kruskal's over union-find) gives many short dead ends and an even texture across the whole maze.
- **`.wilson`** (loop-erased random walks) draws a uniform sample over *every* possible maze of the grid, so there is no bias.

You can read the maze back as geometry in these ways:

- `walls(in: rect)` returns the line work, ready to stroke. Collinear wall segments are merged into single long runs, which keeps the result clean for stroking, hatching, and plotter SVG. `drawMaze` strokes it in one call.
- `solution(fromColumn:fromRow:toColumn:toRow:)` returns the unique path between two cells. `longestPath()` returns the maze's diameter, and its two ends make the natural entrance and exit.
- `contour(of:in:)` lays a cell path over a rectangle as a polyline through the cell centers. `isOpen(_:column:row:)` reads a single passage.

```swift
seed(9)
let m = maze(columns: 24, rows: 24)
stroke(.white); strokeWeight(4); strokeCap(.round)
drawMaze(m)
stroke(.orange)
drawPolyline(m.contour(of: m.longestPath(), in: bounds).points)
```

The classic one-line BASIC maze has a different look: random `╱` and `╲` diagonals, with corridors implied rather than carved. For that look, see the `.diagonals` tile in [Truchet tiling](./Truchet.md). See the `Patterns/Maze` example, which shows all three algorithms with the longest path tracing through.

<a name="apollonianGasket"></a>

#### apollonianGasket

```swift
apollonianGasket(in circle: Circle, minRadius: Double,
                 rotation: Double = 0, maxCount: Int = 20_000) -> [Circle]
```

This fills a circle with the classic fractal foam. Three equal circles touch each other inside the rim. Every three-way gap then gets the one circle that exactly touches all three of its parents, and this repeats down to `minRadius`. The construction is a closed form with no randomness, because the Descartes circle theorem fixes each new circle. So the same inputs always build the same foam. Circles come back in generation order, so the index doubles as an age for tinting. `rotation` spins the three seed circles around the center.

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

Related: [`Geometry`](./Geometry.md) (the square `Grid` these extend, `Contour`, shape booleans), [`Truchet tiling`](./Truchet.md) (one tile per grid cell, each at a random rotation), [`Voronoi & Delaunay`](./Voronoi.md) (cells from scattered points instead of a lattice), [`Classic curves`](./Curves.md) (the catalog of closed-form curves).
