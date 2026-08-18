#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 6</sup>

---

# 6. Grids and repetition

<img src="Images/06-GridsAndRepetition/Meander.jpg" alt="A dense tangle of rounded strands meandering over a dark ground, colored in drifting patches of coral, cream, and teal" width="560">

Every strand in this tangle is built from one shape, a quarter circle. It is stamped into a grid a couple hundred times, and each copy is spun by a coin flip. That's the whole chapter in one image. Grids are how generative art gets its sense of order, and repetition is how it gets its rhythm. A little disorder inside a strict structure, the move you know from Chapter 4, is where the life comes from. By the end you'll have the tangle, and a click that re-rolls it forever. You'll also have the two tools that carried it, a grid you loop once and transforms that move the paper under your shapes.

## One loop, not two

You've already built grids twice, the long way. Chapter 2's color field and Chapter 4's disorder grid both did the same chores. Pick a margin, then divide the leftover width into cells. Run a loop inside a loop, and rebuild each cell's x and y from the indices. Those chores are what `grid` is for:

```swift
import Ollin

final class ColorTiles: Sketch {
    let ramp = Ramp([
        Color(hex: 0x14213D), Color(hex: 0x5E60CE),
        Color(hex: 0xF77F00), Color(hex: 0xFCBF49),
    ])

    override func draw() {
        background(Color(hex: 0xF2EDE4))
        noStroke()
        for cell in grid(columns: 12, rows: 12, padding: 70, gutter: 10).cells {
            let diagonal = Double(cell.column + cell.row) / 22
            fill(ramp.color(at: diagonal))
            drawRect(cell.frame)
        }
    }
}
```

<img src="Images/06-GridsAndRepetition/ColorTiles.jpg" alt="A twelve-by-twelve grid of square tiles fading from midnight blue to amber along the diagonal" width="560">

One loop. `grid(columns:rows:padding:gutter:)` lays a grid over the canvas, where `padding` is the outer margin and `gutter` the gap between tiles. Its `cells` is a list you loop, and every cell arrives knowing everything about itself. It carries its `frame`, the rectangle to draw, plus its `center`, its `column` and its `row`. Those indices are the point. The old nested loops existed mostly so you'd have a column number and a row number in hand. Here every cell carries its own, so the indexed tricks stay one-loop simple. A checkerboard from `(cell.column + cell.row) % 2` is one, and this diagonal fade is another.

<img src="Images/06-GridsAndRepetition/GridAnatomy.jpg" alt="Grid anatomy: cells with padding and gutter labeled and one cell's frame and center called out; beside them, points as a dot per cell and as a lattice spanning the edges" width="680">

The grid offers two things to loop, and you pick by what you're drawing. `cells` are the tiles. `points` are the dots, one per cell center by default. Pass `distribution: .spanning` for a lattice that reaches the edges, the layout you want when the piece *is* a grid of dots. A dot field is two lines:

```swift
for p in grid(columns: 12, rows: 12, padding: 70, distribution: .spanning).points {
    drawCircle(center: p.position, radius: 6)
}
```

Two more things are worth knowing before we move on. `grid(...)` covers the whole canvas, but `Grid(in: someRectangle, ...)` lays one inside any rectangle. Since a cell's `frame` is itself a rectangle, grids nest. A grid where each cell holds a smaller grid is one more loop, and a classic look. And for margins that differ per edge, `padding:` takes more than a bare number: `.symmetric(horizontal: 40, vertical: 20)`, or any mix via `Insets`.

> **Swift note.** `grid(...).cells` chains a call and a property, building the grid and then asking for its cells. `cell` in the loop is a small value with named parts you read with a dot (`cell.frame`, `cell.column`), and `drawRect` accepts the frame whole, with no unpacking into x and y. `p.position` is a `Vector2`, a pair of coordinates carried as one value, and `drawCircle(center:radius:)` takes it directly. Chapter 8 makes proper friends with vectors, and until then you can read `Vector2` as "a point".

## Move the paper

The grid raises a question immediately. How do you draw something *rotated* inside a cell? `drawRect` and friends don't take an angle. The answer is one of the oldest ideas in computer graphics, and it feels backwards for about ten minutes. You don't rotate the shape, you rotate the *paper*.

