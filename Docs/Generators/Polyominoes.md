#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Polyominoes`</sup>

---

## Polyominoes

**`Polyomino`** is a set of squares joined edge to edge. Use **`tilePolyominoes`** to fit a collection of them into a region, so that every cell is covered exactly once. The pentomino puzzle, the domino board, and a floor laid from a few shapes are all the same question. The twelve pentominoes hold sixty squares between them, so the classic boards they are set against are 6x10, 5x12, 4x15, and 3x20.

<img src="../../Guide/Images/07-Tiles/FittingPieces.jpg" alt="Three parts: the twelve pentominoes drawn as outlines along the top, all twelve fitted into a six by ten board on the left, and on the right a six by six checkerboard with two opposite corners cut out and marked, the board that cannot be covered by dominoes" width="680">

A piece is a *shape*, not a place. Every piece normalizes itself back to the origin when it is made, so two ways of writing the same piece give the same value. That also lets you compare a piece with its own turns to count how many ways it can sit. Where a piece ends up is carried by the placement instead.

### Contents

- [Polyomino](#piece)
- [The outline](#outline)
- [tilePolyominoes](#tiling)
- [Practical notes](#notes)

<a name="piece"></a>

#### Polyomino

```swift
struct Polyomino {
    init(_ rows: [String])                 // ["XX.", ".XX"], any non-dot is filled
    init(cells: [Cell])
    let cells: [Cell]                      // normalized and sorted
    var count: Int, columns: Int, rows: Int
    func rotated() -> Polyomino            // a quarter turn clockwise
    func mirrored() -> Polyomino
    func orientations(reflections: Bool = true) -> [Polyomino]
    static func rectangle(columns: Int, rows: Int) -> Polyomino
    static let pentominoes: [Polyomino]    // the twelve, F I L N P T U V W X Y Z
    static let pentominoNames: [String]
    static let tetrominoes: [Polyomino]    // the five, I O T S L
}
```

The clearest way to write a piece is to draw it:

```swift
let tee = Polyomino([".X.",
                     "XXX"])
tee.orientations().count      // 4
```

**`orientations` counts rather than assumes.** Four turns and a mirror of each give eight ways at most. A symmetric piece gives fewer: the plus has one, the straight line two, the T four, and only a fully lopsided piece has all eight. Added up over the twelve pentominoes that comes to 63, which is the number the solver works with.

<a name="outline"></a>

#### The outline

```swift
func outlines(cellSize: Double, origin: Vector2 = .zero) -> [Contour]
```

`outlines` gives the piece as its boundary, which is the edges only one cell owns, chained end to end. Stroke or fill those when a piece should read as one shape rather than as a run of squares.

```swift
for outline in piece.outlines(cellSize: 40) {
    drawShape(Shape(outline.points))
}
```

One closed contour comes back per boundary loop. A piece with a hole in it, which takes at least seven squares, hands back the hole as its own loop, wound the other way. The corners along a straight run are dropped, so a straight edge is two points rather than five.

<a name="tiling"></a>

#### tilePolyominoes

```swift
tilePolyominoes(_ pieces: [Polyomino], covering region: Polyomino,
                reuse: Bool = false, reflections: Bool = true) -> [PolyominoPlacement]?

struct PolyominoPlacement {
    let piece: Int              // index into the pieces given
    let shape: Polyomino        // the orientation used
    let at: Polyomino.Cell      // where the shape's origin lands
    var cells: [Polyomino.Cell]
    func outlines(cellSize: Double, origin: Vector2 = .zero) -> [Contour]
}
```

The result covers every cell of `region` exactly once, and it is nil when no such fit exists.

```swift
let board = Polyomino.rectangle(columns: 10, rows: 6)
guard let fit = tilePolyominoes(Polyomino.pentominoes, covering: board) else { return }
for placement in fit {
    fill(palette[placement.piece % palette.count])
    for outline in placement.outlines(cellSize: 60) { drawShape(Shape(outline.points)) }
}
```

- **`reuse`** sets whether you get a puzzle or a floor. Off, the default, each piece is used at most once, which is the pentomino puzzle. On, a piece may be used as often as it fits, which is how a few shapes tile a whole region.
- **`reflections`** decides whether a piece may be turned over. Off, a lopsided piece can no longer cover its own mirror image.
- **The seeded form** takes the sketch's own generator. The seed then decides which of the many fits comes back, and the same seed always gives the same one. Call it from a sketch as `tilePolyominoes(pieces, covering: board)`, or pass your own generator with `using: &rng`.

The search fills whichever cell has the **fewest ways left** to be covered. It counts those ways as pieces go down rather than recounting them. That is what keeps a long thin board from being searched end to end. A 3x20 strip takes seconds this way, and minutes if the cells are filled in order instead.

<a name="notes"></a>

#### Practical notes

- **Nil means the whole space was searched and no fit exists.** Dominoes cannot cover a board with two opposite corners cut off. No search can shorten that reason. Each domino covers one square of each color, and the cut board has two more of one color than the other. Keep regions to a puzzle's size rather than a wall's when the answer might be nil.
- **Solving is not a per-frame job.** A twelve-pentomino board takes about a second. Solve in `setup()` or on a click, then animate the drawing rather than the search.
- The region is a `Polyomino` too, so any set of cells will do. That covers a rectangle with a bite out of it, a letter, or a scatter of islands.
- Placements come back in the order the search laid them down. Reveal them one at a time and the drawing shows how the fit was found.

Example: `Patterns/Pentominoes`. Guide: [Chapter 7](../../Guide/07-Tiles.md).

---

#### Where this comes from

Solomon W. Golomb introduced the pentominoes and the name, in "Checker Boards and Polyominoes" (*American Mathematical Monthly* 61/10, 1954) and in the 1965 book *Polyominoes*. The fewest-ways-first search is the selection rule from Donald Knuth's "Dancing Links" (2000). See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Tiling and layout](../Drawing/Tiling.md): hex and triangle grids, subdivision, mazes, the Apollonian gasket
- [Aperiodic tilings](../Drawing/AperiodicTilings.md): Penrose, Wang tiles, girih, the spectre
- [Wave Function Collapse](./WaveFunctionCollapse.md): the other way to fill a grid under constraints, by picking rather than searching
