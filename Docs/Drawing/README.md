#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Drawing</sup>

---

## Drawing

- [`Drawing`](./Drawing.md) - `background`, `fill`/`stroke`, the shapes, and the transform stack
- [`Accumulation`](./Accumulation.md) - `noClear` to keep the canvas across frames so drawing piles up (long exposures, paint-on-canvas, light accumulation)
- [`HDR & tone-mapping`](./HDR.md) - `toneMap` to roll bright, out-of-range light off the screen instead of clipping it (the linear-float pipeline behind every frame; the glow/bloom and sandpainting looks)
- [`Wide gamut & HDR output`](./ColorOutput.md) - `colorOutput` to present through Display P3 and keep highlights brighter than white, `Color(displayP3:)` for colors outside sRGB, and HDR10 video export
- [`Retained batches`](./Batches.md) - `makeBatch`/`drawBatch` to record heavy static drawing once and replay it each frame from the GPU for (almost) nothing, the draw-time transform placing or stamping the whole recording
- [`Layered effects`](./Effects.md) - `renderTarget`/`withTarget` to draw into off-screen layers, `filtered`/`postProcess` to run GPU filters (blur, bloom, color grade, gradient map, edges, halftone, …) over them, composited back with blend modes; `combined` to combine two layers (mask, displace, mix, depth-of-field defocus); `generate` for procedural pattern sources, `feedback` for trails and tunnels, and `compose { }` (with `aside` helper layers) to declare a stack of layers as one block
- [`Text`](./Text.md) - `drawText` with bitmap, outline (`.ttf`/`.otf`), and stroke (single-line / plotter) fonts, plus `textToShapes` (text as geometry)
- [`Images`](./Images.md) - `loadImage`, `drawImage`, `tint`, and pixel access: load or author a raster image, draw it scaled or transformed, recolor it
- [`Glyph mosaic`](./GlyphMosaic.md) - `drawGlyphMosaic`, an image rebuilt as a grid of text glyphs, each cell's character chosen by its measured ink in the active font
- [`Halftone`](./Halftone.md) - `drawHalftone`, an image rebuilt as the classic print dot screen: area-exact dots on a rotated grid, real circles for the plotter path
- [`Pixel sorting`](./PixelSorting.md) - `Image.pixelSorted`, brightness-bounded runs of an image's own pixels reordered along rows or columns (the classic glitch melt)
- [`Color`](./Color.md) - the `Color` type, the OKLab family and mixing, `Ramp`s and `Palette`s (loaded from a file or extracted from an image), dithering an image down to a palette, and perceptual `Colormap`s
- [`Geometry`](./Geometry.md) - the `Vector2`, `Rectangle`, `Grid`, `Shape`/`Contour`, and `Path` value types (including the `Grid` layout helper, curved outlines, shape booleans, and offsetting)
- [`SVG import`](./SVG.md) - `loadSVG`/`drawSVG` to read vector artwork into `Shape`s and `Contour`s (paths with curves and arcs, the basic shapes, groups and transforms, fills and strokes), ready for booleans, offsets, hatching, and re-export
- [`Fourier epicycles`](./Epicycles.md) - `Epicycles` + `drawEpicycles`: rebuild any closed outline as a chain of spinning circles (the discrete Fourier transform as a drawing machine), with a term-count dial from soft phantom to exact trace
- [`Classic curves`](./Curves.md) - the closed-form curve canon as geometry builders: `phyllotaxis`, `lissajous`, `rose`, `superellipse`, `supershape`, `hypotrochoid`/`epitrochoid` (the spirograph gears), `guilloche` (the rose engine's twisted, cam-shaped rings), the damped-pendulum `Harmonograph`, and Chaikin `smoothed(iterations:)` corner cutting
- [`Shape morphing`](./Morphing.md) - `ShapeMorph`: tween one `Shape` into another with every in-between a real vector shape (contour pairing, corner-keeping correspondence, holes that grow in and out); `Shape` is `Tweenable`, so a `Timeline` sequences geometry
- [`Voronoi & Delaunay`](./Voronoi.md) - tessellate points into vector geometry: Voronoi cells (the "crystallization" look) and the dual Delaunay triangle mesh, with Lloyd relaxation
- [`Truchet tiling`](./Truchet.md) - one tile per grid cell spun to a random orientation, so identical parts line up into flowing loops (`.arcs`) or a maze (`.diagonals`)
- [`Hitomezashi stitching`](./Hitomezashi.md) - one bit per grid line phases its dashes, and the shifted lines weave into staircases, loops, and a two-tone cloth
- [`Tiling & layout`](./Tiling.md) - the other ways to divide a canvas: `HexGrid`/`TriangleGrid` (the hex and triangle tilings, with hex distance, neighbors, and exact picking), `subdivide` (recursive panels, binary or quadtree), `Maze` (three carving algorithms, walls as clean line-work, solution and longest paths), and `apollonianGasket` (the kissing-circles foam)
- [`Aperiodic tilings`](./AperiodicTilings.md) - the tilings that never repeat: `penroseTiling` (kites and darts, rhombs, with the matching-rule arcs), `wangTiling` (edge-matching squares as one connected quilt), `girihPattern` (Islamic star patterns over any polygons, plus the five girih tiles), and `spectreTiling` (the einstein, straight or strictly chiral curved)
- [`Strange attractors`](./Attractors.md) - chaotic systems as points: continuous 3D orbits (Lorenz, Rössler, Aizawa, …) integrated with Runge-Kutta and orbited through the camera, 2D iterated maps (Clifford, de Jong, Hénon, Gumowski-Mira, Ikeda, hopalong) accumulated into density fields, and `AttractorFlow`, a million GPU particles riding one field at once
- [`SDF combinators`](./Combinators.md) - compose signed-distance fields so shapes *merge* instead of stack: smooth union/subtract/intersect and morph, round/onion, and domain mirror/tile, via the `SDF` value type + `drawSDF` and a scoped `smoothUnion { }` block, in 2D and a raymarched 3D form (`SDF3D` + `drawSDF3D`)

For writing GPU code yourself (fragment shaders, the shader library, and compute kernels), see [Shaders](../Shaders/README.md).
