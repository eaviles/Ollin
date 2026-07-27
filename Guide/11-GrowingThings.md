#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 11</sup>

---

# 11. Growing things

<img src="Images/11-GrowingThings/Garden.jpg" alt="A dark garden bed: a pale branching tree with a thick trunk fills the sky, six green fern-like plants stand along the soil, and gray-green lichen sprawls at the ground line" width="560">

Chapter 10 grew behavior; this chapter grows form. Everything in the garden above was grown, not drawn: the tree claimed its patch of air branch by branch, the plants were written by a grammar that rewrites itself, and the lichen froze into place one wandering particle at a time. Four ways to grow, and by the end you'll have planted all of them in one bed.

## A tree from one rule

Start with the oldest trick there is: a function that calls itself. Draw a trunk. At its top, draw two smaller trees, one tilted left, one tilted right. Each of those draws its own trunk and its own two smaller trees, and so on down, until the trees are too small to bother. Make `MySketches/TreeByHand.swift`:

```swift
import Ollin

final class TreeByHand: Sketch {
    @Param("Angle", 0.1...0.6) var angle = 0.32
    @Param("Shrink", 0.55...0.78) var shrink = 0.7

    override func draw() {
        background(Color(hex: 0x101318))
        stroke(Color(hex: 0xE8DCC0))
        strokeCap(.round)

        withState {
            translate(width / 2, height - 110)
            branch(length: 235, depth: 9)
        }
    }

    func branch(length: Double, depth: Int) {
        guard depth > 0 else { return }
        let sway = sin(time * 0.8 + Double(depth)) * 0.02
        strokeWeight(Double(depth) * 0.9)
        drawLine(0, 0, 0, -length)
        translate(0, -length)
        withState {
            rotate(-angle + sway)
            branch(length: length * shrink, depth: depth - 1)
        }
        withState {
            rotate(angle * 1.15 + sway)
            branch(length: length * shrink, depth: depth - 1)
        }
    }
}
```

<img src="Images/11-GrowingThings/TreeByHand.jpg" alt="A bare fractal tree in pale ink on a dark canvas: one trunk splitting into two branches, each splitting again, nine levels deep into a fine canopy" width="560">

This is **recursion**: a rule applied to its own output. `branch` draws one segment and then asks `branch` to finish the job, twice, smaller. The `depth` counter is what keeps it from asking forever, and `guard depth > 0 else { return }` is the floor it stops on. Nine levels is `2⁹` tips, five hundred twelve of them, out of fourteen lines of code.

Look at where `withState` sits, because it's doing the quiet work. Each branch draws in its own coordinate world (Chapter 6's trick): `translate` walks to the top of the segment just drawn, each `withState { rotate(...) ... }` tilts, recurses, and *puts the transform back* when its block ends. That put-it-back is the whole trick of drawing a tree: after the left subtree finishes, wherever its thousands of segments wandered, the pen is back at the fork, facing the way the fork faced, ready for the right subtree. A saved-and-restored state is how every branching drawing in this chapter works, and it's about to get a name from 1968.

The `* 1.15` on the right angle is a small honesty about nature: perfectly symmetric trees read as diagrams. Drag the two knobs while it runs; `Shrink` near 0.78 grows old oaks, `Angle` near 0.15 grows poplars.

> **Swift note.** A method can call itself by name, no ceremony needed. The one rule is that something must change on the way down (here `depth - 1`) so a call eventually stops. Each call gets its own copy of `length` and `depth`, which is why the left subtree's shrinking doesn't disturb the right's.

## Rules that rewrite

In 1968 the biologist Aristid Lindenmayer wanted to describe how plants grow, and wrote it as grammar: start from a short string of symbols, and each season, rewrite every symbol by a fixed rule, all at once. The strings these **L-systems** produce turn into drawings through a turtle: read the final string left to right as pen commands. `F` means draw forward. `+` and `-` mean turn by the system's angle. `[` means *save the pen's position and heading*, and `]` means *put it back*: the same save-and-restore you just met as `withState`, spelled as punctuation.

Here's the guide's plant grammar, rewritten one, two, three, and four times:

<img src="Images/11-GrowingThings/LSystemExpansion.jpg" alt="Four panels of the same plant grammar drawn after one to four rounds of rewriting, growing from a bare stalk to a full fern, with the letter count under each panel rising from 18 to 1551" width="680">

