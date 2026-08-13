#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Text</sup>

---

## Text

Drawing text with `drawText` — bitmap (pixel-grid) and outline (`.ttf`/`.otf`) fonts.

| Example | What it shows |
|---|---|
| [HelloText](HelloText/Sketch.swift) | a breathing title, a multi-line caption, and the character set marqueeing along the bottom (`drawText`, `textSize`/`textAlign`/`textWidth`) |
| [PlaydateFont](PlaydateFont/Sketch.swift) | loading a Playdate `.fnt` pixel font bundled beside the sketch — an arcade attract screen (`BitmapFont(fntContentsOf:)`, `textFont`) |
| [OutlineText](OutlineText/Sketch.swift) | a real `.ttf`/`.otf` face drawn at display size, with the word's glyph outlines pulled out as `Shape`s and rippled — text as geometry (`OutlineFont`, `textToShapes`, fill + stroke) |
| [TextVolume](TextVolume/Sketch.swift) | a screen-filling wall of body text redrawn every frame through the SDF glyph atlas, a brightness wave rolling down the rows — the volume scale path (`textMode(.atlas)`) |
| [GlyphWave](GlyphWave/Sketch.swift) | each letter bobbing on a travelling wave, tilting into the motion, with its own hue — the per-glyph `drawText` closure (`drawText(_:at:) { g in … }`, `TextGlyph`) |
| [TextOnPath](TextOnPath/Sketch.swift) | a message riding an undulating curve, each glyph rotated to the tangent and scrolling along it (`drawText(_:along:offset:)`) |
| [TextBox](TextBox/Sketch.swift) | a paragraph wrapping inside a box whose width breathes, reflowing every frame (`drawText(_:in:)`, word wrap + box alignment) |
| [VariableFont](VariableFont/Sketch.swift) | a word morphing through a variable font's weight and width axes, with a static weight ramp beneath (`OutlineFont.variation`, `weight`) |
| [StrokeText](StrokeText/Sketch.swift) | single-line plotter type — Hershey pen paths stroked (not filled), a breathing title plus a wave-riding marquee (`StrokeFont`, `strokeCap`/`strokeJoin`) |
| [TextMetrics](TextMetrics/Sketch.swift) | the metrics of a word made visible — baseline, origin, ascent/descent bars, and bounding box — over a brightness ramp (`textWidth`/`textAscent`/`textDescent`/`textBounds`) |
| [GlyphContours](GlyphContours/Sketch.swift) | a word's outline flattened to points and drawn three ways: a smooth curve, a polyline, and dots, sample density breathing (`textToShapes`, `drawCurve`/`drawPolyline`/`drawPoints`) |
| [PointShimmer](PointShimmer/Sketch.swift) | type dissolved into a point field that wobbles like heat haze — each point pushed sideways by a sine of its height (`textToShapes` → points) |
| [JitterType](JitterType/Sketch.swift) | letters rattling like a bad photocopy — each glyph's vertices jittered by a pulsing random offset (`textToShapes`, `Shape.mapPoints`, `randomSeed`) |
| [Scripts](Scripts/Sketch.swift) | one specimen sheet in five scripts: Arabic right to left, Devanagari reordered, Thai with stacked marks, Japanese wrapped in a box with no spaces to break at, and an emoji drawn as the picture the font carries (`textDirection`, per-piece `drawText`, `fontsUsed(for:)`) |

Run one with `swift run Example-Text-<Name>`, e.g. `swift run Example-Text-HelloText`.
