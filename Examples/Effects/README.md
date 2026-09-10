#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Effects</sup>

---

## Effects

| [![Antialias](https://media.ollin.art/examples/Effects/Antialias/still-640.jpg?v=4be8b3d2)](Antialias/) | [![Aside](https://media.ollin.art/examples/Effects/Aside/still-640.jpg?v=a4edb23d)](Aside/) | [![Brushwork](https://media.ollin.art/examples/Effects/Brushwork/still-640.jpg?v=2e9f6b8e)](Brushwork/) | [![Cellular](https://media.ollin.art/examples/Effects/Cellular/still-640.jpg?v=59068a76)](Cellular/) |
|---|---|---|---|
| [Antialias](Antialias/) | [Aside](Aside/) | [Brushwork](Brushwork/) | [Cellular](Cellular/) |
| [![Coherence](https://media.ollin.art/examples/Effects/Coherence/still-640.jpg?v=2366f0ea)](Coherence/) | [![Defocus](https://media.ollin.art/examples/Effects/Defocus/still-640.jpg?v=acf95e95)](Defocus/) | [![DiffusionCurves](https://media.ollin.art/examples/Effects/DiffusionCurves/still-640.jpg?v=6ff87d9b)](DiffusionCurves/) | [![Dispersion](https://media.ollin.art/examples/Effects/Dispersion/still-640.jpg?v=1d34627d)](Dispersion/) |
| [Coherence](Coherence/) | [Defocus](Defocus/) | [DiffusionCurves](DiffusionCurves/) | [Dispersion](Dispersion/) |
| [![DistanceField](https://media.ollin.art/examples/Effects/DistanceField/still-640.jpg?v=a22c39b5)](DistanceField/) | [![DomainColoring](https://media.ollin.art/examples/Effects/DomainColoring/still-640.jpg?v=80d87f59)](DomainColoring/) | [![Droste](https://media.ollin.art/examples/Effects/Droste/still-640.jpg?v=d6f9f746)](Droste/) | [![EscapeTime](https://media.ollin.art/examples/Effects/EscapeTime/still-640.jpg?v=2edc6aa2)](EscapeTime/) |
| [DistanceField](DistanceField/) | [DomainColoring](DomainColoring/) | [Droste](Droste/) | [EscapeTime](EscapeTime/) |
| [![Feedback](https://media.ollin.art/examples/Effects/Feedback/still-640.jpg?v=e5bbe686)](Feedback/) | [![FilterCatalog](https://media.ollin.art/examples/Effects/FilterCatalog/still-640.jpg?v=01b6ff25)](FilterCatalog/) | [![FlowStreaks](https://media.ollin.art/examples/Effects/FlowStreaks/still-640.jpg?v=15aec062)](FlowStreaks/) | [![Fourier](https://media.ollin.art/examples/Effects/Fourier/still-640.jpg?v=d88ccf65)](Fourier/) |
| [Feedback](Feedback/) | [FilterCatalog](FilterCatalog/) | [FlowStreaks](FlowStreaks/) | [Fourier](Fourier/) |
| [![GaborNoise](https://media.ollin.art/examples/Effects/GaborNoise/still-640.jpg?v=e55226c1)](GaborNoise/) | [![GeneratorCatalog](https://media.ollin.art/examples/Effects/GeneratorCatalog/still-640.jpg?v=99c84940)](GeneratorCatalog/) | [![Glitter](https://media.ollin.art/examples/Effects/Glitter/still-640.jpg?v=9b525929)](Glitter/) | [![Hatching](https://media.ollin.art/examples/Effects/Hatching/still-640.jpg?v=d795995b)](Hatching/) |
| [GaborNoise](GaborNoise/) | [GeneratorCatalog](GeneratorCatalog/) | [Glitter](Glitter/) | [Hatching](Hatching/) |
| [![InkDrawing](https://media.ollin.art/examples/Effects/InkDrawing/still-640.jpg?v=a00a9949)](InkDrawing/) | [![Layers](https://media.ollin.art/examples/Effects/Layers/still-640.jpg?v=c3655ef8)](Layers/) | [![Light](https://media.ollin.art/examples/Effects/Light/still-640.jpg?v=4438e953)](Light/) | [![MeshGradient](https://media.ollin.art/examples/Effects/MeshGradient/still-640.jpg?v=bcf169d9)](MeshGradient/) |
| [InkDrawing](InkDrawing/) | [Layers](Layers/) | [Light](Light/) | [MeshGradient](MeshGradient/) |
| [![NewtonBasins](https://media.ollin.art/examples/Effects/NewtonBasins/still-640.jpg?v=61035e7b)](NewtonBasins/) | [![PigmentMix](https://media.ollin.art/examples/Effects/PigmentMix/still-640.jpg?v=05a0eeeb)](PigmentMix/) | [![Relight](https://media.ollin.art/examples/Effects/Relight/still-640.jpg?v=d9d244ea)](Relight/) | [![SeamlessClone](https://media.ollin.art/examples/Effects/SeamlessClone/still-640.jpg?v=7a00749e)](SeamlessClone/) |
| [NewtonBasins](NewtonBasins/) | [PigmentMix](PigmentMix/) | [Relight](Relight/) | [SeamlessClone](SeamlessClone/) |
| [![SoapFilm](https://media.ollin.art/examples/Effects/SoapFilm/still-640.jpg?v=cc0d88e3)](SoapFilm/) | [![SummedArea](https://media.ollin.art/examples/Effects/SummedArea/still-640.jpg?v=56e55d42)](SummedArea/) |  |  |
| [SoapFilm](SoapFilm/) | [SummedArea](SummedArea/) |  |  |

These examples show layered effects. You draw into off-screen layers, filter them on the GPU, and composite them back with blend modes. They cover filters (`filtered(_:)` / `postProcess(_:)`), procedural sources (`generate(_:)`), previous-frame feedback (`withFeedback`), the declarative `compose { }` stack, and the two-input combine path (`combined(with:)` / `aside { }`). See the [Layered effects reference](../../Docs/Drawing/Effects.md).

| Example | What it shows |
|---|---|
| [Layers](Layers/Sketch.swift) | layered effects written both ways: the imperative `makeRenderTarget` + `filtered` + `drawImage` path and the `compose { }` DSL produce the same frame, and a parameter switches between them |
| [FilterCatalog](FilterCatalog/Sketch.swift) | the whole `Filter` catalog on one contact sheet over a bundled portrait: a segmented parameter switches between the blur, color & tone, stylize & optical, retro, distortion, and design families |
| [InkDrawing](InkDrawing/Sketch.swift) | a bundled photograph drawn as pen and ink: the flow-based difference of Gaussians, with the line scale, the cut and its softness, and the flow along each edge on parameters (`.xdog`) |
| [Brushwork](Brushwork/Sketch.swift) | a bundled photograph of a wall of marigolds painted as brushwork: the anisotropic Kuwahara filter, whose paint patches are drawn out along the picture's own flow, with the brush size, its stretch, and its sharpness on parameters (`.brushwork`) |
| [Coherence](Coherence/Sketch.swift) | a bundled portrait flattened into regions with crisp edges: the coherence-enhancing filter, which smooths along the picture's flow and sharpens across it with a shock, with the rounds, the flow, the reach, and the sign's smoothing on parameters (`.shock`) |
| [Hatching](Hatching/Sketch.swift) | an engraved landscape under a crossing sun: pen strokes laid along the picture's own flow, as many of them as the tone is dark, with the spacing, the stroke length, how many directions cross, and the two inks on parameters (`.hatching`) |
| [Antialias](Antialias/Sketch.swift) | the stair-steps in a shader-written layer, smoothed from the image alone and shown split-screen beside the raw layer (`.antialias`) |
| [Relight](Relight/Sketch.swift) | a layer read as a height map and lit as an embossed physical material: matte, metal, glass, sand, and liquid (`.relight`) |
| [Glitter](Glitter/Sketch.swift) | iridescent and glittering shapes: the thin-film `.iridescence` sheen and the sparkle-fleck `.glitter` filter, applied per shape with `compose { }` |
| [SoapFilm](SoapFilm/Sketch.swift) | the measured spectral pair: `.thinFilm` interference, whose colors follow the real order a draining soap film passes through, over the streaks of a `.diffraction` grating |
| [GeneratorCatalog](GeneratorCatalog/Sketch.swift) | the procedural `Generator` catalog: the basic patterns, the animated design set, the closed-form fields, and chains where a generated layer passes into filters and blends |
| [Cellular](Cellular/Sketch.swift) | the three styles of the Worley cellular generator (cells, borders, mosaic), with the feature points moving on phase-periodic orbits so the field loops without a seam (`.cellular`) |
| [GaborNoise](GaborNoise/Sketch.swift) | Gabor noise, a field whose spectrum is designed: one wavelength, one direction or every direction, a band as narrow as asked, the waves sliding on a loop; the CPU form of the same field reads the crests and dots them (`.gaborNoise`, `GaborNoise`) |
| [EscapeTime](EscapeTime/Sketch.swift) | one escape-time iteration read six ways: the Mandelbrot set and a morphing Julia set colored by escape time, and four orbit traps colored by how close the orbit passes to a shape (`.mandelbrot` / `.julia` / `.orbitTrap`) |
| [NewtonBasins](NewtonBasins/Sketch.swift) | Newton's basins: roots placed on the plane, the method run from every pixel, each pixel colored by the root it lands on and shaded by the steps it took; the roots ride slow orbits so the basins pour, `relaxation` scales the step, and a dark lake is where the method never lands |
| [Feedback](Feedback/Sketch.swift) | a layer that keeps its previous frame and draws over it: a spiralling feedback tunnel (`withFeedback`) |
| [Fourier](Fourier/Sketch.swift) | a bundled photograph, its spectrum, and the transform back: draw a shape over the spectrum to filter the picture by scale (`.fourier`, `.spectrum`, `.inverseFourier`) |
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
| [SeamlessClone](SeamlessClone/Sketch.swift) | a slab of pebbles pasted and cloned onto a photograph of Cozumel at dusk, so the join disappears: the patch keeps its own marks and takes on the color of its surroundings |
| [PigmentMix](PigmentMix/Sketch.swift) | the same yellow wash over the same blue field, combined as light on one side and as paint on the other: the linear dissolve mixes to gray, while the pigment mix gives green and leaves the unpainted ground alone (`.mix` / `.paintMix`) |
| [SummedArea](SummedArea/Sketch.swift) | one table that turns the average of any square into four lookups, so a 400-pixel blur costs the same as a 4-pixel one, and each pixel can be thresholded against its own neighborhood instead of one number for the whole page (`.boxBlur`, `.adaptiveThreshold`) |

Run one with `swift run Example-Effects-<Name>`, for example `swift run Example-Effects-Layers`.
