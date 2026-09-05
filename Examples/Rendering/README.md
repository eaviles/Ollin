#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Rendering</sup>

---

## Rendering

These examples show how the frame composites. Every frame is built in a linear floating-point canvas, and a final pass tone-maps that canvas to the screen. Because the canvas is linear and floating-point, light can sum past white and blend modes add as light. Marks can also accumulate across frames instead of clearing, which is the "sandpainting" track. See the [Drawing](../../Docs/Drawing/Drawing.md), [HDR & tone-mapping](../../Docs/Drawing/HDR.md), [Accumulation](../../Docs/Drawing/Accumulation.md), and [Retained batches](../../Docs/Drawing/Batches.md) references.

| Example | What it shows |
|---|---|
| [Accumulation](Accumulation/Sketch.swift) | a persistent canvas that builds up over frames: slow pens and a soft mouse spray add faint light to a surface that is never cleared (`noClear()`) |
| [ToneMapping](ToneMapping/Sketch.swift) | lamps that sum as HDR light in float and are tone-mapped onto the screen instead of clipping, with a flat `.normal` control for comparison (`toneMap(_:)`, `blendMode(.add)`) |
| [ColorOutput](ColorOutput/Sketch.swift) | colors outside sRGB and highlights brighter than white (`colorOutput`, `Color(displayP3:)`) |
| [DepthOfField](DepthOfField/Sketch.swift) | depth of field that comes from scattered light: each pass sends a million samples through a bokeh ball and deposits them as light (`drawParticles(style: .light)`) into a running mean (`Accumulator`), which converges instead of getting brighter, and the result is printed with `developed` (drag to change the focus distance) |
| [LineSpray](LineSpray/Sketch.swift) | a sphere of a hundred and fifty rings of light seen through a real lens: `LineSpray` scatters points along every line through a `Bokeh` ball into a running mean until bokeh appears, and the camera, the lens, and the print are parameters |
| [RetainedBatch](RetainedBatch/Sketch.swift) | 150k stars recorded once into a `Batch` and replayed at no cost, plus a rosette stamped at many placements (`makeBatch`/`drawBatch`; flip the parameter to see the per-frame cost) |
| [InstancedMesh](InstancedMesh/Sketch.swift) | 12,000 pillars that move with a wave, drawn from one mesh and one draw call (`drawMesh(_:instances:)`; flip the parameter to see the per-copy cost) |
| [MeshField](MeshField/Sketch.swift) | 240,000 solids across a foggy plain, culled on the GPU per copy (`MeshField`/`drawMeshField`; flip the parameter to see what culling saves) |
| [Grassland](Grassland/Sketch.swift) | 500,000 blades of grass built inside the draw call, which sway and receive shadows (`StrandField`/`drawStrands`; flip the parameter to see distance grading) |
| [ViewBoxes](ViewBoxes/Sketch.swift) | one piece under six seeds on one canvas: each `withViewBox` clips and remaps a cell, so the block inside is written as if it owned the window, with its own `background` and its own mouse |

Run one with `swift run Example-Rendering-<Name>`, for example `swift run Example-Rendering-ToneMapping`.
