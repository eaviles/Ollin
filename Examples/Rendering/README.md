#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Rendering</sup>

---

## Rendering

How the frame composites. Every frame is built in a linear floating-point canvas a final pass tone-maps to the screen, so light can sum past white, blend modes add as light, and marks accumulate across frames instead of clearing: the "sandpainting" track. See the [Drawing](../../Docs/Drawing/Drawing.md), [HDR & tone-mapping](../../Docs/Drawing/HDR.md), [Accumulation](../../Docs/Drawing/Accumulation.md), and [Retained batches](../../Docs/Drawing/Batches.md) references.

| Example | What it shows |
|---|---|
| [Blending](Blending/Sketch.swift) | additive blending: faint disks summing as light (`blendMode(.add)`) |
| [Accumulation](Accumulation/Sketch.swift) | a persistent canvas that builds up over frames (`noClear()`) |
| [ToneMapping](ToneMapping/Sketch.swift) | HDR light summed in float, rolled onto the screen instead of clipping (`toneMap(_:)`) |
| [ColorOutput](ColorOutput/Sketch.swift) | colors outside sRGB and highlights brighter than white (`colorOutput`, `Color(displayP3:)`) |
| [DepthOfField](DepthOfField/Sketch.swift) | sandpainting depth of field: bokeh earned by scattering accumulated samples (drag to rack focus) |
| [RetainedBatch](RetainedBatch/Sketch.swift) | 150k stars recorded once into a `Batch` and replayed for free, plus a rosette stamped at many placements (`makeBatch`/`drawBatch`; flip the knob to feel the per-frame cost) |
| [InstancedMesh](InstancedMesh/Sketch.swift) | 12,000 wave-riding pillars from one mesh and one draw call (`drawMesh(_:instances:)`; flip the knob to feel the per-copy cost) |
| [MeshField](MeshField/Sketch.swift) | 240,000 solids across a foggy plain, GPU-culled per copy (`MeshField`/`drawMeshField`; flip the knob to feel what culling saves) |
| [Grassland](Grassland/Sketch.swift) | 500,000 blades of grass grown inside the draw call, swaying, shadow-receiving (`StrandField`/`drawStrands`; flip the knob to feel distance grading) |

Run one with `swift run Example-Rendering-<Name>`, e.g. `swift run Example-Rendering-Blending`.
