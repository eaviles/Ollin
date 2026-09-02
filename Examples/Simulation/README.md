#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Simulation</sup>

---

## Simulation

Systems that evolve on the GPU each frame: the built-in `Sim` field catalog (stateful textures you draw into to seed or force; see the [Layered effects reference](../../Docs/Drawing/Effects.md)), the [artificial-life](../../Docs/Simulation/ArtificialLife.md) particle systems, and the [particle fluids & soft bodies](../../Docs/Simulation/Fluids.md). Distinct from [Physics](../Physics/) (CPU rigid and soft bodies) and [Compute](../Compute/) (raw kernels over buffers and textures).

| Example | What it shows |
|---|---|
| [GrayScott](GrayScott/Sketch.swift) | a Gray-Scott reaction-diffusion field evolving on the GPU (`makeSimField(.reactionDiffusion(...))`) |
| [Automata](Automata/Sketch.swift) | eight classic cellular automata behind one rule picker: Game of Life, Brian's Brain, Griffeath's cyclic automaton, an excitable medium, the hodgepodge machine, the Abelian sandpile, Lenia, and falling sand, each with its own ramp, seeding recipe, and knobs; drag to paint, hold a key to erase (`makeSimField(...)`) |
| [LifeQuilt](LifeQuilt/Sketch.swift) | the classic life rules stepped by hand on the CPU and quilted from triangular wedges colored by a radial cosine palette, the by-hand contrast to the GPU rules in Automata (`drawTriangle`, SDF) |
| [MultiScaleTuring](MultiScaleTuring/Sketch.swift) | McCabe's multi-scale Turing patterns: five scales competing per pixel, self-organizing from noise into diatom-like relief, foldable into a rosette (`makeSimField(.multiScaleTuring(...))`) |
| [Fluid](Fluid/Sketch.swift) | a real-time incompressible fluid carrying colour, drag to swirl (`makeSimField(.fluid(...))`) |
| [SelfWarp](SelfWarp/Sketch.swift) | the picture dragging its own history: orbiting orbs smeared into ribbons along their measured motion, drag to paint with a wake (`makeSimField(.selfWarp(...))`) |
| [Ripples](Ripples/Sketch.swift) | a rain-swept water surface: the 2D wave equation shaded as liquid, click to drop (`makeSimField(.ripples(...))`) |
| [Watercolor](Watercolor/Sketch.swift) | wet paint on rough paper: a scripted wash, wet-in-wet charge, backrun bloom, and glaze you can take over with the mouse (`watercolor(pigments:)`) |
| [ParticleLife](ParticleLife/Sketch.swift) | attraction/repulsion matrices growing membranes, chasers, and worms (`makeParticleLife(...)`) |
| [PrimordialParticles](PrimordialParticles/Sketch.swift) | one turning rule growing dividing cells (`makePrimordialParticles(...)`) |
| [Physarum](Physarum/Sketch.swift) | slime-mold agents growing branching trail networks (`makePhysarum(...)`) |
| [ParticleFluid](ParticleFluid/Sketch.swift) | a box of water made of particles, dam break to splash to pool, drag to grab (`makeParticleFluid(...)`) |
| [SoftBodies](SoftBodies/Sketch.swift) | shape-matched jelly blobs tumbling into a pile, drag to knead (`makeSoftBodies(...)`) |
| [Swarm](Swarm/Sketch.swift) | steering at scale: 30,000 creatures deciding where to go from the same short list of urges, worked out on the GPU, so the same weights make a flock, a crowd, or a drifting cloud (`makeSwarm(...)`) |
| [SwarmChemistry](SwarmChemistry/Sketch.swift) | every particle carries its own copy of the rule it moves by, and on contact one copy overwrites the other: a recipe spreads because the particles holding it keep meeting others and winning |
| [ParticleLenia](ParticleLenia/Sketch.swift) | no force law at all: an energy field, and particles walking downhill on it, with a ring-shaped kernel reading how crowded each one is |
| [Attractor](Attractor/Sketch.swift) | a strange attractor as moving material rather than a still curve: a million particles integrating the same velocity field on the GPU, pulled onto the shape and then streaming along it |
| [Evolution](Evolution/Sketch.swift) | thirty thousand attempts at one journey, none of which knows the route: a genome is a list of pushes, whoever lands nearest is likelier to be a parent, and the route is found in a dozen generations |
| [Breeding](Breeding/Sketch.swift) | evolution with nobody keeping score: sixteen ornaments drawn from eight numbers each, and the only thing deciding who has children is which ones you liked looking at |

Run one with `swift run Example-Simulation-<Name>`, e.g. `swift run Example-Simulation-ParticleFluid`.
