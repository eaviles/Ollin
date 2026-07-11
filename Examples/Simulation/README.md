#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Simulation</sup>

---

## Simulation

Systems that evolve on the GPU each frame: the built-in `Sim` field catalog (stateful textures you draw into to seed or force; see the [Layered effects reference](../../Docs/Drawing/Effects.md)), the [artificial-life](../../Docs/Simulation/ArtificialLife.md) particle systems, and the [particle fluids & soft bodies](../../Docs/Simulation/Fluids.md). Distinct from [Physics](../Physics/) (CPU rigid and soft bodies) and [Compute](../Compute/) (raw kernels over buffers and textures).

| Example | What it shows |
|---|---|
| [GrayScott](GrayScott/Sketch.swift) | a Gray-Scott reaction-diffusion field evolving on the GPU (`simField(.reactionDiffusion(...))`) |
| [GameOfLife](GameOfLife/Sketch.swift) | Conway's Game of Life on the GPU, draw to seed cells (`simField(.gameOfLife)`) |
| [Fluid](Fluid/Sketch.swift) | a real-time incompressible fluid carrying colour, drag to swirl (`simField(.fluid(...))`) |
| [ParticleLife](ParticleLife/Sketch.swift) | attraction/repulsion matrices growing membranes, chasers, and worms (`particleLife(...)`) |
| [PrimordialParticles](PrimordialParticles/Sketch.swift) | one turning rule growing dividing cells (`primordialParticles(...)`) |
| [Physarum](Physarum/Sketch.swift) | slime-mold agents growing branching trail networks (`physarum(...)`) |
| [ParticleFluid](ParticleFluid/Sketch.swift) | a box of water made of particles, dam break to splash to pool, drag to grab (`particleFluid(...)`) |
| [SoftBodies](SoftBodies/Sketch.swift) | shape-matched jelly blobs tumbling into a pile, drag to knead (`softBodies(...)`) |

Run one with `swift run Example-Simulation-<Name>`, e.g. `swift run Example-Simulation-ParticleFluid`.
