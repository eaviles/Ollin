#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Simulation</sup>

---

## Simulation

Stateful GPU fields that evolve each frame and that you draw into to seed or force: the `SimField` half of the effects substrate. Distinct from [Physics](../Physics/) (rigid and soft bodies) and [Compute](../Compute/) (raw kernels over buffers and textures): these are the built-in `Sim` catalog. See the [Layered effects reference](../../Docs/Drawing/Effects.md).

| Example | What it shows |
|---|---|
| [Simulation](Simulation/Sketch.swift) | a Gray-Scott reaction-diffusion field evolving on the GPU (`simField(.reactionDiffusion(...))`) |
| [GameOfLife](GameOfLife/Sketch.swift) | Conway's Game of Life on the GPU, draw to seed cells (`simField(.gameOfLife)`) |
| [Fluid](Fluid/Sketch.swift) | a real-time incompressible fluid carrying colour, drag to swirl (`simField(.fluid(...))`) |

Run one with `swift run Example-Simulation-<Name>`, e.g. `swift run Example-Simulation-Fluid`.
