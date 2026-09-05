#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Artificial life`</sup>

---

## Artificial life

Ollin has five classic emergent-behavior systems, and each one runs on the GPU. They are **Particle Life**, the **Primordial Particle System (PPS)**, **Physarum** (slime mold), **Particle Lenia**, and **swarm chemistry**. They are recipes you call from `draw()`, so they need no satellite and they ship with `import Ollin`. All but Physarum are built on the [`SpatialHash`](../Shaders/Compute.md#spatialhash) neighbor search, which is how tens of thousands of particles can respond to their neighbors every frame. Physarum works the other way, because its agents communicate through a trail field.

All five share one caveat. These systems are chaotic, and a GPU atomic race sets the order of the particles within a cell of the neighbor search. A run is therefore **not** reproducible frame-for-frame across machines or exports. Seed a system to get a repeatable *starting* layout, but do not expect a pixel-identical video every time.

<img src="../../Guide/Images/20-ParticleSimulations/ArtificialLife.jpg" alt="Three dark panels. Left, Particle Life in dense magenta, yellow, green, and red clusters forming membranes and cells. Middle, the Primordial Particle System, yellow rings of crowded particles scattered among lone blue wanderers. Right, Physarum, a pale branching network of transport loops on a violet trail field" width="680">

### Contents

- [Particle Life](#particle-life)
- [Primordial Particle System](#pps)
- [Physarum](#physarum)
- [Particle Lenia](#particle-lenia)
- [Swarm chemistry](#swarm-chemistry)
- [Building your own on `SpatialHash`](#your-own)

<a id="particle-life"></a>
### Particle Life

Particle Life uses a few kinds of particle and one attraction-or-repulsion number for each ordered pair of kinds. That alone produces membranes, cells, chasers, and worms. The model is Jeffrey Ventrella's *Clusters*, the widely copied "particle life". Every particle gets a short-range push away from any particle that is too close to it. Past a `beta` fraction of the interaction radius it is attracted or repelled instead, by the amount in the matrix entry for the two kinds. Asymmetry in the matrix (red chases blue, blue flees red) is what keeps the motion going.

```swift
var life: ParticleLife!

override func setup() {
    background(.black); noClear()
    life = makeParticleLife(count: 24_000, kinds: 6, radius: 46)
}

override func draw() {
    background(.black)
    blendMode(.add)
    updateParticleLife(life)
    drawParticles(life)
}
```

`count`, `kinds`, and `radius` are fixed when you build the sim. The interaction matrix starts out random, and `life.randomizeMatrix(seed:)` makes a fresh one. Three more parameters shape how the motion looks, and you can set them on any frame or bind them to a `@Param`:

| Parameter | Meaning | Default |
| --- | --- | --- |
| `beta` | where the repulsion core ends and attraction begins, as a fraction of `radius` (0…1) | 0.3 |
| `forceFactor` | the overall strength of the interaction forces | 6 |
| `frictionHalfLife` | seconds for a particle's velocity to halve, which is the viscosity of the medium | 0.04 |

Example: `Examples/Simulation/ParticleLife`.

<a id="pps"></a>
### Primordial Particle System

One turning rule is enough to produce cells that grow, divide, and die (Schmickl, Stefanec & Crailsheim, *Scientific Reports* 2016). On every step each particle counts the neighbors within `radius`, and sorts them into the ones on its left and the ones on its right. It then turns toward the busier side by a fixed amount `alpha` plus a crowd-proportional amount `beta · N`. Finally it steps forward at a constant `speed`. Ollin colors each particle by how crowded it is. Cell walls read magenta and yellow as they form, and free wanderers stay green and blue.

```swift
var pps: PPS!

override func setup() {
    let radius = 22.0
    pps = makePrimordialParticles(count: PPS.suggestedCount(for: radius, in: bounds), radius: radius)
}

override func draw() {
    background(Color(white: 0.06))
    updatePrimordialParticles(pps)
    drawParticles(pps)
}
```

The defaults are the paper's canonical set, `alpha = 180°` and `beta = 17°`. The `speed` default is the paper's too, scaled from its `radius = 5` up to the radius you use. You set all three through `pps.alphaDegrees`, `pps.betaDegrees`, and `pps.speed`. Density matters as much as those three do. `PPS.suggestedCount(for:in:)` picks a `count` that gives a particle in the open about the paper's 13 to 15 neighbors, which is the density where cells form.

Example: `Examples/Simulation/PrimordialParticles`.

<a id="physarum"></a>
### Physarum

Thousands of agents lay down a chemical trail and steer toward it, which grows the branching transport networks of slime mold (Jeff Jones, 2010). Each agent samples three points ahead (left, center, right), turns toward the strongest reading, steps forward, and deposits a little trail. The trail map then blurs and fades slightly on each step. No agent reads another agent directly, so this system needs no neighbor search. You draw the trail rather than the agents:

```swift
var slime: Physarum!

override func setup() { slime = makePhysarum(agents: 220_000, resolution: 1024) }

override func draw() {
    updatePhysarum(slime)
    drawImage(slime.image, in: bounds)
}
```

The agents start in a central disc facing outward, so a radial web spreads across the field over the first few seconds. The sensing and trail parameters decide how it looks:

| Parameter | Meaning | Default (Jones) |
| --- | --- | --- |
| `senseAngle` | degrees between the center sensor and each side sensor | 22.5 |
| `turnAngle` | degrees an agent turns toward the stronger side each step | 45 |
| `senseDistance` | how far ahead the sensors sample, in texels | 9 |
| `stepSize` | how far an agent moves each step, in texels | 1 |
| `evaporation` | the fraction of the trail that dissipates each step (0…1) | 0.1 |
| `glow` | display gain, which is how fast trail strength saturates to white | 1 |

`resolution` is the size of the trail map, and the sim runs at that resolution whatever the canvas size is. Use `makePhysarum(agents:width:height:seed:)` for a map that is not square. Deposits accumulate in an atomic grid, so the trail stays well defined when many agents land on the same texel.

Example: `Examples/Simulation/Physarum`.

<a id="particle-lenia"></a>
### Particle Lenia

Particle Lenia has no force law. It has an energy field instead, and the particles walk downhill on it. Each particle adds up a ring-shaped kernel over its neighbors to get a field value `U`. A growth function scores that crowding, and a repulsion term keeps two particles from standing in the same place. The particle then moves in whichever direction improves the total `E = R − G(U)`. Those three rules produce membranes, cells that hold their shape, rotors, and bodies that split in two.

<img src="../../Guide/Images/20-ParticleSimulations/ParticleLenia.jpg" alt="Three dark panels of colored dots. Left, a cell with a fringed pale-green membrane, a warm red interior, and small vesicles inside it. Middle, a looser coral-like labyrinth of green channels with a blue halo of scattered particles. Right, a solid red body inside one clean smooth green membrane" width="680">

```swift
var lenia: ParticleLenia!

override func setup() {
    background(.black); noClear()
    lenia = makeParticleLenia(count: 6000, spacing: 9)
}

override func draw() {
    background(.black)
    blendMode(.add)
    updateParticleLenia(lenia)
    drawParticles(lenia)
}
```

`spacing` is the only length you set. It says how many canvas points one model unit is drawn as, so a configuration keeps its shape at any canvas size. Everything below is part of the model itself, and you can change it on any frame:

| Parameter | Meaning | Default |
| --- | --- | --- |
| `muK` | radius of the kernel's ring of influence, in model units | 4 |
| `sigmaK` | how wide that ring is | 1 |
| `muG` | the field value where growth peaks, which is the crowding a particle prefers | 0.6 |
| `sigmaG` | how narrow that preference is (a small value is strict, and a strict preference makes a sharp edge) | 0.15 |
| `cRep` | how hard two particles closer than one unit push apart | 1 |
| `speed` | model time per second of wall clock | 1 |

The two force terms pull against each other, and each one does a single job. Growth is the only term that attracts. Repulsion is the only term that acts at very short range. The kernel is a *ring*, so two particles in the same place add almost nothing to each other's field. Growth on its own would therefore leave them on top of each other.

There is no kernel weight to set, because the weight is not a free parameter. It is whatever makes the kernel integrate to one over the plane, so Ollin derives it from `muK` and `sigmaK`. That is what keeps `muG` meaning the same crowding when you move the ring. At the published ring the weight comes out as the 0.022 the paper prints.

Particles start packed in a disc at the middle, about one per unit of area. If they were scattered over a whole canvas instead, most of them would start outside every kernel and have nothing to organize around. The run would then open with a long minute of nothing.

Example: `Examples/Simulation/ParticleLenia`.

<a id="swarm-chemistry"></a>
### Swarm chemistry

Every particle carries its own copy of the rule it moves by, and on contact one copy overwrites the other. There is no generation boundary, and nothing is scored. A recipe spreads because the particles holding it keep meeting particles that hold a different one and winning those contacts. That alone is enough for a recipe to take over.

A **recipe** is eight numbers. Three of them are how far a particle sees, the speed it prefers, and the top speed it can reach. The other five are the strengths of cohesion, alignment, separation, random steering, and pace-keeping. A run starts with a handful of random recipes shared out evenly, and from then on those recipes compete.

```swift
var chem: SwarmChemistry!

override func setup() {
    chem = makeSwarmChemistry(count: 4000, kinds: 6)
}

override func draw() {
    // A translucent wipe, not a hard clear: these particles move a few points a step,
    // so a still frame of dots shows density where trails show movement.
    background(Color(white: 0.04).withAlpha(0.14))
    updateSwarmChemistry(chem)
    drawParticles(chem)
}
```

| Parameter | Meaning | Default |
| --- | --- | --- |
| `transmits` | whether recipes copy on contact at all (false freezes them into a plain mixture of kinds) | true |
| `competition` | who wins a contact: `.faster`, `.slower`, or `.majority` (whoever is surrounded by more of its own line) | `.majority` |
| `mutationRate` | the chance a recipe mutates as it is copied | 0.01 |
| `mutationAmount` | how far one mutated value may move, as a fraction of its range | 0.08 |

`competition` defines what doing well means in this model, so it sets the character of a whole run. Setting `transmits` to false gives you the model without the evolutionary layer. That leaves a fixed mixture of different kinds, which is worth watching on its own.

**Mutation happens per contact, not per generation.** A particle in a crowd makes contact several times a second. That is why the default rate is far below the rate a generational algorithm like [`Evolution`](Evolution.md) uses. At a generational rate a recipe takes dozens of small changes during a single takeover, so it arrives as noise. You see that as the whole population dissolving into an even gas.

The color of a particle is its recipe. Cohesion, alignment, and separation are drawn as red, green, and blue, which is the published visualization. A takeover therefore looks like one color replacing the others, and a mutation looks like a shift in shade rather than a new color.

<img src="../../Guide/Images/20-ParticleSimulations/SwarmChemistry.jpg" alt="Three dark panels showing one contest at three ages, with a colored share bar under each. At 71 steps, several small clusters of olive and white particles among scattered green and blue ones, and a bar split six ways. At 401 steps, two larger bodies and a bar split two ways. At 1501 steps, one large body with a green fringe and a bar almost entirely one color" width="680">

Read the state back with `snapshotLineageCounts()`, `snapshotRecipes()`, and `snapshotLineages()`. `snapshotLineageCounts()` reports how many particles each opening line still holds, which is the scoreboard the model never keeps for itself. All three wait until the GPU has caught up, so call them a few times a second rather than every frame.

**Recipes are stored in the published units**, so a recipe written down anywhere means the same behavior here. That takes a conversion, because those ranges were chosen for a world whose particles sit about fifty units apart. The units also carry length, since separation is measured in length² per step². Ollin works the conversion out from how densely `count` particles fill `bounds`, and it derives the sight radius and the contact distance the same way. A particle then sees about as many others as a particle in the published world did, and there is nothing else for you to set. If a recipe went in unconverted, separation would come out several times too strong and the swarm would blow apart.

Example: `Examples/Simulation/SwarmChemistry`.

<a id="your-own"></a>
### Building your own on `SpatialHash`

Particle Life and PPS keep the neighbor search inside a typed sim. To build your own particle-interaction system, drive the public [`SpatialHash`](../Shaders/Compute.md#spatialhash) directly. Hold your own `PingPong<OllinParticle>`, and pass the hash your positions each frame with `neighborStep(_:over:reading:writing:)`. Then write a kernel that walks each particle's neighbors with the `OLLIN_FOR_NEIGHBORS` macro. The [Compute page](../Shaders/Compute.md#spatialhash) has the kernel contract, and `Examples/Compute/NeighborSearch` is a worked example.

### Notes

- **Credits.** Each of these systems is reimplemented from a published technique, and every source is credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md). The sources are Particle Life (Ventrella / Tom Mohr), PPS (Schmickl et al.), Physarum (Jones), Particle Lenia (Mordvintsev, Niklasson and Randazzo), swarm chemistry (Sayama), and the counting-sort neighbor search (Hoetzlein).
- **Draw order.** Particle Life, PPS, Particle Lenia, and swarm chemistry render as discs in call order, like any other drawing. Physarum draws as an `Image`. You can compose any of them with the rest of a sketch freely.
- **Cost is neighbor density.** The hash makes the per-frame cost scale with the number of *near* pairs, not with the number of all pairs. A larger `radius` gives denser neighborhoods, so raising `radius` costs more than raising `count` by itself.