Nothing about the drawing code changes between panels. The drawing gets richer because the *sentence* gets longer: every `X` in the string sprouts the whole shoot pattern each round, so eighteen letters become fifteen hundred in four rewrites. Growth by rewriting is exponential, which is exactly how a twig's worth of rule makes a tree's worth of structure.

Ollin ships the grammar machine as `LSystem`, thirteen classic presets, and a turtle that returns ordinary contours. Drawing one is a line:

```swift
import Ollin

final class Fern: Sketch {
    override func draw() {
        background(Color(hex: 0x101318))
        stroke(Color(hex: 0x9AD9A0))
        strokeWeight(1.6)
        strokeCap(.round)
        drawLSystem(.plant, iterations: 5)
    }
}
```

<img src="Images/11-GrowingThings/Fern.jpg" alt="A drooping fern-like plant in soft green line work, grown from the plant grammar at five rewriting rounds" width="560">

`drawLSystem` fits the grown form to the canvas and strokes it; its sibling `lSystem(...)` returns the contours instead, for when you want to place, color, or export them yourself (the garden does). A grammar of your own is one constructor: `LSystem(axiom: "F", rules: ["F": "F+F-F-F+F"], angle: 90)` is the Koch curve, and the [L-systems reference](../Docs/Generators/LSystem.md) lists the whole preset shelf, from `.dragonCurve` to `.hilbertCurve`.

One more idea turns plants into *populations*. Give a symbol several possible rewrites and let a seeded roll pick one each time it's rewritten (`.randomPlant` does this), and every plant grown from the same grammar is a different individual with the same species' look. Chapter 4's promise pays off here: because the rolls come from your `seed`, the same seed grows the same garden, down to the last twig.

## Growth that claims space

Grammars grow blind: the fern doesn't know where the canvas ends or where its own leaves already are. The next grower looks before it grows. Scatter *attraction points* over the region you want filled; plant a root; then repeat three moves. Every attractor pulls on the closest branch tip within its reach. Every pulled tip grows one small step toward the average of its pulls. Every attractor a branch reaches is consumed, so its pull disappears and the growth moves on:

<img src="Images/11-GrowingThings/ClaimingSpace.jpg" alt="Four panels of the same growth at step 6, 18, 40, and finished: ink veins spread from a bottom root into a field of orange dots, and the dots vanish as branches reach them" width="680">

This is **space colonization**, and it grows the most convincing veins, roots, and trees in generative art, because it grows the way real veins do: toward unclaimed space, never doubling back into crowded territory. In Ollin it's `SpaceColonization`, another stepper you hold (the Chapter 10 shape):

```swift
let veins = SpaceColonization(attractors: poissonDisk(radius: 26),
                              roots: [Vector2(width / 2, height - 70)])
```

