#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Rendering</sup>

---

## Rendering

How the frame composites. Every frame is built in a linear floating-point canvas a final pass tone-maps to the screen, so light can sum past white, blend modes add as light, and marks accumulate across frames instead of clearing: the "sandpainting" track. See the [Drawing](../../Docs/Drawing/Drawing.md), [HDR & tone-mapping](../../Docs/Drawing/HDR.md), [Accumulation](../../Docs/Drawing/Accumulation.md), and [Retained batches](../../Docs/Drawing/Batches.md) references.

| Example | What it shows |
|---|---|
| [Accumulation](Accumulation/Sketch.swift) | a persistent canvas that builds up over frames: slow pens and a soft mouse spray piling faint light on an uncleared surface (`noClear()`) |
| [ToneMapping](ToneMapping/Sketch.swift) | lamps summing as HDR light in float, rolled onto the screen instead of clipping, with a flat `.normal` control for comparison (`toneMap(_:)`, `blendMode(.add)`) |
| [ColorOutput](ColorOutput/Sketch.swift) | colors outside sRGB and highlights brighter than white (`colorOutput`, `Color(displayP3:)`) |
| [DepthOfField](DepthOfField/Sketch.swift) | depth of field that emerges from scattered light: a million samples a pass through a bokeh ball, deposited as light (`drawParticles(style: .light)`) into a running mean (`Accumulator`) that converges instead of brightening, printed with `developed` (drag to rack focus) |
| [LineSpray](LineSpray/Sketch.swift) | a sphere of a hundred and fifty rings of light seen through a real lens: `LineSpray` scattering points along every line through a `Bokeh` ball into a running mean until bokeh emerges, with the camera, the lens, and the print as parameters |
| [RetainedBatch](RetainedBatch/Sketch.swift) | 150k stars recorded once into a `Batch` and replayed for free, plus a rosette stamped at many placements (`makeBatch`/`drawBatch`; flip the parameter to feel the per-frame cost) |
| [InstancedMesh](InstancedMesh/Sketch.swift) | 12,000 wave-riding pillars from one mesh and one draw call (`drawMesh(_:instances:)`; flip the parameter to feel the per-copy cost) |
| [MeshField](MeshField/Sketch.swift) | 240,000 solids across a foggy plain, GPU-culled per copy (`MeshField`/`drawMeshField`; flip the parameter to feel what culling saves) |
| [Grassland](Grassland/Sketch.swift) | 500,000 blades of grass grown inside the draw call, swaying, shadow-receiving (`StrandField`/`drawStrands`; flip the parameter to feel distance grading) |
| [ViewBoxes](ViewBoxes/Sketch.swift) | one piece under six seeds on one canvas: each `withViewBox` clips and remaps a cell so the block inside is written as though it owned the window, with its own `background` and its own mouse |

Run one with `swift run Example-Rendering-<Name>`, e.g. `swift run Example-Rendering-ToneMapping`.
