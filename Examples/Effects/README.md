#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Effects</sup>

---

## Effects

These examples show layered effects. You draw into off-screen layers, filter them on the GPU, and composite them back with blend modes. They cover filters (`filtered(_:)` / `postProcess(_:)`), procedural sources (`generate(_:)`), previous-frame feedback (`withFeedback`), the declarative `compose { }` stack, and the two-input combine path (`combined(with:)` / `aside { }`). See the [Layered effects reference](../../Docs/Drawing/Effects.md).

| Example | What it shows |
|---|---|
| [Layers](Layers/Sketch.swift) | layered effects written both ways: the imperative `makeRenderTarget` + `filtered` + `drawImage` path and the `compose { }` DSL produce the same frame, and a parameter switches between them |
| [FilterCatalog](FilterCatalog/Sketch.swift) | the whole `Filter` catalog on one contact sheet: a segmented parameter switches between the blur, color & tone, stylize & optical, retro, distortion, and design families |
| [Antialias](Antialias/Sketch.swift) | the stair-steps in a shader-written layer, smoothed from the image alone and shown split-screen beside the raw layer (`.antialias`) |
| [Relight](Relight/Sketch.swift) | a layer read as a height map and lit as an embossed physical material: matte, metal, glass, sand, and liquid (`.relight`) |
| [Glitter](Glitter/Sketch.swift) | iridescent and glittering shapes: the thin-film `.iridescence` sheen and the sparkle-fleck `.glitter` filter, applied per shape with `compose { }` |
| [SoapFilm](SoapFilm/Sketch.swift) | the measured spectral pair: `.thinFilm` interference, whose colors follow the real order a draining soap film passes through, over the streaks of a `.diffraction` grating |
| [GeneratorCatalog](GeneratorCatalog/Sketch.swift) | the procedural `Generator` catalog: the basic patterns, the animated design set, the closed-form fields, and chains where a generated layer passes into filters and blends |
| [Cellular](Cellular/Sketch.swift) | the three styles of the Worley cellular generator (cells, borders, mosaic), with the feature points moving on phase-periodic orbits so the field loops without a seam (`.cellular`) |
| [EscapeTime](EscapeTime/Sketch.swift) | one escape-time iteration read six ways: the Mandelbrot set and a morphing Julia set colored by escape time, and four orbit traps colored by how close the orbit passes to a shape (`.mandelbrot` / `.julia` / `.orbitTrap`) |
| [Feedback](Feedback/Sketch.swift) | a layer that keeps its previous frame and draws over it: a spiralling feedback tunnel (`withFeedback`) |
| [Fourier](Fourier/Sketch.swift) | a picture, its spectrum, and the transform back: draw a shape over the spectrum to filter the picture by scale (`.fourier`, `.spectrum`, `.inverseFourier`) |
| [Aside](Aside/Sketch.swift) | multi-input effects: a displacement map and a spotlight mask fed into layers (`aside { }`) |
| [FlowStreaks](FlowStreaks/Sketch.swift) | a grainy picture streaked along a direction field, three ways: a noise layer read as an angle, drifting blobs read along their contours, and their normal map read as vectors (`.streaked(along:)` / `combined(with:.lineIntegralConvolution)`) |
| [Defocus](Defocus/Sketch.swift) | depth of field through the two-input combine: a hand-drawn depth map defocuses a layer, and an iris with `blades` and the `catsEye` barrel shapes the highlights (`combined(with:.defocus)`) |
| [Dispersion](Dispersion/Sketch.swift) | the chromatic aberration family: the five ways to pull the color channels apart, the spectral tap budget, and a split driven by another layer (`.chromaticAberration(mode:)` / `.disperse`) |
| [MeshGradient](MeshGradient/Sketch.swift) | the mesh-gradient generator: color blobs drift on their own orbits over a domain-warped field |
| [DiffusionCurves](DiffusionCurves/Sketch.swift) | a few marks act as fixed color sources, and the color spreads out between them until it settles (`.diffuse`) |
| [DistanceField](DistanceField/Sketch.swift) | the distance field of a layer: at every pixel, how far the nearest edge is and in which direction |
| [Light](Light/Sketch.swift) | a room, a lamp that follows the pointer, and the light that reaches every pixel of the room: soft shadows, falloff, beams through a comb, and walls that spill their color back into the room (`combined(with:.light)`) |
| [Droste](Droste/Sketch.swift) | a ring of lit windows that repeats inside itself without end: the copies twist into one spiral, and holding the mouse unwinds them to plain rings (`.droste(inner:twist:zoom:)`) |
| [DomainColoring](DomainColoring/Sketch.swift) | a complex function colored over the plane it acts on, so you can read its zeros and poles off the color wheels |
| [SeamlessClone](SeamlessClone/Sketch.swift) | one layer pasted into another so the join disappears: the patch keeps its own marks and takes on the color of its surroundings |
| [PigmentMix](PigmentMix/Sketch.swift) | the same yellow wash over the same blue field, combined as light on one side and as paint on the other: the linear dissolve mixes to gray, while the pigment mix gives green and leaves the unpainted ground alone (`.mix` / `.paintMix`) |
| [SummedArea](SummedArea/Sketch.swift) | one table that turns the average of any square into four lookups, so a 400-pixel blur costs the same as a 4-pixel one, and each pixel can be thresholded against its own neighborhood instead of one number for the whole page (`.boxBlur`, `.adaptiveThreshold`) |

Run one with `swift run Example-Effects-<Name>`, for example `swift run Example-Effects-Layers`.
