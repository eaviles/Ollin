#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Shaders</sup>

---

## Shaders

Writing GPU code yourself. Fragment shaders run through the effect graph, compute kernels run over buffers and textures, and each has a helper library spliced in for free.

- [`Shaders`](./Shaders.md) - write your own fragment shader (`Shader` + a `shade(uv, info)` function) and run it through the effect graph as a generator, filter, or combine, with a built-in shader library and line-accurate compile errors
- [`Visuals`](./Visuals.md) - compose animated imagery by chaining (`Visual`): sources (oscillator, noise, voronoi, shape) through warps, color moves, blends, and modulations, the whole chain compiling into a single GPU pass with every number animatable for free
- [`Shader library`](./ShaderLibrary.md) - reference for the helper functions a fragment shader or compute kernel can call: color/OKLab, hashes, value/gradient/curl noise, the 2D signed-distance catalog (`smin`, `sdEllipse`, `sdHeart`, …), and the repeat/mirror/polar domain operators
- [`Compute & GPU particles`](./Compute.md) - GPU compute over buffers and textures: `Particles` (a million updated and drawn on the GPU each frame, the "sandpainting" engine) and `Simulation` (reaction-diffusion, cellular automata, and other ping-pong texture sims), over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core, with the shared shader library spliced into every kernel
