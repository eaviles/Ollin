#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Simulation</sup>

---

## Simulation

| [![Attractor](https://media.ollin.art/examples/Simulation/Attractor/still-640.jpg?v=31fb728b)](Attractor/) | [![Automata](https://media.ollin.art/examples/Simulation/Automata/still-640.jpg?v=a84844fd)](Automata/) | [![Breeding](https://media.ollin.art/examples/Simulation/Breeding/still-640.jpg?v=d1c47ace)](Breeding/) | [![Crowd](https://media.ollin.art/examples/Simulation/Crowd/still-640.jpg?v=989f852f)](Crowd/) |
|---|---|---|---|
| [Attractor](Attractor/) | [Automata](Automata/) | [Breeding](Breeding/) | [Crowd](Crowd/) |
| [![Evolution](https://media.ollin.art/examples/Simulation/Evolution/still-640.jpg?v=d94560fe)](Evolution/) | [![Fluid](https://media.ollin.art/examples/Simulation/Fluid/still-640.jpg?v=161f36af)](Fluid/) | [![GrayScott](https://media.ollin.art/examples/Simulation/GrayScott/still-640.jpg?v=235b5914)](GrayScott/) | [![Kuramoto](https://media.ollin.art/examples/Simulation/Kuramoto/still-640.jpg?v=f2864c53)](Kuramoto/) |
| [Evolution](Evolution/) | [Fluid](Fluid/) | [GrayScott](GrayScott/) | [Kuramoto](Kuramoto/) |
| [![LifeQuilt](https://media.ollin.art/examples/Simulation/LifeQuilt/still-640.jpg?v=2a13e774)](LifeQuilt/) | [![MultiScaleTuring](https://media.ollin.art/examples/Simulation/MultiScaleTuring/still-640.jpg?v=77161fa5)](MultiScaleTuring/) | [![ParticleFluid](https://media.ollin.art/examples/Simulation/ParticleFluid/still-640.jpg?v=51fb013b)](ParticleFluid/) | [![ParticleLenia](https://media.ollin.art/examples/Simulation/ParticleLenia/still-640.jpg?v=558f6ef2)](ParticleLenia/) |
| [LifeQuilt](LifeQuilt/) | [MultiScaleTuring](MultiScaleTuring/) | [ParticleFluid](ParticleFluid/) | [ParticleLenia](ParticleLenia/) |
| [![ParticleLife](https://media.ollin.art/examples/Simulation/ParticleLife/still-640.jpg?v=5f5f65ed)](ParticleLife/) | [![Physarum](https://media.ollin.art/examples/Simulation/Physarum/still-640.jpg?v=f458ed86)](Physarum/) | [![PredatorPrey](https://media.ollin.art/examples/Simulation/PredatorPrey/still-640.jpg?v=19e4583a)](PredatorPrey/) | [![PrimordialParticles](https://media.ollin.art/examples/Simulation/PrimordialParticles/still-640.jpg?v=6fd5c2d2)](PrimordialParticles/) |
| [ParticleLife](ParticleLife/) | [Physarum](Physarum/) | [PredatorPrey](PredatorPrey/) | [PrimordialParticles](PrimordialParticles/) |
| [![Ripples](https://media.ollin.art/examples/Simulation/Ripples/still-640.jpg?v=ad44f0d1)](Ripples/) | [![SelfWarp](https://media.ollin.art/examples/Simulation/SelfWarp/still-640.jpg?v=b798e8fa)](SelfWarp/) | [![SoftBodies](https://media.ollin.art/examples/Simulation/SoftBodies/still-640.jpg?v=b401f5fb)](SoftBodies/) | [![Swarm](https://media.ollin.art/examples/Simulation/Swarm/still-640.jpg?v=aece2131)](Swarm/) |
| [Ripples](Ripples/) | [SelfWarp](SelfWarp/) | [SoftBodies](SoftBodies/) | [Swarm](Swarm/) |
| [![SwarmChemistry](https://media.ollin.art/examples/Simulation/SwarmChemistry/still-640.jpg?v=c59c8fd8)](SwarmChemistry/) | [![Watercolor](https://media.ollin.art/examples/Simulation/Watercolor/still-640.jpg?v=c450ffd5)](Watercolor/) | [![Wind](https://media.ollin.art/examples/Simulation/Wind/still-640.jpg?v=32bbace9)](Wind/) |  |
| [SwarmChemistry](SwarmChemistry/) | [Watercolor](Watercolor/) | [Wind](Wind/) |  |

These examples run systems that change on the GPU each frame. They cover three areas: the built-in `Sim` field catalog, the [artificial-life](../../Docs/Simulation/ArtificialLife.md) particle systems, and the [particle fluids & soft bodies](../../Docs/Simulation/Fluids.md). A `Sim` field is a stateful texture that you draw into to seed or force it; see the [Layered effects reference](../../Docs/Drawing/Effects.md). This folder is separate from [Physics](../Physics/), which covers CPU rigid and soft bodies, and from [Compute](../Compute/), which covers raw kernels over buffers and textures.

| Example | What it shows |
|---|---|
| [GrayScott](GrayScott/Sketch.swift) | a Gray-Scott reaction-diffusion field that evolves on the GPU (`makeSimField(.reactionDiffusion(...))`) |
| [Wind](Wind/Sketch.swift) | a simulation of your own: a wind carrying dust, run by two kernels the sketch writes (`Sim.shader`), a drag pushing it through the inject kernel, a noise layer stirring it as an input, the edge switched live between wrapping and walls, the wind drawn as arrows (`.arrows`), and the mean speed read back every half second (`snapshot()`) |
| [PredatorPrey](PredatorPrey/Sketch.swift) | two populations on one land, prey and predators chasing each other in waves: an invasion front, then rotating spirals in its wake. Drag to release predators (`makeSimField(.predatorPrey(...))`) |
| [Automata](Automata/Sketch.swift) | thirteen classic cellular automata under one rule picker: Game of Life, Brian's Brain, Wireworld, Griffeath's cyclic automaton, an excitable medium, the hodgepodge machine, the forest fire, Schelling's segregation, the Ising model, the Abelian sandpile, Lenia, SmoothLife, and falling sand. Each one has its own ramp, seeding recipe, and parameters. Drag to paint, and hold a key to erase (`makeSimField(...)`) |
| [Kuramoto](Kuramoto/Sketch.swift) | fireflies falling into step: four hundred `Kuramoto` oscillators flashing at their own pace, pulled toward the crowd, with the phases on a wheel and the order parameter as an arrow from its center; below the critical coupling they twinkle at random, above it they flash as one (`Kuramoto`, `coherence`) |
| [Crowd](Crowd/Sketch.swift) | walkers that make room for each other: every one takes the velocity nearest its wish that keeps it clear of the others for the next second, trusting each neighbor to do half. Four scenes: a room draining through a door, a corridor where opposing streams sort into lanes, four streams crossing, and a ring crossing to its far side, with jammed walkers ringed in orange (`Crowd`, `preferredVelocity`, `isJammed`) |
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
