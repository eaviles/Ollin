#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Text</sup>

---

## Text

Drawing text with `drawText` — bitmap (pixel-grid) and outline (`.ttf`/`.otf`) fonts.

| Example | What it shows |
|---|---|
| [HelloText](HelloText/Sketch.swift) | a breathing title, a multi-line caption, and the character set marqueeing along the bottom (`drawText`, `textSize`/`textAlign`/`textWidth`) |
| [PlaydateFont](PlaydateFont/Sketch.swift) | loading a Playdate `.fnt` pixel font bundled beside the sketch — an arcade attract screen (`BitmapFont(fntContentsOf:)`, `textFont`) |
| [OutlineText](OutlineText/Sketch.swift) | a real `.ttf`/`.otf` face drawn at display size, with the word's glyph outlines pulled out as `Shape`s and rippled — text as geometry (`OutlineFont`, `textToShapes`, fill + stroke) |
| [GlyphWave](GlyphWave/Sketch.swift) | each letter bobbing on a travelling wave, tilting into the motion, with its own hue — the per-glyph `drawText` closure (`drawText(_:at:) { g in … }`, `TextGlyph`) |
| [TextOnPath](TextOnPath/Sketch.swift) | a message riding an undulating curve, each glyph rotated to the tangent and scrolling along it (`drawText(_:along:offset:)`) |
| [TextBox](TextBox/Sketch.swift) | a paragraph wrapping inside a box whose width breathes, reflowing every frame (`drawText(_:in:)`, word wrap + box alignment) |
| [VariableFont](VariableFont/Sketch.swift) | a word morphing through a variable font's weight and width axes, with a static weight ramp beneath (`OutlineFont.variation`, `weight`) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-HelloText`.
