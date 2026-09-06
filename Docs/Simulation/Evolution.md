#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Evolution`</sup>

---

## Evolution

This page covers populations that get better at something through variation and selection, rather than through anything you wrote down. There are two halves, for two different sizes of problem:

- **[`Evolution`](#gpu)** runs tens of thousands of individuals on the GPU. Each individual carries a genome and flies it. Each is then scored on how close it came to a target, and replaced by the children of whoever did best.
- **[`Population`](#population)** is a handful of genomes that a *person* judges. You draw them, pick your favorites, and breed them. Nobody writes a score.

Both come with `import Ollin`, so no satellite is needed.

The two are not the same tool at different sizes. A scored search can only find what its score was written to want. A search you judge by eye can go somewhere you did not plan to go, because you can change your mind between generations.

### Contents

- [A population on the GPU](#gpu)
- [The genome, the trial, the score](#mechanism)
- [Parameters](#parameters)
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
    run = makeEvolution(count: 30_000, genes: 28,
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

That is the whole sketch. You place a start, a target, and any walls in the way, and selection finds a route around them. The first generation sprays in every direction. For a few generations the population piles into the walls. Then one lucky genome gets through the gap, and the rest of the population follows it.

<img src="../../Guide/Images/20-ParticleSimulations/Evolution.jpg" alt="Three dark panels, each with a wall across the middle broken by a narrow gap and a gold ring near the top. Left, generation 1: a violet blob of dots at the bottom and a thin scatter above the wall. Middle, generation 8: a broad blue and green plume rising through the gap and spreading toward the ring. Right, generation 23: one clean arc, violet at the bottom through blue and green to gold, threading the gap and ending in the ring" width="880">

A run names a population size, a genome length, and two points, and nothing else. That is enough because **everything about the pace is derived from the distance the trial has to cover**. The top speed crosses that distance in about two seconds. The trial lasts long enough to take a longer route around. One gene pushes hard enough to reach the top speed in a quarter of a trial. Those figures are derived again every frame. So dragging the target re-paces the whole run, instead of leaving it tuned for where the target used to be.

<a id="mechanism"></a>
### The genome, the trial, the score

A genome is a short list of steering impulses, played back in order over the trial. The genome is the plan for the flight, and the flight shows how good the plan is.

When a trial ends, every individual is scored, and the population is replaced in one pass:

- **Closest approach** to the target, as a fraction of the way there, squared. Squaring puts the selection pressure where it matters. Near the target, a small gain in distance is a large gain in score. Far from it, every genome scores about as badly as the next.
- **Hitting a wall** ends the flight, and the individual keeps a tenth of the score it had earned.
- **Arriving** scores in its own band, above every near miss, and an earlier arrival scores higher. So a population that has found the target goes on to find the quickest way to it.

Parents are chosen by **tournament**. Each parent is the best of `tournament` individuals picked at random. This is the one selection method that needs no total, no sort, and no normalizing, because it only ever *compares* two scores. Because it only compares, a whole generation can be bred in a single pass, with every child computed on its own. The wheel-of-fortune method that [`Population`](#population) uses needs the sum of everyone's scores before it can pick anybody. A GPU pass would have to stop to agree on that sum. Tournament selection also means that the *scale* of a score never matters, only its order.

There is no explicit elitism, and none is needed, because every child draws `2 * tournament` rivals. Across a whole generation, the best individual is passed over only about `e^(-2 * tournament)` of the time. At the default `tournament` of 4, that is three generations in ten thousand.

A child takes each gene from one parent or the other with an even chance. Then each gene has a `mutationRate` chance of being **nudged** by up to `mutationAmount`. The nudge is added to the value the gene already held, rather than replacing it. So a mutated path is a bent version of its parents' path, not a fresh random one.

<a id="parameters"></a>
### Parameters

| | |
|---|---|
| `start`, `target` | Where a trial begins, and the point a flight is selected for reaching. |
| `targetRadius` | How close to the target counts as arrived. |
| `obstacles` | Up to eight `Rectangle` walls that stop a flight. |
| `tournament` | How many rivals a parent is the best of. A larger value is stronger selection, so the run converges sooner and explores less. Default 4. |
| `mutationRate` | The chance that a gene is nudged as it is copied. Default 0.04. |
| `mutationAmount` | How far a nudge may move a gene. Genes lie in `-1...1`. Default 0.35. |
| `maxSpeed`, `trialDuration`, `thrust` | The pace. `nil` (the default) derives each one from the distance. Set one to take over that value. |
| `colors`, `opacity`, `size` | How an individual is drawn. Its color follows how far along the way it has got. |
| `generation`, `progress` | Which generation is running, and how far through the current trial it is. |

The default `colors` shift in hue and hold their brightness roughly level, for the same reason that [`AttractorFlow`](../Drawing/Attractors.md#flow)'s colors do. With additive drawing, brightness already means *how many flights came this way*. A whole population leaves from one point. Every flight begins there, so a ramp running from dark to light would make that point look like the flights that have got furthest.

<a id="report"></a>
### How a run is doing

The picture is the readout. When the spray narrows into a route, the search is working. For a caption or a parameter, turn on `measuresGenerations` and read `lastGeneration`:

```swift
run.measuresGenerations = true    // in setup()

// in draw()
if let last = run.lastGeneration {
    drawCaption("generation \(run.generation) · \(Int(last.arrived * 100))% reached it")
}
```

`Report` carries `best`, `mean`, `arrived` (the fraction that reached the target), and `closest`. The `mean` is the value that tells you a run is improving, because the best individual can be a fluke and the average cannot.

Measuring is off by default, because it means reading the whole population back from the GPU. That read is cheap once every few seconds and not cheap every frame. The read is taken without stalling the GPU, so the report can be one frame stale. Treat it as a summary, not as an exact record.

<a id="population"></a>
### Breeding by hand

This is the older of the two ideas. It is also the stranger one, because nothing here scores a genome. Sixteen candidates sit on screen, and the only thing that decides which of them have children is that somebody liked looking at them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/20-ParticleSimulations/PickAndBreed-dark.jpg">
  <img src="../../Guide/Images/20-ParticleSimulations/PickAndBreed.jpg" alt="Two four-by-four grids of small radial ornaments. In the left grid every ornament is different and two are outlined in orange. In the right grid, one breeding later, all sixteen are recognizable variations on the outlined pair" width="680">
</picture>

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

Choosing one genome makes a generation of mutated copies of it. Choosing two or more mates them in pairs. **Choosing nothing does nothing.** If you pick no genome, the generation on screen stays as it is. So pick something, or call `reroll()` to start again.

The genomes you chose are carried into the next generation unchanged (`keepsParents`, on by default). With sixteen candidates and a person judging, one breeding is a large step. Without this, the genome you just picked could be gone the moment you picked it.

The other form scores every genome with a closure and breeds by fitness:

```swift
pool.breed { genome in fitness(of: shape(from: genome)) }
```

That is the wheel-of-fortune method. A genome's share of the next generation's parents is its share of the total score. A score below zero counts as zero, because a share cannot be negative. When every score is zero, parents are picked evenly, rather than the run freezing on the first genome.

<a id="genome"></a>
### Genomes

A `Genome` is a list of numbers between 0 and 1 that your sketch reads as whatever it likes. That range is `Population`'s alone. The GPU `Evolution` tier above holds steering impulses instead, and those run `-1...1`. Nothing in the genome knows what its numbers mean. That is what lets one be mutated and mated without the framework knowing what is being evolved.

```swift
let radius = g.value(0, in: 20 ... 180)                   // a Double in a range
let arms   = g.value(1, in: 3 ... 9)                      // a whole number, both ends reachable
let style  = g.value(2, among: [Style.solid, .hollow])    // one of a list
let filled = g.isSet(3, chance: 0.3)                       // yes or no
```

Read a gene through one of those calls rather than by hand. The mapping from `0...1` into the value you want then stays in one place. An index past the end wraps round to the start rather than trapping. So a sketch that grows a new trait still draws while you widen the genome. Two traits that read the same gene move together, which is worth knowing when a drawing suddenly starts repeating itself.

`Population` also accepts genomes you already have (`Population(_:seed:)`), so you can resume a run or start from a hand-written point.

<a id="mixing"></a>
### Mixing and mutation

`crossover` chooses how two parents make a child:

| | |
|---|---|
| `.independent` | Each gene comes from one parent or the other with an even chance. This mixes the two most thoroughly, and it is the usual choice. |
| `.split` | Genes before a random point come from one parent, and the rest from the other. This keeps runs of genes together, which matters when neighboring genes work as a group. |
| `.blend` | Every gene lands part way between the parents' values. A child that looks like a blend of them rather than a mixture of their parts, which suits genes that are quantities rather than choices. |

`mutationRate` defaults to **0.2** here and to 0.04 on the GPU tier, and the gap is on purpose. A person judges maybe twenty candidates a generation, and sits through maybe twenty generations. So a few hundred looks have to cover the ground that a scored run covers in millions. That means variation has to arrive fast enough to be worth looking at. A scored run uses a rate of a few percent instead, the figure usually published for this kind of search. There the population is large and the generations are cheap.

<a id="notes"></a>
### Notes

- **A run is reproducible on one machine, not across GPUs.** A tiny difference in one flight changes which individual wins a tournament. From that point the run on one GPU and the run on another diverge. There is no pixel snapshot of a run, the same as for the other systems on the [compute path](../Shaders/Compute.md).
- **`Population` never touches the sketch's `random`.** It owns its own random stream, seeded when you build it. So adding a `Population` cannot shift any of the sketch's other random rolls.
- **Flights are open-loop.** A genome is decided before the trial starts, and nothing is fed back into it during the flight. So a population that has found the target arrives at speed and carries straight on past it. That is how the technique works, not a fault, because braking would need a genome that can see where it is.
- **Genes decide, they do not steer.** Fewer genes make a smoother, coarser path, which evolution finds sooner. More genes give finer control over a longer search.
- **Judging by eye is the reason to use `Population`.** If you can write the score, write the score.

Examples: `Examples/Simulation/Evolution`, `Examples/Simulation/Breeding`.

### See also

- [`Swarm`](Swarm.md) - steering behaviors at GPU scale, over the same compute path
- [`Artificial life`](ArtificialLife.md) - particle life, primordial particles, and slime mold
- [`Compute`](../Shaders/Compute.md) - the kernels, buffers, and particle path underneath
- [`Variations`](../Core/Variations.md) - the seed as a piece's identity
