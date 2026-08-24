#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Crease patterns`</sup>

---

## Crease patterns: folding and cutting

A folded thing is written down as the flat sheet it came from, with every fold drawn as a straight line. There are two kinds of line: a **mountain**, which points up out of the sheet, and a **valley**, which points down into it. That is the whole notation. Draw those lines and you have said everything about the finished form.

A sheet that is **cut** rather than folded is written the same way, and that is kirigami. It behaves differently for a good reason: a cut sheet can grow, and a folded one can only rearrange itself.

Both come out of Ollin as plain geometry, which matters more here than usual. A crease pattern is a set of instructions for a machine: the fold lines go to a scoring blade or a pen, and the cut lines go to a cutter. So the same pattern draws on the canvas, [hatches](./Geometry.md), and [exports to SVG](../Output/Fabrication.md).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/07-Tiles/CreaseAndFold-dark.jpg">
  <img src="../../Guide/Images/07-Tiles/CreaseAndFold.jpg" alt="Three dark panels. A flat crease pattern of leaning parallelograms, its folds marked in orange and blue; the same sheet folded into a corrugated field of panels seen from a corner; and a grid of pale squares turned one way and the next, with diamond holes open between them" width="680">
</picture>

### The two laws

Not every set of lines can be folded. Two laws, each about a single vertex, decide it:

```
  Kawasaki's law                         Maekawa's law

        \  b |  c /                      count the mountains and the
         \   |   /                       valleys meeting at a vertex:
      a   \  |  /   d                    one is always exactly two
   _________\|/_________                 more than the other
             *
                                             M - V  =  +2  or  -2
      a - b + c - d = 0
```

Walk around a vertex and list the angles between one fold and the next. Add the first, take away the second, add the third, and so on all the way around. The sheet can fold flat only if that number comes to zero, at every vertex. `kawasakiResidual(at:)` is that number, `maekawaResidual(at:)` is the count, and `isFlatFoldable` asks both at every interior vertex.

The laws are necessary rather than sufficient. They see one vertex at a time, so they cannot notice a sheet that would have to pass through itself. A pattern that fails them certainly cannot fold flat.

### Contents

