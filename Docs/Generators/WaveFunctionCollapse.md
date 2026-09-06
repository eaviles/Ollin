#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Wave Function Collapse`</sup>

---

## Wave Function Collapse

Fill a grid from a small set of tiles so that **every pair of neighbors is legal**. Each cell starts out holding *all* the tiles at once, which is called a superposition. The solver takes the most constrained cell and collapses it to a single tile, picked at random by weight. It then passes that choice to the neighbors and drops the options that no longer fit. It repeats both steps until every cell is decided. This is the constraint-solving, texture-synthesis technique behind procedurally generated tile maps.

The result is a grid of tile indices, and you draw it however you like. Each tile is a `Shape` or a small draw block, so it feeds the existing geometry path. A solve is a pure function of the [`seed`](./Random.md#seed), so the same seed always produces the same layout.

There are two models, and they differ in where the rules come from. The **tiled** model, below, takes tiles you designed and edge sockets you declared. The [**overlapping**](#overlapping) model takes a small picture and works out the vocabulary for itself.

### Contents

- [Tiles and sockets](#tiles)
- [Solving and drawing](#solve)
- [Rotations](#rotations)
- [Learning from a picture: the overlapping model](#overlapping)
- [What it's for, and what it isn't](#envelope)

<a name="tiles"></a>

#### Tiles and sockets

A `WFCTile` is four edge **sockets** and a `weight`. Two tiles may sit next to each other when the sockets on their shared edge are *equal*. A socket is therefore an `Int` label for what an edge connects to. For example, a socket can mark a pipe or no pipe, and it can mark a grass edge or a water edge. Sockets are listed clockwise from the top.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/13-GrowingThings/TilesAgree-dark.jpg">
  <img src="../../Guide/Images/13-GrowingThings/TilesAgree.jpg" alt="Left, three enlarged pipe tiles with orange dots marking their pipe sockets and hollow dots their blank edges; right, an eleven-by-eleven solved grid where every pipe meets a pipe and the network connects" width="680">
</picture>

```swift
WFCTile(_ sockets: [Int], weight: Double = 1)   // [top, right, bottom, left]
```

```swift
let blank    = WFCTile([0, 0, 0, 0])            // no pipe on any edge
let vertical = WFCTile([1, 0, 1, 0])            // a pipe top-to-bottom
let elbow    = WFCTile([1, 1, 0, 0])            // a pipe turning top-to-right
```

A higher `weight` makes a tile more likely when a cell collapses, so you can push a layout toward straights rather than crossings, for example.

<a name="solve"></a>

#### Solving and drawing

Solve with the `wfc` shorthand, then draw the result with `drawWFC`. Solving takes real time, so do it once rather than every frame. Keep the result in a stored property, or guard the call so it runs on the first frame.

```swift
func wfc(tiles: [WFCTile], columns: Int, rows: Int, attempts: Int = 40) -> [[Int]]?
func drawWFC(_ grid: [[Int]], in bounds: Rectangle? = nil, padding: Insets = 0, gutter: Double = 0,
             tile: (Int, Rectangle) -> Void)
```

`wfc` returns the tile indices as `grid[column][row]`. It returns `nil` when it cannot find a legal filling within `attempts` restarts. A contradiction is a cell left with no legal tile, and one contradiction restarts the whole solve. Contradictions are rare with a forgiving tileset, and adding a blank tile makes them almost impossible. `drawWFC` lays a [`Grid`](../Drawing/Geometry.md) over `bounds` and hands your closure each cell's tile index and frame.

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

Because you draw straight from a tile's `sockets`, one draw block covers a tile and all of its rotations. See the `WaveFunctionCollapse` example.

<a name="rotations"></a>

#### Rotations

Most tilesets are one drawn shape plus its rotations. `rotations()` makes those rotations for you and turns the sockets to match, so you declare each shape once.

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

Declaring tiles and sockets takes work, and some textures do not break into tiles at all. The overlapping model skips that step. You hand it a **small example picture**, and it cuts the sample into every `patternSize × patternSize` patch the sample contains. It counts how often each patch occurs, then works out which patches may overlap. The solve then fills a much larger grid so that every overlap agrees.

What comes out is new as a whole, but every small part of it comes from the sample. Stated exactly, the guarantee is that **every square of the output is a square the sample already contained.**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/13-GrowingThings/LearnedFromAPicture-dark.jpg">
  <img src="../../Guide/Images/13-GrowingThings/LearnedFromAPicture.jpg" alt="Left, a sixteen by sixteen hand-drawn plan of thick black walls; right, a forty-eight by thirty picture in the same style, with the same wall thickness and the same corners, arranged completely differently" width="680">
</picture>

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
| `patternSize` | How much context a patch carries. `2` keeps only the loosest sense of the sample. `3` is the usual choice, and it reproduces corners and junctions accurately. `4` and up reproduce whole motifs, but you get less variety and a much slower solve. |
| `symmetry` | Which copies of the sample to learn from as well. `.none` is the sample as drawn, `.rotations` adds the four quarter turns, and `.all` adds the turns and the mirror of each. |
| `wrapsSample` | Read the sample as wrapping at its edges, so patches are cut from every position. Use true for a sample that tiles. Use false to keep the sample's own border out of the vocabulary. |
| `tileable` | Solve the output as a torus, so the result tiles seamlessly with itself. |

**`symmetry` costs you orientation.** Some samples have a clear up and down, such as a skyline, a waterline, or flowers standing on ground. Use `.none` for those, or the result comes back sideways. Use `.all` for a texture with no particular orientation. It gives the solver more patterns to work with, and it does not ask you for a bigger sample.

**`wrapsSample` is easy to get wrong, and the default loses edges.** Reading the sample as wrapping joins its bottom row to its top row. A sample with ground along the bottom then teaches patches where ground sits directly under sky. Synthesize from those patches and the ground repeats in bands up the picture. Pass `wrapsSample: false` when your sample has a meaningful top and bottom.

Learning is the slow half, and it does not depend on the output. A sketch that solves more than once builds the model itself and keeps it:

```swift
let model = OverlappingWFC(learningFrom: sample, patternSize: 3)   // once, in setup
// ... then as often as you like
let texture = wfc(model, width: 64, height: 64)
```

`OverlappingWFC` also reports what it learned, and that is worth drawing while you tune a sample. `patternCount` is how many patterns there are, `pattern(_:)` gives each patch as its own small image, and `weight(_:)` gives how often that patch occurred.

Two practical notes follow. First, **draw the result a rectangle at a time rather than with `drawImage`** when you scale it up much. `drawImage` smooths the image, which turns a 3-pixel wall into a gradient. A rectangle per pixel also exports to SVG and PDF as real rectangles. Second, **do this once**, in `setup` or guarded so it runs on the first frame. Neither learning nor solving belongs in a frame loop.

<a name="envelope"></a>

#### What it's for, and what it isn't

**The sample should be small and use few colors**: pixel art or a hand-drawn motif, tens of pixels a side, a handful of colors. Patches are matched by exact color equality. A photograph has a distinct color in nearly every patch, so nearly every patch is unique. Nothing then overlaps anything else, and the solve has nothing to choose between. A sample past 256 colors or 1024 patterns is refused with a note saying so, rather than grinding away.

**A solve can fail, and failures begin above about 50 pixels a side.** A contradiction is a cell left with no fitting pattern. Each one restarts the whole solve, `attempts` times, and then `wfc` returns `nil`. This is a limit of the technique, not of the implementation. The problem is NP-hard in general, so success rates fall off sharply as the output grows. Solve a smaller texture, loosen the sample, or drop `patternSize` to `2`.

**`tileable` can be impossible rather than only hard.** The sample may have a repeating structure whose period does not divide the output size. No seamless answer exists at that size, so every attempt fails. Size the output to a multiple of the sample's period to fix it, because retrying never will.

**Not here yet:** a way to constrain the solve before it starts. Such a constraint would pin the bottom row to ground, fix a pixel, or seed a region. The reference implementation has a `ground` flag for the first of those. The flag names a pattern by index, and that index depends on the order the patterns were extracted in. When the sample or the symmetry changes, the flag quietly means something different. A version worth having would name a color or a region instead.

---

Related: [`Truchet tiling`](../Drawing/Truchet.md) (tiles chosen at random rather than by constraint), [`Circle packing`](./Packing.md), [`L-systems`](./LSystem.md), and [`Differential growth`](./DifferentialGrowth.md) (the other generative-geometry generators), [`Geometry`](../Drawing/Geometry.md) (the `Grid` the layout draws through), [`Images`](../Drawing/Images.md) (the `Image` a sample comes from and a texture goes back to).