<img src="Images/06-GridsAndRepetition/TransformSteps.jpg" alt="Four panels drawing the same flag with the same call: untransformed at the origin, then translated, then rotated a twelfth of a turn, then scaled up" width="680">

Three calls move the paper. `translate(x, y)` slides the origin, the point that counts as (0, 0), somewhere else. `rotate(angle)` turns the paper around that origin (angles work like Chapter 3: `.tau / 4` is a quarter turn). `scale(factor)` stretches it. After any of them, every drawing call is measured on the moved paper, which is what the diagram shows. All four flags are the very same `drawRect` at the very same numbers, drawn on paper that had been slid, turned, and stretched first.

The moves accumulate as `draw()` runs, so you also need the undo. That's `withState`:

```swift
withState {
    translate(cell.center)      // origin to this cell's middle
    rotate(.tau / 8)            // paper turns an eighth
    drawRect(-40, -40, 80, 80)  // a tilted square, centered on (0, 0)
}                               // paper snaps back as if nothing happened
```

Everything inside the braces draws on the moved paper. At the closing brace the paper is restored, along with any `fill` or `stroke` you changed inside. This is the cell-drawing recipe you'll use for the rest of the guide. Translate to the cell's center, turn or stretch as the piece demands, then draw *around the origin*. Coordinates like `(-40, -40)` straddle (0, 0). Put the recipe in a grid, add a seeded coin flip from Chapter 4, and identical parts start composing figures nobody drew:

```swift
import Ollin

final class Pinwheels: Sketch {
    let ink = Color(hex: 0x232020)
    let accent = Color(hex: 0xC1272D)

    override func draw() {
        randomSeed(11)
        background(Color(hex: 0xF2EDE4))
        noStroke()

        for cell in grid(columns: 10, rows: 10, padding: 70).cells {
            let quarter = randomChoice([0, 1, 2, 3])
            withState {
                translate(cell.center)
                rotate(Double(quarter) * .tau / 4)
                fill(random() < 0.12 ? accent : ink)
                let h = cell.frame.width / 2
                drawPolygon([Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h)])
            }
        }
    }
}
```

<img src="Images/06-GridsAndRepetition/Pinwheels.jpg" alt="A ten-by-ten field of black right triangles at random quarter turns, a few in red; pinwheels, hourglasses, and arrows emerge from the repetition" width="560">

One right triangle, half a cell drawn by handing `drawPolygon` its three corners. Four possible spins, and the neighbors do the rest. Hourglasses, pinwheels, and arrows assemble themselves wherever the spins happen to agree. Nobody placed those figures. That's the effect this chapter keeps returning to. It only works because every triangle is *exactly* the same size in *exactly* the same place in its cell, so any two spins fit together. Hold that thought for Truchet.

> **Swift note.** `random() < 0.12 ? accent : ink` is the compact if, which reads as the condition, then the value when true, then the value when false. And notice that `withState { ... }` takes a block of code in braces, like `draw()` itself. Running the block with the paper moved and then restoring it is the whole trick.

## Symmetry for free

Rotating the paper around a cell gave a quilt. Rotate around the canvas center instead, and repetition becomes symmetry. Every sketch carries that center as a property called `center`, which is just the `Vector2` at `width / 2, height / 2` and saves you writing it out:

```swift
import Ollin

final class Rosette: Sketch {
    let ink = Color(hex: 0x232020)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF2EDE4))
        translate(center)

        for _ in 0..<12 {
            rotate(.tau / 12)
            drawArm()
        }
    }

    func drawArm() {
        stroke(ink)
        strokeWeight(5)
        drawLine(70, 0, 340, 0)
        drawLine(250, 0, 300, -52)

        noStroke()
        fill(accent)
        drawCircle(340, 0, 26)
        fill(ink)
        drawCircle(300, -52, 13)
        drawCircle(160, 0, 9)
    }
}
```

<img src="Images/06-GridsAndRepetition/Rosette.jpg" alt="A twelve-fold rosette: one branching arm with disks at its tips, repeated by rotation into a botanical snowflake" width="560">

