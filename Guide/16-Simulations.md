#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 16</sup>

---

# 16. Simulations

<img src="Images/16-Simulations/Organism.jpg" alt="A dense teal brain-coral labyrinth grown by reaction-diffusion, its winding ridges lit with a wet sheen against deep navy gaps" width="560">

Nobody drew those corridors. They grew, over six hundred frames, from a scatter of dots and two chemical rules, and if you ran the sketch and dragged the mouse, your marks would grow the same way. This chapter is about **simulations**, fields that carry their own state on the GPU and evolve it every frame by simple local rules. You bring the seed; the rules do the drawing.

## State that lives on the GPU

Chapter 14's feedback layer was the first taste, a picture fed its transformed self back in, frame after frame. A simulation field replaces "transform the whole picture" with something more local and more alive, because every cell of the field computes its next value *from its neighbors*, all at once, every frame. It's Chapter 15's per-pixel function with one addition that changes everything: memory.

In Ollin that's a `SimField`. Like `Feedback`, it's persistent (make it once, keep it), and you never write the kernel for the built-in ones: pick a `Sim`, draw into the field to seed it, and composite its `image`:

```swift
var life: SimField?
override func setup() { }                     // created on first draw, held forever

override func draw() {
    if life == nil { life = simField(.gameOfLife(), scale: 0.08) }
    guard let life else { return }
    withField(life) {
        if mouseIsPressed { fill(.white); drawCircle(mouseX, mouseY, 20) }
    }
    drawImage(life.image, 0, 0)
}
```

`withField` works like Chapter 14's `withTarget`, and what a drawn mark *means* depends on the simulation. For the Game of Life, white means alive.

## The Game of Life

Conway's Game of Life is the classic proof that simple local rules make worlds. Each cell of a grid is alive or dead, and one generation to the next it only ever asks about its eight neighbors:

<img src="Images/16-Simulations/LifeRules.jpg" alt="Three three-by-three neighborhoods and their outcomes: a cell with one neighbor dies, a cell with two or three lives on, an empty cell with exactly three neighbors is born" width="680">

That's the entire rulebook. No cell knows about the picture; there is no picture, as far as any cell is concerned. And yet seed a field with a random soup and structures appear: stable blocks, blinking pairs, and now and then a *glider* that walks off across the grid on its own:

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

<img src="Images/16-Simulations/LifeField.jpg" alt="A Game of Life field ninety generations after a random soup: scattered still lifes, blinkers, and small debris in crisp white cells on black" width="560">

The `scale: 0.08` matters, because a sim field's `scale` sets its internal resolution, and for a cellular automaton one texel is one cell, so a low scale gives cells you can see. (For the other sims, lower scale just means broader, cheaper features.)

## More ways to be an automaton

The Game of Life is one rule on one grid, and the same recipe runs in several other shapes. Two of them are cheap enough to run on the CPU, which means they hand you plain arrays instead of a field and you draw the result however you like.

**Wolfram's elementary rules** shrink the grid to a single row. Each cell looks only at itself and its two neighbors, so there are eight possible neighborhoods, and a rule is nothing more than which of those eight leave a cell alive, which packs into one number from 0 to 255. `elementaryCA` runs one and hands back a row per generation, so drawing time downward turns a one-dimensional automaton into a two-dimensional picture:

```swift
let rows = elementaryCA(rule: 30, width: 161, generations: 161)
```

<img src="Images/16-Simulations/WolframAndTurmite.jpg" alt="Two panels of black cells on cream. Left, rule 30 grown from a single cell into a triangle whose left half is regular stripes and whose right half is irregular, dotted with white triangles. Right, Langton's ant, a chaotic blot crossed by straight diagonal highways running off the edges" width="680">

Rule 30, on the left, is the famous one, because a rule that small has no business producing something that irregular, and Wolfram used its middle column as a source of random numbers for years. Rule 90 draws the Sierpinski triangle, and rule 110 turns out to be complicated enough to compute anything a computer can. `totalisticCA` is the same idea with more colors, where a cell reads the *sum* of its neighborhood rather than the exact pattern.

**A turmite** is an ant on a grid instead of a whole row of cells. It reads the color under it, writes a new one, turns, steps forward, and adopts a new state, and that is the entire creature. Langton's ant, the classic, spends about ten thousand steps making an incoherent blot and then, with no warning at all, starts laying a perfectly regular diagonal highway and walks off along it forever. Nobody has a satisfying explanation for why. You hold one and step it, the way you held a `DifferentialGrowth` in Chapter 10:

