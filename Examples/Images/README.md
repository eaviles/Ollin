#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Images</sup>

---

## Images

Loading, drawing, tinting, and authoring raster images (the `Image` value type, `drawImage`, `tint`, and the `Image[x, y]` pixel subscript), plus the image-as-input renderings that turn a picture into glyphs, streaks, halftone dots, a single line, a branching tree of veins, a wound thread, or a molten field.

| Example | What it shows |
|---|---|
| [GlyphMosaic](GlyphMosaic/Sketch.swift) | a drifting field of light rebuilt as a grid of geometric marks, each cell's character chosen by its measured ink in the bundled bitmap font (`drawGlyphMosaic`, `GlyphSet`, a custom character set) |
| [Halftone](Halftone/Sketch.swift) | a shaded still life as a print dot screen that swings through a quarter turn while the tone holds, the inverted reading on mouse hold, plotter-ready via `--export-svg` (`drawHalftone`, `pitch`, `angle`, `inverted`) |
| [LuminanceMelt](LuminanceMelt/Sketch.swift) | a painted dusk seascape liquified by a warped noise field and poured through a four-stop palette, the source on mouse hold (`.melt`, `renderTarget`, `filtered`) |
| [PixelField](PixelField/Sketch.swift) | a blank image painted pixel by pixel into a flowing colormap field, drawn under an animated warm↔cool `tint`, with a row of swatches read back with `get` (`Image(width:height:)`, `image[x, y]`, `tint`) |
| [PixelSort](PixelSort/Sketch.swift) | a painted dusk skyline melted into falling streaks, the sort window breathing over the loop and a second axis on mouse hold (`Image.pixelSorted`, threshold intervals, `reversed`) |
| [SingleLine](SingleLine/Sketch.swift) | a ringed planet drawn by one unbroken line that reveals and unwinds, stipple plus traveling-salesman tour, plotter-ready via `--export-svg` (`singleLine(of:points:)`, `cutoff`) |
| [SlitScan](SlitScan/Sketch.swift) | time smeared across space over a painted feed: the classic left-to-right scan, radial time on mouse hold, the live source inset (`SlitScan`, `push`, `image(delay:)`) |
| [SpanningTree](SpanningTree/Sketch.swift) | a leaf's stipples joined by the minimum spanning tree, so the dots come out as veins drawn chain by chain in plotting order, plotter-ready via `--export-svg` (`spanningTree(of:points:)`) |
| [StringArt](StringArt/Sketch.swift) | a crescent moon knitted from one continuous thread over 200 rim pins, each chord chosen greedily for the darkness it still covers, the winding accumulating live (`StringArt`, `step`, `thread`) |

Run one with `swift run Example-Images-<Name>`, e.g. `swift run Example-Images-PixelField`.
