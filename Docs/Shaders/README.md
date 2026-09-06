#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Shaders</sup>

---

## Shaders

These pages cover writing GPU code yourself. A fragment shader runs through the effect graph, and a compute kernel runs over buffers and textures. Both get the helper library spliced in automatically.

- [`Shaders`](./Shaders.md) - write your own fragment shader as a `Shader` plus a `shade(uv, info)` function. It runs through the effect graph as a generator, a filter, or a combine. The built-in shader library is available to it, and a compile error reports the exact line.
- [`Visuals`](./Visuals.md) - compose animated imagery by chaining a `Visual`. A source (oscillator, noise, voronoi, shape) passes through warps, color moves, blends, and modulations. The whole chain compiles into a single GPU pass, and every number in it can animate at no extra cost.
- [`Shader library`](./ShaderLibrary.md) - reference for the helper functions a fragment shader or a compute kernel can call. It covers color and OKLab, hashes, and value noise, gradient noise, and curl noise. It also covers the 2D signed-distance catalog (`smin`, `sdEllipse`, `sdHeart`, …) and the repeat, mirror, and polar domain operators.
- [`Compute & GPU particles`](./Compute.md) - GPU compute over buffers and textures. `Particles` is the "sandpainting" engine. It updates and draws a million particles on the GPU each frame. `Simulation` runs reaction-diffusion, cellular automata, and other ping-pong texture sims. Both sit over the `ComputeKernel`, `ComputeBuffer`, and `ComputeTexture` core, and the shared shader library is spliced into every kernel.