```swift
let ant = Turmite(.langton, columns: 260, rows: 260)

// each frame:
ant.step(500)
for painted in ant.paintedCells { /* draw a cell */ }
```

**Lenia** goes the other way and makes the Game of Life *continuous*. Instead of cells that are alive or dead, every texel carries a smooth mass between 0 and 1, and instead of counting eight neighbors, each texel weighs a soft ring of neighborhood around it and grows or starves depending on how close that weight lands to a target. It's a `Sim` like the others:

```swift
dish = simField(.lenia(radius: 13), scale: 0.55)
```

<img src="Images/16-Simulations/Lenia.jpg" alt="Lenia colonies on near-black: several large patches of fine cream-colored ridges with soft glowing teal edges, growing outward into open space, with a few small round organisms drifting alone at the left" width="560">

Those knobs are the model's whole personality. `radius` is how far the ring reaches, and the growth center and width are the target mass and how forgiving the rule is about missing it. The one thing to know before running it is that **Lenia needs a dense seed**. Sparse mass starves and fades to nothing, which looks like a bug and isn't, so give it a generous soup of soft marks and a few hundred frames. What grows are colonies with soft glowing edges, and at the right settings, small self-contained creatures that swim.

## A pile of sand

One more automaton belongs in this family, and it comes with the best origin story in the chapter. Drop grains of sand on a grid. A cell can hold three; the moment it holds four it topples, sending one grain to each of its four neighbors. A neighbor that was sitting at three is now at four, so it topples too, and one grain landing in the wrong place can send an avalanche across the whole field. The order you process the topplings in turns out not to matter at all, because the pile always settles into exactly the same configuration. That theorem is what puts the *Abelian* in the Abelian sandpile, and it's also why Ollin can topple every unstable cell at once on the GPU:

```swift
var pile: SimField!
let counts = Ramp(stops: [(0.00, Color(hex: 0x10141F)),
                          (0.25, Color(hex: 0x2C6E91)),
                          (0.50, Color(hex: 0xE3A857)),
                          (0.75, Color(hex: 0xF2E9DC)),
                          (1.00, .white)])

override func setup() {
    pile = simField(.sandpile(pour: 1024), scale: 0.5)
}

override func draw() {
    background(.black)
    withField(pile) {
        if frameCount == 1 {          // drop a mountain, once
            noStroke()
            fill(.white)
            drawCircle(width / 2, height / 2, 16)
        }
    }
    drawImage(pile.filtered(.gradientMap(counts)).image, 0, 0)
}
```

Drawing pours. A mark adds `pour` grains, scaled by its brightness, to every texel it covers, every frame it's there, and nothing erases, because the only way sand leaves is by toppling off the field's open edge. This sketch pours on the first frame only, which is the classic protocol: drop a mountain on one spot and let it collapse. The state is the grain count in quarters, so a settled cell reads 0, ¼, ½, or ¾ gray, four flat levels, which is why the `Ramp` puts a color at each quarter, one per count, and saves the top of the ramp for cells caught mid-topple:

<img src="Images/16-Simulations/Sandpile.jpg" alt="A large circular sandpile on cream paper, fully settled: dense self-similar lacework of gold and ink-blue triangular filigree arranged with fourfold symmetry, ringed by smoother petal-shaped lobes at the rim" width="560">

Everything in that figure came out of the rule. Nobody drew the circle, the fourfold symmetry, or the lace of self-similar triangles; a mountain of identical grains and one threshold made all of it. And the picture wasn't even the discovery. Bak, Tang, and Wiesenfeld noticed that a pile fed slowly organizes itself to the edge of collapse and stays there: the next grain might do nothing, or might set off an avalanche of any size, with the sizes following a power law, and nobody had to tune anything to get it there. They named the idea *self-organized criticality*, and it became the standard first model for earthquakes, forest fires, and every other system that arranges its own instability.

`topplings` is the pacing dial. An avalanche front moves one cell per pass, so `.sandpile(topplings: 1)` lets you watch each wave roll across the pile, and 128 hurries a collapse. And a mark you *hold* is a torrent rather than a drop: its middle stays molten, cells at four grains and above churning at the top of the ramp, for as long as you keep pouring, then crystallizes into lacework when you stop. The `Simulation/Sandpile` example is exactly that piece: a mountain collapsing in front of you, and a torrent wherever you hold the mouse.

## Two chemicals

Reaction-diffusion is the Game of Life's continuous cousin, and the engine of this chapter's finished piece. The idea comes from Alan Turing. Two chemicals spread through a surface and react, one feeding the pattern and one killing it, and in the balance between those two rates, patterns *make themselves*. Ollin ships it as `.reactionDiffusion(feed:kill:)`, and those two numbers are the whole temperament of the system:

