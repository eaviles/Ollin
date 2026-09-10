#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Rendering</sup>

---

## Rendering

| [![Accumulation](https://media.ollin.art/examples/Rendering/Accumulation/still-640.jpg?v=da9d2e69)](Accumulation/) | [![ColorOutput](https://media.ollin.art/examples/Rendering/ColorOutput/still-640.jpg?v=77208b6b)](ColorOutput/) | [![DepthOfField](https://media.ollin.art/examples/Rendering/DepthOfField/still-640.jpg?v=43c520e8)](DepthOfField/) | [![Grassland](https://media.ollin.art/examples/Rendering/Grassland/still-640.jpg?v=5b003151)](Grassland/) |
|---|---|---|---|
| [Accumulation](Accumulation/) | [ColorOutput](ColorOutput/) | [DepthOfField](DepthOfField/) | [Grassland](Grassland/) |
| [![InstancedMesh](https://media.ollin.art/examples/Rendering/InstancedMesh/still-640.jpg?v=45979eb3)](InstancedMesh/) | [![LineSpray](https://media.ollin.art/examples/Rendering/LineSpray/still-640.jpg?v=4033c15e)](LineSpray/) | [![MeshField](https://media.ollin.art/examples/Rendering/MeshField/still-640.jpg?v=56dc4b3c)](MeshField/) | [![RetainedBatch](https://media.ollin.art/examples/Rendering/RetainedBatch/still-640.jpg?v=e534f740)](RetainedBatch/) |
| [InstancedMesh](InstancedMesh/) | [LineSpray](LineSpray/) | [MeshField](MeshField/) | [RetainedBatch](RetainedBatch/) |
| [![ToneMapping](https://media.ollin.art/examples/Rendering/ToneMapping/still-640.jpg?v=96c4a92f)](ToneMapping/) | [![ViewBoxes](https://media.ollin.art/examples/Rendering/ViewBoxes/still-640.jpg?v=4cef24c5)](ViewBoxes/) |  |  |
| [ToneMapping](ToneMapping/) | [ViewBoxes](ViewBoxes/) |  |  |

These examples show how the frame composites. Every frame is built in a linear floating-point canvas, and a final pass tone-maps that canvas to the screen. Because the canvas is linear and floating-point, light can sum past white and blend modes add as light. Marks can also accumulate across frames instead of clearing, which is the "sandpainting" track. See the [Drawing](../../Docs/Drawing/Drawing.md), [HDR & tone mapping](../../Docs/Drawing/HDR.md), [Accumulation](../../Docs/Drawing/Accumulation.md), and [Retained batches](../../Docs/Drawing/Batches.md) references.

| Example | What it shows |
|---|---|
| [Accumulation](Accumulation/Sketch.swift) | a persistent canvas that builds up over frames: slow pens and a soft mouse spray add faint light to a surface that is never cleared (`noClear()`) |
| [ToneMapping](ToneMapping/Sketch.swift) | lamps that sum as HDR light in float and are tone-mapped onto the screen instead of clipping, with a flat `.normal` control for comparison (`toneMap(_:)`, `blendMode(.add)`) |
| [ColorOutput](ColorOutput/Sketch.swift) | colors outside sRGB and highlights brighter than white (`colorOutput`, `Color(displayP3:)`) |
| [DepthOfField](DepthOfField/Sketch.swift) | depth of field that comes from scattered light: each pass sends a million samples through a bokeh ball and deposits them as light (`drawParticles(style: .light)`) into a running mean (`Accumulator`), which converges instead of getting brighter, and the result is printed with `developed` (drag to change the focus distance) |
| [LineSpray](LineSpray/Sketch.swift) | a sphere of a hundred and fifty rings of light seen through a real lens: `LineSpray` scatters points along every line through a `Bokeh` ball into a running mean until bokeh appears, and the camera, the lens, and the print are parameters |
| [RetainedBatch](RetainedBatch/Sketch.swift) | 150k stars recorded once into a `Batch` and replayed at no cost, plus a rosette stamped at many placements (`makeBatch`/`drawBatch`; flip the parameter to see the per-frame cost) |
| [InstancedMesh](InstancedMesh/Sketch.swift) | 12,400 pillars that move with a wave, drawn from one mesh and one draw call (`drawMesh(_:instances:)`; flip the parameter to see the per-copy cost) |
| [MeshField](MeshField/Sketch.swift) | 240,000 solids across a foggy plain, culled on the GPU per copy (`MeshField`/`drawMeshField`; flip the parameter to see what culling saves) |
| [Grassland](Grassland/Sketch.swift) | 500,000 blades of grass built inside the draw call, which sway and receive shadows (`StrandField`/`drawStrands`; flip the parameter to see distance grading) |
| [ViewBoxes](ViewBoxes/Sketch.swift) | one piece under six seeds on one canvas: each `withViewBox` clips and remaps a cell, so the block inside is written as if it owned the window, with its own `background` and its own mouse |

Run one with `swift run Example-Rendering-<Name>`, for example `swift run Example-Rendering-ToneMapping`.
