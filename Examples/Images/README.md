#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Images</sup>

---

## Images

Loading, drawing, tinting, and authoring raster images (the `Image` value type, `drawImage`, `tint`, and the `Image[x, y]` pixel subscript), plus the image-as-input renderings that turn a picture into glyphs, streaks, or a single line.

| Example | What it shows |
|---|---|
| [GlyphMosaic](GlyphMosaic/Sketch.swift) | a drifting field of light rebuilt as a grid of geometric marks, each cell's character chosen by its measured ink in the bundled bitmap font (`drawGlyphMosaic`, `GlyphSet`, a custom character set) |
| [PixelField](PixelField/Sketch.swift) | a blank image painted pixel by pixel into a flowing colormap field, drawn under an animated warm↔cool `tint`, with a row of swatches read back with `get` (`Image(width:height:)`, `image[x, y]`, `tint`) |
| [PixelSort](PixelSort/Sketch.swift) | a painted dusk skyline melted into falling streaks, the sort window breathing over the loop and a second axis on mouse hold (`Image.pixelSorted`, threshold intervals, `reversed`) |
| [SingleLine](SingleLine/Sketch.swift) | a ringed planet drawn by one unbroken line that reveals and unwinds, stipple plus traveling-salesman tour, plotter-ready via `--export-svg` (`singleLine(of:points:)`, `cutoff`) |
| [SlitScan](SlitScan/Sketch.swift) | time smeared across space over a painted feed: the classic left-to-right scan, radial time on mouse hold, the live source inset (`SlitScan`, `push`, `image(delay:)`) |

Run one with `swift run Example-Images-<Name>`, e.g. `swift run Example-Images-PixelField`.