<img src="Images/16-Simulations/FeedKillMap.jpg" alt="A six-by-four grid of reaction-diffusion dishes at different feed and kill settings: most sit quiet, while a diagonal band grows spots, rings, mazes, and mitosing dots" width="680">

Read the map honestly, because most of the parameter space is quiet. Life, in this system, is a narrow band where feeding and killing balance, and every regime along that band has its own signature: dividing dots (the defaults), worm mazes, coral walls. Put `feed` and `kill` on `@Param` knobs and you can walk the map live, and the `Simulation/GrayScott` example is exactly that.

Seeding is drawing, same as before, and it's worth watching what one mark becomes:

<img src="Images/16-Simulations/Seeding.jpg" alt="Four dishes seeded with the same ring at different moments, showing its growth: the raw ring, a thickened double ring, a wavy cross, and a labyrinth filling the dish" width="680">

One more habit is worth forming here. The raw field is *data*, not a picture. Reaction-diffusion's state reads as dim red-green, so you give it a look by filtering, using the same catalog as everything else: `dish.filtered(.gradientMap(.viridis))`, a `.threshold` for hard ink, or Chapter 14's `.relight` to light it as matter.

## The same rule at many sizes

Turing's idea has another descendant worth knowing, and it takes a different turn. Instead of two chemicals, it uses one substance, and instead of one scale, it runs several at once.

Start with the single-scale version, because the whole thing is built from it. Take an average of the field over a small disc, take another over a larger disc, and compare them. Where the small average is the greater, brighten the pixel a little; otherwise darken it. The small disc is called the *activator* and the large one the *inhibitor*, and that one comparison, run over and over, grows the stripes on a zebra.

Now run five of those rules side by side, with radii doubling from small to large. At every pixel, every step, you ask which of the five has its two averages closest together, and let only that one act. Jonathan McCabe's insight is that "closest together" means *this is the scale that has the least to say here*, and letting it act is what lets each part of the picture settle at its own size:

<img src="Images/16-Simulations/TuringScales.jpg" alt="Two fields side by side, both shaded as gray relief. The left is a uniform maze of equal-width ridges at one size. The right has broad smooth lobes and dark winding channels, with much finer maze-like detail packed inside them" width="720">

```swift
var field: SimField!

override func setup() {
    field = simField(.multiScaleTuring(), scale: 0.5)
}

override func draw() {
    background(.black)
    drawImage(field.filtered(.relight(height: 0.35)).image, 0, 0)
}
```

That's the whole sketch, and the missing piece is the point: there's no `withField` block, because this is the first sim in the chapter that needs no seeding. It starts from noise and organizes itself. Reading the field is what keeps it stepping, so `drawImage` alone is enough. Draw into it if you want to *disturb* a settled pattern, and it will heal around the mark.

The look is worth a word. People usually reach for `.gradientMap` on a grayscale field, but try `.relight` first here. The algorithm is flat and two-dimensional and knows nothing about light, yet the result reads convincingly like something photographed under a microscope. McCabe noticed this too, and the resemblance to electron micrographs of diatoms is what the pictures are known for.

Two knobs repay understanding, because each one is the difference between the pattern and a near-miss. Keep the **amounts equal** across scales: every step renormalizes the field to fill its range, so whichever scale pushes hardest sets that range and squeezes the others toward mid gray, leaving you one scale's pattern with the rest as a faint wash. And **`variationRadius`** decides how large a region a scale can claim, by setting how far each scale's disagreement is averaged before the scales are compared. Read at a single point, a fine scale's disagreement passes through zero along every contour of its own structure, and since *least* disagreement wins, it takes a dense web of pixels across the whole field and buries the coarse scales entirely.

Add `symmetry` and the field folds around its center. `.rosette(n)` does it to every rung at once, which is where the diatom resemblance becomes uncanny:

```swift
field = simField(.multiScaleTuring(scales: .rosette(9)), scale: 0.5)
```

## Water you can stir

The third built-in sim is a real fluid: an incompressible flow that carries color. Marks inject dye, and `withField`'s `force:` pushes the flow where the marks land, so a moving brush stirs what it paints:

```swift
var fluid: SimField?

override func draw() {
    background(Color(hex: 0x05070C))
    if fluid == nil { fluid = simField(.fluid(curl: 34), scale: 0.5) }
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
    drawImage(fluid.filtered(.bloom(threshold: 0.4, intensity: 1.1, radius: 14)).image, 0, 0)
}
```

<img src="Images/16-Simulations/Dye.jpg" alt="A comet of dye stirred by an orbiting brush: a bright yellow head trailing a turbulent tail that fades through orange to deep red" width="560">

