#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Artificial life`</sup>

---

## Artificial life

Three classic emergent-behavior systems, each running on the GPU: **Particle Life**, the **Primordial Particle System (PPS)**, and **Physarum** (slime mold). They are recipes you call from `draw()`, no satellite needed (they ship with `import Ollin`). Particle Life and PPS are built on the [`SpatialHash`](../Shaders/Compute.md#spatialhash) neighbor search, so tens of thousands of particles can feel their neighbors every frame; Physarum communicates through a trail field instead.

One shared caveat: these systems are chaotic, and the neighbor search's within-cell order is set by a GPU atomic race, so a run is **not** reproducible frame-for-frame across machines or exports. Seed them for a repeatable *starting* layout, but do not expect a pixel-identical video every time.

### Contents

- [Particle Life](#particle-life)
- [Primordial Particle System](#pps)
- [Physarum](#physarum)
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

<a id="your-own"></a>
### Building your own on `SpatialHash`

Particle Life and PPS hide the neighbor search inside a typed sim. To build your own particle-interaction system, drive the public [`SpatialHash`](../Shaders/Compute.md#spatialhash) directly: hold your own `PingPong<OllinParticle>`, hand the hash your positions each frame with `neighborStep(_:over:reading:writing:)`, and write a kernel that walks each particle's neighbors with the `OLLIN_FOR_NEIGHBORS` macro. See the [Compute page](../Shaders/Compute.md#spatialhash) for the kernel contract and `Examples/Compute/NeighborSearch` for a worked example.

### Notes

- **Credits.** Particle Life (Ventrella / Tom Mohr), PPS (Schmickl et al.), Physarum (Jones), and the counting-sort neighbor search (Hoetzlein) are reimplemented from the published techniques and credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).
- **Draw order.** Particle Life and PPS render as additive discs in call order like any other drawing; Physarum draws as an `Image`. Compose them with the rest of a sketch freely.
- **Cost is neighbor density.** The hash makes the per-frame cost scale with the number of *near* pairs, not all pairs, so a larger `radius` (denser neighborhoods) costs more than a larger `count` alone.
