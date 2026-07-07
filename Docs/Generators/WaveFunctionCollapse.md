#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Wave Function Collapse`</sup>

---

## Wave Function Collapse

Fill a grid from a small set of tiles so that **every pair of neighbors is legal**. Each cell starts holding *all* tiles at once (a superposition); the solver repeatedly collapses the most-constrained cell to a single tile (a weighted random pick) and propagates that choice to its neighbors, eliminating options that no longer fit, until every cell is decided. It's the constraint-solving, texture-synthesis technique behind procedurally generated tile maps.

The result is a grid of tile indices, which you draw however you like: each tile is a `Shape` or a small draw block, so it feeds the existing geometry path. A solve is a pure function of the [`seed`](./Random.md#seed), so the same seed always produces the same layout.

```
  each cell holds all tiles        collapse the most            propagate: neighbors
       ┌───┬───┬───┐               constrained cell              lose options that no
       │▤▤▤│▤▤▤│▤▤▤│                   ┌───┬───┐                 longer fit, spreading
       ├───┼───┼───┤        →          │ ═ │▤▤▤│      →          outward until stable,
       │▤▤▤│▤▤▤│▤▤▤│                   └───┴───┘                 then collapse the next
       └───┴───┴───┘
```

### Contents

- [Tiles and sockets](#tiles)
- [Solving and drawing](#solve)
- [Rotations](#rotations)

<a name="tiles"></a>

#### Tiles and sockets

A `WFCTile` is four edge **sockets** and a `weight`. Two tiles may sit next to each other when the sockets on their shared edge are *equal*, so a socket is just a label (an `Int`) for what an edge connects to: a pipe versus no pipe, a grass edge versus a water edge, and so on. Sockets are listed clockwise from the top.

```swift
WFCTile(_ sockets: [Int], weight: Double = 1)   // [top, right, bottom, left]
```

```swift
let blank    = WFCTile([0, 0, 0, 0])            // no pipe on any edge
let vertical = WFCTile([1, 0, 1, 0])            // a pipe top-to-bottom
let elbow    = WFCTile([1, 1, 0, 0])            // a pipe turning top-to-right
```

A higher `weight` makes a tile more likely when a cell collapses, so you can bias a layout toward (say) straights over crossings.

<a name="solve"></a>

#### Solving and drawing

Solve with the `wfc` sugar, then draw the result with `drawWFC`. Solving is not cheap, so do it once (in a stored property, or guarded so it runs on the first frame) rather than every frame.

```swift
func wfc(tiles: [WFCTile], columns: Int, rows: Int, attempts: Int = 40) -> [[Int]]?
func drawWFC(_ grid: [[Int]], in bounds: Rectangle? = nil, padding: Insets = 0, gutter: Double = 0,
             tile: (Int, Rectangle) -> Void)
```

`wfc` returns the `grid[column][row]` tile indices, or `nil` if it couldn't find a legal filling within `attempts` restarts (a contradiction, a cell left with no legal tile, restarts the whole solve; contradictions are rare with a forgiving tileset, and a blank tile makes one all but impossible). `drawWFC` lays a [`Grid`](../Drawing/Geometry.md) over `bounds` and hands your closure each cell's tile index and frame.

```swift
if let grid = wfc(tiles: tiles, columns: 18, rows: 18) {
    strokeWeight(6); strokeCap(.round)
    drawWFC(grid, padding: .all(40)) { index, cell in
        // draw a line from the cell center to each edge that carries a pipe
        let sockets = tiles[index].sockets
        let mids = [Vector2(cell.center.x, cell.y), Vector2(cell.x + cell.width, cell.center.y),
                    Vector2(cell.center.x, cell.y + cell.height), Vector2(cell.x, cell.center.y)]
        for edge in 0..<4 where sockets[edge] != 0 { drawLine(cell.center, mids[edge]) }
    }
}
```

Because you draw straight from a tile's `sockets`, one draw block covers a tile and all its rotations. See the `WaveFunctionCollapse` example.

<a name="rotations"></a>

#### Rotations

Most tilesets are one drawn shape plus its rotations. `rotations()` generates them for you, rotating the sockets to match, so you declare each shape once.

```swift
func rotated() -> WFCTile              // 90° clockwise, sockets rotated to match
func rotations(_ count: Int = 4) -> [WFCTile]
```

```swift
let tiles = [WFCTile([0, 0, 0, 0], weight: 1.1)]     // blank
    + WFCTile([1, 0, 1, 0], weight: 1.6).rotations(2) // straight: vertical + horizontal
    + WFCTile([1, 1, 0, 0], weight: 1.3).rotations()  // elbow: four corners
    + WFCTile([1, 1, 1, 0], weight: 0.5).rotations()  // tee: four orientations
    + [WFCTile([1, 1, 1, 1], weight: 0.3)]            // cross (rotations are identical)
```

---

Related: [`Truchet tiling`](../Drawing/Truchet.md) (tiles chosen at random rather than by constraint), [`Circle packing`](./Packing.md), [`L-systems`](./LSystem.md), and [`Differential growth`](./DifferentialGrowth.md) (the other generative-geometry generators), [`Geometry`](../Drawing/Geometry.md) (the `Grid` the layout draws through).
