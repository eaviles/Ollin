#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Export</sup>

---

## Export

These examples get a sketch out of the window, four ways. They save the rendered frame as a raster image. They serialize the draw calls behind that frame to vector paths for a pen plotter, with hatching where a fill has to become line work. They plan those paths as a G-code toolpath for a machine, and draw the plan so you can see the route first. They also record a run as it plays, picture and sound together. See the [Export reference](../../Docs/Output/Export.md).

| [![Capture](https://media.ollin.art/examples/Export/Capture/still-640.jpg)](Capture/) | [![Cutout](https://media.ollin.art/examples/Export/Cutout/still-640.jpg)](Cutout/) | [![Hatching](https://media.ollin.art/examples/Export/Hatching/still-640.jpg)](Hatching/) | [![LineDrawing](https://media.ollin.art/examples/Export/LineDrawing/still-640.jpg)](LineDrawing/) |
|---|---|---|---|
| [Capture](Capture/) | [Cutout](Cutout/) | [Hatching](Hatching/) | [LineDrawing](LineDrawing/) |
| [![Record](https://media.ollin.art/examples/Export/Record/still-640.jpg)](Record/) |  |  |  |
| [Record](Record/) |  |  |  |

| Example | What it shows |
|---|---|
| [Capture](Capture/Sketch.swift) | the frame-grab seam: an extension that saves the rendered frame to a PNG when you press **S** |
| [VectorExport](VectorExport/Sketch.swift) | SVG export: the shape catalog serialized to vector paths (`--export-svg`) |
| [Hatching](Hatching/Sketch.swift) | filled shapes shaded as pen line work for a plotter (`--export-svg --hatch`) |
| [Toolpath](Toolpath/Sketch.swift) | the machine's route before anything moves: `GCode.toolpath(_:in:)` plans the line work, and the sketch draws that plan, with the paths in plot order, the pen-up travels between them, and a pen that moves along the route at machine speed |
| [Embroidery](Embroidery/Sketch.swift) | the stitches before the machine sews them: a leaf composed as contours, planned with `Embroidery.stitches(_:in:)`, and drawn as its plan, with a dot at every penetration, the thread between them, the jumps, and a needle walking the plan at machine speed (`--export-embroidery`) |
| [Drafting](Drafting/Sketch.swift) | the layers a shop program will open: a box panel drawn in three colors, cut, score, and engrave, each planned with `DXF.drafting(_:in:)` and listed beside the drawing with its entity count (`--export-dxf`) |
| [LineDrawing](LineDrawing/Sketch.swift) | a 3D scene as line work a machine can follow: `lineDrawing(of:)` takes the meshes and the camera and gives back paths with what the surfaces hide taken out, with the crease angle, the test spacing, and the hidden stretches on parameters (`--export-svg`, `--export-gcode`) |
| [Cutout](Cutout/Sketch.swift) | a piece that leaves its background behind: `background(.clear)` makes the canvas see-through, and the PNG, the sequence, and a `proRes4444` or `hevcWithAlpha` clip keep the alpha, so it lands over another layer instead of over black |
| [Record](Record/Sketch.swift) | a run recorded as it plays: **R** starts and stops a real-time take of picture and sound together, and the take is stamped with the wall clock, so a slow frame lasts longer instead of stretching time |

Run one with `swift run Example-Export-<Name>`, for example `swift run Example-Export-VectorExport`.