`curl` sets how much fine swirling detail the flow keeps, the dissipations how fast motion and color fade, and a mouse delta makes the obvious `force`. Hand this sketch a trackpad and it disappears people for a while.

## A pool you can drop things into

The fluid above carries color around. The fourth built-in sim is water of a different kind, a surface that goes up and down, which is the 2D wave equation running on a height field. It's the interactive ripple pool, and it's the sim with the most direct relationship between what you draw and what happens.

<img src="Images/16-Simulations/RipplePool.jpg" alt="A blue pool with three sets of concentric ripples spreading from separate drop points, the rings crossing each other and fading toward the edges" width="560">

```swift
var pool: SimField!

override func setup() {
    pool = simField(.ripples(damping: 0.995))
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

A mark you draw into this field doesn't set the surface, it *adds* to it. The brightness of what you draw becomes height poured onto the water, that bump collapses under its own weight, and rings spread out, cross each other, reflect gently off a soft rim, and die away at the rate `damping` sets.

Two things about dropping follow from that, and both are easy to get wrong. The drop should be **soft**, which is why `dab` paints a radial gradient fading to nothing rather than a plain circle. A hard-edged disc is a step in the surface, and a step contains every frequency at once, so it rings like a struck plate instead of splashing like a drop. And a drop should be **brief**. Holding an opaque mark in place pours water into the pool every single frame, and the surface climbs away from you.

The other thing worth knowing is that this field's raw `image` is not a picture of water. It stores height in the red channel and velocity in green, both signed, which makes it a debugging view. Shading it is a separate step, and `.relight` is the natural one because it reads the height as a real surface and lights it.

## Paint that behaves

Every sim so far has been a system you seed and watch. The watercolor field is a sim about a *material*: a sheet of rough paper where water flows, carries pigment, and dries the way real paint does. You don't imitate watercolor's look with filters; you lay down wet paint and the physics produces the look.

```swift
var paint: WatercolorField!

override func setup() {
    paint = watercolor(pigments: [.frenchUltramarine, .quinacridoneRose])
}

