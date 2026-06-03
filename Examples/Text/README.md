#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Text</sup>

---

## Text

Drawing text with `drawText` — bitmap (pixel-grid) and outline (`.ttf`/`.otf`) fonts.

| Example | What it shows |
|---|---|
| [HelloText](HelloText/Sketch.swift) | a breathing title, a multi-line caption, and the character set marqueeing along the bottom (`drawText`, `textSize`/`textAlign`/`textWidth`) |
| [PlaydateFont](PlaydateFont/Sketch.swift) | loading a Playdate `.fnt` pixel font bundled beside the sketch — an arcade attract screen (`BitmapFont(fntContentsOf:)`, `textFont`) |
| [OutlineText](OutlineText/Sketch.swift) | a real `.ttf`/`.otf` face drawn at display size, with the word's glyph outlines pulled out as `Shape`s and rippled — text as geometry (`OutlineFont`, `textToShapes`, fill + stroke) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-HelloText`.
