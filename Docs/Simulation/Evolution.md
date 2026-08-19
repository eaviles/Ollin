#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Evolution`</sup>

---

## Evolution

Populations that get better at something, by variation and selection rather than by anything you wrote down. Two halves, for two different sizes of problem:

- **[`Evolution`](#gpu)** runs tens of thousands of individuals on the GPU. Each carries a genome, flies it, is scored on how close it came to a target, and is replaced by the children of whoever did best.
- **[`Population`](#population)** is a handful of genomes a *person* judges. Draw them, pick your favorites, breed. Nobody writes a score.

Both ship with `import Ollin`, no satellite needed.

The two are not the same tool at different sizes. A scored search can only find what the score was written to want. A search you judge by eye can go somewhere you did not know you were headed. You are allowed to change your mind between generations.

### Contents

- [A population on the GPU](#gpu)
- [The genome, the trial, the score](#mechanism)
- [Knobs](#knobs)
- [How a run is doing](#report)
- [Breeding by hand](#population)
- [Genomes](#genome)
- [Mixing and mutation](#mixing)
- [Notes](#notes)

<a id="gpu"></a>
### A population on the GPU

```swift
var run: Evolution!

override func setup() {
    background(.black); noClear()
    run = evolution(count: 30_000, genes: 28,
                    from: Vector2(540, 990), to: Vector2(540, 110))
    run.obstacles = [Rectangle(x: 0, y: 620, width: 640, height: 34),
                     Rectangle(x: 800, y: 620, width: 280, height: 34)]
}

override func draw() {
    // A translucent sheet, not a wipe, so a flight leaves the trail that shows
    // the route it took.
    blendMode(.normal)
    noStroke()
    fill(Color(white: 0.02, alpha: 0.05))
    drawRect(0, 0, width, height)

    blendMode(.add)
    updateEvolution(run)
    drawParticles(run)
}
```

That is the whole sketch. You place a start, a target, and whatever walls are in the way. Selection finds its own way around them. The first generation sprays in every direction. The population piles into the walls for a few generations. Then one lucky genome slips through the gap, and the crowd pours after it.

A run names a population, a genome length, and two points, and nothing else. The reason is that **everything about the pace is derived from the distance the trial has to cover**. The top speed crosses that distance in about two seconds. The trial runs long enough to go the long way round. One gene pushes hard enough to reach the top speed in a quarter of a trial. Those figures are re-derived every frame. So dragging the target re-paces the whole run, rather than leaving it tuned for where the target used to be.

<a id="mechanism"></a>
### The genome, the trial, the score

A genome is a short list of steering impulses, played back over the trial in order. It *is* a plan for a journey, and the flight is what that plan turns out to be worth.

A trial ends, everyone is scored, and the population is replaced in one pass:

- **Closest approach** to the target, as a fraction of the way there, squared. Squaring is what puts the pressure where it matters. Near the target a small gain is a large one, and far from it every genome is about as bad as the next.
- **Hitting a wall** ends the flight and keeps a tenth of what it had earned.
- **Arriving** is its own band, above every near miss, and the sooner it happened the higher. So a population that has found the target goes on to find the quick way to it.

Parents are chosen by **tournament**. Each parent is the best of `tournament` individuals picked at random. That is the one selection method needing no total, no sort, and no normalizing, because it only ever *compares* two scores. Comparing is what lets a whole generation be bred in a single pass, with every child working alone. The wheel-of-fortune method [`Population`](#population) uses needs the sum of everyone's scores before it can pick anybody. A GPU pass would have to stop and agree on that sum. Tournament also means the *scale* of a score never matters, only its order.

There is no explicit elitism, and none is needed. Every child draws `2 * tournament` rivals. Across a whole generation the best individual is passed over only about `e^(-2 * tournament)` of the time. At the default that is three generations in ten thousand.

A child takes each gene from one parent or the other with an even chance. Then each gene has a `mutationRate` chance of being **nudged** by up to `mutationAmount`. The nudge is added to what the gene already held, rather than replacing it. A mutated path is a bent version of its parents' rather than a fresh random one.

<a id="knobs"></a>
### Knobs

| | |
|---|---|
| `start`, `target` | Where a trial begins and what it is selected for reaching. |
| `targetRadius` | How close counts as arrived. |
| `obstacles` | Up to eight `Rectangle` walls a flight is stopped by. |
| `tournament` | How many rivals a parent is the best of. Larger is stronger selection, so it converges sooner and explores less. Default 4. |
| `mutationRate` | Chance a gene is nudged as it is copied. Default 0.04. |
| `mutationAmount` | How far a nudge may reach. Genes live in -1…1. Default 0.35. |
| `maxSpeed`, `trialDuration`, `thrust` | The pace. `nil` (the default) derives each from the distance. Set one to take it over. |
| `colors`, `opacity`, `size` | An individual is colored by how far along the way it has got. |
| `generation`, `progress` | Which generation, and how far through the current trial. |

The default `colors` shift hue and hold their brightness roughly level, for the same reason [`AttractorFlow`](../Drawing/Attractors.md#flow)'s do. Drawn additively, brightness already means *how many flights came this way*. A whole population leaves at one point, so a ramp running dark to light would report the launch crowd as the leaders.

<a id="report"></a>
### How a run is doing

The picture is the readout. The spray narrowing into a route is the search working. For a caption or a knob, turn on `measuresGenerations` and read `lastGeneration`:

```swift
run.measuresGenerations = true    // in setup()

// in draw()
if let last = run.lastGeneration {
    drawCaption("generation \(run.generation) · \(Int(last.arrived * 100))% reached it")
}
```

`Report` carries `best`, `mean`, `arrived` (the fraction that reached the target), and `closest`. The `mean` is the one that tells you a run is improving. The best individual can be a fluke, the average cannot.

It is off by default, because measuring means reading the whole population back from the GPU. That is cheap once every few seconds and not cheap every frame. The read is also taken without stalling the GPU, so it can be a frame stale. It is a summary, not a ledger.

<a id="population"></a>
### Breeding by hand

This is the older idea, and the stranger one. Sixteen candidates sit on screen. The only thing deciding which of them have children is that somebody liked looking at them.

```swift
var pool: Population!
var chosen: Set<Int> = []

override func setup() {
    pool = population(count: 16, genes: 8)
}

override func draw() {
    background(.black)
    for (i, cell) in Grid(in: bounds, columns: 4, rows: 4).cells.enumerated() {
        withState {
            translate(cell.center.x, cell.center.y)
            drawOrnament(pool[i])            // your drawing, from the genome's numbers
        }
    }
}

override func mousePressed() { /* toggle the tile under the cursor in `chosen` */ }

override func keyPressed() {
    if key == " " { pool.breed(from: chosen); chosen = [] }
}
```

Choosing one genome makes a generation of mutated copies of it. Choosing two or more mates them in pairs. **Choosing nothing does nothing at all.** A generation nobody liked is still the only generation there is. Pick something, or call `reroll()` to start again.

The genomes you chose are carried into the next generation untouched (`keepsParents`, on by default). With sixteen candidates and a person judging, one breeding is a large step. Without this, the thing you just picked can be gone the moment you pick it.

The other form scores every genome with a closure and breeds by fitness:

```swift
pool.breed { genome in fitness(of: shape(from: genome)) }
```

That is the wheel-of-fortune method. A genome's share of the next generation's parents is its share of the total score. A score below zero counts as zero, since a share cannot be negative. When every score is zero, parents are picked evenly rather than freezing on the first genome.

<a id="genome"></a>
### Genomes

A `Genome` is a bag of numbers between 0 and 1 that your sketch reads as whatever it likes. Nothing in it knows what it means, which is exactly what lets one be mutated and mated without the framework knowing what is being evolved.

```swift
let radius = g.value(0, in: 20 ... 180)                   // a Double in a range
let arms   = g.value(1, in: 3 ... 9)                      // a whole number, both ends reachable
let style  = g.value(2, among: [Style.solid, .hollow])    // one of a list
let filled = g.flag(3, chance: 0.3)                       // yes or no
```

Read a gene through one of those rather than by hand. The mapping from 0…1 into what you actually want then stays in one place. Genes past the end wrap round to the start rather than trapping. A sketch that grows a new trait still draws while you widen the genome. Two traits reading the same gene move together, which is worth knowing if a drawing suddenly starts rhyming with itself.

`Population` also takes genomes you already have (`Population(_:seed:)`), for resuming a run or starting from a hand-written point.

<a id="mixing"></a>
### Mixing and mutation

`crossover` picks how two parents make a third:

| | |
|---|---|
| `.independent` | Each gene from one parent or the other with an even chance. Mixes the two most thoroughly, and the usual choice. |
| `.split` | Genes before a random point from one parent, the rest from the other. Keeps runs of genes together, which matters when neighboring genes work as a group. |
| `.blend` | Every gene lands part way between the parents. A child that looks like a blend of them rather than a mixture of their parts, which suits genes that are quantities rather than choices. |

`mutationRate` defaults to **0.2** here and 0.04 on the GPU tier, and the gap is on purpose. A person judges maybe twenty candidates a generation, and will sit through maybe twenty generations. So a few hundred looks have to cover ground a scored run covers in millions. Variation has to arrive fast enough to be worth looking at. A scored run wants the published few percent instead, because there the population is large and the generations are cheap.

<a id="notes"></a>
### Notes

- **A run is reproducible on one machine, not across GPUs.** A hair of difference in one flight changes which individual wins a tournament, and from there two populations have parted company. There is no pixel snapshot of one, the same as the other systems on the [compute path](../Shaders/Compute.md).
- **`Population` never touches the sketch's `random`.** It owns its own stream, seeded when you build it, so adding one cannot shift any of a sketch's other rolls.
- **Flights are open-loop.** A genome is decided before the trial starts and nothing is fed back into it, so a population that has found the target arrives at speed and carries straight on past it. That is the technique, not a fault. Braking would need a genome that can see where it is.
- **Genes decide, they do not steer.** Fewer genes make a smoother, coarser path that evolution finds sooner. More genes give finer control over a longer search.
- **Judging by eye is the reason to reach for `Population`.** If you can write the score, write the score.

Examples: `Examples/Simulation/Evolution`, `Examples/Simulation/Breeding`.

### See also

- [`Swarm`](Swarm.md) - steering behaviors at GPU scale, over the same compute path
- [`Artificial life`](ArtificialLife.md) - particle life, primordial particles, and slime mold
- [`Compute`](../Shaders/Compute.md) - the kernels, buffers, and particle path underneath
- [`Variations`](../Core/Variations.md) - the seed as a piece's identity
