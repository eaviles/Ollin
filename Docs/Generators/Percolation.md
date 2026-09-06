#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Percolation`</sup>

---

## Percolation

**`Percolation`** fills a grid with open cells at a probability you choose, then reads the **clusters**. A cluster is a group of open cells joined edge to edge. This is the standard model of a phase transition. Below the critical probability the open cells form scattered islands. Just past it, one giant cluster suddenly reaches across the whole grid. That threshold sits near 0.5927 on the square lattice, so sweeping `probability` through it is what shows the change.

The fill draws from the seeded generator, so the same seed always builds the same grid. Everything comes back as geometry. You get cell rectangles to fill, and traced boundary loops that you can stroke, hatch, and export to SVG for a pen plotter.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/04-Randomness/ChanceInCrowds-dark.jpg">
  <img src="../../Guide/Images/04-Randomness/ChanceInCrowds.jpg" alt="Three dark grid panels. At probability 0.50, scattered blue islands; at 0.56, one pale cluster strains most of the way across; at 0.63, a single gold cluster spans the grid, traced with a pale outline" width="680">
</picture>

### Contents

- [Percolation](#filling)
- [Reading the clusters](#clusters)
- [Outlines and cell rectangles](#geometry)
- [Practical notes](#notes)

<a name="filling"></a>

#### Percolation

```swift
Percolation(columns: Int, rows: Int, probability: Double,
            using: &rng)                                  // the seeded fill
Percolation(columns: Int, rows: Int, openCells: [Bool])   // a grid you filled yourself
percolation(columns: Int, rows: Int, probability: Double) // the sketch form, seeded by `seed(_:)`

Percolation.criticalProbability   // 0.592746, the square-lattice site threshold
```

The first form opens each cell at random with `probability`. The second takes any row-major boolean grid. That means the cluster reading also works on a thresholded image, a noise field, or a pattern of your own. `Percolation.criticalProbability` is the measured threshold, so a sketch can move around that value without writing the number out.

```swift
seed(9)
let grid = percolation(columns: 48, rows: 48, probability: 0.6)
noStroke()
fill(Color(hex: 0xE8B44A))
for cell in grid.cellRects(of: 0, in: bounds) { drawRect(cell) }
```

<a name="clusters"></a>

#### Reading the clusters

```swift
grid.clusterCount                       // how many clusters
grid.clusterSizes                       // cell counts, largest first
grid.cluster(_ index:)                  // one cluster's (column, row) cells
grid.isOpen(column:row:)                // one cell's state
grid.clusterIndex(column:row:)          // which cluster a cell belongs to
grid.spanningClusterIndex               // the top-to-bottom cluster, if any
grid.spans                              // whether one exists
```

Clusters come back largest first, so index `0` is always the biggest and you can color them by size in a plain loop. Cells join through their four edge neighbors, and two cells that touch only at a corner are not connected. `spans` answers the classic question, which is whether some cluster touches both the top row and the bottom row.

<a name="geometry"></a>

#### Outlines and cell rectangles

```swift
grid.cellRects(of: index, in: rect)   // one small Rectangle per cell, to fill
grid.outlines(of: index, in: rect)    // closed boundary loops, to stroke or plot
```

`cellRects` places a cluster's cells into any rectangle, ready for `drawRect`. `outlines` traces the same cluster's boundary as closed `Contour` loops, with exact corners and straight runs merged into single edges. You get the outer edge plus one loop for each enclosed hole. Where two lobes meet at a single corner, the trace takes the tighter turn, so no loop ever crosses itself.

```swift
stroke(.white)
noFill()
for loop in grid.outlines(of: 0, in: bounds) { drawPolygon(loop.points) }
```

<a name="notes"></a>

#### Practical notes

- **Sweep the threshold slowly.** Everything that matters happens within a few hundredths of `criticalProbability`. Move `probability` with a slow sine around that value, and you see the islands grow, strain, and snap into one span. For a working sketch, see `Examples/Patterns/Percolation`.
- **Fix the field, move the threshold.** Pick one random value per cell once, then open each cell whose value sits under the current probability. The landscape holds still while the flood rises, which reads far better than picking new values every frame.
- **The threshold moves with the rules.** 0.5927 belongs to the square lattice with four neighbors. Your own `openCells` grids, such as an image or a noise field, have their own thresholds, and you find one by eye.
- **The outlines suit a pen plotter.** Each loop is one closed rectilinear polyline. The [SVG export](../Output/Export.md) writes them as line-work, and its `--hatch` pass fills them like any other closed shape.

---

Related: [`Cellular automata`](./CellularAutomata.md) covers grids that change by rule instead of by chance. See [`Tiling & layout`](../Drawing/Tiling.md) for the `Maze`, the other grid whose geometry comes back as merged line runs. See [`Noise`](./Noise.md) for a field you can threshold into `openCells`.
