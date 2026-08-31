#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Text</sup>

---

## Text

Drawing text with `drawText` — bitmap (pixel-grid) and outline (`.ttf`/`.otf`) fonts.

| Example | What it shows |
|---|---|
| [HelloText](HelloText/Sketch.swift) | a breathing title, a multi-line caption, and the character set marqueeing along the bottom (`drawText`, `textSize`/`textAlign`/`textWidth`) |
| [PlaydateFont](PlaydateFont/Sketch.swift) | loading a Playdate `.fnt` pixel font bundled beside the sketch — an arcade attract screen (`BitmapFont(fntContentsOf:)`, `textFont`) |
| [TypeAsGeometry](TypeAsGeometry/Sketch.swift) | text as geometry: a real `.ttf`/`.otf` face drawn at display size, the word's glyph outlines pulled out as `Shape`s and reworked two ways, rippled by a flow field and rattled by a seeded per-frame jitter (`OutlineFont`, `textToShapes`, `Shape.mapPoints`, `randomSeed`) |
| [TextVolume](TextVolume/Sketch.swift) | a screen-filling wall of body text redrawn every frame through the SDF glyph atlas, a brightness wave rolling down the rows — the volume scale path (`textMode(.atlas)`) |
| [GlyphWave](GlyphWave/Sketch.swift) | each letter bobbing on a travelling wave, tilting into the motion, with its own hue — the per-glyph `drawText` closure (`drawText(_:at:) { g in … }`, `TextGlyph`) |
| [TextOnPath](TextOnPath/Sketch.swift) | a message riding an undulating curve, each glyph rotated to the tangent and scrolling along it (`drawText(_:along:offset:)`) |
| [TextBox](TextBox/Sketch.swift) | a paragraph wrapping inside a box whose width breathes, reflowing every frame across a line grid spaced by the font's leading (`drawText(_:in:)`, word wrap + box alignment, `textLeading`) |
| [VariableFont](VariableFont/Sketch.swift) | a word morphing through a variable font's weight and width axes, with a static weight ramp beneath (`OutlineFont.variation`, `weight`) |
| [StrokeText](StrokeText/Sketch.swift) | single-line plotter type — Hershey pen paths stroked (not filled), a breathing title plus a wave-riding marquee (`StrokeFont`, `strokeCap`/`strokeJoin`) |
| [TextMetrics](TextMetrics/Sketch.swift) | the metrics of a word made visible — baseline, origin, ascent/descent bars, and bounding box — over a brightness ramp (`textWidth`/`textAscent`/`textDescent`/`textBounds`) |
| [GlyphContours](GlyphContours/Sketch.swift) | a word's outline flattened to points and drawn three ways: a smooth curve, a polygon, and dots that shimmer like heat haze, each pushed sideways by a sine of its height, sample density breathing (`textToShapes`, `drawCurve`/`drawPolygon`/`drawPoints`) |
| [Scripts](Scripts/Sketch.swift) | one specimen sheet in five scripts: Arabic right to left, Devanagari reordered, Thai with stacked marks, Japanese wrapped in a box with no spaces to break at, and an emoji drawn as the picture the font carries, plus one character no installed face has, caught before it draws (`textDirection`, per-piece `drawText`, `fontsUsed(for:)`, `textMissingCharacters`) |
| [Columns](Columns/Sketch.swift) | the Pillow Book set down the page in columns that fill right to left, justified into its box, with the brackets and comma taking the sideways shapes the font keeps for them (`textDirection(.topToBottom)`, `textJustify`, box layout) |
| [HangingStops](HangingStops/Sketch.swift) | one passage in two identical boxes, with a rule down each measured edge: on the right the full stops that would not fit sit past it instead of taking their neighbour to the next line (`textHangingPunctuation`, box layout) |
| [MongolianColumns](MongolianColumns/Sketch.swift) | the other vertical writing: columns that fill left to right, their letters joined into one stroke, laid out by shaping the line across the page and turning it a quarter turn (`textDirection(.topToBottomLeftToRight)`, `textBounds`) |

Run one with `swift run Example-Text-<Name>`, e.g. `swift run Example-Text-HelloText`.
