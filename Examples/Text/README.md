#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Text</sup>

---

## Text

These examples draw text with `drawText`, using bitmap (pixel-grid) fonts and outline (`.ttf`/`.otf`) fonts.

| [![GlyphContours](https://media.ollin.art/examples/Text/GlyphContours/still-640.jpg)](GlyphContours/) | [![GlyphWave](https://media.ollin.art/examples/Text/GlyphWave/still-640.jpg)](GlyphWave/) | [![HelloText](https://media.ollin.art/examples/Text/HelloText/still-640.jpg)](HelloText/) | [![PlaydateFont](https://media.ollin.art/examples/Text/PlaydateFont/still-640.jpg)](PlaydateFont/) |
|---|---|---|---|
| [GlyphContours](GlyphContours/) | [GlyphWave](GlyphWave/) | [HelloText](HelloText/) | [PlaydateFont](PlaydateFont/) |
| [![StrokeText](https://media.ollin.art/examples/Text/StrokeText/still-640.jpg)](StrokeText/) | [![TextBox](https://media.ollin.art/examples/Text/TextBox/still-640.jpg)](TextBox/) | [![TextMetrics](https://media.ollin.art/examples/Text/TextMetrics/still-640.jpg)](TextMetrics/) | [![TextOnPath](https://media.ollin.art/examples/Text/TextOnPath/still-640.jpg)](TextOnPath/) |
| [StrokeText](StrokeText/) | [TextBox](TextBox/) | [TextMetrics](TextMetrics/) | [TextOnPath](TextOnPath/) |
| [![TextVolume](https://media.ollin.art/examples/Text/TextVolume/still-640.jpg)](TextVolume/) | [![TypeAsGeometry](https://media.ollin.art/examples/Text/TypeAsGeometry/still-640.jpg)](TypeAsGeometry/) | [![VariableFont](https://media.ollin.art/examples/Text/VariableFont/still-640.jpg)](VariableFont/) |  |
| [TextVolume](TextVolume/) | [TypeAsGeometry](TypeAsGeometry/) | [VariableFont](VariableFont/) |  |

| Example | What it shows |
|---|---|
| [HelloText](HelloText/Sketch.swift) | a title that grows and shrinks, a multi-line caption, and the character set scrolling along the bottom (`drawText`, `textSize`/`textAlign`/`textWidth`) |
| [PlaydateFont](PlaydateFont/Sketch.swift) | an arcade attract screen drawn with a Playdate `.fnt` pixel font, loaded from a file bundled beside the sketch (`BitmapFont(fntContentsOf:)`, `textFont`) |
| [TypeAsGeometry](TypeAsGeometry/Sketch.swift) | text as geometry: a real `.ttf`/`.otf` face drawn at display size, then the word's glyph outlines taken out as `Shape`s and changed two ways, rippled by a flow field and shaken by a seeded per-frame jitter (`OutlineFont`, `textToShapes`, `Shape.mapPoints`, `randomSeed`) |
| [TextVolume](TextVolume/Sketch.swift) | a wall of body text that fills the screen, redrawn every frame through the SDF glyph atlas with a brightness wave moving down the rows: the path for text at volume (`textMode(.atlas)`) |
| [GlyphWave](GlyphWave/Sketch.swift) | each letter rising and falling on a travelling wave, tilting into the motion, with its own hue, drawn through the per-glyph `drawText` closure (`drawText(_:at:) { g in … }`, `TextGlyph`) |
| [TextOnPath](TextOnPath/Sketch.swift) | a message laid along a wavy curve, each glyph rotated to the tangent and scrolling along it (`drawText(_:along:offset:)`) |
| [TextBox](TextBox/Sketch.swift) | a paragraph wrapping inside a box whose width grows and shrinks, so the text reflows every frame across a line grid spaced by the font's leading (`drawText(_:in:)`, word wrap + box alignment, `textLeading`) |
| [VariableFont](VariableFont/Sketch.swift) | a word changing shape through a variable font's weight and width axes, with a static weight ramp beneath it (`OutlineFont.variation`, `weight`) |
| [StrokeText](StrokeText/Sketch.swift) | single-line plotter type: Hershey pen paths stroked rather than filled, as a title that grows and shrinks plus a marquee moving on a wave (`StrokeFont`, `strokeCap`/`strokeJoin`) |
| [TextMetrics](TextMetrics/Sketch.swift) | the metrics of a word drawn as marks (baseline, origin, ascent/descent bars, and bounding box) over a brightness ramp (`textWidth`/`textAscent`/`textDescent`/`textBounds`) |
| [GlyphContours](GlyphContours/Sketch.swift) | a word's outline flattened to points and drawn three ways: a smooth curve, a polygon, and dots that shimmer like heat haze, each pushed sideways by a sine of its height, while the sample density rises and falls (`textToShapes`, `drawCurve`/`drawPolygon`/`drawPoints`) |
| [Scripts](Scripts/Sketch.swift) | one specimen sheet in five scripts: Arabic right to left, Devanagari reordered, Thai with stacked marks, Japanese wrapped in a box with no spaces to break at, and an emoji drawn as the picture the font carries, plus one character that no installed face has, found before it draws (`textDirection`, per-piece `drawText`, `fontsUsed(for:)`, `textMissingCharacters`) |
| [Columns](Columns/Sketch.swift) | the Pillow Book set down the page in columns that fill right to left, justified into its box, with the brackets and the comma using the sideways forms the font keeps for them (`textDirection(.topToBottom)`, `textJustify`, box layout) |
| [HangingStops](HangingStops/Sketch.swift) | one passage in two identical boxes, each with a rule down its measured edge: in the right box, a full stop that would not fit sits past the rule instead of taking the character before it to the next line (`textHangingPunctuation`, box layout) |
| [MongolianColumns](MongolianColumns/Sketch.swift) | the other vertical script: columns that fill left to right, with the letters joined into one stroke, laid out by shaping the line across the page and then turning it a quarter turn (`textDirection(.topToBottomLeftToRight)`, `textBounds`) |

Run one with `swift run Example-Text-<Name>`, for example `swift run Example-Text-HelloText`.
