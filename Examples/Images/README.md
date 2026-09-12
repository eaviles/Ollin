#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Images</sup>

---

## Images

| [![Autostereogram](https://media.ollin.art/examples/Images/Autostereogram/still-640.jpg?v=a02b4c97)](Autostereogram/) | [![Dropped](https://media.ollin.art/examples/Images/Dropped/still-640.jpg?v=bf8292af)](Dropped/) | [![Fit](https://media.ollin.art/examples/Images/Fit/still-640.jpg?v=0b369e71)](Fit/) | [![GlyphMosaic](https://media.ollin.art/examples/Images/GlyphMosaic/still-640.jpg?v=56f962ea)](GlyphMosaic/) |
|---|---|---|---|
| [Autostereogram](Autostereogram/) | [Dropped](Dropped/) | [Fit](Fit/) | [GlyphMosaic](GlyphMosaic/) |
| [![Halftone](https://media.ollin.art/examples/Images/Halftone/still-640.jpg?v=d453baa5)](Halftone/) | [![LuminanceMelt](https://media.ollin.art/examples/Images/LuminanceMelt/still-640.jpg?v=97bd1adb)](LuminanceMelt/) | [![PhotoMosaic](https://media.ollin.art/examples/Images/PhotoMosaic/still-640.jpg?v=ca5adb0b)](PhotoMosaic/) | [![PixelField](https://media.ollin.art/examples/Images/PixelField/still-640.jpg?v=700607e1)](PixelField/) |
| [Halftone](Halftone/) | [LuminanceMelt](LuminanceMelt/) | [PhotoMosaic](PhotoMosaic/) | [PixelField](PixelField/) |
| [![PixelSort](https://media.ollin.art/examples/Images/PixelSort/still-640.jpg?v=a03fd15a)](PixelSort/) | [![SeamCarve](https://media.ollin.art/examples/Images/SeamCarve/still-640.jpg?v=a5c915bf)](SeamCarve/) | [![SingleLine](https://media.ollin.art/examples/Images/SingleLine/still-640.jpg?v=47ebfb44)](SingleLine/) | [![SlitScan](https://media.ollin.art/examples/Images/SlitScan/still-640.jpg?v=0aa946a5)](SlitScan/) |
| [PixelSort](PixelSort/) | [SeamCarve](SeamCarve/) | [SingleLine](SingleLine/) | [SlitScan](SlitScan/) |
| [![SpanningTree](https://media.ollin.art/examples/Images/SpanningTree/still-640.jpg?v=7674d7bc)](SpanningTree/) | [![StringArt](https://media.ollin.art/examples/Images/StringArt/still-640.jpg?v=36d57253)](StringArt/) |  |  |
| [SpanningTree](SpanningTree/) | [StringArt](StringArt/) |  |  |

These examples load, draw, tint, and author raster images through the `Image` value type, `drawImage`, `tint`, and the `Image[x, y]` pixel subscript. They also cover the image-as-input renderings, which turn a picture into glyphs, streaks, halftone dots, a single line, a branching tree of veins, a wound thread, or a molten field.

| Example | What it shows |
|---|---|
| [Dropped](Dropped/Sketch.swift) | pictures dropped on the window from the Finder, each landing where it was dropped: `filesDropped()` and `droppedFiles()` hand over the paths, `loadImage` reads them, and a file that is not a picture is named instead |
| [Fit](Fit/Sketch.swift) | one photograph of a city, cropped to 3:2, drawn into three 2:3 boxes, one per `ImageFit`: `.stretch` narrows the round dome, `.contain` leaves part of the box showing, and `.cover` fills the box and crops the people at the left away (`drawImage(_:in:fit:)`, `Image.cropped(toAspect:)`) |
| [GlyphMosaic](GlyphMosaic/Sketch.swift) | a bundled portrait under a passing band of light, rebuilt as a grid of geometric marks, where each cell's character is chosen by how much ink that glyph has in the bundled bitmap font (`drawGlyphMosaic`, `GlyphSet`, a custom character set) |
| [Halftone](Halftone/Sketch.swift) | a bundled portrait drawn as a print dot screen that rotates a quarter turn while the tone stays the same, with the inverted reading on mouse hold, and plotter-ready through `--export-svg` (`drawHalftone`, `pitch`, `angle`, `inverted`) |
| [LuminanceMelt](LuminanceMelt/Sketch.swift) | a bundled portrait melted by a warped noise field and recolored through a four-stop palette, with the source image on mouse hold (`.melt`, `renderTarget`, `filtered`) |
| [PixelField](PixelField/Sketch.swift) | a blank image painted pixel by pixel into a flowing colormap field, then drawn under a `tint` that animates between warm and cool, with a row of swatches read back with `get` (`Image(width:height:)`, `image[x, y]`, `tint`) |
| [Autostereogram](Autostereogram/Sketch.swift) | a turning ring of blocks hidden in a field of noise, where the relief moves out as far as the eyes can still pair the repeated pattern, with the depth map on mouse hold (`Image.autostereogram`) |
| [PhotoMosaic](PhotoMosaic/Sketch.swift) | a bundled portrait rebuilt from a hundred small pieces cut from the twenty sample photographs, where each cell takes the picture nearest to it by average color, and the tint changes over the loop (`Image.mosaic`, `drawMosaic`, `averageColor`) |
| [PixelSort](PixelSort/Sketch.swift) | a photographed alley melted into falling streaks, where the sort window widens and narrows over the loop, with a second axis on mouse hold (`Image.pixelSorted`, threshold intervals, `reversed`) |
| [SeamCarve](SeamCarve/Sketch.swift) | a photographed alley made narrower in two ways, with the removed seams drawn over the source: carved, so the sky goes and the walls keep their width, and squeezed on mouse hold, so they lean (`Image.seamCarved`, `seamMap`, `seams`) |
| [SingleLine](SingleLine/Sketch.swift) | a bundled profile photograph drawn by one unbroken line that appears and then unwinds, built from stipple points joined by a traveling-salesman tour, and plotter-ready through `--export-svg` (`singleLine(of:points:)`, `cutoff`) |
| [SlitScan](SlitScan/Sketch.swift) | time spread across space over a painted feed: the classic left-to-right scan, radial time on mouse hold, and the live source shown as an inset (`SlitScan`, `push`, `image(delay:)`) |
| [SpanningTree](SpanningTree/Sketch.swift) | a bundled profile photograph's stipple points joined by the minimum spanning tree, so the dots become veins drawn chain by chain in plotting order, and plotter-ready through `--export-svg` (`spanningTree(of:points:)`) |
| [StringArt](StringArt/Sketch.swift) | a bundled profile photograph wound from one continuous thread over 200 rim pins, where each chord is chosen greedily for the darkness it still covers, and the winding builds up live (`StringArt`, `step`, `thread`) |

Run one with `swift run Example-Images-<Name>`, for example `swift run Example-Images-PixelField`.
