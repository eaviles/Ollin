#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Glyph mosaic`</sup>

---

## Glyph mosaic

**`drawGlyphMosaic`** rebuilds an image as a grid of text glyphs: each cell measures the brightness underneath and shows the character whose ink matches. It's the classic text-mode rendering, generalized. The character set is any string you type, and the ramp is not hand-ordered: every glyph's actual ink coverage is measured in the active font, so quadrant blocks, checkered squares, braille dots, and plain letters all sort themselves correctly, and characters the font doesn't cover simply drop out.

```
  the picture              drawGlyphMosaic(picture)

  ░░▒▒▓▓██                   · ∙ ▚ ▩ ⣿ ■
  ░░░▒▒▓▓▓          →          · x ⊞ ▦ ▩
  ░░░░▒▒▒▓                       · + ▤ ▧
  ░░░░░▒▒▒                          · = ⊞

  bright cells earn dense marks, faint cells a lone dot,
  and cells below the sparsest glyph stay truly empty
```

By default bright cells get dense glyphs (light marks on a dark canvas, the terminal reading); pass `inverted: true` for the paper reading, where dark cells carry the ink. Deterministic given (image, columns, characters, font), so a mosaic is snapshot- and recipe-safe.

### Contents

- [drawGlyphMosaic](#draw)
- [glyphMosaic (the data form)](#data)
- [Character sets](#sets)
- [Practical notes](#notes)

<a name="draw"></a>

#### drawGlyphMosaic

```swift
drawGlyphMosaic(_ image: Image,
                columns: Int = 72,
                characters: String = GlyphSet.technical,
                in bounds: Rectangle? = nil,
                inverted: Bool = false,
                colored: Bool = false,
                glyphScale: Double = 0.85)
```

Draw `image` as a glyph mosaic, sampled `columns` cells across. The image keeps its aspect inside `bounds` (the whole canvas by default). Glyphs draw with the current `fill`, or tinted by the image itself with `colored: true`.

```swift
textFont(BitmapFont.builtin)     // the bundled bitmap font covers every mark
fill(.white)
drawGlyphMosaic(picture, columns: 72)
```

`glyphScale` is the fraction of its cell each glyph draws at. The default leaves a gutter between cells, so even solid blocks read as discrete marks; `1` tiles the full-cell block and shade characters edge to edge for an unbroken mosaic.

<a name="data"></a>

#### glyphMosaic (the data form)

```swift
glyphMosaic(of image: Image,
            columns: Int = 72,
            characters: String = GlyphSet.technical,
            in bounds: Rectangle? = nil,
            inverted: Bool = false) -> [GlyphMosaicCell]
```

The same mapping as data: one `GlyphMosaicCell` per cell that earned a glyph, carrying `column` / `row`, `center`, `size`, the chosen `character`, and the sampled `brightness` and average `color` underneath. Use it to draw your own way: jitter positions, animate per-cell, color by your own rule, or turn each glyph into vector geometry with [`textToShapes`](./Text.md#texttoshapes) for the plotter and [SVG](../Output/Export.md) paths.

```swift
for cell in glyphMosaic(of: picture, columns: 60) {
    fill(Color(hue: cell.brightness, saturation: 0.6, brightness: 1))
    drawText(String(cell.character), at: cell.center)
}
```

<a name="sets"></a>

#### Character sets

Any string is a character set; the measured ramp orders it by ink. Three curated sets ship as `GlyphSet` statics:

- **`GlyphSet.technical`** (the default): geometric and technical marks, dots through crosses, fine grids, checkered squares, quadrant blocks, and braille textures, ending in the solid blocks. At its best in the bundled bitmap font, which covers every mark.
- **`GlyphSet.classic`**: the traditional letterform ramp (`.:-=+*#%@`) for the typewriter look, at home in any outline font.
- **`GlyphSet.blocks`**: block elements only, for a chunky mosaic with no recognizable characters (pair with `glyphScale: 1` to tile it seamlessly).

The measured ramp is what makes custom sets easy: `"·+x▚█"` works, and so does a set that tops out below solid (drop the blocks and shades and the brightest cells stay discrete marks with gutters, which is often the better look).

<a name="notes"></a>

#### Practical notes

- **It re-reads the image every call**, so a mosaic over a live painting or a video frame animates for free; the ramp itself is measured once per (font, characters) and cached.
- **The empty floor is deliberate.** A cell whose ink target falls below half the sparsest glyph's coverage draws nothing, so shadows read as true voids rather than a field of dots.
- **Brightness is perceptual.** Cells average their pixels, then map through the same transfer the eye expects, so midtones land midway up the ramp. Transparency carries no ink in either mapping.
- **Texture-backed images have no CPU pixels.** A video frame or camera image reads through its `snapshot()` first, like every CPU image pass.
- **Bitmap fonts count lit pixels exactly**; outline fonts integrate the filled glyph area; stroke (plotter) fonts take pen travel. Each kind is consistent within itself, and the ramp normalizes to its densest member.

---

Related: [`Text`](./Text.md) (fonts, `drawText`, text as geometry), [`Images`](./Images.md) (the pixel access it samples), [`Stippling`](../Generators/Stippling.md) (tone from free dots instead of a glyph grid), [`Pixel sorting`](./PixelSorting.md) (another image-as-input transform).
