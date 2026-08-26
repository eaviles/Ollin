#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Compute</sup>

---

## Compute

Work handed to the GPU and kept there. A compute kernel updates a buffer of particles or a pair of textures every frame, and the data never travels back to the CPU to be looked at, which is what makes a million of anything affordable. See the [Compute reference](../../Docs/Shaders/Compute.md).

| Example | What it shows |
|---|---|
| [CurlField](CurlField/Sketch.swift) | a million particles flowing through a curl-noise field, updated by a kernel and drawn as faint additive discs, so where the streams cross they sum into light; the flow is divergence-free, so the particles braid without ever clumping into sinks (`curlNoise`) |
| [ReactionDiffusion](ReactionDiffusion/Sketch.swift) | two chemicals diffusing and reacting in every cell of a 512-square field, with the feed and kill rates varying across it so coral, fingerprints, and stripes coexist in one frame; drag to inject (the texture half of the compute path) |
| [NeighborSearch](NeighborSearch/Sketch.swift) | the particle-interaction loop with nothing hidden: hold your own `PingPong` buffer, hand `SpatialHash` the positions each frame, and write the kernel that walks each particle's neighbors (`neighborStep`) |

Run one with `swift run Example-Compute-<Name>`, e.g. `swift run Example-Compute-CurlField`.