override func draw() {
    withField(paint) {
        noStroke()
        if mouseIsPressed { fill(paint.ink(0)); drawCircle(mouseX, mouseY, 24) }
    }
    drawImage(paint.image, 0, 0)
}
```

Painting is drawing into the field, with the palette riding the color channels: red is the first pigment, green the second, blue the third, and **alpha is water**. `paint.ink(0)` builds the brush color for the first pigment, `paint.water()` is a clean wet brush, and `noStroke()` matters more than usual, because a stroked mark would ring every stamp with its stroke color, and black is water with no pigment in it.

<img src="Images/16-Simulations/WetPaint.jpg" alt="A simulated watercolor painting: a horizontal ultramarine wash with a darkened edge and rose charged into its middle, a pale backrun bloom with branching ridges where water was dropped, and a vertical yellow band glazed across everything, turning green where it crosses the blue" width="560">

Leave a stroke alone and its edge darkens on its own: the wet rim sheds water, the interior refills it, and that slow one-way traffic ferries pigment to the boundary, which is the dark rim every real wet-on-dry stroke dries with. Paint a loaded stroke into a wash that's still wet and it spreads soft and feathery instead. Each pigment keeps its own habits along the way: dense paints settle where you put them, granulating ones like `.frenchUltramarine` collect in the paper's hollows and dry speckled, staining ones grip and won't lift.

Two verbs manage the sheet between washes. `paint.dry()` bakes everything so far into a fixed glaze; the next wash paints over it without disturbing it, and the layers mix like light through stained glass rather than like ink (hansa yellow over ultramarine makes the muted green those real paints actually mix). `paint.blot()` lifts only the standing water and leaves the pigment sitting damp, which is the state a *backrun* wants: hold a clean-water touch in a blotted wash and the water floods back through the damp paint, shoving pigment ahead of it into a pale bloom with a dark branching rim. A single tap only nudges; holding the wet brush is what blooms. The water does the painting, and your job is deciding where it lands.

There are knobs for the paper too: `dryBrush` above zero makes strokes skip across the raised tooth and break up, `grain` sizes the tooth, and `paperSeed` picks the sheet. A pigment you can't find in the twelve presets you can invent by describing it: `WatercolorPigment(overWhite:overBlack:)` takes the color a layer shows over white and over black paper and works out the optics from those two swatches. The full model, effect by effect, is on the [watercolor page](../Docs/Simulation/Watercolor.md).

## Standing waves

Not every wave needs simulating. In 1787 Ernst Chladni scattered sand on a metal plate and drew a bow across its edge, and the sand skipped away from the parts that were moving and settled along the lines that weren't. Those lines are the plate's nodes, and the figures they make are beautiful enough that Chladni toured Europe demonstrating them.

The square plate's answer has a closed form, so Ollin gives you the value directly instead of a simulation:

```swift
let s = chladni(u, v, m: 5, n: 2)      // -1…1, over plate coordinates 0…1
```

`u` and `v` run `0...1` across the plate, and `m` and `n` are the mode numbers, which is to say how the plate was driven. The result is how far the plate is displaced at that spot, so sand settles wherever the value is near zero. That's the whole recipe: scatter grains, keep the ones sitting near a nodal line.

<img src="Images/16-Simulations/ChladniModes.jpg" alt="Six panels of Chladni figures at different mode numbers, each showing dark sand collected along curved and diagonal nodal lines on a pale plate, the patterns growing more intricate as the numbers rise" width="680">

One rule saves an afternoon. Setting `m` equal to `n` cancels the whole expression to zero, and the plate's diagonal is nodal in every mode, so those are properties of the physics rather than bugs to work around. Keep `m` larger than `n` and every mode gives you a figure.

`m` and `n` don't have to be whole numbers, which is the door to animation. Fractional modes morph continuously from one figure to the next, so a slow tour through mode space makes the sand rearrange itself in a way that looks like the bow moving. Keep `m` above `n` at every stop along the way, or the tour crosses the degenerate diagonal and the figure blinks out.

For a whole plate at once there's a GPU version, which is the faster way to fill the canvas:

```swift
drawImage(generate(.chladni(m: 5, n: 2)).image, 0, 0)
drawImage(generate(.chladni(m: 7, n: 3, style: .wave, phase: time)).image, 0, 0)
```

`.sand` gathers grains onto the nodes like the figure above, and `.wave` shows the plate swinging through its cycle instead. And since the nodal lines are just where the field crosses zero, the vector version of a Chladni figure is a contour extraction away, which the [isolines reference](../Docs/Generators/Isolines.md) covers.

The natural next step is to stop choosing the mode numbers by hand. [Chapter 20](20-SoundAndControl.md) listens to sound, and picking `m` and `n` by which pitches are actually loud turns a piece of music into the plate that would have produced it. The `Audio/ChladniResonance` example does exactly that.

## Iteration without memory

Does everything that iterates need a field that persists? No, and the counterexample is the most famous iteration in mathematics. The **escape-time fractals** run their whole life inside a single frame:

```swift
drawImage(generate(.mandelbrot(phase: time * 0.03)).image, 0, 0)
```

Here is the entire method. Every pixel stands for a complex number, and the pixel runs one tiny loop of its own: square the number you have, add a fixed one, repeat. Some starting points stay near home forever. Others eventually run away to infinity, and the only thing the fractal records is **how many steps that took**. That count, turned into a color, is the picture. The regions that never escape are the set itself, painted in `interior`.

<img src="Images/16-Simulations/FractalPair.jpg" alt="Three panels in blue, gold, and cream. The whole Mandelbrot set with a small red circle marking a point on the edge of its left bulb; a Julia set of dense spiral filigree; and a deep zoom into the Mandelbrot boundary showing the same shapes recurring at a smaller scale" width="680">

The first two panels are the same loop, differing only in which of its two numbers is held still. In the **Mandelbrot set**, the added number varies from pixel to pixel and the orbit always starts at zero. In a **Julia set**, that added number is fixed for the whole image (you pass it as `c`) and each pixel starts its orbit at its own position instead.

That is why the red mark matters. It sits at `c = -0.79 + 0.15i`, and the middle panel is the Julia set for exactly that `c`. Move the mark and you get a different Julia set, and the rule of thumb worth keeping is that points near the Mandelbrot set's *edge* give the richest ones. Deep inside gives a plain blob, far outside gives dust. Every Julia set is a portrait of one point of the Mandelbrot set.

The bands look stepless rather than like contour lines because the coloring uses a smoothed escape count rather than a whole number, and `cycles` sets how many times the palette repeats across the range. `phase` walks the colors along the bands, which is the drifting-color animation, and it costs nothing because it recolors rather than recomputes.

There is one thing to get right, and it's the third panel:

```swift
generate(.mandelbrot(center: Vector2(-0.7463, 0.1102), zoom: 900, iterations: 400))
```

**`zoom` and `iterations` have to climb together.** The iteration cap is how long you're willing to wait before calling a point "trapped", and as you magnify the boundary, more points need more steps to reveal that they do escape after all. Leave `iterations` at its default while zooming and the fine filigree fills in as a flat blob, because everything is being declared trapped too early. If a zoom looks like it lost its detail, raise the cap before you suspect anything else.

Which brings the sidebar back to the chapter. The simulation fields spread their iteration across *frames*, because their rules need neighbors and memory, so a Gray-Scott pattern at frame 900 genuinely required the 899 before it. The fractal needs neither, so its whole life fits in one evaluation and any frame can be computed on its own. Both are the same lesson at different speeds: iterate something simple, and structure appears. `Examples/Effects/Fractals` sets a Julia's `c` drifting so the filigree morphs continuously, which is the best argument for the technique that exists.

## A million grains

The fields so far evolved *textures*. The other half of GPU simulation evolves *particles*, a buffer of hundreds of thousands of individuals, each updated by a small program, none of them ever touching the CPU. In Ollin that's `Particles`, and the update is a snippet of Metal, the same language as Chapter 15's shaders, presented here as a recipe you can adapt without ceremony:

```swift
lazy var sand = Particles(count: 1_000_000, step: """
    if (life <= 0.0) {                       // (re)spawn the dead
        position = hash22(float2(float(id), float(u.frameCount))) * u.resolution;
        life = 1.0;
    }
    position += curlNoise(position * 0.002 + u.time * 0.05) * 80.0 * u.dt;
    life -= u.dt;
    color = float4(0.6, 0.8, 1.0, 0.4);
    size = 1.4;
""")

