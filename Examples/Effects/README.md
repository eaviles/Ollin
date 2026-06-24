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
| [Distortion](Distortion/Sketch.swift) | uv-warp filters that re-sample the image: kaleidoscope, swirl, bulge, wave, ripple, polar, … |
| [Patterns](Patterns/Sketch.swift) | procedural pattern `Generator`s (`generate(_:)`) and a composed mix |
| [Feedback](Feedback/Sketch.swift) | a layer that remembers itself across frames: a spiralling feedback tunnel (`withFeedback`) |
| [Compose](Compose/Sketch.swift) | the `compose { }` DSL: a blurred backdrop, a bloomed ring, a screened lattice |
| [Aside](Aside/Sketch.swift) | multi-input effects: a displacement map and a spotlight mask fed into layers (`aside { }`) |
| [Defocus](Defocus/Sketch.swift) | depth of field via the two-input combine: a layer defocused by a hand-drawn depth map (`combined(with:.defocus)`) |

Run one with `swift run Example-Effects-<Name>`, e.g. `swift run Example-Effects-Bloom`.
