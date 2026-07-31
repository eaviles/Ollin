#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 4</sup>

---

# 4. Randomness

<img src="Images/04-Randomness/DisorderGrid.jpg" alt="A nine-by-nine grid of nested square outlines on warm paper, perfectly ordered at the top and dissolving into tangled quadrilaterals toward the bottom, with a few red, blue, and ochre accents" width="560">

Randomness is the "generative" in generative art. You stop placing every mark yourself and start writing the rules that place them. Adding chance takes one call, and all the craft is in *controlling* it, deciding what may vary and by how much, and getting the exact same "accident" back tomorrow. Chapter 2 used all of this in its poster and promised the full story later. This chapter is that story, and it ends in the piece above: a grid that begins in perfect order and comes apart one row at a time.

## Rolling dice

`random` is the dice, and it comes in three forms:

```swift
random()          // 0 up to 1
random(8)         // 0 up to 8
random(-20, 20)   // anywhere between the two
```

Each call hands back a fresh, unpredictable number in the range (up to but never touching the top). That's all the machinery you need for a while. Roll positions and sizes and you have the oldest generative move there is, the scatter. Make `MySketches/Scatter.swift`:

```swift
import Ollin

final class Scatter: Sketch {
    override func draw() {
        background(Color(hex: 0x0E1116))
        noStroke()
        fill(Color(hex: 0xFFB703, alpha: 0.85))
        for _ in 0..<80 {
            drawCircle(random(width), random(height), random(3, 14))
        }
    }
}
```