This time there's no `withState`, on purpose. Each `rotate(.tau / 12)` *adds* to the last, so the twelve copies of the arm land a twelfth of a turn apart and close the circle exactly. The arm itself is deliberately lopsided, a stem along the x axis, one branch reaching up, disks of different sizes. A symmetric arm makes a boring rosette. The symmetry comes from the repetition, so the part is free to be as crooked as it likes. Change `12` to `5` or `48`, redraw the arm, drop `time` into the rotation. Every mandala, snowflake, and kaleidoscope pattern you've seen is some cousin of this loop.

> **Swift note.** `func drawArm()` declares a helper function on your sketch, a named block you call like any built-in. Pulling the arm out of the loop keeps `draw()` readable and gives you one obvious place to redesign the arm.

## The fold, done for you

Writing that loop yourself is worth doing once, because it shows you what symmetry actually is. After that there's a shortcut, and it can do something the loop can't.

```swift
symmetry(8)                  // every draw call now happens eight times
symmetry(8, mirrored: true)  // sixteen times, alternate copies flipped
noSymmetry()                 // back to normal
```

`symmetry` is drawing state, like `fill` or a transform, so it applies to everything you draw until you turn it off, and `withState { }` scopes it. Once it's on you stop thinking about repetition entirely. You draw one wedge, and every circle, line, and shape in it lands in all the folds at once.

<img src="Images/06-GridsAndRepetition/Kaleidoscope.jpg" alt="Three panels: a single small crooked wedge with a red dot at its tip, the same wedge under eightfold symmetry forming a snowflake, and under mirrored eightfold symmetry forming a denser one with paired reflections" width="680">

The mirrored form is the part worth having. A plain rotation copies your wedge around like a pinwheel, and every copy still leans the same way. Mirroring flips alternate copies, so neighbors face each other and the seams between them close. That's the difference between a pinwheel and an actual kaleidoscope. Doing it by hand means negative scales and reversed winding, a mess you now don't have to write.

The folds are computed around wherever you are when you call it, so `translate` first if the center isn't the canvas center. And because it happens per draw call rather than per shape, a whole composition folds just as easily as a single arm.

## Drawing inside a shape

Repetition fills space. Sometimes you want it to fill *only part* of the space, and specifically a part shaped like something.

```swift
withClip(star) {
    // everything here lands only inside the star
}
```

<img src="Images/06-GridsAndRepetition/ClipRegions.jpg" alt="Three panels of the same diagonal orange stripes: confined to a star, confined to a circle, and confined to both at once so only the overlap of star and circle is striped" width="680">

`withClip` takes a `Shape`, a `Rectangle`, or a `Circle`, and confines everything drawn inside the block to that region. What makes it useful rather than merely convenient is that you don't have to work out the intersection yourself. The stripes in the figure are the same handful of long diagonal lines in all three panels. They are drawn straight past the edges, and the region decides what survives.

Nesting is the other half. A clip inside a clip keeps only what falls in both. That is how the third panel gets the lens-shaped overlap, with no geometry on your part. Letters make good clips too, since Chapter 7's `textToShapes` hands back shapes, so you can pour a whole pattern into a word.

## Grids that aren't square

The `Grid` this chapter opened with divides a rectangle into rectangles, which covers a great deal but not everything. Four more shapes of division come with Ollin, and all of them read the same way. Ask for the cells, then loop over them once.

<img src="Images/06-GridsAndRepetition/OtherGrids.jpg" alt="Four panels: a honeycomb tinted by ring distance from one cell, a field of alternating up and down triangles, a rectangle split recursively into unequal panels, and a carved maze" width="680">

```swift
for cell in hexGrid(columns: 12, rows: 10, gutter: 6).cells {
    drawPolygon(cell.corners)
}
for cell in triangleGrid(columns: 21, rows: 10).cells {
    fill(cell.pointsUp ? .white : .black)
    drawPolygon(cell.vertices)
}
for cell in subdivide(minSize: 90, chance: 0.75) {
    drawRect(cell.frame)
}
drawMaze(maze(columns: 24, rows: 24))
```