override func draw() {
    background(.black)
    blendMode(.add)         // particles sum as light
    updateParticles(sand)   // one GPU simulation step
    drawParticles(sand)     // a million additive discs
}
```

Inside the snippet, each particle's `position`, `color`, `size`, and `life` are yours to read and write, `u` carries time and resolution, and the helpers you know (`hash22`, `curlNoise`, `fbm`) are already in scope. What does count buy? Exactly what it looks like:

<img src="Images/16-Simulations/MillionGrains.jpg" alt="Three strips of the same particle system at ten thousand, a hundred thousand, and a million grains: sparse embers, a grainy dune, and a smooth field of light" width="560">

Each grain sheds the same faint light; density does the drawing. At ten thousand you see individuals, at a million you see a *material*. Pair this with Chapter 14's `noClear()` and `toneMap(.aces)` and the grains deposit into the long-exposure sandpainting look (the `Rendering/DepthOfField` example pushes it all the way to a photographic bokeh field). The [compute reference](../Docs/Shaders/Compute.md) has the full snippet vocabulary, `.metal`-file loading, and the typed core underneath.

## Crowds that organize themselves

The grains in the last section never noticed each other. Making a hundred thousand particles *aware* of their neighbors is a harder problem than it looks, because asking "who is near me" the obvious way means comparing everyone against everyone, which is billions of comparisons a frame. The standard fix is to sort the particles into a grid of cells first, so each one only ever checks the nine cells around it. Ollin ships that sort as `SpatialHash`, and it's public, so you can build your own neighbor-aware system on it. Three classic ones come already built.

<img src="Images/16-Simulations/ArtificialLife.jpg" alt="Three dark panels. Left, Particle Life in dense magenta, yellow, green, and red clusters forming membranes and cells. Middle, the Primordial Particle System, yellow rings of crowded particles scattered among lone blue wanderers. Right, Physarum, a pale branching network of transport loops on a violet trail field" width="680">

**Particle Life** gives you a few *kinds* of particle and one attraction number for every ordered pair of kinds. That's the whole model. Red is drawn to green, green flees blue, and out of that asymmetry come membranes, cells, chasers, and worms that nobody designed:

```swift
life = particleLife(count: 24_000, kinds: 6, radius: 46)

// each frame:
updateParticleLife(life)
drawParticles(life)
```

The matrix is rolled at build, and `life.randomizeMatrix(seed:)` rolls a fresh one. Most rolls are dull and a few are alive, which makes this another seed-hunting system in the spirit of Chapter 4.

**The Primordial Particle System** is leaner still. Each particle counts its neighbors, notices whether more of them sit to its left or its right, and turns toward the busier side by a fixed amount plus a crowd-proportional one. From that single rule come cells that grow, divide, and die. The middle panel above is a few seconds in, with yellow marking the crowded cell walls and blue the free wanderers.

**Physarum** models slime mold and needs no neighbor search at all, because its agents talk through the floor instead of to each other. Each one sniffs three points ahead, turns toward the strongest trail, steps forward, and deposits a little trail of its own, and the trail map blurs and fades a touch each frame. What emerges is the branching transport network on the right, the same kind of network real slime mold famously uses to solve mazes:

```swift
slime = physarum(agents: 220_000, resolution: 1024)

