#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Text`</sup>

---

## Text

Ollin draws text with a **bitmap font**: a glyph is a small grid of pixels, and each lit pixel is stamped as one square on the same instanced-SDF path the shapes use. So text needs no rasterizer and no separate pipeline — it rides the transform stack, composites in draw order with everything else, and stays crisp at any size.

A font is ready out of the box — `BitmapFont.builtin` is **[Cozette](https://github.com/the-moonwitch/Cozette)** by Ines (MIT), a 13px pixel font bundled with Ollin — so `drawText` works with zero setup. It covers a wide range: Latin (including the Spanish accents `á é í ó ú`, `ñ`, `ü`, `¿`, `¡`), Cyrillic, Greek, and Japanese kana. Call these bare inside `draw()`; they forward to the `Drawer`. Text takes the current [`fill`](./Drawing.md#fill) color.

### Contents

- [drawText](#drawtext) — draw a string
- [textFont](#textfont), [textSize](#textsize), [textAlign](#textalign) — text state
- [textWidth](#textwidth) — measure a string
- [BitmapFont](#bitmapfont) — the font value type, and authoring your own

<a name="drawtext"></a>

### drawText

```swift
drawText(_ string: String, _ x: Double, _ y: Double)
drawText(_ string: String, at position: Vector2)
```

Draw `string` at a point, in the current `fill` color, using the active `textFont` / `textSize` / `textAlign`. `\n` starts a new line. Because each pixel is an SDF square, text rotates and scales with the [transform stack](./Drawing.md#translate) like any other geometry. `noFill()` draws nothing; characters the font doesn't have advance the pen but draw nothing.

```swift
background(.black)
fill(.white)
textSize(120)
textAlign(.center, .middle)
drawText("ollin", width / 2, height / 2)
```

<a name="textfont"></a>

### textFont

```swift
textFont(_ font: BitmapFont)
```

Set the active font. Defaults to `.builtin`. (See [BitmapFont](#bitmapfont) to build your own.)

<a name="textsize"></a>

### textSize

```swift
textSize(_ size: Double)
```

Set the rendered text height in points — the height one line of glyphs occupies on screen. A `BitmapFont` is authored at a native pixel height; `textSize` scales each pixel to a module of `size / font.pixelHeight` points, so `textSize(140)` makes a capital letter 140 points tall whatever the font's grid. Defaults to 24.

<a name="textalign"></a>

### textAlign

```swift
textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline)
```

Set how text is anchored to the `drawText` position.

- Horizontal (`TextAlignH`): `.left` (default) starts the text at the x, `.center` centers it, `.right` ends it at the x.
- Vertical (`TextAlignV`): `.baseline` (default, like p5) sits the first line's baseline on the y; `.top` / `.bottom` align the block's top / bottom edge; `.middle` centers the whole block.

```swift
textAlign(.center, .top)
drawText("two\nlines", width / 2, 100)   // centered, growing downward from y = 100
```

<a name="textwidth"></a>

### textWidth

```swift
textWidth(_ string: String) -> Double
```

The on-screen width of `string`'s widest line, in points, at the current `textFont` / `textSize` — for laying text out (centering by hand, wrapping, marquees).

```swift
let w = textWidth(label)
drawRect(center: Vector2(x, y), width: w + 24, height: textSize_ + 16)   // a padded backing
```

<a name="bitmapfont"></a>

### BitmapFont

A `BitmapFont` is a value type: a table of `BitmapGlyph`s (each a small bit grid) plus layout metrics (`pixelHeight`, `baseline`, `lineHeight`). The built-in font is **Cozette** (see above).

Load your own pixel font from a **BDF** file (the standard bitmap-font format, what the X11 catalog and Cozette ship):

```swift
if let mine = BitmapFont(bdfContentsOf: url) {
    textFont(mine)
}
```

Or hand-author a fixed-cell font from ASCII art with the grid initializer — `#` marks a lit pixel:

```swift
let blocks = BitmapFont(grid: [
    "A": [".##.", "#..#", "####", "#..#", "#..#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    // …
], pixelHeight: 5)

textFont(blocks)
drawText("AI", width / 2, height / 2)
```

#### Loading a Playdate `.fnt`

Ollin also reads the **Playdate `.fnt`** format — a line-oriented metrics file (per-glyph widths, `tracking`, and kerning pairs) paired with a 1-bit glyph strike, either embedded in the file as base64 or sitting beside it as a `<name>-table-<width>-<height>.png`. It's a common pixel-font format, with a large pool of free community fonts to draw from. Kerning pairs in the file are applied automatically during layout.

```swift
let url = Bundle.module.url(forResource: "MyFont", withExtension: "fnt")!
if let font = BitmapFont(fntContentsOf: url) {
    textFont(font)
}
```

`BitmapFont(fntContentsOf:)` handles both forms — it finds the sibling `-table` PNG when the strike is external. If you already have the text (say, fetched over the network), `BitmapFont(fnt:)` parses the self-contained embedded form directly:

```swift
let text = try String(contentsOf: someURL, encoding: .utf8)
if let font = BitmapFont(fnt: text) { textFont(font) }
```

Ollin bundles only the *loader*, not a library of `.fnt` fonts — drop your own beside your sketch (the `PlaydateFont` example does exactly this). Free, redistributable pixel fonts are easy to find; the public-domain set at [playdate-arcade-fonts](https://github.com/idleberg/playdate-arcade-fonts) is one source.

---

Coordinates use a **top-left origin with y increasing downward**, the same as the rest of Ollin's drawing surface.
