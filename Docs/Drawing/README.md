#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Drawing</sup>

---

## Drawing

- [`Drawing`](./Drawing.md) - `background`, `fill`/`stroke`, the shapes, and the transform stack
- [`Accumulation`](./Accumulation.md) - `noClear` to keep the canvas across frames so drawing piles up (long exposures, paint-on-canvas, light accumulation)
- [`HDR & tone-mapping`](./HDR.md) - `toneMap` to roll bright, out-of-range light off the screen instead of clipping it (the linear-float pipeline behind every frame; the glow/bloom and sandpainting looks)
- [`Layered effects`](./Effects.md) - `renderTarget`/`withTarget` to draw into off-screen layers, `filtered`/`postProcess` to run GPU filters (blur, bloom, color grade, gradient map, edges, halftone, …) over them, composited back with blend modes; `combined` to combine two layers (mask, displace, mix, depth-of-field defocus); `generate` for procedural pattern sources, `feedback` for trails and tunnels, and `compose { }` (with `aside` helper layers) to declare a stack of layers as one block
- [`Compute & GPU particles`](./Compute.md) - GPU compute over buffers and textures: `Particles` (a million updated and drawn on the GPU each frame — the "sandpainting" engine) and `Simulation` (reaction-diffusion, cellular automata, and other ping-pong texture sims), over the `ComputeKernel`/`ComputeBuffer`/`ComputeTexture` core
- [`Text`](./Text.md) - `drawText` with bitmap, outline (`.ttf`/`.otf`), and stroke (single-line / plotter) fonts, plus `textToShapes` (text as geometry)
- [`Images`](./Images.md) - `loadImage`, `drawImage`, `tint`, and pixel access: load or author a raster image, draw it scaled or transformed, recolor it
- [`Color`](./Color.md) - the `Color` type, the OKLab family and mixing, `Ramp`s and `Palette`s, and perceptual `Colormap`s
- [`Geometry`](./Geometry.md) - the `Vector2`, `Rectangle`, `Shape`/`Contour`, and `Path` value types (including curved outlines, shape booleans, and offsetting)
- [`Voronoi & Delaunay`](./Voronoi.md) - tessellate points into vector geometry: Voronoi cells (the "crystallization" look) and the dual Delaunay triangle mesh, with Lloyd relaxation
- [`SDF combinators`](./Combinators.md) - compose signed-distance fields so shapes *merge* instead of stack: smooth union/subtract/intersect and morph, round/onion, and domain mirror/tile, via the `SDF` value type + `drawSDF` and a scoped `smoothUnion { }` block, in 2D and a raymarched 3D form (`SDF3D` + `drawSDF3D`)
- [`Shaders`](./Shaders.md) - write your own fragment shader (`Shader` + a `shade(uv, info)` function) and run it through the effect graph as a generator, filter, or combine, with a built-in shader library (palettes, noise, hashes, `smin`, domain operators) and line-accurate compile errors
