#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Export</sup>

---

## Export

Getting a sketch out of the window: the rendered frame grabbed to a raster image, and the same draw calls serialized to vector paths for a pen plotter. See the [Export reference](../../Docs/Output/Export.md).

| Example | What it shows |
|---|---|
| [Capture](Capture/Sketch.swift) | the frame-grab seam: an extension that saves the rendered frame to a PNG (press **S**) |
| [VectorExport](VectorExport/Sketch.swift) | SVG export: the shape catalog serialized to vector paths (`--export-svg`) |
| [Hatching](Hatching/Sketch.swift) | filled shapes shaded as pen line work for a plotter (`--export-svg --hatch`) |
| [Toolpath](Toolpath/Sketch.swift) | the machine's route before anything moves: line work planned by `GCode.toolpath(_:in:)` and drawn as its own plan, paths in plot order, pen-up travels between them, and a pen walking it at machine speed |
| [Record](Record/Sketch.swift) | a run kept as it is played: **R** starts and stops a real-time take, picture and sound together, stamped with the wall clock so a slow frame lasts longer instead of stretching time |

Run one with `swift run Example-Export-<Name>`, e.g. `swift run Example-Export-VectorExport`.
