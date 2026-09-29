#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 23</sup>

---

# 23. Simulations on a grid

<img src="Images/23-GridSimulations/Organism.jpg" alt="A dense teal brain-coral labyrinth grown by reaction-diffusion, its winding ridges lit with a wet sheen against deep navy gaps" width="560">

A simulation field is a grid of cells on the GPU, and every frame each cell changes by asking its neighbors. You seed one by drawing into it, and run rules on it from the Game of Life to reaction-diffusion. The corridors at the top grew from a scatter of dots, and whatever you draw while the sketch runs joins the chemistry. The other rules follow in families: automata, piles and fires, crowds past a threshold, chemistries, fields that move, materials, and your own rule.

## State that lives on the GPU: SimField and withField

[Chapter 19](19-LayersAndEffects.md)'s feedback layer was the first taste of a picture fed its transformed self back in, frame after frame. A simulation field replaces "transform the whole picture" with something more local. Every cell of the field computes its next value *from its neighbors*, all at once, every frame. It is [Chapter 18](18-YourFirstShader.md)'s per-pixel function with one addition, memory.

In Ollin that is a `SimField`. Like `Feedback`, it persists, so make it once and keep it. You never write the kernel for the built-in ones. Pick a `Sim`, draw into the field to seed it, and composite its `image`:

```swift
var life: SimField?

override func draw() {
    if life == nil { life = makeSimField(.gameOfLife(), scale: 0.08) }   // once, then kept
    guard let life else { return }
    withField(life) {
        if mouseIsPressed { fill(.white); drawCircle(mouseX, mouseY, 20) }
    }
    drawImage(life.image, 0, 0)
}
```

