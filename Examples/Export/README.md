#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Export</sup>

---

## Export

These examples get a sketch out of the window. They save the rendered frame as a raster image, and they serialize the draw calls behind that frame to vector paths for a pen plotter. See the [Export reference](../../Docs/Output/Export.md).

| Example | What it shows |
|---|---|
| [Capture](Capture/Sketch.swift) | the frame-grab seam: an extension that saves the rendered frame to a PNG when you press **S** |
| [VectorExport](VectorExport/Sketch.swift) | SVG export: the shape catalog serialized to vector paths (`--export-svg`) |
| [Hatching](Hatching/Sketch.swift) | filled shapes shaded as pen line work for a plotter (`--export-svg --hatch`) |
| [Toolpath](Toolpath/Sketch.swift) | the machine's route before anything moves: `GCode.toolpath(_:in:)` plans the line work, and the sketch draws that plan, with the paths in plot order, the pen-up travels between them, and a pen that moves along the route at machine speed |
| [Record](Record/Sketch.swift) | a run recorded as it plays: **R** starts and stops a real-time take of picture and sound together, and the take is stamped with the wall clock, so a slow frame lasts longer instead of stretching time |

Run one with `swift run Example-Export-<Name>`, for example `swift run Example-Export-VectorExport`.
