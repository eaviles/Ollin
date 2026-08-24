#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Polyominoes`</sup>

---

## Polyominoes

**`Polyomino`** is a set of squares joined edge to edge, and **`tilePolyominoes`** fits a bag of them into a region so that every cell is covered exactly once. That is the pentomino puzzle, the domino board, and the floor laid from a few shapes, all the same question.

```
   .XX          the twelve pentominoes, in the usual letter order
   XX.          F  I  L  N  P  T  U  V  W  X  Y  Z
   .X.
                sixty squares in total, which is why the boards
   the F        they are set against are 6x10, 5x12, 4x15, 3x20
```

<img src="../../Guide/Images/07-Tiles/FittingPieces.jpg" alt="Three parts: the twelve pentominoes drawn as outlines along the top, all twelve fitted into a six by ten board on the left, and on the right a six by six checkerboard with two opposite corners cut out and marked, the board that cannot be covered by dominoes" width="680">

A piece is a *shape*, not a place: it normalizes itself back to the origin whenever it is made, so two ways of writing the same piece are the same value, and a piece can be compared with its own turns to count how many ways it can sit. Where a piece ends up is carried by the placement instead.

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

The readable way to write a piece is to draw it:

```swift
let tee = Polyomino([".X.",
                     "XXX"])
tee.orientations().count      // 4
```

**`orientations` counts rather than assumes.** Four turns and a mirror of each gives eight ways at most, but a symmetric piece gives fewer: the plus has one, the straight line two, the T four, and only a fully lopsided piece has all eight. Adding up over the twelve pentominoes gives 63, which is the number the solver actually works with.

<a name="outline"></a>

#### The outline

```swift
func outlines(cellSize: Double, origin: Vector2 = .zero) -> [Contour]
```

The piece as its boundary: the edges only one cell owns, chained end to end. This is what to stroke or fill when a piece should read as one shape rather than as a run of squares.

```swift
for outline in piece.outlines(cellSize: 40) {
    drawShape(Shape(outline.points))
}
```

One closed contour comes back per boundary loop, so a piece with a hole in it (which starts at seven squares) hands back the hole as its own loop, wound the other way. The corners along a straight run are dropped, so a straight edge is two points rather than five.

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

Every cell of `region` covered exactly once, or nil when no such fit exists.

```swift
let board = Polyomino.rectangle(columns: 10, rows: 6)
guard let fit = tilePolyominoes(Polyomino.pentominoes, covering: board) else { return }
for placement in fit {
    fill(palette[placement.piece % palette.count])
    for outline in placement.outlines(cellSize: 60) { drawShape(Shape(outline.points)) }
}
```

- **`reuse`** is the difference between a puzzle and a floor. Off (the default) each piece is used at most once, which is the pentomino puzzle. On, a piece may be used as often as it fits, which is how a few shapes tile a whole region.
- **`reflections`** decides whether a piece may be turned over. Off, a lopsided piece can no longer cover its own mirror image.
- **The seeded form** takes the sketch's own generator, so the seed decides which of the many fits comes back and the same seed always gives the same one. Call it from a sketch as `tilePolyominoes(pieces, covering: board)`, or pass your own generator with `using: &rng`.

The search fills whichever cell has the **fewest ways left** to be covered, counting them as pieces go down rather than recounting. That is what keeps a long thin board from being searched end to end: a three-by-twenty strip takes seconds this way and minutes if the cells are simply filled in order.

<a name="notes"></a>

#### Practical notes

- **Nil means no fit exists, and it means the whole space was searched.** A board with two opposite corners cut off refuses dominoes, for a reason no search can shorten: each domino covers one square of each color, and the cut board has two more of one than the other. Keep regions to a puzzle's size rather than a wall's when the answer might be nil.
- **Solving is not a per-frame job.** A twelve-pentomino board takes about a second, so solve in `setup()` or on a click and animate the drawing, not the search.
- The region is a `Polyomino` too, so any set of cells will do: a rectangle with a bite out of it, a letter, a scatter of islands.
- Placements come back in the order the search laid them, which is worth using: revealing them one at a time shows how the fit was found.

Example: `Patterns/Pentominoes`. Guide: [Chapter 7](../../Guide/07-Tiles.md).

---

#### Where this comes from

The pentominoes and the name are Solomon W. Golomb's ("Checker Boards and Polyominoes", *American Mathematical Monthly* 61/10, 1954, and the 1965 book *Polyominoes*). The fewest-ways-first search is the selection rule from Donald Knuth's "Dancing Links" (2000). See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Tiling and layout](../Drawing/Tiling.md): hex and triangle grids, subdivision, mazes, the Apollonian gasket
- [Aperiodic tilings](../Drawing/AperiodicTilings.md): Penrose, Wang tiles, girih, the spectre
- [Wave Function Collapse](./WaveFunctionCollapse.md): the other way to fill a grid under constraints, by picking rather than searching