The field is made on the first frame and held in a property, so every later frame steps the same field. `withField` works like [Chapter 19](19-LayersAndEffects.md#a-drawing-you-can-hold-render-targets)'s `withTarget`, and what a drawn mark *means* depends on the simulation. For the Game of Life, white means alive.

## The Game of Life: a first field

Conway's Game of Life is the classic proof that simple local rules make worlds. Each cell of a grid is alive or dead, and from one generation to the next it asks only about its eight neighbors:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/LifeRules-dark.jpg">
  <img src="Images/23-GridSimulations/LifeRules.jpg" alt="Three three-by-three neighborhoods and their outcomes: a cell with one neighbor dies, a cell with two or three lives on, an empty cell with exactly three neighbors is born" width="680">
</picture>

That is the entire rule. No cell knows about the picture. Seed a field with a random soup anyway and structures appear. You get stable blocks, blinking pairs, and now and then a *glider* that walks off across the grid on its own:

```swift
withField(life) {
    noStroke()
    fill(.white)
    if frameCount == 1 {                       // a random soup, once
        for _ in 0 ..< 700 {
            drawCircle(width * 0.5 + random(-260, 260),
                       height * 0.5 + random(-260, 260), 7)
        }
    }
}
```

<img src="Images/23-GridSimulations/LifeField.jpg" alt="A Game of Life field ninety generations after a random soup: scattered still lifes, blinkers, and small debris in crisp white cells on black" width="560">

The `scale: 0.08` matters, because a sim field's `scale` sets its internal resolution. For a cellular automaton one texel is one cell, so a low scale gives cells you can see. For the other sims, a lower scale means broader, cheaper features.

## A field is data: gradientMap, levels, and relight

Life's `image` already reads as a picture, because a cell is black or white. Most fields do not. The raw field is *data*. Reaction-diffusion stores two chemicals as dim red and green. The ripple pool stores a height and a velocity, and a pile of sand stores a count of grains as a gray level. `image` hands you that data as stored, which is useful for seeing what a field is doing and rarely what you want on the canvas. So you give a field a look by filtering it, through the same catalog [Chapter 19](19-LayersAndEffects.md#filters) used on a layer. Three filters do most of the work:

- `.gradientMap` reads each texel's brightness and looks a color up along a `Ramp` from [Chapter 2](02-Color.md), or a `Colormap` such as `.viridis` or `.magma`. One color per level is how an automaton's few states become a picture, and a smooth ramp is how a chemical's concentration becomes skin.
- `.levels(blackPoint:whitePoint:)` stretches a narrow band of values to the full range. A field whose state sits in one narrow band maps to nearly one gray. Pull the band's two ends to black and white, and the structure inside it appears. Do this before the gradient map, so the ramp gets the full range to work with.
- `.relight` from [Chapter 20](20-PicturesRestyled.md) reads the field as height and lights it, which turns ridges into relief and a height field into water.

```swift
let inks = Ramp([Color(hex: 0x06131F), Color(hex: 0x3FA893)])
drawImage(life.filtered(.gradientMap(inks)).image, 0, 0)
```

Filters chain, so `.filtered(.levels(blackPoint: 0.16, whitePoint: 0.42)).filtered(.gradientMap(inks))` runs one after the other. The organism at the end of the spine stacks all three. The `.threshold` filter is there for hard ink. The raw `image` stays the view to reach for when a field is doing something you did not expect.

## Two chemicals: reaction-diffusion

Reaction-diffusion is the Game of Life's continuous cousin, and the engine of the organism. The idea comes from Alan Turing. Two chemicals spread through a surface and react, one feeding the pattern and one killing it. In the balance between those two rates, patterns *make themselves*. Ollin ships the two-chemical form as `.reactionDiffusion(feed:kill:)`, and those two numbers are the system's temperament:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/FeedKillMap-dark.jpg">
  <img src="Images/23-GridSimulations/FeedKillMap.jpg" alt="A six-by-four grid of reaction-diffusion dishes at different feed and kill settings: about half sit quiet, while a diagonal band grows large spots, rings, mazes, and grids of small dots" width="680">
</picture>

About half the map is quiet. Patterns grow only in a band where feeding and killing balance, and each regime along that band has its own signature. There are dividing dots, and there are the worm mazes and coral walls the defaults grow. Put `feed` and `kill` on `@Param` parameters and you can walk the map live. The [`Simulation/GrayScott`](../Examples/Simulation/GrayScott/Sketch.swift) example runs the dish at the defaults, a place to start from.

The regime does not have to be one choice for the whole dish. Give the sim two settings, `.reactionDiffusion(feed: 0.046, kill: 0.065, toFeed: 0.055, toKill: 0.062)`, then attach any drawn or generated layer as `dish.modulation`. That layer's brightness picks the spot on the map for every texel: black runs the first pair, white the second. A picture can choose the chemistry, place by place. It stays one simulation, so the two patterns grow into each other instead of meeting at a mask's hard edge. The `Vision/TuringMirror` example draws the camera's person matte into that layer. The field grows maze walls on your silhouette and spots everywhere else, and it reorganizes as you move.

Here is the same idea with a drawn layer instead of a camera, so the boundary can be looked at:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/ChemistryByPicture-dark.jpg">
  <img src="Images/23-GridSimulations/ChemistryByPicture.jpg" alt="Three square panels. Left, a soft-edged white disc on black. Middle, one reaction-diffusion dish colored teal on blue: a maze of walls inside the disc's footprint thinning out into scattered spots beyond it, with wall ends reaching into the spot field. Right, two separate dishes, a maze cut into a spot field along a circle drawn in orange, the pattern stopping dead at the line" width="680">
</picture>

The disc is the map. Inside it the field runs the maze pair, and outside it the spot pair. Across the soft edge the maze's walls thin out into dots instead of stopping. The right dish is what a mask gives instead: two separate simulations cut along the same circle, and the seam knows nothing about either. Draw the map every frame before you read the field, since a frame with no map runs the plain black-end pair.

Seeding is drawing, as it was for Life. Watch what one mark becomes:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/Seeding-dark.jpg">
  <img src="Images/23-GridSimulations/Seeding.jpg" alt="Four dishes seeded with the same ring at different moments, showing its growth: the raw ring, a thickened double ring, a wavy cross, and a labyrinth filling the dish" width="680">
</picture>

## Putting it together: the organism

The finished sketch grows a culture. It composes the four steps above. A field is made once and held. A scatter of spores is drawn into it on the first frame, seeding a reaction-diffusion dish in its maze regime. Whatever you draw while it runs joins the chemistry. The display is the data step's pipeline: a levels stretch, a gradient map for the skin, and a liquid relight so the ridges catch light. Make `MySketches/Organism.swift`:

```swift
import Ollin

final class Organism: Sketch {
    var dish: SimField?

    override func setup() {
        seed(7)
        toneMap(.aces, exposure: 1.15)
    }

    override func draw() {
        background(Color(hex: 0x04070B))
        if dish == nil { dish = makeSimField(.reactionDiffusion(feed: 0.055, kill: 0.062), scale: 0.5) }
        guard let dish else { return }

        withField(dish) {
            noStroke()
            fill(.white)
            if frameCount == 1 {                       // the culture's first spores
                for p in poissonDisk(radius: 170) { drawCircle(center: p, radius: 5) }
            }
            if mouseIsPressed {                        // and whatever you draw
                drawCircle(mouseX, mouseY, 9)
            }
        }

        let skin = Ramp([Color(hex: 0x06131F), Color(hex: 0x0E4C5C),
                         Color(hex: 0x3FA893), Color(hex: 0xF2E3C2)])
        drawImage(dish.filtered(.levels(blackPoint: 0.16, whitePoint: 0.42))
                      .filtered(.gradientMap(skin))
                      .filtered(.relight(.liquid, height: 1.4)).image, 0, 0)
    }
}
```

Run it live and draw. Your marks do not appear on the canvas. They enter the chemistry, and thirty frames later something is growing where your hand was. You set the conditions, and the picture grows from them. What each piece contributes:

- `poissonDisk(radius:)` from [Chapter 4](04-Randomness.md) scatters the spores evenly, and `seed(7)` in `setup()` makes the same scatter every run. `feed: 0.055` and `kill: 0.062` sit in the maze regime of the map above.
- The levels stretch pulls the dish's dim state, most of it between 0.16 and 0.42, out to the full range. The four-color ramp then paints it from the deep gaps to the pale ridges.
- `.relight(.liquid, height: 1.4)` reads the ramped picture as height and lights it wet. `toneMap(.aces, exposure: 1.15)` from [Chapter 19](19-LayersAndEffects.md#brighter-than-the-screen-tonemap) keeps the highlights from clipping.

Then make it yours:

- Walk the map by putting `feed` and `kill` on parameters, and steer the culture between mitosis, worms, and coral while it grows.
- Recolor the skin ramp. The same labyrinth reads as coral, lichen, or circuitry depending entirely on four colors.
- Seed with meaning. [Chapter 8](08-Words.md)'s `drawText` into the field grows a word into a labyrinth that slowly forgets it was a word.
- Swap `.relight(.liquid)` for `.relight(.metal, color:)` and the organism becomes an engraving.

A culture is best kept as it grows, so keep it as a video. The command `swift run OllinLive MySketches/Organism.swift --export-video organism.mp4 --seconds 20` records the first twenty seconds, from the spores on.

## More ways to be an automaton: elementary rules, turmites, Lenia, SmoothLife, excitable media, and Wireworld

The organism ran one rule on one grid. The Game of Life is the best known of a whole family of such rules, and Ollin ships several more. Two of them are cheap enough to run on the CPU, and they hand you plain arrays instead of a field. The rest are fields like the ones above, each with a seed of its own kind.

### A single row of cells: Wolfram's elementary rules

An **elementary cellular automaton** shrinks the grid to a single row. Each cell looks only at itself and its two neighbors, so there are eight possible neighborhoods. A rule is nothing more than which of those eight leave a cell alive. That packs into one number from 0 to 255. Drawing each generation below the last turns a one-dimensional automaton into a two-dimensional picture. These rules are for that picture, which shows a whole history at once. Stephen Wolfram cataloged and numbered the 256 rules in 1983.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/WolframAndTurmite-dark.jpg">
  <img src="Images/23-GridSimulations/WolframAndTurmite.jpg" alt="Two panels of black cells on cream. Left, rule 30 grown from a single cell into a triangle whose left half is regular stripes and whose right half is irregular, dotted with white triangles. Right, Langton's ant on a grid that wraps, several chaotic blots joined by straight diagonal highways" width="680">
</picture>

```swift
let rows = elementaryCA(rule: 30, width: 161, generations: 161)
```

`elementaryCA` runs one rule and hands back a row per generation. Rule 30, on the left, is the famous one, because no rule that small should produce something that irregular. Wolfram used its middle column as a source of random numbers for years. Rule 90 draws the Sierpinski triangle, and rule 110 is complicated enough to compute anything a computer can. `totalisticCA` is the same idea with more colors, where a cell reads the *sum* of its neighborhood rather than the exact pattern.

### An ant on a grid: turmites

A **turmite** is an ant on a grid instead of a whole row of cells. It reads the color under it, writes a new one, turns, steps forward, and adopts a new state. That is all a turmite is, and it is for watching order arrive out of a rule that has none in it. Langton's ant, the classic, spends about ten thousand steps making a shapeless blot. Then, with no warning, it starts laying a regular diagonal highway and walks off along it. On a grid that wraps, as the right panel's does, the highway comes back around and the ant builds another blot where it lands. Why the highway appears has no satisfying explanation yet. Christopher Langton described the ant in 1986, and turmites generalize it. The right panel of the figure above is one. You hold it and step it, the way you held a `DifferentialGrowth` in [Chapter 13](13-GrowingThings.md):

```swift
let ant = Turmite(.langton, columns: 260, rows: 260)

// each frame:
ant.step(500)
for painted in ant.paintedCells { /* draw a cell */ }
```

### Life made continuous: Lenia

**Lenia** makes the Game of Life *continuous*. Instead of cells that are alive or dead, every texel carries a smooth mass between 0 and 1. And instead of counting eight neighbors, each texel weighs a soft ring of neighborhood around it. It then grows or starves, depending on how close that weight lands to a target. It is for colonies with soft glowing edges and, at the right settings, small self-contained creatures that swim. Bert Wang-Chak Chan published it in 2019. Ollin implements the exponential kernel and growth rule of his paper, with its Orbium creature as the defaults. It is a `Sim` like the others:

<img src="Images/23-GridSimulations/Lenia.jpg" alt="Lenia colonies on near-black: several large patches of fine cream-colored ridges with soft glowing teal edges, growing outward into open space, with a few small round organisms drifting alone at the left" width="560">

```swift
dish = makeSimField(.lenia(radius: 13), scale: 0.55)
```

The arguments are the model's personality. `radius` is how far the ring reaches. `growthCenter` is the target mass, and `growthWidth` is how forgiving the rule is about missing it. One thing to know before running it: **Lenia needs a dense seed**. Sparse mass starves and fades to nothing, so give it a generous soup of soft marks and a few hundred frames.

### Life with soft edges: SmoothLife

**SmoothLife** keeps Life's rule and changes only what a cell is. A cell is a disc rather than a texel, and its neighbors are the ring around that disc. Each step reads how full the disc is and how full the ring is. Life's "born on three, survive on two or three" becomes two intervals of ring filling, one for birth and one for survival. Their edges are soft instead of cliffs. It is the model for a glider that slides in any direction, since nothing in it knows about the grid. Stephan Rafler found that smooth glider in it, and published the model in 2011.

<img src="Images/23-GridSimulations/SmoothLife.jpg" alt="SmoothLife on near-black: a dozen small cream rings, each a glider with a dark hollow, sliding across the field, and two larger ragged colonies at the left mid-split" width="560">

```swift
dish = makeSimField(.smoothLife(radius: 14), scale: 0.35)
```

The seed decides what grows, as density does for Lenia. A plain disc becomes a still ring or dies. A disc a little under the radius, with a notch bitten out of one side, becomes a glider that leads with the notch. The defaults are the paper's glider regime, so leave `birth` and `survival` alone at first. Play with `radius`, which sets how big a creature is in cells. Then play with the field's `scale`, which sets both what each step costs and how big a cell is on the canvas.

### The medium that has to rest: excitable media

An **excitable medium** is a family of automata built on one restriction: a cell that fires cannot fire again until it has rested. That restriction is how nerve fibers, heart muscle, and certain chemical reactions carry their signals. The medium remembers where a wave has just been, and that memory is what pushes the wave forward. A spark cannot spread back into the spent cells behind it, so it has nowhere to go but outward. It is for rings, spirals, and wave trains that run forever. The plainest member is the Greenberg-Hastings model of 1978, `.excitable`. Three relatives ship beside it: David Griffeath's cyclic automaton, Brian Silverman's Brian's Brain, and Martin Gerhardt and Heike Schuster's hodgepodge machine.

<img src="Images/23-GridSimulations/ExcitableFamily.jpg" alt="Four square panels. Top left, nested rainbow spirals and diamond wave trains of a cyclic automaton. Top right, fine concentric orange-and-black chevron wave trains radiating from a central spiral pair. Bottom left, sparse white and blue cell clusters scattered on black. Bottom right, thick concentric rings in rainbow thermal colors, red rims around green-and-yellow cores, on a dark purple ground" width="560">

```swift
medium = makeSimField(.excitable(states: 5), scale: 0.25)

// in draw(), inside withField(medium) { }:
if mouseIsPressed { fill(.white); drawCircle(mouseX, mouseY, 8) }
```

In `.excitable` a resting cell fires when a neighbor is firing. A fired cell then climbs alone through a refractory tail, one step per frame, and comes back ready. The field starts at rest, so you draw to spark it. A dab makes a ring. Two rings erase each other where they meet, because each runs into the other's spent wake. The move to know is to grow one large ring, then wipe half the plane with black. The two cut ends have nothing spent behind them anymore, so they curl. You get a pair of counter-rotating spirals that turn forever, re-lighting the medium on every lap. The wave trains filling the top-right panel all pour out of one such pair.

`.cyclic` wires the same idea into a loop. Every cell is one of fourteen colors, and each color is eaten by the color after it. The order goes around a circle, with no rest state at all. Every color loses to the next one, forever. Like the Turing field later in this chapter, it needs no seeding, so it fills itself with seeded random states. From there it plays four acts in order: colored static, growing droplets, the first spiral defects, and then spirals that own the field. That is the top-left panel.

`.briansBrain()` is the fastest of the family. A ready cell fires when *exactly two* of its eight neighbors are firing, rests for one step, and is ready again. Almost any loose sprinkle explodes into gliders that race the grid forever, which is the bottom-left panel's permanent traffic. A solid painted blob dies on the spot. Its interior rests all at once, and along a flat edge every outside cell sees three firing neighbors where a birth needs two. So sprinkle loose soup, never a disc.

`.hodgepodge` models an infection, in the bottom-right panel. Cells run from healthy to fully ill and back to healthy in one step. The healthy catch infection from sick neighbors, and the sick climb by their neighborhood's average plus a constant, `infectionRate`, the speed of infection. Turn it up and the field locks into curling waves that look like the Belousov-Zhabotinsky reaction, the chemical clock the automaton was built to mimic. All four fields are one `makeSimField` call each, recolored through `.gradientMap` the way [the organism](#putting-it-together-the-organism) was.

### A circuit made of cells: Wireworld

**Wireworld** is an automaton built to compute with. It has four states: empty, wire, and the two halves of an electron, its head and its tail. A head becomes a tail. A tail becomes wire. Wire becomes a head when exactly one or two of its eight neighbors are heads. That last clause is the machine. One or two lets a signal run down a wire, and the tail behind it cannot be re-lit, so it never runs back. Three or more stops it, and that refusal is what a diode and every logic gate are built from. It is for circuits you can watch run. Brian Silverman made it in 1987, and it reached most people through A. K. Dewdney's *Scientific American* column in 1990.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/Wireworld-dark.jpg">
  <img src="Images/23-GridSimulations/Wireworld.jpg" alt="Left, four boxes in a column, empty, wire, head, and tail, with arrows down between the last three labeled one or two neighbors are heads and always, the next step, and an arrow back up the side from tail to wire. Right, a circuit of yellow wire on black: two ring clocks on the left feeding one long bus through diodes, blue electron heads with red tails running along it, and two small lamps at the end" width="700">
</picture>

```swift
var board: SimField!
let circuit = ["#tH######.........",
               "#.......#.........",
               "#.......##########",
               "#.......#.........",
               "#########........."]
let legend: [Character: WireworldCell] = [".": .empty, "#": .conductor, "t": .tail, "H": .head]

override func setup() {
    board = makeSimField(.wireworld(), scale: 0.1)   // ten canvas pixels to a cell
}

override func draw() {
    background(.black)
    withField(board) {
        noStroke()
        if frameCount == 1 {                          // stamp the circuit once
            for (y, row) in circuit.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    fill(legend[ch]!.color)
                    drawRect(Double(x) * 10, Double(y) * 10, 10, 10)
                }
            }
        }
    }
    drawImage(board.image, 0, 0)
}
```

> **Swift note.** `legend` is a dictionary, a table from one value to another, written as pairs in brackets. Its keys are `Character` values. The call `row.enumerated()` walks a string one character at a time, so `legend[ch]` looks the cell up by the letter. The dictionary is not called `key` because every sketch already has a `key`, the last key pressed. A stored property of that name would collide with it. The lookup answers an optional, since a letter might be missing, and the `!` takes the answer as [Chapter 14](14-FieldsAndFlow.md) did. `where ch != "."` on the loop is [Chapter 11](11-ForcesAndPhysics.md)'s filter, and `SimField!` is the same shape as [Chapter 12](12-FlocksAndSwarms.md)'s `Boids!`.

The field starts empty and you draw the circuit. The usual way in is text, one character per cell, which is how these circuits have been shared since the 1980s. The block above stamps its rows on the first frame. That ring with one electron on it is a clock. The electron laps the ring, and each time it passes the tap on the right it sends a pulse down the wire. The ring is nine cells by five, twenty-four around, and the electron laps it in twenty, because the eight-cell neighborhood lets it cut the corners. Put a second ring of another size on the same bus and the two pulse trains interleave. The figure's diode is the two-wide bar with a gap under it. What decides is how many heads the wire on the far side sees. Coming from the wire's side, the exit wire sees two heads and lights, so the signal crosses. Coming the other way, the exit wire sees three at once and stays dark, so the signal dies there. `WireworldCell` names the four grays, so a pen that lays wire is `fill(WireworldCell.conductor.color)` and one that places an electron is `.head.color`. Keep the cells large enough to read, since a circuit is a picture of its own wiring.

## Piles and fires: the sandpile and the forest fire

The organism's dish ran one rule that spreads. Two automata in the catalog are about things piling up and burning down instead, and both are known for the same discovery. Neither has a dial that sets how big its avalanches or its fires get, and each arranges itself so that they come in every size.

### A pile of sand: the Abelian sandpile

The **Abelian sandpile** drops grains of sand on a grid. A cell can hold three. The moment it holds four it topples, sending one grain to each of its four neighbors. A neighbor that was sitting at three is now at four, so it topples too. One grain landing in the wrong place can send an avalanche across the field. The order you process the topplings in does not matter, because the pile always settles into the same configuration. That theorem is what puts the *Abelian* in the name. It is also why Ollin can topple every unstable cell at once on the GPU. The pile is for lacework that comes from the rule alone, and for avalanches of every size. Per Bak, Chao Tang, and Kurt Wiesenfeld proposed it in 1987, and Deepak Dhar proved in 1990 that its topplings commute.

<img src="Images/23-GridSimulations/Sandpile.jpg" alt="A large circular sandpile on cream paper, fully settled: dense self-similar lacework of gold and ink-blue triangular filigree arranged with fourfold symmetry, ringed by smoother petal-shaped lobes at the rim" width="560">

```swift
var pile: SimField!
let counts = Ramp(stops: [(0.00, Color(hex: 0xF5F1E6)),
                          (0.25, Color(hex: 0xA9C0CF)),
                          (0.50, Color(hex: 0xD9A441)),
                          (0.75, Color(hex: 0x2E3440)),
                          (1.00, Color(hex: 0xB3402A))])

override func setup() {
    pile = makeSimField(.sandpile(pour: 1024, topplings: 128), scale: 1)
}

override func draw() {
    background(Color(hex: 0xF5F1E6))
    withField(pile) {
        if frameCount == 1 {          // drop a mountain, once
            noStroke()
            fill(.white)
            drawCircle(width / 2, height / 2, 10)
        }
    }
    drawImage(pile.filtered(.gradientMap(counts)).image, 0, 0)
}
```

> **Swift note.** `Ramp(stops:)` takes a list of pairs, each a position along the ramp and the color there. The pairs are written as the tuples [Chapter 9](09-Pictures.md) introduced. [Chapter 2](02-Color.md)'s `Ramp([...])` spaced its colors evenly; this form places each one.

Drawing pours. A mark adds `pour` grains to every texel it covers, scaled by its brightness, every frame it is there. Nothing erases, because the only way sand leaves is by toppling off the field's open edge. This sketch pours on the first frame only, which is the classic protocol: drop a mountain on one spot and let it collapse. The state is the grain count in quarters, so a settled cell reads 0, ¼, ½, or ¾ gray, four flat levels. That is why the `Ramp` puts a color at each quarter, one per count, and saves the top of the ramp for cells caught mid-topple.

Everything in the figure came out of the rule. A mountain of identical grains and one threshold made the circle, the fourfold symmetry, and the lace of self-similar triangles. The picture was not the discovery, either. Bak, Tang, and Wiesenfeld noticed that a pile fed slowly organizes itself to the edge of collapse and stays there. The next grain might do nothing, or might set off an avalanche of any size, with the sizes following a power law. No dial had to be tuned to get there. They named the idea *self-organized criticality*. It became the standard first model for earthquakes, forest fires, and every other system that arranges its own instability.

`topplings` is the pacing dial. An avalanche front moves one cell per pass, so `.sandpile(topplings: 1)` lets you watch each wave roll across the pile. The block above uses 128, which hurries the collapse. The field runs at `scale: 1` here, one cell per canvas pixel, so the lace is as fine as the canvas. A mark you *hold* is a torrent rather than a drop. Its middle stays molten for as long as you keep pouring, with cells at four grains and above churning at the top of the ramp. It crystallizes into lacework when you stop. The [`Simulation/Automata`](../Examples/Simulation/Automata/Sketch.swift) example's sandpile rule is that sketch, a mountain collapsing in front of you, and a torrent wherever you hold the mouse.

### A forest that keeps burning: the forest fire

The **forest fire** is an automaton whose rule is three lines. Every cell is bare ground, a tree, or burning. A burning cell is bare ground next step. A tree catches from any burning neighbor, and otherwise catches on its own with a small chance, which is the lightning. Bare ground grows a tree with a small chance. It is for watching a system find its own critical density. The forest fire is the sandpile's self-organized criticality in a system that looks nothing like a sandpile. Barbara Drossel and Franz Schwabl published the model in 1992. They added the lightning to an earlier forest-fire model of Bak, Kan Chen, and Tang, and the lightning is what puts the field at criticality.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/ForestFire-dark.jpg">
  <img src="Images/23-GridSimulations/ForestFire.jpg" alt="Left, three boxes in a column, bare ground, a tree, and burning, with arrows down between them labeled it grows with a small chance each step and a neighbor is alight or lightning strikes, and an arrow back up the side labeled always the next step. Right, a field running the rule, a green forest cut by dark scars with amber fire lines in it" width="700">
</picture>

```swift
var woods: SimField!
let colors = Ramp(stops: [(0.0, Color(hex: 0x17120E)),     // bare ground
                          (0.5, Color(hex: 0x2F7D45)),     // a tree
                          (1.0, Color(hex: 0xFFC24A))])    // burning

override func setup() {
    woods = makeSimField(.forestFire(growth: 0.02, lightning: 0.00004), scale: 0.25)
}

override func draw() {
    background(.black)
    drawImage(woods.filtered(.gradientMap(colors)).image, 0, 0)
}
```

There is nothing to seed. The field starts bare and grows itself in, and that is the first thing to watch. Trees fill the map, the first strike takes a stand, another takes a bigger one, and after a while the density stops changing. Nothing in the rule names that density. It is the level where a stand is just connected enough for a fire to run through it. The fire then clears the crowd that got it there. Turn `growth` up and the forest closes faster, so fires get bigger. Turn `lightning` up toward `growth` and no tree lives long enough to have neighbors, which is the end of the forest.

The ratio between the two rates is the dial, so keep `lightning` far below `growth`. The block above sets it at five hundred to one, and the default is higher still. In that range fires come in every size, from one tree to most of the map, with no size more typical than another. Drawing works as it does everywhere else here. White sets cells burning, so you can start a fire where you want one. Black clears a firebreak, and the flames stop at it while the trees grow back into it. The `Simulation/Automata` example's forest rule is this sketch with both rates on parameters, which is the fastest way to feel what the ratio does.

## Crowds that cross a threshold: percolation, Schelling's board, the Ising model, and oscillators on a lattice

The organism grew from a scatter into one connected labyrinth, and the forest settled at the density where a stand connects. Percolation, Schelling's board, the Ising model, and oscillators on a lattice are about that moment, a crowd of cells crossing a threshold together. Percolation is a grid of coin flips that suddenly spans. Schelling's board sorts itself, the Ising model is a magnet that freezes, and the lattice falls into step. Two of them run on the CPU and two are fields.

### When chance acts as a crowd: percolation

**Percolation** is a question asked of a whole grid at once. Fill the grid with cells, each one open with the same probability. Then ask whether the open cells connect from the top edge to the bottom. Each cell flips its coin alone, and no rule ever mentions a threshold. Yet the grid's answer flips almost all at once, near a probability of 0.5927. Below it the open cells stay separate islands, however long you wait. A little above it, one giant cluster reaches across the whole grid. Physics calls a sudden collective change like this a phase transition, and this grid is its standard model. That is what percolation is for: a phase transition you can draw. It entered mathematics through Simon Broadbent and John Hammersley's 1957 paper on fluids seeping through porous stone. The square-lattice threshold used here is the value Mark Newman and Robert Ziff measured in 2000.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/ChanceInCrowds-dark.jpg">
  <img src="Images/23-GridSimulations/ChanceInCrowds.jpg" alt="Three dark grid panels. At probability 0.50, scattered blue islands; at 0.56, one pale cluster strains most of the way across; at 0.63, a single gold cluster spans the grid, traced with a pale outline" width="680">
</picture>

```swift
seed(9)
let grid = percolation(columns: 48, rows: 48, probability: 0.6)
noStroke()
fill(Color(hex: 0xE8B44A))
for cell in grid.cellRects(of: 0, in: bounds) { drawRect(cell) }
```

`percolation` hands back the clusters largest first, so cluster `0` is always the giant. The property `grid.spans` answers the top-to-bottom question, and `spanningClusterIndex` names the cluster that did it. The method `outlines(of:in:)` traces any cluster's boundary as closed loops a plotter can draw. Unlike the fields in this chapter, `percolation` is one roll on the CPU, with no state that steps from frame to frame. The threshold lives in the API as `Percolation.criticalProbability`, so a sketch can move around it without hard-coding the number. [`Examples/Patterns/Percolation`](../Examples/Patterns/Percolation/Sketch.swift) sweeps back and forth through it, and the span snaps into place each time it crosses. The [percolation reference](../Docs/Generators/Percolation.md) has the full surface, including reading clusters off a grid you filled some other way.

### A neighborhood sorting itself: Schelling's board

**Schelling's board** holds agents of two kinds, with some cells left empty. Each agent has a mild wish: at least a third of its neighbors should be its own kind. Any agent that is not content moves to a nearby empty cell where it would be. The board is not about physics or chemistry. It is for a question about cities. The answer is the board sorting itself into solid blocks, sharply, from a wish nobody would call intolerant. Thomas Schelling, an economist, played it with coins in 1971. The step-to-a-nearby-empty-cell rule here is his paper's move to the nearest satisfactory square, carried out one hop at a time. `.schelling` is that board on the GPU:

<img src="Images/23-GridSimulations/Schelling.jpg" alt="Three square panels of a board of orange and teal cells with dark empty cells scattered through them. Left, an even random mix. Middle, the same board fifteen steps later, the two colors beginning to gather into patches. Right, four hundred steps in, the two colors gathered into patches several cells wide, with empty cells scattered through them" width="700">

```swift
var board: SimField!

override func setup() {
    board = makeSimField(.schelling(preference: 0.3), scale: 0.25)
}
```

There is nothing to seed. The field starts as a random mix of the two kinds with a quarter of the cells empty. The empties are the point, since they are where the movers go. An agent that is not content steps into an empty cell nearby, one where it would be content if there is one within reach. It keeps stepping until it is. `preference` is the wish. At 0.3, the figure's setting, the board settles into patches, and at 0.5 it sorts hard. Raise it while the board is settled and it comes unsettled and sorts further. `mobility` is the pace, the chance an unhappy agent moves in a pass. At the default the sort takes a couple of seconds, which is the part to watch. At 1 it is over in a few frames.

The measure to watch is the share of an agent's neighbors that are its own kind. It starts at half, because the mix is random, and at a preference of 0.3 it climbs well past sixty percent. Each agent asked for a third and would have been content with it. The board is what all of those small wishes add up to. The gap between the wish and the result is what made the paper famous.

### Spins against the heat: the Ising model

The **Ising model** is a grid of atoms, each a small magnet pointing up or down. Each wants to agree with its neighbors, and all of them are shaken by heat. It is the oldest model of a magnet and the simplest system in physics with a phase transition. It is for a picture of order freezing out of noise, and of the critical point between. Wilhelm Lenz proposed it in 1920 and his student Ernst Ising solved the one-dimensional chain in his 1925 paper, finding no magnet in it. The two-dimensional grid has one, and Lars Onsager's 1944 solution located where it appears. The rule that runs it here is the Metropolis algorithm. Nicholas Metropolis, Arianna and Marshall Rosenbluth, and Augusta and Edward Teller published it in 1953. It was the first Monte Carlo method of its kind. `.ising` is that grid on the GPU:

<img src="Images/23-GridSimulations/Ising.jpg" alt="Three square panels of navy and cream cells. Left, large ragged patches of each color, a few cells across to a third of the panel. Middle, patches inside patches at every size, from single cells to broad regions. Right, an even fine speckle of the two colors with no patches at all" width="700">

```swift
var spins: SimField!

override func setup() {
    spins = makeSimField(.ising(temperature: 1.5), scale: 0.25)
}
```

Every cell is a spin, and the rule is a bargain with the heat. A spin whose flip would make it agree with more of its four neighbors flips. A spin whose flip would make it disagree flips anyway, with a chance that falls as the disagreement grows and rises with the `temperature`. That second clause is the model. Without it the field would freeze after a few sweeps. Cold, at a temperature of 1 or 1.5, the field magnetizes: patches of up and down grow and swallow each other until one wins. Hot, at 4, the heat wins and the field is noise. Onsager's critical temperature of about 2.27 lies between them, and it is the default, `Sim.isingCriticalTemperature`. At that temperature neither side wins, and clusters appear at every size, patches inside patches inside patches. That is what a phase transition looks like, and it is the middle panel.

There is nothing to seed. The field starts as a random mix, which is the field at infinite temperature, and cooling it is the picture. Drag the temperature down from the critical value while it runs and the clusters coarsen into domains. Drag it up and they dissolve. `field` is an outside magnet pulling every spin one way, and a small one is enough to decide which color wins a cold field. Draw a white patch and it magnetizes up, and draw a black one and it flips down; `IsingSpin` names the two. The heat then works on the patch. A run replays under its `seed`, because every coin the rule throws is a hash of the cell, the pass, and the seed. So an export never shows a frame the window did not.

### In step with the neighbors: oscillators on a lattice

The spins above agree with their neighbors about which way to point. The fireflies of [Chapter 12](12-FlocksAndSwarms.md#falling-into-step-kuramoto) agree about *when*, and each of them listens to the whole crowd. Put them on a grid and let each listen only to the cells beside it, and the agreement gets a geography. The lattice form of `Kuramoto` is for that geography. Patches fall into step and drift apart, a wave of agreement crosses the field, and `localCoherence` maps where it has locked. The model is Yoshiki Kuramoto's, the one [Chapter 12](12-FlocksAndSwarms.md#falling-into-step-kuramoto) credits, and the lattice is one layout of it. Make a `Kuramoto` with `columns` and `rows`, and the neighbors are the cells beside it on a square or hex lattice, listening `range` rings out:

```swift
var grid: HexGrid { hexGrid(columns: 24, rows: 20) }
let sync = Kuramoto(columns: 24, rows: 20, layout: .hex, coupling: 3, spread: 0.3, range: 1, seed: 7)

override func draw() {
    sync.advance()
    let locked = sync.localCoherence
    for (i, cell) in grid.enumerated() {
        fill(Color(hue: sync.phases[i] / .tau, saturation: locked[i], brightness: 0.9))
        drawPolygon(cell.corners)
    }
}
```

The crowd's site `i` is the cell `grid[i]`, because the lattice and the hex grid stagger their rows the same way. What you draw is what is coupled. Like percolation, this runs on the CPU rather than in a field on the GPU. The [`Simulation/Kuramoto`](../Examples/Simulation/Kuramoto/Sketch.swift) example is [Chapter 12](12-FlocksAndSwarms.md)'s meadow of fireflies, and a `Kuramoto` given `columns` and `rows` is this lattice. The lesson is the one this family keeps finding: a local rule, a global result, and a threshold where the result appears.

## Other chemistries: predator and prey, and multi-scale Turing

The organism's reaction-diffusion is one chemistry, two quantities feeding and consuming each other across a surface. The predator-prey field and the multi-scale Turing field run a rule of that kind. The first puts two species on a land instead of two chemicals. The second keeps a single substance and runs Turing's idea at several sizes at once.

### Two species: predator and prey

The **predator-prey field** puts prey and predators on one land and lets both wander. Prey breed toward what the land can hold. Predators eat them, but a full predator eats no faster, and predators die off at their own rate when the prey run out. It is for invasion fronts and the spiral waves that wind up behind them, the picture of spatial ecology. The model is the one Alfred Lotka wrote down in 1925 and Vito Volterra in 1926. It runs here in the form Michael Rosenzweig and Robert MacArthur gave it in 1963, with C. S. Holling's saturating response of 1959. Jonathan Sherratt, Mark Lewis, and Andrew Fowler described the spiral waves behind an invasion in 1995. Alexander Medvinsky and his colleagues made them the picture of spatial ecology in 2002. Ollin ships it as `.predatorPrey()`:

<img src="Images/23-GridSimulations/PredatorPrey.jpg" alt="Two square land maps side by side. Left, sixty frames after five releases: a green meadow with five sets of orange rings running outward, each behind a pale crest, dark troughs between the rings. Right, six hundred frames later: the rings have broken into an irregular sea of curling orange wave fragments over the green, with dark bare patches between them" width="680">

```swift
land = makeSimField(.predatorPrey(), scale: 0.5)
```

The field rests at full prey and no predators, and you draw green to release predators. Each release is a front, and the left map shows five of them: predators eat their way outward into full prey. Behind the front the prey crash, the predators starve, and the meadow grows back, ring after ring. Leave the land running and you get the right map. The fronts have met, and the wake behind them has broken into curling waves, spiral arms with no fixed center. Each patch of land runs the same boom-and-crash cycle a little out of step with its neighbors. A cycle that runs out of step across space *is* a rotating wave.

Three numbers set the ecology. `halfSaturation` is how much prey it takes to fill a predator, `predatorGrowth` how fast full predators multiply, and `predatorDeath` how fast they starve. The defaults sit past the model's oscillation threshold, which is what makes waves. Raise the death rate toward the growth rate, or the half saturation toward the land's capacity. The cycle then calms into a steady coexistence, and the waves die out. The [`Simulation/PredatorPrey`](../Examples/Simulation/PredatorPrey/Sketch.swift) example puts all three on parameters, so you can walk the field from spirals to calm and back.

The raw field is prey in red and predators in green, which already reads as a picture. The maps above run it through a gradient map instead. The map reads the *mix*: bare soil where both are gone, meadow where the prey stand alone, orange where the predators have arrived.

### The same rule at many sizes: multi-scale Turing

**Multi-scale Turing patterns** use one substance instead of two chemicals, and several scales instead of one. The single-scale rule is this: take an average of the field over a small disc, take another over a larger disc, and compare them. Where the small average is the greater, brighten the pixel a little, and otherwise darken it. The small disc is the *activator* and the large one the *inhibitor*. That one comparison, run over and over, grows the stripes on a zebra. Now run five of those rules side by side, with radii doubling from small to large, which is what `.ladder` names. At every pixel, every step, ask which of the five has its two averages closest together, and let only that one act. Jonathan McCabe's insight is that "closest together" means *this is the scale that has the least to say here*. Letting it act is what lets each part of the picture settle at its own size. The patterns are for pictures that look photographed under a microscope. They are McCabe's, from his 2010 Bridges paper "Cyclic Symmetric Multi-Scale Turing Patterns". The single rule is one `TuringScale`, and the left field below runs it alone:

```swift
field = makeSimField(.multiScaleTuring(scales: [TuringScale(activatorRadius: 4, inhibitorRadius: 8, amount: 0.02)]), scale: 0.5)
```

The right field runs the five:

<img src="Images/23-GridSimulations/TuringScales.jpg" alt="Two fields side by side, both shaded as gray relief. The left is a uniform maze of equal-width ridges at one size. The right has broad smooth lobes and dark winding channels, with much finer maze-like detail packed inside them" width="720">

```swift
var field: SimField!

override func setup() {
    field = makeSimField(.multiScaleTuring(scales: .ladder), scale: 0.5)
}

override func draw() {
    background(.black)
    drawImage(field.filtered(.relight(height: 0.35)).image, 0, 0)
}
```

That is the whole sketch, and the missing piece is the point. There is no `withField` block, because this sim needs no seeding. It starts from noise and organizes itself, and reading the field is what keeps it stepping, so `drawImage` alone is enough. Draw into it if you want to *disturb* a settled pattern, and it heals around the mark.

For the look, try `.relight` before `.gradientMap`. The algorithm is flat and two-dimensional and knows nothing about light, yet the result reads like something photographed under a microscope. McCabe noticed this too, and the resemblance to electron micrographs of diatoms is what the pictures are known for.

Two arguments each make the difference between the pattern and a near miss. Keep the **amounts equal** across scales. Every step renormalizes the field to fill its range, so whichever scale pushes hardest sets that range. It squeezes the others toward mid gray, leaving one scale's pattern with the rest as a faint wash. And **`variationRadius`** decides how large a region a scale can claim, by setting how far each scale's disagreement is averaged before the scales are compared. Read at a single point, a fine scale's disagreement passes through zero along every contour of its own structure. Since *least* disagreement wins, it then takes a dense web of pixels across the field, burying the coarse scales entirely.

Add `symmetry` and the field folds around its center. `.rosette(n)` does it to every rung at once, which is where the diatom resemblance becomes hard to shake:

```swift
field = makeSimField(.multiScaleTuring(scales: .rosette(9)), scale: 0.5)
```

## Fields that move: fluid, ripples, and self-warp

The organism's dish, like every field so far, changes what each cell holds. The fluid, the ripple pool, and the self-warp move what they hold across the grid instead. A fluid carries dye along a flow, a pool carries height as a wave, and the self-warp carries the picture itself along its own motion.

### Water you can stir: fluid

The **fluid** sim is an incompressible flow that carries color. Marks inject dye, and `withField`'s `force:` pushes the flow where the marks land, so a moving brush stirs what it paints. It is for smoke, ink in water, and anything that should swirl. The real-time form descends from Jos Stam's 1999 *Stable Fluids* and the GPU formulation Mark Harris popularized:

<img src="Images/23-GridSimulations/Dye.jpg" alt="A comet of dye stirred by an orbiting brush: a bright yellow head trailing a turbulent tail that fades through orange to deep red" width="560">

```swift
var fluid: SimField?

override func draw() {
    background(Color(hex: 0x05070C))
    if fluid == nil { fluid = makeSimField(.fluid(curl: 34), scale: 0.5) }
    guard let fluid else { return }

    let a = time * 1.4
    let brush = Vector2(width / 2 + cos(a) * width * 0.27,
                        height / 2 + sin(a * 1.3) * height * 0.27)
    let push = Vector2(-sin(a), cos(a * 1.3)) * 7      // along the brush's motion
    withField(fluid, force: push) {
        noStroke()
        fill(Color(hue: time * 0.07, saturation: 0.85, brightness: 1))
        drawCircle(center: brush, radius: 15)
    }
    drawImage(fluid.filtered(.bloom(threshold: 0.4, amount: 1.1, radius: 14)).image, 0, 0)
}
```

The `curl` argument sets how much fine swirling detail the flow keeps. The dissipation arguments set how fast motion and color fade. A mouse delta makes a good `force`.

### A pool you can drop things into: ripples

The **ripple pool** is water of a different kind, a surface that goes up and down. It is the 2D wave equation running on a height field, and it is for drops, rings, and reflections that answer the mouse directly. The wave equation is old, and Jean le Rond d'Alembert wrote it down for a vibrating string in 1747. The step here follows Evan Wallace's WebGL Water.

<img src="Images/23-GridSimulations/RipplePool.jpg" alt="A blue pool with three sets of concentric ripples spreading from separate drop points, the rings crossing each other and fading toward the edges" width="560">

```swift
var pool: SimField!

override func setup() {
    pool = makeSimField(.ripples(damping: 0.995))
}

override func draw() {
    background(.black)
    withField(pool) {
        if mouseIsPressed { dab(mouseX, mouseY, radius: 16, strength: 0.5) }
    }
    let water = pool.filtered(.relight(.liquid, angle: -.pi * 0.7, elevation: 0.7,
                                       height: 9, intensity: 1.15,
                                       color: Color(hex: 0x3D6E8F)))
    drawImage(water.image, 0, 0)
}

func dab(_ x: Double, _ y: Double, radius: Double, strength: Double) {
    fill(.radial(center: Vector2(x, y), radius: radius,
                 [Color(white: 1, alpha: strength), Color(white: 1, alpha: 0)]))
    drawCircle(x, y, radius)
}
```

A mark you draw into this field does not set the surface. It *adds* to it. The brightness of what you draw becomes height poured onto the water, and that bump collapses under its own weight. Rings spread out, cross each other, reflect off a soft rim, and die away at the rate `damping` sets.

Two things about dropping follow from that. The drop should be **soft**, which is why `dab` fills a radial gradient fading to nothing, from [Chapter 2](02-Color.md#gradients-as-paint), rather than a plain circle. `Color(white:alpha:)` is a gray by one number with an alpha beside it. A hard-edged disc is a step in the surface, and a step contains every frequency at once. So it rings like a struck plate instead of splashing like a drop. And a drop should be **brief**. Holding an opaque mark in place pours water into the pool every frame, and the surface climbs away from you.

This field's raw `image` is not a picture of water. It stores height in the red channel and velocity in green, both signed, which makes it a debugging view. Shading it is a separate step, and `.relight` is the natural one because it reads the height as a surface and lights it.

### The picture dragging its past: self-warp

The **self-warp** field has no chemistry inside it. Its state is the picture itself. It watches what you draw, works out which way every part of it just moved, and carries everything it has already shown along that motion. Whatever moves smears, and whatever holds still stays sharp. It is for trails and ribbons that follow motion without any code naming a velocity. The motion measurement is Bruce Lucas and Takeo Kanade's 1981 least-squares optical flow, run coarse to fine. The history carry is the same step the fluid uses to move its dye.

<img src="Images/23-GridSimulations/SelfWarp.jpg" alt="Two soft-cored orbs on near-black, an orange one stretched into a long curved ribbon along its orbit and a smaller cyan one trailing a short wake" width="560">

```swift
var warp: SimField!

override func setup() {
    warp = makeSimField(.selfWarp(amount: 0.55, refresh: 0.05))
}

override func draw() {
    withField(warp) {
        background(Color(hex: 0x08080F))
        noStroke()
        let c = bounds.center                    // the canvas middle
        orb(at: c + Vector2(cos(time * 1.15), sin(time * 1.15)) * 310,
            radius: 84, Color(red: 1.0, green: 0.45, blue: 0.15))
        orb(at: c + Vector2(cos(-time * 0.74 + 2.1), sin(-time * 0.74 + 2.1)) * 215,
            radius: 66, Color(red: 0.2, green: 0.75, blue: 1.0))
    }
    drawImage(warp.image, 0, 0)
}

func orb(at center: Vector2, radius: Double, _ color: Color) {
    fill(.radial(center: center, radius: radius,
                 [.white, color, color.withAlpha(0)]))
    drawCircle(center: center, radius: radius)
}
```

You draw the whole scene into the field, background and all, and composite the field instead of the scene. The measuring is the sim's job. It compares this frame's drawing with the last one, so anything that visibly moves, moves the history. The sketch never declares a velocity: the fluid needed a `force:`, and this field reads the push off the picture itself.

`amount` picks the look. At 1 the carried ghost lands back under whatever moved, and the effect nearly vanishes. Below 1 the picture outruns its history and stretches it into the ribbons above. Above 1 the history overshoots, and glitchy echoes race ahead of the motion. Negative drags the past against the motion. `refresh` is how much of the fresh drawing wins back each frame, so low values leave long-lived smears. `decay` a touch under 1 sinks old trails toward black.

The motion is measured from the picture's own shading, so the field reads best on content with soft gradients, edges, or texture. The gradient-cored orbs above are ideal, and a camera or video frame drawn into the field works as well, smearing along whatever moves in it. A flat shape on a flat ground gives the fit nothing to hold.

## Materials: sand that falls and paint that behaves

The organism's rule fits in a sentence. Falling sand and watercolor model a material instead, one moving grains that fall, roll, and sink, and the other wet paint on rough paper.

### Sand that falls: the falling-sand automaton

The **falling-sand automaton** moves grains where the sandpile counted them. Every cell holds one material: empty, water, sand, or wall. Each pass, the grid is cut into 2x2 blocks, and every block settles on its own. A grain over an empty cell falls into it. A grain over water swaps with it, so it sinks and the water rises. A grain that cannot fall straight down rolls into an empty cell diagonally below it. Water swaps with the empty cell beside it, so a pool spreads until it lies flat. A wall never moves. Then the blocks shift by one cell and the next pass runs, so what one block could not see, the next one settles. It is for heaps, slopes, and pools, and for the toy every falling-sand game has been since the early 2000s. It is a block automaton of the kind Tommaso Toffoli and Norman Margolus laid out in their 1987 book *Cellular Automata Machines*. Its roll and friction follow the pass-parallel rule Jonathan Devlin and Micah Schuster described in 2020.

<img src="Images/23-GridSimulations/FallingSand.jpg" alt="On cream paper, an ochre cone of sand sits on a short slate shelf, and below it a blue pool covers the floor with two more ochre heaps sunk to its bottom, the water's top edge slightly rough where the displaced water rose" width="560">

```swift
var sand: SimField!
let materials = Ramp(stops: [(0.000, Color(hex: 0xF5F1E6)),
                             (1 / 3, Color(hex: 0x6F9BC4)),
                             (2 / 3, Color(hex: 0xD9A441)),
                             (1.000, Color(hex: 0x2E3440))])

override func setup() {
    sand = makeSimField(.fallingSand(passes: 16, friction: 0.3), scale: 0.5)
}

override func draw() {
    background(Color(hex: 0xF5F1E6))
    withField(sand) {
        noStroke()
        if frameCount == 1 {                    // a shelf, and a pool below it
            fill(SandMaterial.wall.color)
            drawRect(width * 0.41, height * 0.4, width * 0.18, 8)
            fill(SandMaterial.water.color)
            drawRect(0, height * 0.74, width, height * 0.26)
        }
        if frameCount <= 480 {                  // one tap, open for a while
            fill(SandMaterial.sand.color)
            let wobble = sin(Double(frameCount) * 0.7) * 9 + sin(Double(frameCount) * 1.9) * 4
            drawCircle(width * 0.5 + wobble, 10, 2)
        }
    }
    drawImage(sand.filtered(.gradientMap(materials)).image, 0, 0)
}
```

Drawing pours a material. The field stores the four materials at four gray levels, and `SandMaterial` names them. So `fill(SandMaterial.water.color)` before a mark fills the mark with water. A black mark empties the cells under it. This sketch draws the walls and the pool once, then holds a tap open over the shelf. The tap wobbles on two sines, so the grains do not all land in one column. The stops `1 / 3` and `2 / 3` are the middle two gray levels, written as divisions so they land on the levels.

The cone on the shelf is not drawn. Grains land, roll down the slope, and stop where the slope is as steep as it can stand. Once the heap is wider than the shelf, grains slump off both ends and fall into the pool. They sink through it, heap up on the floor, and the water they push aside rises to the top. `friction` sets how steep a heap can stand. At 0 every grain that can roll does, and the heaps slump flat. At 1 no grain ever rolls, so the stream stacks straight up into a tower.

`passes` is the pacing dial, in passes per frame. A grain falls one cell every two passes, so the default moves it eight cells a frame. Drop it to slow the fall down and watch a single grain find its way. The `Simulation/Automata` example's sand rule is this sketch with a brush. Pour sand, water, or wall with the mouse and see what the rule does with it.

### Paint that behaves: watercolor

The **watercolor field** is a sheet of rough paper where water flows, carries pigment, and dries the way paint does. Every other field here is a system you seed and watch; this one is a material you paint with. You lay down wet paint, and the physics produces the look, with no filter imitating it. It is for washes, glazes, and blooms. The three-layer simulation is Cassidy Curtis, Sean Anderson, Joshua Seims, Kurt Fleischer, and David Salesin's, from their 1997 paper "Computer-Generated Watercolor". The twelve pigment presets carry the coefficients the paper measured.

<img src="Images/23-GridSimulations/WetPaint.jpg" alt="A simulated watercolor painting: a horizontal ultramarine wash with a darkened edge and rose charged into its middle, a pale backrun bloom with branching ridges where water was dropped, and a vertical yellow band glazed across everything, turning green where it crosses the blue" width="560">

```swift
var paint: WatercolorField!

override func setup() {
    paint = watercolor(pigments: [.frenchUltramarine, .quinacridoneRose, .hansaYellow])
}

override func draw() {
    withField(paint) {
        noStroke()
        if mouseIsPressed { fill(paint.ink(0)); drawCircle(mouseX, mouseY, 24) }
    }
    drawImage(paint.image, 0, 0)
}
```

Painting is drawing into the field, with the palette held in the color channels. Red is the first pigment, green the second, blue the third, and **alpha is water**. `paint.ink(0)` builds the brush color for the first pigment, `paint.ink(2)` for the yellow, and `paint.water()` is a clean wet brush. `noStroke()` matters more than usual, because a stroked mark would ring every stamp with its stroke color. And black is water with no pigment in it.

Leave a stroke alone and its edge darkens on its own. The wet rim sheds water and the interior refills it, and that slow one-way traffic ferries pigment to the boundary. It is the dark rim every wet-on-dry stroke dries with. Paint a loaded stroke into a wash that is still wet and it spreads soft and feathery instead. Each pigment keeps its own habits along the way. Dense paints settle where you put them. Granulating ones like `.frenchUltramarine` collect in the paper's hollows and dry speckled, and staining ones grip and will not lift.

Two verbs manage the sheet between washes. `paint.dry()` bakes everything so far into a fixed glaze. The next wash paints over it without disturbing it, and the layers mix like light through stained glass rather than like ink. Hansa yellow over ultramarine makes the muted green those paints mix. `paint.blot()` lifts only the standing water and leaves the pigment sitting damp, which is the state a *backrun* wants. Hold a clean-water touch in a blotted wash and the water floods back through the damp paint. It shoves pigment ahead of it into a pale bloom with a dark branching rim. A single tap only nudges; holding the wet brush is what blooms. The water does the painting, and your job is deciding where it lands.

There are arguments for the paper too, on the longer form `watercolor(.watercolor(pigments: [.frenchUltramarine], dryBrush: 0.3))`. `dryBrush` above zero makes strokes skip across the raised tooth and break up, `grain` sizes the tooth, and `paperSeed` picks the sheet. A pigment you cannot find in the twelve presets you can invent by describing it. `WatercolorPigment(overWhite:overBlack:)` takes the color a layer shows over white and over black paper, and works out the optics from those two swatches. The full model, effect by effect, is on the [watercolor page](../Docs/Simulation/Watercolor.md).

## A rule of your own: Sim.shader

Every field so far ran a rule somebody else wrote. The catalog is long, but sooner or later you want a rule it does not have. It might be a heat that spreads, a wind that carries something, or an automaton with your own table. This entry is how you write one.

### Life rewritten as a kernel: Sim.shader

`Sim.shader` takes a kernel you write and runs it in the same loop as the catalog. The seeding by drawing, the `image`, and the memory from frame to frame are all the same. It is for the rule the catalog does not have. The kernel is a [`Shader`](18-YourFirstShader.md), and its `shade` returns the cell's **next state** from its neighborhood. `cell(info)` is the cell itself and `cell(info, dx, dy)` a neighbor, with `dy` positive downward like the canvas. Here is Life again, as a kernel:

```swift
let life = Sim.shader(Shader("""
float4 shade(float2 uv, ShaderInfo info) {
    float n = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx != 0 || dy != 0) { n += step(0.5, cell(info, dx, dy).r); }
        }
    }
    float me = step(0.5, cell(info).r);
    float alive = (n == 3.0 || (me > 0.5 && n == 2.0)) ? 1.0 : 0.0;
    return float4(alive, alive, alive, 1.0);
}
"""))
```

> **Metal note.** `for (int dy = -1; dy <= 1; dy++)` is a counted loop written the C way. It has a starting value, a condition to keep going, and a step. Here the step is `dy++`, which adds one. `||` means or and `&&` means and, `!=` is not equal as in [Chapter 17](17-MarksAndMedia.md), and `condition ? 1.0 : 0.0` is the compact if from [Chapter 6](06-GridsAndRepetition.md). `step(0.5, x)` is [Chapter 18](18-YourFirstShader.md)'s step, 0 below the threshold and 1 above it, and `.r` reads the state's first channel.

It matches the built-in `.gameOfLife()` cell for cell, which is how you know the readers mean what they say. The state is *data*: nothing you return is treated as a color, and nothing you read has been. A cell can hold a temperature, a velocity, a count, whatever four numbers your rule needs.

The second kernel is how a drawn mark gets in. Without one, a mark lands the way it does for the catalog: laid onto the state by its alpha, white writing 1 and black 0. With `inject:`, your own shader runs where the marks landed, and it reads them through `mark(info)`. That second kernel is what turns a brush into a force. A mark can *add* heat instead of setting it. It can push a wind the way the mouse moved, with the motion handed in through the shader's `params`. The region it acts on is whatever the block drew. So a circle, a line, or a rectangle in `withField` is that shape stepped by your rule:

```swift
plate = makeSimField(.shader(heatStep, inject: addHeat, substeps: 4), scale: 0.5, edge: .clamped)
```

<img src="Images/23-GridSimulations/OwnRule.jpg" alt="A heat plate run by a hand-written kernel: a brush's trail glows pale yellow through magenta and purple on black, spread and cooling, with white arrows showing the heat running down its own slope toward the cold" width="560">

That line carries the two other choices a field of your own makes you think about. **`edge`** is what a cell on the border reads when it looks past the field. The default wraps, which is why a glider that leaves Life's right edge comes back on the left. `.clamped` puts walls there. A read past the edge returns the border cell, which for a diffusing quantity is an insulated boundary, so nothing leaks out of this plate. The catalog's neighbor-reading sims honor the same setting, so Life on a clamped field has corners. **`precision`** is how exactly a number keeps. Half float, the default, holds a whole number exactly only to about two thousand, so a rule that *counts* wants `.float32`.

Two more things round the kit out. A two-channel state reads as a picture through `.arrows`. That is what drew the white arrows above, from the heat's slope stored in the plate's first two channels. And `snapshot()` reads any field back to the CPU as numbers, every cell's four channels as stored, one frame late. A sketch can then hand a sum or a busiest cell to sound, to text, or to a plotter. The [`Simulation/Wind`](../Examples/Simulation/Wind/Sketch.swift) example puts all of it in one sketch. A wind carries dust, a drag pushes it, and a noise layer handed in as an `input` stirs it. The edge is switched live, the arrows are drawn over the dust, and the mean speed is read back twice a second.

## Where this comes from

The Game of Life is John Horton Conway's, from 1970, and reached the world through Martin Gardner's *Scientific American* column. It remains the standard demonstration that computation and life-like behavior need almost nothing to start. Reaction-diffusion begins with Alan Turing's 1952 paper *The Chemical Basis of Morphogenesis*. The two-chemical model Ollin ships is the Gray-Scott variant. The feed/kill map figure follows the territory John Pearson charted in his 1993 classification of its patterns. Karl Sims' interactive tutorial later made that map a creative-coding staple. The families after the organism name their own sources as they go. The automata name Wolfram, Langton, Chan, Rafler, Greenberg and Hastings, Griffeath, Silverman, Gerhardt and Schuster, and Dewdney. The piles and fires name Bak and Tang and Wiesenfeld, Dhar, Drossel and Schwabl, and Bak and Chen and Tang. The crowds name Broadbent and Hammersley, Newman and Ziff, Schelling, Lenz and Ising and Onsager, Metropolis and the Rosenbluths and the Tellers, and Kuramoto. The chemistries name Lotka and Volterra, Rosenzweig and MacArthur, Holling, Sherratt and Lewis and Fowler, Medvinsky, and McCabe. The moving fields name Stam and Harris, d'Alembert and Wallace, and Lucas and Kanade. The materials name Toffoli and Margolus, Devlin and Schuster, and Curtis and his co-authors. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Simulation fields](../Docs/Drawing/Effects.md#simfield): the `Sim` catalog with every argument, seeding semantics, and field scale.
- [A simulation of your own](../Docs/Drawing/Effects.md#simfield-shader): the kernel contract, the readers, the inject, `edge`, `precision`, `inputs`, `.arrows`, and `snapshot()`.
- [Cellular automata](../Docs/Generators/CellularAutomata.md): every elementary and totalistic rule, random start rows, the `Turmite` preset catalog, and writing your own rule table.
- [Percolation](../Docs/Generators/Percolation.md): the crowd game in full, including the outline tracing and reading clusters off any boolean grid.
- [Coupled oscillators on a lattice](../Docs/Simulation/Oscillators.md#on-a-lattice): the square and hex layouts, `range`, the neighbors a site listens to, and [where the crowd has locked](../Docs/Simulation/Oscillators.md#local-coherence).
- [Watercolor](../Docs/Simulation/Watercolor.md): the three layers of the wash, every pigment preset, the paper arguments, and the two verbs between washes.
- Appendix B draws this chapter's math, one picture per idea: [Local rules, global structure](B-JustEnoughMath.md#local-rules-global-structure) and [A parameter space is a map](B-JustEnoughMath.md#a-parameter-space-is-a-map).
- Worked examples: [`Examples/Simulation/GrayScott`](../Examples/Simulation/GrayScott/Sketch.swift), [`Examples/Simulation/Automata`](../Examples/Simulation/Automata/Sketch.swift) (thirteen rules on a picker, Wireworld, Schelling's board, the Ising model, and the falling sand among them), [`Examples/Simulation/MultiScaleTuring`](../Examples/Simulation/MultiScaleTuring/Sketch.swift), [`Examples/Simulation/Fluid`](../Examples/Simulation/Fluid/Sketch.swift), [`Examples/Simulation/SelfWarp`](../Examples/Simulation/SelfWarp/Sketch.swift), [`Examples/Simulation/Ripples`](../Examples/Simulation/Ripples/Sketch.swift), [`Examples/Simulation/Watercolor`](../Examples/Simulation/Watercolor/Sketch.swift), [`Examples/Compute/CurlField`](../Examples/Compute/CurlField/Sketch.swift), and [`Examples/Compute/ReactionDiffusion`](../Examples/Compute/ReactionDiffusion/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 22, Iterated forms](22-IteratedForms.md) · Next: [Chapter 24, Simulations made of particles](24-ParticleSimulations.md)