Run it and you'll notice immediately that the canvas *boils*. Nothing is wrong. `draw()` runs sixty times a second, every frame rolls eighty fresh positions, and you're watching all of them. Sometimes that shimmer is exactly the texture a piece wants (the repository's [`Gaussian` example](../Examples/Randomness/Gaussian/Sketch.swift) leans into it). But most of the time you want chance to make its choices *once* and keep them. For that, you need to know a small secret about where these numbers come from.

> **Swift note.** `for _ in 0..<80` is Chapter 1's counting loop with the counter thrown away. The underscore says "I don't need `i`, just do this eighty times."

## Seeds: randomness you can keep

Here's the secret. There are no dice. A computer's `random` is a *pseudo-random* generator, a completely deterministic scramble that walks a fixed sequence of numbers so thoroughly shuffled they pass for chance. Where the walk starts is called the **seed**. Ordinarily the seed is grabbed from entropy at launch, so every run differs. But set it yourself, and the "randomness" replays exactly:

```swift
randomSeed(5)   // the same rolls, in the same order, every time
```

Add that line at the top of `Scatter`'s `draw()` and the boiling stops. Every frame now reseeds, rolls the *same* eighty positions and sizes, and draws the same constellation. Change the 5 to a 6 and you get a different constellation, equally frozen. Each seed is a complete, repeatable world:

<img src="Images/04-Randomness/SeedSheet.jpg" alt="Nine tiles, each a small constellation of orange dots joined by faint lines, labeled seed 1 through seed 9, every tile a distinctly different arrangement" width="560">

This is the working rhythm of generative art, so it's worth spelling out. The code decides everything the piece *could* be, and a seed picks one of them. You write the rules, then flip through seeds the way a photographer reads a contact sheet (the image above is exactly that), and keep the ones you like. Reproducibility is what turns the whole thing into art direction instead of a slot machine: a keeper is never lost, because code plus seed *is* the piece. Render it twice and the files match pixel for pixel.

There's one relative worth knowing. `seed(5)`, without the `random` prefix, seeds `random` *and* its smooth cousin `noise` in one go. Noise is Chapter 5's whole subject, and until then the two calls do the same job.

## Finding a seed worth keeping

Flipping through seeds by editing the number and rebuilding gets old fast, so Ollin does the flipping for you. Every sketch is born on a seed, called its `variation`, and you can read it while the sketch runs. `drawCaption` prints a line of text along the bottom of the canvas, which is all you need to see the number:

```swift
override func draw() {
    drawCaption("Variation \(variation)")
}
```

Run the sketch and the inspector (press ⌘/ if you launched it on its own) shows that number on a Variation card, with arrows to step to the next seed, a die to roll a random one, and a field to type one in. Each press restarts the sketch on the new seed while your parameter knobs stay where you set them, so you can hunt for a composition without touching the code.

When you want to see many at once, ask for a contact sheet. This renders one frame per seed and tiles them into a single labeled image, exactly like the nine-tile sheet you saw a moment ago:

```sh
swift run Example-Randomness-Variations --export-grid sheet.png --seeds 25
swift run Example-Randomness-Variations --export keeper.png --seed 10   # render the one you liked
```

One rule makes this worth doing. A seed is worth flipping through only when it decides something structural: which palette, how dense, how large. Make those choices in `setup()`, where the seeded rolls happen once, and let `draw()` animate what `setup()` decided. Do it in `draw()` instead and every seed gives you the same piece, shaken slightly differently.

## Letting chance decide

So far chance has answered "where" and "how big", which are both questions of amount. It can also answer yes-or-no and which-one, and those two turn randomness from decoration into composition:

<img src="Images/04-Randomness/Choices.jpg" alt="Four strips: two rows of dots showing probability gates at 0.25 and 0.75 where filled dots mark passes, a strip of squares uniformly picking four palette colors, and a strip dominated by indigo from a weighted pick" width="680">

The **gate** is an `if` with a threshold. `random()` lands uniformly in 0 to 1, so the fraction below your threshold is the probability of passing:

```swift
if random() < 0.25 {   // about a quarter of the time
    drawCircle(x, y, 9)
}
```

Read the top strip in the figure and count. About a quarter of the slots made it through, but they arrive in clumps and gaps rather than neatly spaced. That lumpiness is what real chance looks like, since dice have no memory of the last roll, and it's half of why generative pieces read as alive rather than patterned.

The **pick** chooses from a list, and it's one call:

```swift
let palette: [Color] = [.indigo, .teal, .gold, .coral]   // any four you like
fill(randomChoice(palette))
```

And when equal odds are too equal, hand the pick **weights**, one per choice, in any scale you like:

```swift
let trio = [Color.indigo, .coral, .gold]
fill(randomChoice(trio, weights: [6, 3, 1]))   // the figure's last strip
```

With weights of six, three, and one, the first color wins six times as often as the last, and a weight of zero would never win at all. Under the hood this is the gate again, one roll checked against thresholds stacked in proportion to the weights. Most compositions want a dominant, a support, and a spice, and three weights buy you that. A related call, `shuffled(palette)`, hands back the whole list in a seeded random order.

## The two shapes of chance

Everything so far spreads its rolls *uniformly*, meaning every value in the range is equally likely, like rain on a flat field. Nature rarely distributes things that way. Heights, errors, leaf sizes, and the places darts actually land all pile up near a middle and thin out symmetrically. That's the **Gaussian** (or normal) distribution, the bell curve, and Ollin rolls it directly:

<img src="Images/04-Randomness/UniformVsGaussian.jpg" alt="Two scatter panels with histograms beneath: uniform random spreads dots evenly with a flat histogram, Gaussian random piles dots around the center with a bell-shaped histogram" width="680">

```swift
let x = randomGaussian(mean: width / 2, deviation: 120)
```

`mean` is the center of the pile; `deviation` is its spread, in the same units. About two thirds of the rolls land within one deviation of the mean and nearly all within three, so there's no hard edge, just increasing rarity. Reach for this whenever you want scatter that reads as *settled* rather than *sprayed*, like dust motes around a lamp or spatter around a brush stroke. Uniform says "anywhere here"; Gaussian says "around here."

## A walk with no destination

One more idea completes the starter kit, and it's the one that points at the rest of this guide. So far every roll has stood alone, because no roll remembers the one before. Watch what happens when you give chance a memory, by letting each roll *nudge* a value instead of replacing it:

<img src="Images/04-Randomness/WalkVsJumps.jpg" alt="Two strips: fresh rolls per step produce a jagged hash of a line, while accumulated nudges produce a wandering path" width="680">

The top strip re-rolls `y` from scratch at every step, so it stays a jagged hash. The bottom strip keeps `y` and adds a small `random(-9, 9)` to it each step, and suddenly there's a *path* that wanders, drifts, and doubles back. This is the **random walk**, the humble ancestor of most organic motion in generative art. Give the same treatment to a point in two dimensions and it traces a journey.

To draw that journey you need one shape this guide hasn't written out yet. `drawLine(x1, y1, x2, y2)` draws a straight segment between two points, and it's the third of the basic shapes from Chapter 1's contact sheet. Joining each step of the walk to the next is all it takes. Make `MySketches/WalkGrows.swift`:

```swift
import Ollin

final class WalkGrows: Sketch {
    override func draw() {
        background(Color(hex: 0x0E1116))
        randomSeed(7)
        stroke(Color(hex: 0x64DFDF, alpha: 0.8))
        strokeWeight(2.5)

        var x = width / 2
        var y = height / 2
        let steps = min(2400, Int(time * 240))   // 240 new steps a second
        for _ in 0..<steps {
            let nx = x + random(-16, 16)
            let ny = y + random(-16, 16)
            drawLine(x, y, nx, ny)
            x = nx
            y = ny
        }

        noStroke()
        fill(.white)
        drawCircle(x, y, 9)
    }
}
```

<img src="Images/04-Randomness/WalkGrows.jpg" alt="A teal random walk on a dark canvas, dense tangled clusters joined by corridors, with a white dot marking the walker's current position" width="560">

Run it and the walk *grows* in front of you, ten seconds from first step to rest. The trick pulls the whole chapter together. The walk is seeded, so every frame redraws the *identical* path from the start, and the only thing time controls is how many steps of it you get to see. Chance decides the shape once; time just reveals more of it. Notice the anatomy of the path, tight tangles connected by sudden corridors. Statisticians call this the drunkard's walk, and the tangles are the lamp posts.

> **Swift note.** Wrapping a number in `Int(...)` drops its fraction, so `Int(time * 240)` counts up in whole steps, 240 of them a second. `min(a, b)` hands back the smaller of its two values, which is what stops the count at 2,400.

The walk's core move is a value carried forward and nudged (`x = nx`), and it's where Part II begins, because velocity, springs, and flocks all carry a value forward and nudge it. The walk does have one visual flaw, the constant jitter, and that's exactly what Chapter 5 fixes, since noise wanders the same way without it.

## Three walks, three rules

Writing that walk by hand is worth doing, and after that Ollin has it ready, along with two relatives that each change exactly one rule about what the next step is allowed to be.

<img src="Images/04-Randomness/WalkFamily.jpg" alt="Three panels from the same seed: a dense tangle pooling in one area, a set of tight clusters joined by long straight leaps, and an orange path on a grid that fills the square without ever crossing itself" width="680">

```swift
randomWalk(steps: 5000, stepLength: 3)
levyFlight(steps: 900, minStep: 1.5, maxStep: 90)
selfAvoidingWalk(cellSize: 22)
```

**`randomWalk`** is the one you just wrote, seeded and shipped. Notice what it does with five thousand steps in the first panel: it pools. A walk with equal-sized steps spreads outward only as fast as the square root of the number of steps, so it spends most of its time revisiting a small patch.

**`levyFlight`** changes the step size rule. Instead of every step being about the same length, the lengths come from a distribution where small steps are overwhelmingly likely but occasionally an enormous one comes up. The result is the second panel: tight clusters joined by long straight leaps. This turns out to be how foraging animals actually move when they don't know where the food is, which is why the pattern shows up in tracking data for albatrosses, sharks, and bees. One knob needs care, and `minStep` must stay above zero, because the distribution's tail runs to infinity at zero and a zero minimum produces steps that never end.

**`selfAvoidingWalk`** changes the memory rule. It moves on a grid and refuses to enter a cell it has already visited, so it can't pool, and it fills its region instead. It also gets stuck, which is not a bug but the whole character of the thing. When every neighbor has been used, the walk stops, and where it stops is part of the drawing.

All three are seeded like everything else in this chapter, so the same seed gives the same journey.

## Putting it together: order, with a pinch of disorder

This is the piece from the top of the chapter, and it holds still on purpose, because its motion lives *between* variations, one click apart. The idea is borrowed openly from the founding generation of computer artists, Vera Molnár above all, who worked exactly this way. You take a perfectly ordered structure, a grid of nested squares, and add disorder in small, controlled amounts. Here each square's corners get a random nudge, and the permitted nudge grows from nothing in the top row to full strength at the bottom, so a single image walks from architecture to scribble. Make `MySketches/DisorderGrid.swift`:

```swift
import Ollin

final class DisorderGrid: Sketch {
    @Param("Disorder", 0...1) var disorder = 0.6
    @Param("Seed", 1...9999) var gridSeed = 7

    let ink = Color(hex: 0x232020)
    let accents: [Color] = [
        Color(hex: 0xC1272D), Color(hex: 0x2E5FA3), Color(hex: 0xD9A21B),
    ]

    override func draw() {
        randomSeed(gridSeed)
        background(Color(hex: 0xF2EDE4))
        noFill()
        strokeWeight(2.5)

        let columns = 9, rows = 9, layers = 4
        let margin = 90.0
        let cell = (width - margin * 2) / Double(columns)
        for r in 0..<rows {
            let unrest = Double(r) / Double(rows - 1) * disorder
            let d = unrest * cell * 0.35
            for c in 0..<columns {
                let left = margin + Double(c) * cell
                let top = margin + Double(r) * cell
                for k in 0..<layers {
                    let inset = cell * 0.1 * Double(k + 1)
                    let x1 = left + inset + random(-1, 1) * d
                    let y1 = top + inset + random(-1, 1) * d
                    let x2 = left + cell - inset + random(-1, 1) * d
                    let y2 = top + inset + random(-1, 1) * d
                    let x3 = left + cell - inset + random(-1, 1) * d
                    let y3 = top + cell - inset + random(-1, 1) * d
                    let x4 = left + inset + random(-1, 1) * d
                    let y4 = top + cell - inset + random(-1, 1) * d
                    stroke(ink)
                    if random() < 0.08 {
                        stroke(randomChoice(accents))
                    }
                    drawLine(x1, y1, x2, y2)
                    drawLine(x2, y2, x3, y3)
                    drawLine(x3, y3, x4, y4)
                    drawLine(x4, y4, x1, y1)
                }
            }
        }
    }

    override func mousePressed() {
        gridSeed += 1
    }
}
```

Run it with `swift run OllinLive MySketches/DisorderGrid.swift` and take it apart:

- `randomSeed(gridSeed)` runs first, so the whole drawing is one seed's variation, held perfectly still. The `Seed` knob picks which one, and you can click the canvas to step to the next variation or click the knob's value box and type a favorite. `Seed` starts at a whole number (`7`, not `7.0`), so it's a whole-number knob, the same move as Chapter 3's `Waves`.
- `unrest` is the composition. Row 0 computes it as zero (no nudge allowed, perfect nesting), the bottom row gets the full `Disorder` knob, and every row between gets its share. One line decides the piece's entire top-to-bottom structure.
- Each quadrilateral is four corners sitting on the posts of a perfect square, `inset` deep into its cell, and every corner coordinate rolls its own `random(-1, 1)` nudge, scaled by the row's reach `d`. That's eight rolls per shape, so the squares don't just shift, they *deform*. Four `drawLine` calls close the loop.
- The accent is a gate and a pick working together, straight from this chapter, with eight percent of quads trading ink for `randomChoice(accents)`.
- Turn `Disorder` to zero and the grid snaps to perfect order: the piece contains its own before picture. Because the *pattern* of rolls never changes with the knob (only their reach), the same tangles grow back in the same places as you turn it up again.

When a seed earns it, export the still:

```sh
swift run OllinLive MySketches/DisorderGrid.swift --export disorder.png
```

Then push it somewhere new:

- Let the disorder grow left to right instead, by building `unrest` from `c` and `columns`.
- Give the inner squares more license than the outer ones, by scaling `d` with `Double(k + 1) / 4`.
- Put the motion back. Writing `let d = unrest * cell * 0.35 * (sin(time * .tau / 8) * 0.5 + 0.5)` breathes the piece between order and chaos every eight seconds, and Chapter 3's loop rule means a `--export-gif` of it loops seamlessly.
- Retune the accents. At `0.02` they read as stray errors, and at `0.3` as confetti. Both are worth trying.

## Where this comes from

The grammar of this chapter is the founding grammar of computer art. Vera Molnár, who began making combinatorial drawings by hand in 1959 with what she called her *machine imaginaire* (dice standing in for the computer she didn't yet have), spent six decades applying precise doses of chance to grids of squares. Her phrase "1% of disorder" is the finished piece's entire recipe, and this guide's repository carries two homages to her plotter work in [`Examples/Recreations/VeraMolnar`](../Examples/Recreations/VeraMolnar/). Georg Nees's *Schotter* (1968), a column of squares tumbling from order into rubble, set the order-above, chaos-below composition this chapter's finished piece borrows. The "pseudo" in pseudo-random goes back to John von Neumann's 1940s number generators, and Ollin's is SplitMix64 (Guy L. Steele Jr., Doug Lea, and Christine H. Flood, 2014). `randomGaussian` uses George Marsaglia's polar method (1964), and the random walk got its enduring nickname from Karl Pearson's 1905 letter to *Nature* asking where a drunk man ends up. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Random](../Docs/Generators/Random.md): the full reference, including `randomVector` (a roll inside a rectangle), `ring` (a roll inside a ring, great for halos), and the seeded `shuffled`.
- [Variations](../Docs/Core/Variations.md): `variation` and the seed-exploration tools in full, including contact sheets (`--export-grid`) and re-rendering a keeper (`--seed`).
- [Walks](../Docs/Generators/Walks.md): the hand-rolled walk from this chapter, shipped and seeded, plus two relatives worth meeting. `levyFlight` mostly shuffles and occasionally leaps, which is how foraging animals actually move, and `selfAvoidingWalk` refuses to cross its own path.
- [Noise](../Docs/Generators/Noise.md): the next chapter's subject, if you can't wait to make chance glide.
- Worked examples, all in [`Examples/Randomness/`](../Examples/Randomness/): `Variations` (a whole composition per seed), `Gaussian` (the bell curve as boiling scatter), `RandomBand` (uniform, for contrast), and `Ring` (the ring roll).
- The Molnár homages in [`Examples/Recreations/VeraMolnar/`](../Examples/Recreations/VeraMolnar/): `DesOrdres` (seeded disorder scrubbed by the mouse) and `Interruptions` (a field of tilted ticks, its gaps carved by the noise you'll meet in Chapter 5).

---

[Contents](README.md#contents) · Previous: [Chapter 3, Motion and time](03-MotionAndTime.md) · Next: [Chapter 5, Noise](05-Noise.md)
