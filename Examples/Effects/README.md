#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Effects</sup>

---

## Effects

Layered effects: draw into off-screen layers, filter them on the GPU, and composite them back with blend modes. Filters (`filtered(_:)` / `postProcess(_:)`), procedural sources (`generate(_:)`), previous-frame feedback (`withFeedback`), the declarative `compose { }` stack, and the two-input combine path (`combined(with:)` / `aside { }`). See the [Layered effects reference](../../Docs/Drawing/Effects.md).

| Example | What it shows |
|---|---|
| [Layers](Layers/Sketch.swift) | layered effects written both ways: the imperative `makeRenderTarget` + `filtered` + `drawImage` path and the `compose { }` DSL producing the same frame, flipped by a parameter |
| [FilterCatalog](FilterCatalog/Sketch.swift) | the whole `Filter` catalog on one switchable contact sheet: the blur, color & tone, stylize & optical, retro, distortion, and design families on a segmented parameter |
| [Antialias](Antialias/Sketch.swift) | the stair-steps in a shader-written layer smoothed from the image alone, split-screen against the raw layer (`.antialias`) |
| [Relight](Relight/Sketch.swift) | a layer read as a height map and lit as embossed physical matter: matte, metal, glass, sand, liquid (`.relight`) |
| [Glitter](Glitter/Sketch.swift) | iridescent and glittering shapes: the thin-film `.iridescence` sheen and the sparkle-fleck `.glitter` filter, per shape via `compose { }` |
| [SoapFilm](SoapFilm/Sketch.swift) | the measured spectral pair: `.thinFilm` interference draining through the real film color order, over `.diffraction` grating streaks |
| [GeneratorCatalog](GeneratorCatalog/Sketch.swift) | the procedural `Generator` catalog: the basic patterns, the animated design set, the closed-form fields, and chains where a generated layer flows on into filters and blends |
| [Cellular](Cellular/Sketch.swift) | the Worley cellular generator's three styles (cells, borders, mosaic), the feature points wandering on phase-periodic orbits so the field loops seamlessly (`.cellular`) |
| [EscapeTime](EscapeTime/Sketch.swift) | one escape-time iteration, six readings: the Mandelbrot set and a morphing Julia set colored by escape, and four orbit traps colored by the orbit's closest pass to a shape (`.mandelbrot` / `.julia` / `.orbitTrap`) |
| [Feedback](Feedback/Sketch.swift) | a layer that remembers itself across frames: a spiralling feedback tunnel (`withFeedback`) |
| [Fourier](Fourier/Sketch.swift) | a picture, what it is made of, and the way back: filtering by scale with a shape drawn over the spectrum (`.fourier`, `.spectrum`, `.inverseFourier`) |
| [Aside](Aside/Sketch.swift) | multi-input effects: a displacement map and a spotlight mask fed into layers (`aside { }`) |
| [FlowStreaks](FlowStreaks/Sketch.swift) | a grainy picture brushed along a direction field: a noise layer read as an angle, drifting blobs read along their contours, and their normal map read as vectors (`.streaked(along:)` / `combined(with:.lineIntegralConvolution)`) |
| [Defocus](Defocus/Sketch.swift) | depth of field via the two-input combine: a layer defocused by a hand-drawn depth map, the highlights shaped by an iris with `blades` and the `catsEye` barrel (`combined(with:.defocus)`) |
| [Dispersion](Dispersion/Sketch.swift) | chromatic aberration as a family: the five ways to pull the channels apart, the spectral tap budget, and the layer-driven split (`.chromaticAberration(mode:)` / `.disperse`) |
| [MeshGradient](MeshGradient/Sketch.swift) | the mesh-gradient generator: color blobs drifting on their own orbits over a domain-warped field |
| [DiffusionCurves](DiffusionCurves/Sketch.swift) | a few marks held as color sources and the color let out between them until it settles (`.diffuse`) |
| [DistanceField](DistanceField/Sketch.swift) | a layer asked how far the nearest edge is, and which way, at every pixel |
| [Light](Light/Sketch.swift) | a room, a lamp carried on the pointer, and the light that reaches every pixel of it: soft shadows, falloff, beams through a comb, and walls that give their color back (`combined(with:.light)`) |
| [Droste](Droste/Sketch.swift) | a ring of lit windows falling into itself without end, the copies wound into one spiral, unwound to plain rings on mouse hold (`.droste(inner:twist:zoom:)`) |
| [DomainColoring](DomainColoring/Sketch.swift) | a complex function painted over the plane it acts on, its zeros and poles read off the color wheels |
| [SeamlessClone](SeamlessClone/Sketch.swift) | one layer dropped into another so the join disappears: the patch keeps its marks and takes the surroundings' color |
| [PigmentMix](PigmentMix/Sketch.swift) | the same yellow wash over the same blue field, combined as light and as paint side by side: the linear dissolve meets in gray, the pigment mix meets in green and leaves the unpainted ground alone (`.mix` / `.paintMix`) |
| [SummedArea](SummedArea/Sketch.swift) | one table that turns the average of any square into four lookups, so a 400-pixel blur costs what a 4-pixel one does, and each pixel can be cut against its own neighborhood instead of one number for the page (`.boxBlur`, `.adaptiveThreshold`) |

Run one with `swift run Example-Effects-<Name>`, e.g. `swift run Example-Effects-Layers`.
