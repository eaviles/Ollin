#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Shaders</sup>

---

## Shaders

Writing GPU code yourself. Fragment shaders run through the effect graph, compute kernels run over buffers and textures, and each has a helper library spliced in for free.

- [`Shaders`](./Shaders.md) - write your own fragment shader (`Shader` + a `shade(uv, info)` function) and run it through the effect graph as a generator, filter, or combine, with a built-in shader library and line-accurate compile errors
- [`Shader library`](./ShaderLibrary.md) - reference for the helper functions a fragment shader can call: color/OKLab, hashes, value/gradient noise, the 2D signed-distance catalog (`smin`, `sdEllipse`, `sdHeart`, …), and the repeat/mirror/polar domain operators
- [`Compute & GPU particles`](./Compute.md) - GPU compute over buffers and textures: `Particles` (a million updated and drawn on the GPU each frame, the "sandpainting" engine) and `Simulation` (reaction-diffusion, cellular automata, and other ping-pong texture sims), over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core, with its own compute prelude
