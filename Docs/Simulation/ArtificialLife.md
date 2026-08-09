#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Artificial life`</sup>

---

## Artificial life

Five classic emergent-behavior systems, each running on the GPU: **Particle Life**, the **Primordial Particle System (PPS)**, **Physarum** (slime mold), **Particle Lenia**, and **swarm chemistry**. They are recipes you call from `draw()`, no satellite needed (they ship with `import Ollin`). All but Physarum are built on the [`SpatialHash`](../Shaders/Compute.md#spatialhash) neighbor search, so tens of thousands of particles can feel their neighbors every frame; Physarum communicates through a trail field instead.

One shared caveat: these systems are chaotic, and the neighbor search's within-cell order is set by a GPU atomic race, so a run is **not** reproducible frame-for-frame across machines or exports. Seed them for a repeatable *starting* layout, but do not expect a pixel-identical video every time.

### Contents

- [Particle Life](#particle-life)
- [Primordial Particle System](#pps)
- [Physarum](#physarum)
- [Particle Lenia](#particle-lenia)
- [Swarm chemistry](#swarm-chemistry)
- [Building your own on `SpatialHash`](#your-own)

<a id="particle-life"></a>
### Particle Life

A few kinds of particle, one attraction-or-repulsion number for each ordered pair of kinds, and from that alone come membranes, cells, chasers, and worms (Jeffrey Ventrella's *Clusters*, the widely copied "particle life"). Every particle feels a short-range shove away from whoever is too close, then, past a `beta` fraction of the interaction radius, an attraction or repulsion set by the matrix entry for the two kinds. Asymmetry in the matrix (red chases blue, blue flees red) is what keeps it alive.

```swift
var life: ParticleLife!

override func setup() {
    background(.black); noClear()
    life = particleLife(count: 24_000, kinds: 6, radius: 46)
}

override func draw() {
    background(.black)
    blendMode(.add)
    updateParticleLife(life)
    drawParticles(life)
}
```

`count`, `kinds`, and `radius` are fixed at build; the interaction matrix is random (roll a fresh one with `life.randomizeMatrix(seed:)`). The live feel comes from three knobs you can set any frame or bind to a `@Param`:

| Knob | Meaning | Default |
| --- | --- | --- |
| `beta` | where the repulsion core ends and attraction begins, as a fraction of `radius` (0…1) | 0.3 |
| `forceFactor` | overall strength of the interaction forces | 6 |
| `frictionHalfLife` | seconds for a particle's velocity to halve (the medium's viscosity) | 0.04 |

Example: `Examples/Simulation/ParticleLife`.

<a id="pps"></a>
### Primordial Particle System

One turning rule, and cells that grow, divide, and die emerge from it (Schmickl, Stefanec & Crailsheim, *Scientific Reports* 2016). Every step each particle counts its neighbors within `radius`, splits them into how many sit to its left versus its right, turns by a fixed amount `alpha` plus a crowd-proportional amount `beta · N` toward the busier side, and steps forward at a constant `speed`. Particles are colored by how crowded they are, so forming cell walls read magenta and yellow while free wanderers stay green and blue.

```swift
var pps: PPS!

override func setup() {
    let radius = 22.0
    pps = primordialParticles(count: PPS.suggestedCount(for: radius, in: bounds), radius: radius)
}

override func draw() {
    background(Color(white: 0.06))
    updatePPS(pps)
    drawParticles(pps)
}
```

The defaults are the paper's canonical set, `alpha = 180°`, `beta = 17°`, and a `speed` scaled from the paper's `radius = 5` up to yours (all settable as `pps.alphaDegrees` / `pps.betaDegrees` / `pps.speed`). Density matters: `PPS.suggestedCount(for:in:)` picks a `count` that puts an open particle near the paper's 13 to 15 neighbors, which is where the cell-forming regime lives.

Example: `Examples/Simulation/PrimordialParticles`.

<a id="physarum"></a>
### Physarum

Thousands of agents that lay down a chemical trail and steer toward it, growing the branching transport networks of slime mold (Jeff Jones, 2010). Each agent sniffs three points ahead (left, center, right), turns toward the strongest, steps forward, and deposits a little trail; the trail map then blurs and fades a touch each step. No agent talks to another directly, so it needs no neighbor search. You draw the trail, not the agents:

```swift
var slime: Physarum!

override func setup() { slime = physarum(agents: 220_000, resolution: 1024) }

override func draw() {
    updatePhysarum(slime)
    drawImage(slime.image, in: bounds)
}
```

The agents start in a central disc facing out, so a radial web reaches across the field over the first few seconds. The look lives in the sensing and trail knobs:

| Knob | Meaning | Default (Jones) |
| --- | --- | --- |
| `senseAngle` | degrees between the center sensor and each side sensor | 22.5 |
| `turnAngle` | degrees an agent turns toward the stronger side each step | 45 |
| `senseDistance` | how far ahead the sensors sample, in texels | 9 |
| `stepSize` | how far an agent moves each step, in texels | 1 |
| `evaporation` | fraction of the trail that dissipates each step (0…1) | 0.1 |
| `glow` | display gain (how fast trail strength saturates to white) | 1 |

`resolution` is the trail-map size (the sim runs at that resolution, independent of canvas size). Use `physarum(agents:width:height:seed:)` for a non-square map. Deposit is accumulated with an atomic grid, so the trail is well defined despite many agents landing on the same texel.

Example: `Examples/Simulation/Physarum`.

<a id="particle-lenia"></a>
### Particle Lenia

No force law at all: an energy field, and particles walking downhill on it. Each particle adds up a ring-shaped kernel over its neighbors to get a field value `U`, a growth function scores that crowding, a repulsion term keeps anyone from standing on anyone, and the particle moves whichever way the total `E = R − G(U)` improves. Out of those three lines come membranes, cells that hold their shape, rotors, and things that split in two.

```swift
var lenia: ParticleLenia!

override func setup() {
    background(.black); noClear()
    lenia = particleLenia(count: 6000, spacing: 9)
}

override func draw() {
    background(.black)
    blendMode(.add)
    updateParticleLenia(lenia)
    drawParticles(lenia)
}
```

`spacing` is the only length you name: it says how many canvas points one model unit is drawn as, so a configuration keeps its shape at any size. Everything else is the model itself, live every frame:

| Knob | Meaning | Default |
| --- | --- | --- |
| `muK` | radius of the kernel's ring of influence, in model units | 4 |
| `sigmaK` | how wide that ring is | 1 |
| `muG` | the field value growth peaks at: the crowding a particle prefers | 0.6 |
| `sigmaG` | how narrow that preference is (small is fussy, and fussy makes a sharp edge) | 0.15 |
| `cRep` | how hard two particles closer than one unit push apart | 1 |
| `speed` | model time per second of wall clock | 1 |

The two force terms pull against each other, and it is worth knowing which does what: **growth is the only attractive term**, and **repulsion is the only term with an opinion at very short range**. The kernel is a *ring*, so two particles in the same place contribute almost nothing to each other's field, and growth on its own is perfectly happy to let them coincide.

There is no kernel weight to set. It is not a free parameter: the weight is whatever makes the kernel integrate to one over the plane, so Ollin derives it from `muK` and `sigmaK`. That is what keeps `muG` meaning the same crowding when you move the ring, and at the published ring it comes out as the 0.022 the paper prints.

Particles start packed in a disc at the middle, about one per unit of area. Scattered over a whole canvas instead, most would open outside everyone's kernel with nothing to organize with, and the first thing you would see is a long minute of nothing.

Example: `Examples/Simulation/ParticleLenia`.

<a id="swarm-chemistry"></a>
### Swarm chemistry

Every particle carries its own copy of the rule it moves by, and on contact one copy overwrites the other. There is no generation boundary and nothing is being scored. A recipe spreads because the particles holding it keep meeting particles holding something else and winning, which turns out to be enough.

A **recipe** is eight numbers: how far a particle sees, the speed it likes, the speed it can reach, and the strengths of cohesion, alignment, separation, random steering, and pace-keeping. The world opens with a handful of random recipes shared out evenly, and from then on they compete.

```swift
var chem: SwarmChemistry!

override func setup() {
    chem = swarmChemistry(count: 4000, kinds: 6)
}

override func draw() {
    // A translucent wipe, not a hard clear: these particles move a few points a step,
    // so a still frame of dots shows density where trails show movement.
    background(Color(white: 0.04).withAlpha(0.14))
    updateSwarmChemistry(chem)
    drawParticles(chem)
}
```

| Knob | Meaning | Default |
| --- | --- | --- |
| `transmits` | whether recipes copy on contact at all; false freezes them into a plain mixture of kinds | true |
| `competition` | who wins a contact: `.faster`, `.slower`, or `.majority` (whoever is surrounded by more of its own line) | `.majority` |
| `mutationRate` | chance a recipe mutates as it is copied | 0.01 |
| `mutationAmount` | how far one mutated value may move, as a fraction of its range | 0.08 |

`competition` is what "doing well" even means here, and it is the whole character of a run. Setting `transmits` to false gives you the model before the evolutionary layer: a fixed heterogeneous mixture, which is worth seeing on its own.

**Mutation is per contact, not per generation**, and a particle in a crowd makes contact several times a second. That is why the default rate is far below what a generational algorithm like [`Evolution`](Evolution.md) uses: at that rate a recipe takes dozens of nudges within a single takeover and arrives as noise, which shows up as the whole population dissolving into an even gas.

Color is the recipe itself (cohesion, alignment and separation as red, green and blue, the published visualization), so a takeover reads as one color eating the others and a mutation as a shift in shade rather than a new color.

Read the state back with `lineageCounts()` (how many particles each opening line still holds, the scoreboard the model never keeps for itself), `snapshotRecipes()`, and `snapshotLineages()`. All three stall until the GPU has caught up, so call them a few times a second rather than every frame.

**Recipes are stored in the published units**, so one written down anywhere means the same behaviour here. That takes a conversion, because those ranges were chosen for a world whose particles sit about fifty units apart and they carry length (separation is in length² per step²). Ollin derives the conversion, along with how far a particle can see and how close counts as a contact, from how densely `count` particles fill `bounds`, so a particle sees about as many others as one in the published world did and there is nothing else for you to name. Dropped in unconverted, separation comes out several times too strong and the swarm blows apart.

Example: `Examples/Simulation/SwarmChemistry`.

<a id="your-own"></a>
### Building your own on `SpatialHash`

Particle Life and PPS hide the neighbor search inside a typed sim. To build your own particle-interaction system, drive the public [`SpatialHash`](../Shaders/Compute.md#spatialhash) directly: hold your own `PingPong<OllinParticle>`, hand the hash your positions each frame with `neighborStep(_:over:reading:writing:)`, and write a kernel that walks each particle's neighbors with the `OLLIN_FOR_NEIGHBORS` macro. See the [Compute page](../Shaders/Compute.md#spatialhash) for the kernel contract and `Examples/Compute/NeighborSearch` for a worked example.

### Notes

- **Credits.** Particle Life (Ventrella / Tom Mohr), PPS (Schmickl et al.), Physarum (Jones), Particle Lenia (Mordvintsev, Niklasson and Randazzo), swarm chemistry (Sayama), and the counting-sort neighbor search (Hoetzlein) are reimplemented from the published techniques and credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).
- **Draw order.** Particle Life, PPS, Particle Lenia and swarm chemistry render as discs in call order like any other drawing; Physarum draws as an `Image`. Compose them with the rest of a sketch freely.
- **Cost is neighbor density.** The hash makes the per-frame cost scale with the number of *near* pairs, not all pairs, so a larger `radius` (denser neighborhoods) costs more than a larger `count` alone.
