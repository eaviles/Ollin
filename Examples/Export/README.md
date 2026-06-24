#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Export</sup>

---

## Export

Getting a sketch out of the window: the rendered frame grabbed to a raster image, and the same draw calls serialized to vector paths for a pen plotter. See the [Export reference](../../Docs/Output/Export.md).

| Example | What it shows |
|---|---|
| [Capture](Capture/Sketch.swift) | the frame-grab seam: an extension that saves the rendered frame to a PNG (press **S**) |
| [VectorExport](VectorExport/Sketch.swift) | SVG export: the shape catalog serialized to vector paths (`--export-svg`) |
| [Hatching](Hatching/Sketch.swift) | filled shapes shaded as pen line work for a plotter (`--export-svg --hatch`) |

Run one with `swift run Example-Export-<Name>`, e.g. `swift run Example-Export-VectorExport`.