// each frame:
updatePhysarum(slime)
drawImage(slime.image, in: bounds)
```

One honest caveat covers all three. The neighbor sort settles ties with a race between GPU threads, and these systems are chaotic, so a run is not reproducible frame for frame. Seed them for a repeatable *starting* layout, but don't expect two exports to match.

## Liquids and jellies

That same neighbor search carries two more systems, and these two behave like matter.

<img src="Images/16-Simulations/FluidAndBlobs.jpg" alt="Two dark panels. Left, a blue particle fluid mid-slosh, a wave climbing the left wall over a churning cavity. Right, nine soft bodies in orange, green, blue, red, purple, and cyan piled at the bottom of a box, squashing flat where they press against each other" width="680">

**`ParticleFluid`** is smoothed-particle hydrodynamics, a long name for a simple bargain: represent a liquid as thousands of particles, have each one measure how crowded it is, and push it away from wherever it's crowded. Density becomes pressure, pressure becomes motion, and a free surface, splashes, and sloshing all come out without anyone modelling them:

```swift
fluid = particleFluid(count: 26_000, radius: 12)

// each frame:
if mouseIsPressed { fluid.pull(at: Vector2(mouseX, mouseY)) }
updateParticleFluid(fluid)
drawParticles(fluid)
```

`gravity` tilts the box, `stiffness` sets how hard the liquid resists being squeezed, and `nearStiffness` is an extra short-range pressure that stops particles clumping and gives the surface its tension. Grabbing a handful with `pull(at:)` and flinging it is most of the fun.

**`SoftBodies`** is the jelly counterpart, and it works by *shape matching*. Each body remembers the shape it was born with, and every step it works out where that shape would be now, its center and its rotation, then pulls its particles back toward those remembered positions. `squish` is how firmly it pulls, and that one knob is the difference between a bouncing ball and a slime:

```swift
blobs = softBodies(count: 12, radius: 80)

