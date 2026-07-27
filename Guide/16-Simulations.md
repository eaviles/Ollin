#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 16</sup>

---

# 16. Simulations

<img src="Images/16-Simulations/Organism.jpg" alt="A dense teal brain-coral labyrinth grown by reaction-diffusion, its winding ridges lit with a wet sheen against deep navy gaps" width="560">

Nobody drew those corridors. They grew, over six hundred frames, from a scatter of dots and two chemical rules, and if you ran the sketch and dragged the mouse, your marks would grow the same way. This chapter is about **simulations**: fields that carry their own state on the GPU and evolve it every frame by simple local rules. You bring the seed; the rules do the drawing.

## State that lives on the GPU

Chapter 14's feedback layer was the first taste: a picture fed its transformed self back in, frame after frame. A simulation field replaces "transform the whole picture" with something more local and more alive: every cell of the field computes its next value *from its neighbors*, all at once, every frame. It's Chapter 15's per-pixel function with one addition that changes everything: memory.

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

The `scale: 0.08` matters: a sim field's `scale` sets its internal resolution, and for a cellular automaton one texel is one cell, so a low scale gives cells you can see. (For the other sims, lower scale just means broader, cheaper features.)

## Two chemicals

Reaction-diffusion is the Game of Life's continuous cousin, and the engine of this chapter's finished piece. The idea, from Alan Turing: two chemicals spread through a surface and react, one feeding the pattern and one killing it, and in the balance between those two rates, patterns *make themselves*. Ollin ships it as `.reactionDiffusion(feed:kill:)`, and those two numbers are the whole temperament of the system:

<img src="Images/16-Simulations/FeedKillMap.jpg" alt="A six-by-four grid of reaction-diffusion dishes at different feed and kill settings: most sit quiet, while a diagonal band grows spots, rings, mazes, and mitosing dots" width="680">

Read the map honestly: most of the parameter space is quiet. Life, in this system, is a narrow band where feeding and killing balance, and every regime along that band has its own signature: dividing dots (the defaults), worm mazes, coral walls. Put `feed` and `kill` on `@Param` knobs and you can walk the map live; the `Simulation/GrayScott` example is exactly that.

Seeding is drawing, same as before, and it's worth watching what one mark becomes:

<img src="Images/16-Simulations/Seeding.jpg" alt="Four dishes seeded with the same ring at different moments, showing its growth: the raw ring, a thickened double ring, a wavy cross, and a labyrinth filling the dish" width="680">

One more habit for this chapter: the raw field is *data*, not a picture. Reaction-diffusion's state reads as dim red-green; you give it a look by filtering, the same catalog as everything else: `dish.filtered(.gradientMap(.viridis))`, a `.threshold` for hard ink, or Chapter 14's `.relight` to light it as matter.

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

## Iteration without memory

A quick sidebar, because it answers a natural question: does everything that iterates need a field that persists? No. The most famous iteration in mathematics runs entirely inside a single frame:

```swift
drawImage(generate(.mandelbrot(phase: time * 0.03)).image, 0, 0)
```

<img src="Images/16-Simulations/FractalPair.jpg" alt="The Mandelbrot set and a Julia set side by side, banded in deep blue, teal, and cream by their escape times" width="680">

Every pixel of the Mandelbrot set runs its own private loop (`z = z² + c`, over and over) and is colored by how fast that orbit flies off to infinity; a Julia set is the same loop with the roles of the two numbers swapped. The simulation fields spread their iteration across *frames* because their rules need neighbors and memory; the fractal needs neither, so its whole life fits in one evaluation. Both are the same lesson at different speeds: iterate something simple, and structure appears. Zooming is one `center:`/`zoom:` away, and `Examples/Effects/Fractals` sets the Julia's `c` drifting so the filigree morphs.

## A million grains

The fields so far evolved *textures*. The other half of GPU simulation evolves *particles*: a buffer of hundreds of thousands of individuals, each updated by a small program, none of them ever touching the CPU. In Ollin that's `Particles`, and the update is a snippet of Metal, the same language as Chapter 15's shaders, presented here as a recipe you can adapt without ceremony:

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

## Putting it together: the organism

The finished piece grows a culture. A scatter of spores seeds a reaction-diffusion dish in its mitosis regime; whatever you draw while it runs joins the chemistry; and the display pipeline is pure Chapter 14: a levels stretch, a gradient map for the skin, and a liquid relight so the ridges catch light. Make `MySketches/Organism.swift`:

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

- Walk the map: put `feed` and `kill` on knobs and steer the culture between mitosis, worms, and coral while it grows.
- Recolor the skin ramp. The same labyrinth reads as coral, lichen, or circuitry depending entirely on four colors.
- Seed with meaning: Chapter 7's `drawText` into the field grows a word into a labyrinth that slowly forgets it was a word.
- Swap `.relight(.liquid)` for `.relight(.metal, color:)` and the organism becomes an engraving.

## Where this comes from

The Game of Life is John Horton Conway's, from 1970, and reached the world through Martin Gardner's *Scientific American* column; it remains the standard demonstration that computation and life-like behavior need almost nothing to start. Reaction-diffusion begins with Alan Turing's 1952 paper *The Chemical Basis of Morphogenesis*; the two-chemical model Ollin ships is the Gray-Scott variant, and the feed/kill map figure follows the territory John Pearson charted in his 1993 classification of its patterns (Karl Sims' interactive tutorial later made that map a creative-coding staple). The real-time fluid descends from Jos Stam's 1999 *Stable Fluids* and the GPU formulation popularized by Mark Harris. The Mandelbrot set is named for Benoit Mandelbrot, who first plotted it in 1980, on the mathematics of Gaston Julia's 1918 sets. GPU particle systems are a demoscene and games inheritance; the additive light-deposit rendering they power here is as old as long-exposure photography. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Simulation fields](../Docs/Drawing/Effects.md#simfield): the `Sim` catalog with every knob, seeding semantics, and field scale.
- [Compute & GPU particles](../Docs/Shaders/Compute.md): the full `Particles` snippet vocabulary, texture kernels, `.metal` files, and the typed core.
- [Escape-time fractals](../Docs/Drawing/Effects.md#generate): `.mandelbrot` / `.julia` framing, iterations, and coloring.
- Worked examples: [`Examples/Simulation/GrayScott`](../Examples/Simulation/GrayScott/Sketch.swift), [`Examples/Simulation/GameOfLife`](../Examples/Simulation/GameOfLife/Sketch.swift), [`Examples/Simulation/Fluid`](../Examples/Simulation/Fluid/Sketch.swift), [`Examples/Effects/Fractals`](../Examples/Effects/Fractals/Sketch.swift), [`Examples/Compute/CurlField`](../Examples/Compute/CurlField/Sketch.swift), and [`Examples/Compute/ReactionDiffusion`](../Examples/Compute/ReactionDiffusion/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 15, Your first shader](15-YourFirstShader.md) · Next: [Chapter 17, 3D, gently](17-3DGently.md)
