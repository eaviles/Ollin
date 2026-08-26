#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Simulation</sup>

---

## Simulation

Systems that evolve on the GPU each frame: the built-in `Sim` field catalog (stateful textures you draw into to seed or force; see the [Layered effects reference](../../Docs/Drawing/Effects.md)), the [artificial-life](../../Docs/Simulation/ArtificialLife.md) particle systems, and the [particle fluids & soft bodies](../../Docs/Simulation/Fluids.md). Distinct from [Physics](../Physics/) (CPU rigid and soft bodies) and [Compute](../Compute/) (raw kernels over buffers and textures).

| Example | What it shows |
|---|---|
| [GrayScott](GrayScott/Sketch.swift) | a Gray-Scott reaction-diffusion field evolving on the GPU (`simField(.reactionDiffusion(...))`) |
| [GameOfLife](GameOfLife/Sketch.swift) | Conway's Game of Life on the GPU, draw to seed cells (`simField(.gameOfLife)`) |
| [BriansBrain](BriansBrain/Sketch.swift) | Brian's Brain: fire on exactly two, rest for one step, gliders forever, drag to sprinkle soup (`simField(.briansBrain())`) |
| [CyclicAutomaton](CyclicAutomaton/Sketch.swift) | Griffeath's cyclic automaton: each color eats the one before it, noise self-organizing into turning spirals (`simField(.cyclic(...))`) |
| [Excitable](Excitable/Sketch.swift) | a Greenberg-Hastings excitable medium: sparks grow rings, a wiped front curls into spirals, dab to spark (`simField(.excitable(...))`) |
| [Hodgepodge](Hodgepodge/Sketch.swift) | the hodgepodge machine: infection chasing recovery into Belousov-Zhabotinsky spirals (`simField(.hodgepodge(...))`) |
| [Lenia](Lenia/Sketch.swift) | Lenia, the continuous Game of Life: a mass field convolved with a soft ring kernel, blobs that pulse, split, and swim, growth knobs live (`simField(.lenia(...))`) |
| [MultiScaleTuring](MultiScaleTuring/Sketch.swift) | McCabe's multi-scale Turing patterns: five scales competing per pixel, self-organizing from noise into diatom-like relief, foldable into a rosette (`simField(.multiScaleTuring(...))`) |
| [Sandpile](Sandpile/Sketch.swift) | the Abelian sandpile: a dropped mountain collapsing four grains at a time into the classic fractal pile, one color per grain count, hold to pour another (`simField(.sandpile(...))`) |
| [Fluid](Fluid/Sketch.swift) | a real-time incompressible fluid carrying colour, drag to swirl (`simField(.fluid(...))`) |
| [SelfWarp](SelfWarp/Sketch.swift) | the picture dragging its own history: orbiting orbs smeared into ribbons along their measured motion, drag to paint with a wake (`simField(.selfWarp(...))`) |
| [Ripples](Ripples/Sketch.swift) | a rain-swept water surface: the 2D wave equation shaded as liquid, click to drop (`simField(.ripples(...))`) |
| [Watercolor](Watercolor/Sketch.swift) | wet paint on rough paper: a scripted wash, wet-in-wet charge, backrun bloom, and glaze you can take over with the mouse (`watercolor(pigments:)`) |
| [ParticleLife](ParticleLife/Sketch.swift) | attraction/repulsion matrices growing membranes, chasers, and worms (`particleLife(...)`) |
| [PrimordialParticles](PrimordialParticles/Sketch.swift) | one turning rule growing dividing cells (`primordialParticles(...)`) |
| [Physarum](Physarum/Sketch.swift) | slime-mold agents growing branching trail networks (`physarum(...)`) |
| [ParticleFluid](ParticleFluid/Sketch.swift) | a box of water made of particles, dam break to splash to pool, drag to grab (`particleFluid(...)`) |
| [SoftBodies](SoftBodies/Sketch.swift) | shape-matched jelly blobs tumbling into a pile, drag to knead (`softBodies(...)`) |

Run one with `swift run Example-Simulation-<Name>`, e.g. `swift run Example-Simulation-ParticleFluid`.
