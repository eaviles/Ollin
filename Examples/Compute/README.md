#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Compute</sup>

---

## Compute

These examples hand work to the GPU and keep it there. A compute kernel updates a buffer of particles or a pair of textures every frame. The data never travels back to the CPU to be read, which is what makes a million of anything cheap to run every frame. See the [Compute reference](../../Docs/Shaders/Compute.md).

| [![CurlField](https://media.ollin.art/examples/Compute/CurlField/still-640.jpg?v=074c89a0)](CurlField/) | [![NeighborSearch](https://media.ollin.art/examples/Compute/NeighborSearch/still-640.jpg?v=437d677f)](NeighborSearch/) | [![ReactionDiffusion](https://media.ollin.art/examples/Compute/ReactionDiffusion/still-640.jpg?v=5685b4e6)](ReactionDiffusion/) |  |
|---|---|---|---|
| [CurlField](CurlField/) | [NeighborSearch](NeighborSearch/) | [ReactionDiffusion](ReactionDiffusion/) |  |

| Example | What it shows |
|---|---|
| [CurlField](CurlField/Sketch.swift) | a million particles flowing through a curl-noise field (`curlNoise`). A kernel updates them, and they draw as faint additive discs, so where the streams cross the discs add together and the crossing brightens. The flow is divergence-free, so the particles weave past each other without ever clumping into sinks |
| [ReactionDiffusion](ReactionDiffusion/Sketch.swift) | two chemicals diffusing and reacting in every cell of a 512-square field. The feed and kill rates vary across the field, so coral, fingerprints, and stripes coexist in one frame. Drag to inject. This is the texture half of the compute path |
| [NeighborSearch](NeighborSearch/Sketch.swift) | the particle-interaction loop with nothing hidden. You hold your own `PingPong` buffer, hand `SpatialHash` the positions each frame, and write the kernel that walks each particle's neighbors (`neighborStep`) |

Run one with `swift run Example-Compute-<Name>`, e.g. `swift run Example-Compute-CurlField`.