`poissonDisk` is doing the scattering: it returns an even, organic sprinkle of points, no two closer than the radius you ask for (Chapter 13 looks inside it; for now, it's a bag of well-spread points). The growth itself has no randomness at all. Same attractors, same roots, same veins, every run.

Three distances shape the result, and they want a relationship: `stepLength` (how far a tip grows per step) should stay smaller than `killRadius` (how close counts as reached), or a tip can step right over its goal, and `killRadius` well under `influenceRadius` (how far an attractor's pull reaches). One practical gotcha: growth only *starts* if some attractor's pull can reach a root, so a tree whose crown floats high above its root needs an `influenceRadius` at least as long as the trunk-to-crown gap. The garden's tree hit exactly this.

The last touch is weight. `thicknesses(leafWidth:exponent:)` gives every node a stroke width by the pipe model: tips are hairline, and every fork is as thick as its children can justify, the way a real trunk carries its crown. The `Patterns/Venation` example grows a whole leaf's veins this way, live.

## Growth by chance

The third grower has no goals at all. Freeze one particle in the middle. Release a random walker from somewhere far away and let it wander; the moment it touches the frozen cluster, it freezes too, and the next walker sets out:

<img src="Images/11-GrowingThings/FrozenWalkers.jpg" alt="Two panels: left, a gray wandering path drifts in from the corner and ends at an orange dot marked frozen on the edge of a small ink cluster; right, a dendritic cluster of eight hundred dots with wispy arms and open hollows" width="680">

That's the entire algorithm, and it's called **diffusion-limited aggregation** (DLA). The shape it grows is not an accident: a wandering particle almost always bumps into a *tip* before it can thread its way into a hollow, so tips grow and hollows starve. Frost on a window, minerals crystallizing in stone, and coral all play this game, which is why the clusters look instantly familiar.

```swift
let cluster = DiffusionLimitedAggregation(seeds: [center], seed: 7)

override func draw() {
    cluster.step(12)          // a dozen new arrivals per frame
    background(.black)
    fill(.white)
    noStroke()
    drawCircles(cluster.positions, radius: 3)
}
```

Because particles freeze in arrival order, `cluster.particles[i]` froze `i`-th, and tinting by index paints the cluster's whole life story as rings of color; each particle also remembers which particle it stuck to, so `segments` gives the branching skeleton as plain lines. `stickiness` below `1` lets walkers slide deeper before freezing (denser, mossier clusters), and seeding a *row* of points instead of one center grows frost creeping up from an edge. The `Patterns/Dendrite` example is the ring-tinted version.

## Every neighbor must agree

The last technique in this chapter grows nothing, strictly speaking, but it belongs with the growers because its results read as one organism. Wave Function Collapse fills a grid from a small set of tiles under one law: neighboring tiles must agree along their shared edge. Each tile declares a *socket* per edge (pipe or blank, in the classic set), and the solver keeps every cell's options open, repeatedly settling the most-constrained cell and propagating what that choice forbids:

<img src="Images/11-GrowingThings/TilesAgree.jpg" alt="Left, three enlarged pipe tiles with orange dots marking their pipe sockets and hollow dots their blank edges; right, an eleven-by-eleven solved grid where every pipe meets a pipe and the network connects" width="680">

Building the tileset is most of the work, and it's pleasantly declarative. A tile is its four edge sockets, top, right, bottom, left; `rotations()` mints the turned variants; a `weight` makes a tile more or less common:

```swift
let blank = WFCTile([0, 0, 0, 0], weight: 1.1)
let line = WFCTile([1, 0, 1, 0], weight: 1.5).rotations(2)
let elbow = WFCTile([1, 1, 0, 0], weight: 1.2).rotations(4)
let tee = WFCTile([1, 1, 1, 0], weight: 0.5).rotations(4)
let tiles = [blank] + line + elbow + tee

let grid = wfc(tiles: tiles, columns: 11, rows: 11)   // [[Int]] of tile indices
```

`wfc` is seeded like everything else, and `drawWFC` walks the solved grid cell by cell handing you the tile index to draw (the figure above draws a stroke from each cell's center to every edge whose socket is `1`, which is the entire renderer for a pipe network). One draw block covers a tile *and* its rotations, because you draw from the sockets, not from a picture per tile. The `Patterns/WaveFunctionCollapse` example re-rolls a fresh legal network every few seconds.

## Putting it together: a garden

Time to plant everything at once. The garden grows three systems in one bed, and one `seed(5)` at the top makes the whole thing a single reproducible organism. Make `MySketches/Garden.swift`:

```swift
import Ollin

final class Garden: Sketch {
    private var tree: SpaceColonization?
    private var plants: [[Contour]] = []
    private var tufts: [DiffusionLimitedAggregation] = []
    private let groundY = 880.0

    override func setup() {
        seed(5)

        // The tree wants the air inside an oval crown above the trunk.
        let crown = Vector2(540, 430)
        let attractors = poissonDisk(in: Rectangle(x: 190, y: 180, width: 700, height: 520),
                                     radius: 24).filter { p in
            let dx = (p.x - crown.x) / 350, dy = (p.y - crown.y) / 260
            return dx * dx + dy * dy < 1
        }
        // The influence radius must reach the crown from the root, or the
        // trunk never starts growing.
        tree = SpaceColonization(attractors: attractors, roots: [Vector2(540, groundY)],
                                 influenceRadius: 280, killRadius: 20, stepLength: 10)

        // A row of plants, each a stochastic L-system in its own patch.
        for (i, x) in [130.0, 260, 400, 700, 830, 950].enumerated() {
            let height = 150 + Double((i * 37) % 90)
            let patch = Rectangle(x: x - 70, y: groundY - height, width: 140, height: height)
            let preset: LSystem = i % 3 == 2 ? .bush : .randomPlant
            plants.append(lSystem(preset, iterations: 4, in: patch, padding: 6))
        }

        // Lichen tufts, half-buried where they were seeded.
        for x in [220.0, 620, 890] {
            tufts.append(DiffusionLimitedAggregation(
                seeds: [Vector2(x, groundY)], particleRadius: 2.2,
                maxParticles: 280, seed: UInt64(x)))
        }
    }

    override func draw() {
        guard let tree else { return }
        tree.step()
        for tuft in tufts { tuft.step(4) }

        background(Color(hex: 0x0F130D))

        // The soil.
        noStroke()
        fill(Color(hex: 0x1A2014))
        drawRect(Rectangle(x: 0, y: groundY, width: width, height: height - groundY))

        // Lichen.
        for (i, tuft) in tufts.enumerated() {
            fill(Color(hex: i % 2 == 0 ? 0x66805E : 0x4E6B57).withAlpha(0.85))
            drawCircles(tuft.positions, radius: 2.2)
        }

        // Plants, in two greens.
        noFill()
        strokeCap(.round)
        strokeWeight(2.4)
        for (i, plant) in plants.enumerated() {
            stroke(Color(hex: i % 2 == 0 ? 0x7FB069 : 0x5C8D5A))
            for contour in plant { drawPolyline(contour.points) }
        }

        // The tree, weighted by the pipe model.
        let widths = tree.thicknesses(leafWidth: 1.1, exponent: 2.4)
        stroke(Color(hex: 0xD9C9A0))
        for (i, node) in tree.nodes.enumerated() {
            guard let parent = node.parent else { continue }
            strokeWeight(widths[i])
            drawLine(tree.nodes[parent].position, node.position)
        }
    }
}
```

<img src="Images/11-GrowingThings/GardenMotion.gif" alt="The garden growing: a pale tree climbs from the soil and branches into its crown while lichen tufts creep outward along the ground between still green plants" width="480">

The plants finish growing before the first frame (rewriting is instant; it's just strings), while the tree and the lichen grow in front of you, which is the honest shape of each algorithm: grammars produce, steppers *live*. Watch the trunk set off upward with no attractor consumed yet, pulled by the whole crown at once.

> **Swift note.** `filter` keeps the elements that pass a test: the crown is carved out of a rectangular scatter by keeping only points inside an oval. Like `map` before it, it reads left to right: take the scatter, keep what passes.

Then make it yours:

- Re-roll the world: change `seed(5)` and every plant, branch, and tuft is a new individual of the same species.
- Seasons: tint the tree's tips by their thickness (thin means young) and the garden gets spring growth; fade the plants' green toward ochre for autumn.
- Let the lichen win: raise the tufts' `maxParticles` to a few thousand and the ground becomes a carpet slowly swallowing the plant stems.
- Grow the tree around an obstacle: cut a hole in the attractor scatter (another `filter`) and the crown will politely grow around the missing space, no extra code.
- A hanging garden: flip the tree's root to the top edge and the crown ellipse below it, and gravity reverses without a single physics line.

## Where this comes from

L-systems are Aristid Lindenmayer's 1968 invention, and their visual language comes from *The Algorithmic Beauty of Plants* (1990), his book with Przemyslaw Prusinkiewicz, still free to read online and still beautiful. Space colonization is by Adam Runions, Brendan Lane, and Prusinkiewicz at the University of Calgary's Algorithmic Botany group ("Modeling Trees with a Space Colonization Algorithm", 2007, after their 2005 leaf-venation work). Diffusion-limited aggregation was described by the physicists Thomas Witten and Leonard Sander in 1981, and generative artists have been growing frost with it ever since. Wave Function Collapse is Maxim Gumin's 2016 algorithm, named with a physicist's wink; the tile-and-socket form here is its simple-tiled model. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [L-systems](../Docs/Generators/LSystem.md): the grammar type, the turtle alphabet, and all thirteen presets.
- [Space colonization](../Docs/Generators/SpaceColonization.md): every knob, plus recipes for venation, lightning, and multi-root plantings.
- [Diffusion-limited aggregation](../Docs/Generators/DiffusionLimitedAggregation.md): stickiness, cages, and drawing the skeleton.
- [Wave Function Collapse](../Docs/Generators/WaveFunctionCollapse.md): sockets, weights, rotations, and what to do when a solve fails.
- [Blue noise](../Docs/Generators/BlueNoise.md): the even scatter the tree's crown was carved from, properly explained in Chapter 13.
- Worked examples: [`Examples/Patterns/LSystem`](../Examples/Patterns/LSystem/Sketch.swift) (the preset contact sheet), [`Examples/Patterns/Venation`](../Examples/Patterns/Venation/Sketch.swift), [`Examples/Patterns/Dendrite`](../Examples/Patterns/Dendrite/Sketch.swift), and [`Examples/Patterns/WaveFunctionCollapse`](../Examples/Patterns/WaveFunctionCollapse/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 10, Flocks and swarms](10-FlocksAndSwarms.md) · Next: [Chapter 12, Fields and flow](12-FieldsAndFlow.md)