- [CreasePattern](#pattern)
- [Drawing one](#drawing)
- [The Miura fold](#miura)
- [The folded sheet](#folded)
- [Rotating squares](#kirigami)
- [Taking it to a machine](#machine)

<a id="pattern"></a>

### CreasePattern

A pattern is a list of `Crease` values, each a line from `start` to `end` with an `assignment` of `.mountain`, `.valley`, `.boundary` (the edge of the sheet), or `.cut`.

```swift
let sheet = CreasePattern.miura(columns: 8, rows: 5)

sheet.creases(.mountain).count      // the lines of one kind
sheet.vertices.count                // where lines meet, each place once
sheet.interiorVertices              // the ones with paper all the way around
sheet.isFlatFoldable                // both laws, at every one of them
```

`fitted(in:)` puts a pattern on the canvas. It scales by the same amount in both directions, and it moves the points rather than the transform. The strokes therefore do not get fatter with it. Equal scaling keeps every angle, so a fitted pattern is still a foldable one.

```swift
let placed = sheet.fitted(in: bounds.inset(by: 60))
```

`inverted` turns the sheet over: every mountain becomes a valley and every valley a mountain. Which way up a sheet is held is a choice, not a property of the pattern.

<a id="drawing"></a>

### Drawing one

`contours(_:)` hands back the lines of one kind, joined into as few strokes as the pattern allows. Where several lines of the same kind meet, the stroke carries on through the straightest one, which is what a pen or a blade wants. `drawCreases(_:_:)` strokes them with the current `stroke`:

```swift
strokeWeight(2)
stroke(Color(hex: 0xE0724A)); drawCreases(placed, .mountain)
stroke(Color(hex: 0x5A8FC7)); drawCreases(placed, .valley)
stroke(.gray);                drawCreases(placed, .boundary)
```

<a id="miura"></a>

### The Miura fold

The best known crease pattern, and the most useful. `MiuraFold` describes one with five numbers:

```swift
var sheet = MiuraFold(columns: 8, rows: 5,
                      major: 1,        // the length of a straight fold, across
                      minor: 0.8,      // one step of a zigzag fold, down
                      angle: .pi / 3)  // the sharp corner of a parallelogram
drawCreases(sheet.pattern.fitted(in: bounds), .mountain)
```

```
   the pattern                      what it does

   \___\___\___\___\                pull two opposite corners and the
   /   /   /   /   /                whole sheet opens at once, in both
   \___\___\___\___\                directions together. push them back
   /   /   /   /   /                and it closes into a flat packet.
```

Two things make it behave that way. Every panel stays flat while the sheet moves, so stiff material folds as happily as paper. And the sheet gets **narrower as it gets shorter**, which is the opposite of what most things do: squeeze a rubber band and it bulges. A material that thins as it shortens is auxetic, and `poissonRatio` is the number for it. It is negative, and the two directions multiply to one, so the other direction is `1 / poissonRatio`.

The pattern is recognizable on the page. Every zigzag fold running down the sheet is a mountain or a valley for its whole length, and the zigzags take turns across the sheet. Every straight fold running across it changes kind at each step.

<a id="folded"></a>

### The folded sheet

`fold` runs from `0` (the flat sheet) to `1` (the flat packet), and `points`, `facets`, and `size` are the folded form in three dimensions:

```swift
sheet.fold = 0.5 * (1 - cos(time))       // open and close it
for panel in sheet.facets { ... }        // four corners each, still flat
sheet.size                               // width, length, and height
```

Nothing stretches at any point in that movement. Every crease is exactly as long folded as it is flat, and every panel is the same parallelogram it was cut as. That is what makes it a *rigid* folding rather than a picture of one. It is also why the fold works in metal and plastic as well as in paper.

<a id="kirigami"></a>

### Rotating squares

The plainest useful kirigami. Cut a grid of squares, leaving a thread of material at every corner, and the squares turn one way and the next as the sheet is pulled. Square holes open between them.

```swift
var lattice = RotatingSquares(columns: 6, rows: 6, side: 90, ligament: 6)
lattice.opening = 0.5 * (1 - cos(time))
for square in lattice.squares { drawPolygon(square.points) }
```

Because every square turns and none of them stretches, the sheet grows the same amount in both directions at once. Its `poissonRatio` is exactly `-1`, which is as far as a flat material can go. Open all the way, the squares have turned 45 degrees and half the sheet is hole.

The mechanism is exact for a corner that is a point. A real sheet needs the `ligament` to hold together, and the wider it is the further the real movement drifts from the ideal one.

<a id="machine"></a>

### Taking it to a machine

`pattern` on either type is the flat sheet, in its own units, before anything is folded or pulled. Fit it to the canvas, draw each kind in its own color for the eye, or send each kind to its own layer for the machine:

```swift
let sheet = RotatingSquares(columns: 8, rows: 8, side: 1, ligament: 0.08).pattern
for line in sheet.contours(.cut) { drawPolyline(line.points) }
```

Run the sketch with `--export-svg` and the strokes come out as vector paths, ready for a cutter or a pen plotter. The joined strokes matter here: a blade that can cut a whole line in one pass leaves a cleaner edge than one that stops and starts at every vertex.

---

Related: [`Geometry`](./Geometry.md) covers the `Contour` and `Rectangle` values the patterns are made of; [`Tiling`](./Tiling.md) and [`Truchet`](./Truchet.md) are the other grid patterns; [`Fabrication`](../Output/Fabrication.md) takes the lines to a cutter or a plotter; [`3D`](../3D/README.md) is where a folded sheet goes if you want to light it.