`hexGrid` and `triangleGrid` are the other two regular tilings, the only other shapes that tile a plane with no gaps and no overlaps. Hexagons can't stretch the way a rectangle can. So the block keeps its true proportions and centers itself, rather than distorting to fill your bounds. The hex grid also knows its own geometry, so `distance(from:to:)` counts rings between two cells. That is what colors the first panel, and exactly what a board game needs.

`subdivide` splits a rectangle in two, then splits the halves, and keeps going until the pieces hit `minSize` or a coin says stop. Uneven panels like that are hard to get from a grid and easy to get from recursion. That is why the result reads as a layout rather than a table.

`maze` carves a **perfect maze**. Every cell is reachable, and there is exactly one route between any two, so it has no loops and no isolated pockets. The algorithm you choose is a texture control as much as a technical one. `.backtracker` gives long winding corridors, while `.kruskal` gives an even sprawl of short dead ends. `drawMaze` strokes the walls, and the maze can also hand you its longest path, which is the single hardest route through it.

One more member of this family is a circle rather than a grid. `apollonianGasket(in:minRadius:)` fills a circle with the classic foam of ever-smaller kissing circles, each one the single circle that exactly touches its three neighbors. There's no randomness in it at all, so the same circle always gives the same foam. The circles come back in the order they were created, so their index doubles as an age you can color by.

## Tiles that agree at their edges

The pinwheel quilt hinted at this. When identical parts meet their cell edges the same way, random spins still fit. In 1704 a French priest named Sébastien Truchet worked out how far that idea goes, and the tiles named after him are its purest form. Ollin ships two as `drawTruchet`:

```swift
randomSeed(4)
stroke(.white)
strokeWeight(7)
strokeCap(.round)
noFill()
drawTruchet(columns: 8, rows: 8, tile: .arcs)
```

<img src="Images/06-GridsAndRepetition/TruchetTiles.jpg" alt="Two panels of white line work on dark squares: quarter-circle arcs joining into meandering loops, and corner-to-corner diagonals forming a maze" width="680">

`.arcs` is two quarter circles per cell, while `.diagonals` is a single corner-to-corner stroke. If you've ever seen the famous one-line maze program from 1982 home computers, that's exactly this tile. Both look far more planned than a coin flip per cell should allow, and the diagram below is the reason:

<img src="Images/06-GridsAndRepetition/TruchetJoins.jpg" alt="The arc tile's two spins, with dots marking where arcs end at edge midpoints; beside them, six randomly spun tiles whose arcs meet exactly at every shared edge midpoint" width="680">

The arc tile touches its cell's boundary in only four places, the edge midpoints, no matter which way it's spun. Think of the midpoints as doorways. Every tile has a doorway in the middle of each wall. So whatever your neighbor did, your marks and theirs meet at the doorway and flow through. Local rule, global order. Each tile only promises to hit its own doorways. The loops, corridors, and long wandering strands emerge across the whole canvas, with no tile knowing about them.

The tiling is drawn from the seeded `random`, so it's reproducible like everything since Chapter 4. Same seed, same maze. And when the plain white line-work isn't enough, `truchet(columns:rows:tile:)` hands you the raw strands instead of drawing them. That is one list of points per arc, which is exactly what the finished piece wants.

## One coin per line

Truchet spent one coin flip per cell. Hitomezashi, the one-stitch pattern of Japanese sashiko embroidery, spends even less: one flip per grid *line*. Every line carries a row of short dashes over alternating cells. The line's single bit picks which alternation, starting on the edge or one cell in. That's the whole rule. Neighboring lines shift against each other, so the dashes meet at the crossings and join into steps, staircases, and closed loops. A handful of coin flips reads as woven cloth.

```swift
seed(11)
stroke(.white); strokeWeight(4); strokeCap(.round)
drawHitomezashi(columns: 24, rows: 24)
```

One design has two faces, and `hitomezashi(columns:rows:)` hands you both. `.stitches` is the thread: one short strand per dash, ready for color, hatching, or a pen plotter, just like the Truchet strands above. `.parities` is the cloth. Every hitomezashi design splits into regions that exactly two tones can fill, and `parities` says which tone each cell wears. Draw the fill first and the stitches after, and every tone boundary lands exactly under a stitch:

```swift
let design = hitomezashi(columns: 24, rows: 24)
for (cell, tone) in zip(design.grid.cells, design.parities) {
    fill(tone ? Color(hex: 0x2C4A7F) : Color(hex: 0x18264A))
    drawRect(cell.frame)
}
stroke(Color(hex: 0xF2E9DC)); strokeWeight(4); strokeCap(.round)
for dash in design.stitches { drawPolyline(dash.points, closed: false) }
```

<img src="Images/06-GridsAndRepetition/HitomezashiFaces.jpg" alt="Two dark panels: cream dashes joining into stepped loops on indigo cloth, and the same design with its regions filled in two blues, every tone boundary sitting under a stitch" width="680">

Bias the flips with `probability:` and the weave drifts into long diagonal staircases. Or skip the coin entirely. `Hitomezashi(grid:rowBits:columnBits:)` takes explicit bits, and shorter arrays repeat along their lines. A favorite trick encodes a word as bits, a vowel as a 1, so a name becomes a design.

## Tiles that never repeat

Everything so far repeats. Slide a hex grid one cell over and it lands on itself. That regularity is most of its charm. But there are tile sets that *cannot* do this. However you lay them, the pattern never repeats, anywhere, ever. Order without repetition is a real, buildable thing.

<img src="Images/06-GridsAndRepetition/AperiodicTiles.jpg" alt="Four panels: Penrose kites and darts with colored arcs, Penrose rhombs, a teal star pattern woven over a honeycomb, and curved spectre tiles with a few orange ones" width="680">

The famous pair is the **Penrose tiling**, two shapes whose edge rules force endless variety with perfect five-fold poise. They are kites and darts, or a thick and a thin rhombus. `penroseTiling` grows one to cover the canvas. Each tile tells you its `kind` and carries two `arcs`, the classic decoration whose ends meet across every edge. So the whole tiling becomes one weave of curves:

```swift
for tile in penroseTiling(.rhombs, tileEdge: 36) {
    fill(tile.kind == .thick ? .indigo : .navy)
    drawShape(tile.shape)
    stroke(.orange)
    for arc in tile.arcs { drawPolyline(arc.points, closed: false) }
}
```

There's no randomness in it. The variety is the geometry's own. And since 2023 there's something stranger, the **spectre**. It is a *single* shape that tiles the plane and can never repeat. Mathematicians called the search for it the einstein problem, "one stone". `spectreTiling(tileEdge:curve:)` grows a patch. Give `curve` about `0.5` and the edges bend, so the tile can't even be flipped over. Each tile flags the rare `isOdd` misfits that sit rotated 30° from all the others, which are exactly the accent marks the pattern wants.

Two more relatives round out the family, both on the [aperiodic tilings](../Docs/Drawing/AperiodicTilings.md) page. **Wang tiles** (`wangTiling`) are squares with colored edges that may only sit together where the colors agree. This is where never-repeating tilings were first discovered. Run the other way, with a seeded fill over a small friendly set, the edge rule turns independent random picks into one connected quilt. And **girih patterns** (`girihPattern`) take the Truchet doorway idea somewhere older and grander. From the midpoint of every tile edge, two rays walk into the tile at a chosen angle and stop where they meet another. Keep the crossings, erase the tiles, and an Islamic star pattern remains. It works over *any* edge-to-edge polygons, including your hex grid's cells and the five traditional girih tile shapes. The contact angle is one dial that morphs the whole design from spiky to woven:

```swift
let cells = hexGrid(columns: 9, rows: 8).cells.map(\.corners)
stroke(.white); noFill()
drawGirih(over: cells, angle: 60)   // 54° is the classic girih-tile angle
```

## Putting it together: a meandering tangle

Now you can build the image at the top. The plan is to lay Truchet arcs over a grid, then stroke every strand twice. A wide pass in a dark rim tone comes first, then a narrower colored pass on top. The strands then read as piping with a little depth. For the color, reach back to Chapter 5 and sample `noise` at each strand's midpoint. Neighbors then wear neighboring colors, and the palette drifts across the tangle like weather, slowly changing with `time`. Make a new file, `MySketches/Meander.swift`:

```swift
import Ollin

final class Meander: Sketch {
    @Param("Columns", 6...26) var columns = 14
    @Param("Seed", 1...9999) var quiltSeed = 3
    @Param("Diagonals") var diagonals = false

    let paper = Color(hex: 0x14161B)
    let ramp = Ramp([
        Color(hex: 0xF2542D), Color(hex: 0xF5DFBB),
        Color(hex: 0x0E9594), Color(hex: 0x127475),
    ])

    override func draw() {
        seed(quiltSeed)
        background(paper)
        noFill()
        strokeCap(.round)

        let cell = width / Double(columns)
        let strands = truchet(columns: columns, rows: columns,
                              tile: diagonals ? .diagonals : .arcs)

        // Two passes: first every strand slightly wide in a rim tone, then
        // the color on top, so strands running close stay separated.
        stroke(Color(hex: 0x2A2E38))
        strokeWeight(cell * 0.40)
        for strand in strands {
            drawPolyline(strand.points)
        }

        strokeWeight(cell * 0.26)
        for strand in strands {
            let mid = strand.midpoint
            let weather = noise(mid.x * 0.0016, mid.y * 0.0016, time * 0.06)
            stroke(ramp.color(at: weather))
            drawPolyline(strand.points)
        }
    }

    override func mousePressed() {
        quiltSeed += 1
    }
}
```

Run it, watch the colors migrate, and click for a fresh tangle. What each piece contributes:

