#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Effects</sup>

---

## Effects

Layered effects: draw into off-screen layers, filter them on the GPU, and composite them back with blend modes. Filters (`filtered(_:)` / `postProcess(_:)`), procedural sources (`generate(_:)`), previous-frame feedback (`withFeedback`), the declarative `compose { }` stack, and the two-input combine path (`combined(with:)` / `aside { }`). See the [Layered effects reference](../../Docs/Drawing/Effects.md).

| Example | What it shows |
|---|---|
| [Bloom](Bloom/Sketch.swift) | a glow earned by extracting the bright parts, blurring, and adding them back (`filtered(.bloom())`) |
| [BlurFilters](BlurFilters/Sketch.swift) | the blur family: Gaussian, edge-preserving bilateral, and directional motion/radial blur |
| [ColorFilters](ColorFilters/Sketch.swift) | the color & tone family as a contact sheet: grade, invert, posterize, duotone, gradient map, … |
| [StylizeFilters](StylizeFilters/Sketch.swift) | the stylize & optical family: edges, sharpen, emboss, halftone, dither, oil paint, crosshatch, … |
| [RetroFilters](RetroFilters/Sketch.swift) | the retro / optical family: scanlines, glitch, CRT |
| [Relight](Relight/Sketch.swift) | a layer read as a height map and lit as embossed physical matter: matte, metal, glass, sand, liquid (`.relight`) |
| [Glitter](Glitter/Sketch.swift) | iridescent and glittering shapes: the thin-film `.iridescence` sheen and the sparkle-fleck `.glitter` filter, per shape via `compose { }` |
| [SoapFilm](SoapFilm/Sketch.swift) | the measured spectral pair: `.thinFilm` interference draining through the real film color order, over `.diffraction` grating streaks |
| [Distortion](Distortion/Sketch.swift) | uv-warp filters that re-sample the image: kaleidoscope, swirl, bulge, wave, ripple, polar, … |
| [Patterns](Patterns/Sketch.swift) | procedural pattern `Generator`s (`generate(_:)`) and a composed mix |
| [Cellular](Cellular/Sketch.swift) | the Worley cellular generator's three styles (cells, borders, mosaic), the feature points wandering on phase-periodic orbits so the field loops seamlessly (`.cellular`) |
| [PatternFields](PatternFields/Sketch.swift) | the pattern fields: quasicrystal, moiré, gyroid slice, phyllotaxis, hex pulses |
| [Fractals](Fractals/Sketch.swift) | escape-time fractals: the Mandelbrot set and a morphing Julia set (`.mandelbrot` / `.julia`) |
| [OrbitTraps](OrbitTraps/Sketch.swift) | orbit traps: the same iteration colored by the orbit's closest pass to a point, cross, circle, or square, two of them sweeping (`.orbitTrap`) |
| [Feedback](Feedback/Sketch.swift) | a layer that remembers itself across frames: a spiralling feedback tunnel (`withFeedback`) |
| [Bokeh](Bokeh/Sketch.swift) | the shape of the opening a highlight came through: an iris with `blades`, and the barrel that lays a highlight down into a lemon toward the corners (`catsEye`) |
| [Compose](Compose/Sketch.swift) | the `compose { }` DSL: a blurred backdrop, a bloomed ring, a screened lattice |
| [Aside](Aside/Sketch.swift) | multi-input effects: a displacement map and a spotlight mask fed into layers (`aside { }`) |
| [Defocus](Defocus/Sketch.swift) | depth of field via the two-input combine: a layer defocused by a hand-drawn depth map (`combined(with:.defocus)`) |
| [Dispersion](Dispersion/Sketch.swift) | chromatic aberration as a family: the five ways to pull the channels apart, the spectral tap budget, and the layer-driven split (`.chromaticAberration(mode:)` / `.disperse`) |
| [DesignFilters](DesignFilters/Sketch.swift) | the design filters: liquid chrome, thermal heatmap, and gem smoke read a layer's alpha shape; fluted glass, water, and paper texture transform the picture |
| [DesignPatterns](DesignPatterns/Sketch.swift) | nine animated design-pattern generators, each one `generate` call: filaments, a smoke ring, revolving panes, a spiral, wavy stripes, … |
| [MeshGradient](MeshGradient/Sketch.swift) | the mesh-gradient generator: color blobs drifting on their own orbits over a domain-warped field |
| [DiffusionCurves](DiffusionCurves/Sketch.swift) | a few marks held as color sources and the color let out between them until it settles (`.diffuse`) |
| [DistanceField](DistanceField/Sketch.swift) | a layer asked how far the nearest edge is, and which way, at every pixel |
| [Droste](Droste/Sketch.swift) | a ring of lit windows falling into itself without end, the copies wound into one spiral, unwound to plain rings on mouse hold (`.droste(inner:twist:zoom:)`) |
| [DomainColoring](DomainColoring/Sketch.swift) | a complex function painted over the plane it acts on, its zeros and poles read off the color wheels |
| [SeamlessClone](SeamlessClone/Sketch.swift) | one layer dropped into another so the join disappears: the patch keeps its marks and takes the surroundings' color |
| [SummedArea](SummedArea/Sketch.swift) | one table that turns the average of any square into four lookups, so a 400-pixel blur costs what a 4-pixel one does, and each pixel can be cut against its own neighborhood instead of one number for the page (`.boxBlur`, `.adaptiveThreshold`) |

Run one with `swift run Example-Effects-<Name>`, e.g. `swift run Example-Effects-Bloom`.
