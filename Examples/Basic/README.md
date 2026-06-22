#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Basic</sup>

---

## Basic

The smallest starting point: a first breathing circle, the shape of a sketch, and the `extend(...)` seam.

| Example | What it shows |
|---|---|
| [HelloCircle](HelloCircle/Sketch.swift) | the smallest program: a breathing circle |
| [Guides](Guides/Sketch.swift) | the `extend(...)` seam: an overlay that draws over the sketch |
| [Capture](Capture/Sketch.swift) | the frame-grab seam: an extension that saves the rendered frame to a PNG (press **S**) |
| [VectorExport](VectorExport/Sketch.swift) | SVG export: the shape catalog serialized to vector paths (`--export-svg`) |
| [Hatching](Hatching/Sketch.swift) | filled shapes shaded as pen line work for a plotter (`--export-svg --hatch`) |
| [Blending](Blending/Sketch.swift) | additive blending: faint disks accumulating as light (`blendMode(.add)`) |
| [Accumulation](Accumulation/Sketch.swift) | a persistent canvas that builds up over frames (`noClear()`) |
| [ToneMapping](ToneMapping/Sketch.swift) | HDR light summed in float, mapped to the screen (`toneMap(_:)`) |
| [DepthOfField](DepthOfField/Sketch.swift) | sandpainting depth of field: bokeh earned by scattering accumulated samples (drag to rack focus) |
| [Bloom](Bloom/Sketch.swift) | layered effects: a glow earned by extracting the bright parts, blurring, and adding them back (`filtered(.bloom())`) |
| [Filters](Filters/Sketch.swift) | a contact sheet of the filter catalog (color, tone, stylize, optical) |
| [Patterns](Patterns/Sketch.swift) | procedural pattern generators (`generate(_:)`) and a composed mix |
| [Feedback](Feedback/Sketch.swift) | a layer that remembers itself: a spiralling feedback tunnel (`withFeedback`) |
| [Compose](Compose/Sketch.swift) | the `compose { }` DSL: a blurred backdrop, a bloomed ring, a screened lattice |
| [Aside](Aside/Sketch.swift) | multi-input effects: a displacement map and a spotlight mask fed into compose layers (`aside { }`) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-HelloCircle`.