- `seed(quiltSeed)` locks both `random` and `noise` at the top of every frame, so the layout holds still while `time` drifts the colors, and the Seed knob (or a click) is a whole new piece.
- `truchet(...)` returns the strands as values instead of drawing them. Each is a contour, a list of points in `.points`, and `drawPolyline` strokes one list.
- The two passes are an old illustrator's trick. The rim pass is a touch wider than the color pass, so wherever two strands run close, a dark seam keeps them apart. Drawing *all* rims before *any* color is what keeps each strand's own segments merging smoothly into one pipe.
- `strand.midpoint` is the point halfway along a strand, and `noise` at that spot (scaled way down, Chapter 5's zoom knob) picks its color from the ramp. Nearby strands ask nearby questions, so color arrives in weather-like patches instead of confetti.
- The knobs cover a lot of ground: `Columns` runs the piece from chunky plumbing at 6 to fine knitting at 26 (the stroke widths ride the cell size, so everything stays in proportion), and the `Diagonals` toggle swaps the whole mood from tangle to circuit board.

Before moving on, make it yours:

- Swap the ramp. Four colors change this piece more than anything else in it; try an all-warm set, or two blues and a shock of yellow.
- Color by strand *position* instead of noise: `mid.y / height` as the ramp's input turns the weather into a sunset gradient.
- Drop the rim pass's width to `cell * 0.55` and the color to `cell * 0.1` for wire-thin strands floating in fat shadows.
- Drive `strokeWeight` in the color pass from the same `weather` value, so warm patches also swell.

## Where this comes from

Truchet tiles are named for Sébastien Truchet, a French Carmelite priest. He published a memoir in 1704 on the patterns a single diagonally split tile can make, after watching ceramic tiles being laid for a château. The quarter-circle arc tile this chapter leans on is a later refinement by the metallurgist and historian Cyril Stanley Smith. His 1987 paper revisited Truchet's work, and connected it to how structure builds hierarchy in materials. Generative artists adopted it so thoroughly that "Truchet tiles" now usually *means* Smith's arcs. The diagonal tile has its own pop-culture monument. The Commodore 64 one-liner `10 PRINT CHR$(205.5+RND(1)); : GOTO 10` is a maze in thirty-eight characters. Its history got an entire excellent book, *10 PRINT*, by Nick Montfort and nine co-authors in 2012. The paper-moving transform model goes back to the earliest days of computer graphics and reached creative coding through Processing's `pushMatrix`/`popMatrix`. The pinwheel quilt is older than all of it, pieced by quilters long before anyone had a coordinate system to rotate. Hitomezashi comes from the same needle-first world: a running-stitch mending tradition from Japan, worked one stitch per grid space. The mathematician Katherine Seaton, with Carol Hayes, showed its designs are exactly the one-bit-per-line encoding this chapter uses. She also proved the two-tone fill always works. The never-repeating tiles have their own lineage. Hao Wang conjectured in 1961 that his edge-matching squares could always be made periodic, and his student Robert Berger proved him wrong. Roger Penrose got the tile count down to two in the 1970s. The one-tile question then stayed open until 2023. David Smith, a retired print technician playing with paper cutouts, found the hat. The spectre followed, with Joseph Myers, Craig Kaplan, and Chaim Goodman-Strauss. The girih strapwork method is E. H. Hankin's polygons-in-contact technique, formalized for the computer by Craig Kaplan. The five girih tiles decorate buildings from medieval Isfahan to Istanbul. If the tangle left you wanting more, Christopher Carlson's multi-scale Truchet tiles are worth a look. They put arcs at mixed cell sizes that still agree at the edges. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Geometry](../Docs/Drawing/Geometry.md): the full `Grid` reference (spanning points, nesting, singular access), `Insets`, and `Rectangle`.
- [Drawing](../Docs/Drawing/Drawing.md): the transform stack in detail, `pushState`/`popState` (the unscoped siblings of `withState`), and every shape that benefits.
- [Kaleidoscope symmetry](../Docs/Drawing/Drawing.md#symmetry): the full reference for `symmetry`/`noSymmetry`, including which drawing paths fold and which don't. The [`Patterns/Kaleidoscope`](../Examples/Patterns/Kaleidoscope/Sketch.swift) example draws a single arm and lets the folds do the rest.
- [Clipping](../Docs/Drawing/Drawing.md#clip): the reference, including how clips interact with layers and what vector export does with them. The [`Shapes/Clipping`](../Examples/Shapes/Clipping/Sketch.swift) example sweeps a lens across a striped star.
- [Truchet](../Docs/Drawing/Truchet.md): both tiles, the contour output, and feeding the strands to booleans, hatching, or SVG export.
- [Hitomezashi](../Docs/Drawing/Hitomezashi.md): the stitch reference, the two faces, biased flips, and explicit bits for encoded designs.
- [Tiling and layout](../Docs/Drawing/Tiling.md): every knob for `HexGrid`, `TriangleGrid`, `Subdivision`, `Maze`, and `apollonianGasket`, including hex orientation and picking, the quadtree split style, all three maze algorithms, and the longest-path helper.
- [Aperiodic tilings](../Docs/Drawing/AperiodicTilings.md): the full reference for `penroseTiling` (both variants and the arcs), `wangTiling` (tile sets, weights, the complete set), `girihPattern` (the contact angle, the five girih tiles, composing them edge to edge), and `spectreTiling`.
- Worked examples: [`Patterns/Grid`](../Examples/Patterns/Grid/Sketch.swift) (the grid helper's tour), [`Patterns/Truchet`](../Examples/Patterns/Truchet/Sketch.swift) (both tiles, animated), [`Patterns/Hitomezashi`](../Examples/Patterns/Hitomezashi/Sketch.swift) (both faces, on a breathing cloth), [`Patterns/Penrose`](../Examples/Patterns/Penrose/Sketch.swift) (rhombs with breathing arcs), [`Patterns/WangTiles`](../Examples/Patterns/WangTiles/Sketch.swift) (the re-laying quilt), [`Patterns/Girih`](../Examples/Patterns/Girih/Sketch.swift) (the angle dial swept live, plus the decagon-and-pentagons medallion), and [`Patterns/Spectre`](../Examples/Patterns/Spectre/Sketch.swift) (the einstein with a drifting tide).
- A teaser for later: [`Patterns/WaveFunctionCollapse`](../Examples/Patterns/WaveFunctionCollapse/Sketch.swift) plays the agree-at-the-edges game with *constraints*, tiles that refuse certain neighbors, and Chapter 11 watches it solve.

---

[Contents](README.md#contents) · Previous: [Chapter 5, Noise](05-Noise.md) · Next: [Chapter 7, Words and pictures](07-WordsAndPictures.md)
