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

There are two models, and they differ in where the rules come from. The **tiled** model, below, takes tiles you designed and edge sockets you declared. The [**overlapping**](#overlapping) model takes a small picture and works the vocabulary out for itself.

### Contents

- [Tiles and sockets](#tiles)
- [Solving and drawing](#solve)
- [Rotations](#rotations)
- [Learning from a picture: the overlapping model](#overlapping)
- [What it's for, and what it isn't](#envelope)

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

<a name="overlapping"></a>

#### Learning from a picture: the overlapping model

Declaring tiles and sockets is work, and some textures don't decompose into tiles at all. The overlapping model skips that step: hand it a **small example picture** and it cuts the sample into every `patternSize × patternSize` patch the sample contains, counts how often each one occurs, and works out which patches may overlap. Solving then fills a much larger grid so that every overlap agrees.

What comes out is new, but locally it's made of nothing that wasn't in the sample. That's the guarantee, and it's worth stating precisely: **every square of the output is a square the sample already contained.**

```swift
func wfc(from sample: Image, width: Int, height: Int,
         patternSize: Int = 3, symmetry: WFCSymmetry = .all,
         wrapsSample: Bool = true, tileable: Bool = false,
         attempts: Int = 10) -> Image?
```

```swift
if let texture = wfc(from: sample, width: 72, height: 44) {
    drawImage(texture, in: bounds)
}
```

| | |
|---|---|
| `patternSize` | How much context a patch carries. `2` keeps only the loosest sense of the sample; `3` is the usual choice and reproduces corners and junctions faithfully; `4` and up reproduce whole motifs, at the cost of variety and a much slower solve. |
| `symmetry` | Which copies of the sample to learn from as well: `.none` (as drawn), `.rotations` (the four quarter turns), or `.all` (the turns and the mirror of each). |
| `wrapsSample` | Read the sample as wrapping at its edges, so patches are cut from every position. True suits a sample that tiles; false keeps the sample's own border out of the vocabulary. |
| `tileable` | Solve the output as a torus, so the result tiles seamlessly with itself. |

**`symmetry` costs you orientation.** A sample that knows which way is up (a skyline, a waterline, flowers standing on ground) wants `.none`, or it will come back sideways. A texture with no particular orientation wants `.all`, which multiplies what the solver has to work with without asking for a bigger sample.

**`wrapsSample` is subtler than it looks, and the default loses edges.** Reading the sample as wrapping joins its bottom row to its top, so a sample with ground along the bottom teaches patches where ground sits directly under sky. Synthesize from that and the ground repeats in bands up the picture. If your sample has a meaningful top and bottom, pass `wrapsSample: false`.

Learning is the expensive half and doesn't depend on the output, so a sketch that solves more than once builds the model itself and keeps it:

```swift
let model = OverlappingWFC(learningFrom: sample, patternSize: 3)   // once, in setup
// ... then as often as you like
let texture = wfc(model, width: 64, height: 64)
```

`OverlappingWFC` also reports what it learned, which is worth drawing while you're tuning a sample: `patternCount`, `pattern(_:)` for each patch as its own little image, and `weight(_:)` for how often it occurred.

Two practical notes. **Draw the result a rectangle at a time rather than with `drawImage`** if you're blowing it up much, because `drawImage` smooths, which turns a 3-pixel wall into a gradient; a rectangle per pixel also exports to SVG and PDF as real rectangles. And **do this once**, in `setup` or guarded so it runs on the first frame; neither half belongs in a frame loop.

<a name="envelope"></a>

#### What it's for, and what it isn't

**The sample wants to be small and few-colored**: pixel art or a hand-drawn motif, tens of pixels a side, a handful of colors. Patches are matched by exact color equality, so a photograph has a distinct color in nearly every patch, nearly every patch is unique, nothing overlaps anything else, and the solve has nothing to choose between. A sample past 256 colors or 1024 patterns is refused with a note saying so rather than grinding.

**A solve can fail, and above about 50 pixels a side it starts to.** A contradiction (a cell left with no pattern that fits) restarts the whole solve, `attempts` times, and then `wfc` returns `nil`. This is the technique, not the implementation: the problem is NP-hard in general, and success rates fall off sharply with output size. Solve a smaller texture, loosen the sample, or drop `patternSize` to `2`.

**`tileable` can be impossible rather than merely hard.** If the sample has a repeating structure whose period doesn't divide the output size, no seamless answer exists at that size and every attempt fails. Sizing the output to a multiple of the sample's period fixes it; retrying never will.

**Not here yet:** a way to constrain the solve before it starts, such as pinning the bottom row to ground, fixing a pixel, or seeding a region. The reference implementation has a `ground` flag for the first of these, but it works by nominating a pattern by index, which depends on extraction order and quietly means something different when the sample or the symmetry changes. A version worth having would name a color or a region instead.

---

Related: [`Truchet tiling`](../Drawing/Truchet.md) (tiles chosen at random rather than by constraint), [`Circle packing`](./Packing.md), [`L-systems`](./LSystem.md), and [`Differential growth`](./DifferentialGrowth.md) (the other generative-geometry generators), [`Geometry`](../Drawing/Geometry.md) (the `Grid` the layout draws through), [`Images`](../Drawing/Images.md) (the `Image` a sample comes from and a texture goes back to).