// each frame:
updateSoftBodies(blobs)
drawParticles(blobs)
```

Bodies collide with each other and flatten where they press together, which is the pile on the right. Both systems run fixed substeps against a clamped clock, so a dropped frame slows them down rather than detonating them, and both carry the same reproducibility caveat as the last section.

## Putting it together: the organism

The finished piece grows a culture. A scatter of spores seeds a reaction-diffusion dish in its mitosis regime, whatever you draw while it runs joins the chemistry, and the display pipeline is pure Chapter 14: a levels stretch, a gradient map for the skin, and a liquid relight so the ridges catch light. Make `MySketches/Organism.swift`:

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
        if dish == nil { dish = simField(.reactionDiffusion(feed: 0.055, kill: 0.062), scale: 0.5) }
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

<img src="Images/16-Simulations/Organism.jpg" alt="The finished organism: a wall-to-wall teal labyrinth of reaction-diffusion ridges with wet highlights, grown from a scatter of dots" width="560">

Run it live and draw. Your marks don't appear on the canvas; they enter the chemistry, and thirty frames later something is growing where your hand was. That's the strange, slightly gardening-like pleasure of simulation pieces: you don't control the picture, you control the conditions.

Then make it yours:

- Walk the map by putting `feed` and `kill` on knobs, and steer the culture between mitosis, worms, and coral while it grows.
- Recolor the skin ramp. The same labyrinth reads as coral, lichen, or circuitry depending entirely on four colors.
- Seed with meaning. Chapter 7's `drawText` into the field grows a word into a labyrinth that slowly forgets it was a word.
- Swap `.relight(.liquid)` for `.relight(.metal, color:)` and the organism becomes an engraving.

## Where this comes from

The Game of Life is John Horton Conway's, from 1970, and reached the world through Martin Gardner's *Scientific American* column; it remains the standard demonstration that computation and life-like behavior need almost nothing to start. The sandpile is Per Bak, Chao Tang, and Kurt Wiesenfeld's 1987 model, the paper that introduced self-organized criticality, and Deepak Dhar proved in 1990 that its topplings commute, which is why the settled pile doesn't depend on the order they run in and why Ollin can run them all at once on the GPU. Reaction-diffusion begins with Alan Turing's 1952 paper *The Chemical Basis of Morphogenesis*, and the two-chemical model Ollin ships is the Gray-Scott variant, and the feed/kill map figure follows the territory John Pearson charted in his 1993 classification of its patterns (Karl Sims' interactive tutorial later made that map a creative-coding staple). The real-time fluid descends from Jos Stam's 1999 *Stable Fluids* and the GPU formulation popularized by Mark Harris. The Mandelbrot set is named for Benoit Mandelbrot, who first plotted it in 1980, on the mathematics of Gaston Julia's 1918 sets. GPU particle systems are a demoscene and games inheritance, and the additive light-deposit rendering they power here is as old as long-exposure photography.

The multi-scale patterns are Jonathan McCabe's, from his 2010 Bridges paper "Cyclic Symmetric Multi-Scale Turing Patterns", which takes Turing's idea in a different direction from Gray-Scott: one substance rather than two, and several scales competing to act rather than one. He has been making artwork from the method for years, and it is his images, not the algorithm, that made it well known.

The newer arrivals have their own names attached. The 256 elementary rules were catalogued and numbered by Stephen Wolfram in 1983, and turmites generalize Christopher Langton's 1986 ant. Lenia is Bert Wang-Chak Chan's continuous generalization of the Game of Life, from his 2019 paper "Lenia: Biology of Artificial Life", and Ollin implements the exponential kernel and growth rule it describes, with the paper's Orbium creature as the defaults. Particle Life descends from Jeffrey Ventrella's *Clusters*, and the Primordial Particle System is Thomas Schmickl, Martin Stefanec, and Karl Crailsheim's, published in *Scientific Reports* in 2016. The slime-mold agents follow Jeff Jones's 2010 model of *Physarum polycephalum* transport networks. The fluid is Matthias Müller and colleagues' 2003 particle-based formulation with the near-density anti-clumping term Simon Clavet, Philippe Beaudoin, and Pierre Poulin added in 2005, and the jellies use Müller's 2005 meshless shape matching.

The two waves in this chapter are older than any of it. The ripple pool integrates the 2D wave equation, which Jean le Rond d'Alembert wrote down for a vibrating string in 1747, and the interactive-water form of it circulated widely as demoscene and graphics-tutorial code through the 1990s. The plate figures are Ernst Chladni's, first published in 1787; the closed form Ollin evaluates comes from the standard treatment of a square plate driven at its center, and Chladni's own demonstrations of them helped earn him the title of the father of acoustics. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Simulation fields](../Docs/Drawing/Effects.md#simfield): the `Sim` catalog with every knob, seeding semantics, and field scale.
- [Compute & GPU particles](../Docs/Shaders/Compute.md): the full `Particles` snippet vocabulary, texture kernels, `.metal` files, and the typed core.
- [Escape-time fractals](../Docs/Drawing/Effects.md#generate): `.mandelbrot` / `.julia` framing, iterations, and coloring.
- [Cellular automata](../Docs/Generators/CellularAutomata.md): every elementary and totalistic rule, random start rows, the `Turmite` preset catalog, and writing your own rule table.
- [Artificial life](../Docs/Simulation/ArtificialLife.md): all three systems with every knob, plus building your own on the public `SpatialHash`.
- [Fluids & soft bodies](../Docs/Simulation/Fluids.md): the SPH and shape-matching knobs, grabbing, and the substep model.
- [Chladni figures](../Docs/Generators/Chladni.md): the closed form, the `.chladni` generator's two styles, the degenerate cases, and pulling nodal lines out as vector contours.
- Worked examples: [`Examples/Simulation/GrayScott`](../Examples/Simulation/GrayScott/Sketch.swift), [`Examples/Simulation/GameOfLife`](../Examples/Simulation/GameOfLife/Sketch.swift), [`Examples/Simulation/MultiScaleTuring`](../Examples/Simulation/MultiScaleTuring/Sketch.swift), [`Examples/Simulation/Sandpile`](../Examples/Simulation/Sandpile/Sketch.swift), [`Examples/Simulation/Fluid`](../Examples/Simulation/Fluid/Sketch.swift), [`Examples/Simulation/Ripples`](../Examples/Simulation/Ripples/Sketch.swift), [`Examples/Simulation/Watercolor`](../Examples/Simulation/Watercolor/Sketch.swift), [`Examples/Patterns/Chladni`](../Examples/Patterns/Chladni/Sketch.swift), [`Examples/Audio/ChladniResonance`](../Examples/Audio/ChladniResonance/Sketch.swift), [`Examples/Effects/Fractals`](../Examples/Effects/Fractals/Sketch.swift), [`Examples/Compute/CurlField`](../Examples/Compute/CurlField/Sketch.swift), and [`Examples/Compute/ReactionDiffusion`](../Examples/Compute/ReactionDiffusion/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 15, Your first shader](15-YourFirstShader.md) · Next: [Chapter 17, 3D, gently](17-3DGently.md)
