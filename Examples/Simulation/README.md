#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Simulation</sup>

---

## Simulation

These examples run systems that change on the GPU each frame. They cover three areas: the built-in `Sim` field catalog, the [artificial-life](../../Docs/Simulation/ArtificialLife.md) particle systems, and the [particle fluids & soft bodies](../../Docs/Simulation/Fluids.md). A `Sim` field is a stateful texture that you draw into to seed or force it; see the [Layered effects reference](../../Docs/Drawing/Effects.md). This folder is separate from [Physics](../Physics/), which covers CPU rigid and soft bodies, and from [Compute](../Compute/), which covers raw kernels over buffers and textures.

| Example | What it shows |
|---|---|
| [GrayScott](GrayScott/Sketch.swift) | a Gray-Scott reaction-diffusion field that evolves on the GPU (`makeSimField(.reactionDiffusion(...))`) |
| [Automata](Automata/Sketch.swift) | eight classic cellular automata under one rule picker: Game of Life, Brian's Brain, Griffeath's cyclic automaton, an excitable medium, the hodgepodge machine, the Abelian sandpile, Lenia, and falling sand. Each one has its own ramp, seeding recipe, and parameters. Drag to paint, and hold a key to erase (`makeSimField(...)`) |
| [LifeQuilt](LifeQuilt/Sketch.swift) | the classic life rules stepped by hand on the CPU and drawn as a quilt of triangular wedges, colored by a radial cosine palette. It is the by-hand counterpart to the GPU rules in Automata (`drawTriangle`, SDF) |
| [MultiScaleTuring](MultiScaleTuring/Sketch.swift) | McCabe's multi-scale Turing patterns: five scales compete at each pixel and organize themselves from noise into a relief that looks like a diatom. You can fold the result into a rosette (`makeSimField(.multiScaleTuring(...))`) |
| [Fluid](Fluid/Sketch.swift) | a real-time incompressible fluid that carries color. Drag to swirl it (`makeSimField(.fluid(...))`) |
| [SelfWarp](SelfWarp/Sketch.swift) | the picture warps its own earlier frames: orbiting orbs smear into ribbons along their measured motion. Drag to paint with a wake (`makeSimField(.selfWarp(...))`) |
| [Ripples](Ripples/Sketch.swift) | a water surface under rain: the 2D wave equation shaded as liquid. Click to add a drop (`makeSimField(.ripples(...))`) |
| [Watercolor](Watercolor/Sketch.swift) | wet paint on rough paper: a scripted wash, a wet-in-wet charge, a backrun bloom, and a glaze. You can take over from the script with the mouse (`watercolor(pigments:)`) |
| [ParticleLife](ParticleLife/Sketch.swift) | attraction and repulsion matrices that grow membranes, chasers, and worms (`makeParticleLife(...)`) |
| [PrimordialParticles](PrimordialParticles/Sketch.swift) | one turning rule that grows cells, and the cells divide (`makePrimordialParticles(...)`) |
| [Physarum](Physarum/Sketch.swift) | slime-mold agents that grow branching trail networks (`makePhysarum(...)`) |
| [ParticleFluid](ParticleFluid/Sketch.swift) | a box of water made of particles. It starts as a dam break, splashes, then settles into a pool. Drag to grab it (`makeParticleFluid(...)`) |
| [SoftBodies](SoftBodies/Sketch.swift) | shape-matched jelly blobs that tumble into a pile. Drag to knead them (`makeSoftBodies(...)`) |
| [Swarm](Swarm/Sketch.swift) | steering at scale: 30,000 creatures decide where to go from the same short list of urges, and the GPU works it out. Because the list is shared, the same weights make a flock, a crowd, or a drifting cloud (`makeSwarm(...)`) |
| [SwarmChemistry](SwarmChemistry/Sketch.swift) | every particle carries its own copy of the rule it moves by. When two particles touch, one copy overwrites the other, so a recipe spreads when the particles that hold it keep meeting others and winning |
| [ParticleLenia](ParticleLenia/Sketch.swift) | no force law at all. Instead there is an energy field, and the particles walk downhill on it. A ring-shaped kernel measures how crowded each particle is |
| [Attractor](Attractor/Sketch.swift) | a strange attractor as moving material rather than a still curve. A million particles integrate the same velocity field on the GPU. They are pulled onto the shape and then stream along it |
| [Evolution](Evolution/Sketch.swift) | thirty thousand attempts at one journey, and none of them knows the route. A genome is a list of pushes. Whoever lands nearest is more likely to become a parent, so the route is found in a dozen generations |
| [Breeding](Breeding/Sketch.swift) | evolution with nobody keeping score. Sixteen ornaments are each drawn from eight numbers, and the only thing that decides which ones have children is which ones you liked looking at |

Run one with `swift run Example-Simulation-<Name>`, e.g. `swift run Example-Simulation-ParticleFluid`.
