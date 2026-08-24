#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Glyph mosaic`</sup>

---

## Glyph mosaic

**`drawGlyphMosaic`** rebuilds an image as a grid of text glyphs. Each cell measures the brightness underneath and shows the character whose ink matches. It's the classic text-mode rendering, generalized. The character set is any string you type, and the ramp is not hand-ordered. Every glyph's actual ink coverage is measured in the active font. So quadrant blocks, checkered squares, braille dots, and plain letters all sort themselves correctly, and characters the font doesn't cover simply drop out.

By default bright cells get dense glyphs, which reads as light marks on a dark canvas, the terminal look. Pass `inverted: true` for the paper reading, where dark cells carry the ink. Deterministic given the image, columns, characters, and font, so a mosaic is snapshot- and recipe-safe.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/PictureAsGlyphs-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/PictureAsGlyphs.jpg" alt="Two dark panels showing the same sunset: on the left a mosaic of ASCII characters that get denser toward the sun, on the right a halftone screen of dots that grow toward the sun" width="680">
</picture>

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

`glyphScale` is the fraction of its cell each glyph draws at. The default leaves a gutter between cells, so even solid blocks read as discrete marks. A value of `1` tiles the full-cell block and shade characters edge to edge for an unbroken mosaic.

<a name="data"></a>

#### glyphMosaic (the data form)

```swift
glyphMosaic(of image: Image,
            columns: Int = 72,
            characters: String = GlyphSet.technical,
            in bounds: Rectangle? = nil,
            inverted: Bool = false) -> [GlyphMosaicCell]
```

The same mapping as data. Each cell that earned a glyph gets one `GlyphMosaicCell`, carrying `column` / `row`, `center`, `size`, and the chosen `character`. It also carries the sampled `brightness` and the average `color` underneath. Use it to draw your own way. Jitter positions, animate per-cell, or color by your own rule. Turning each glyph into vector geometry with [`textToShapes`](./Text.md#texttoshapes) feeds the plotter and [SVG](../Output/Export.md) paths.

<img src="../../Guide/Images/09-Pictures/TypeMosaic.jpg" alt="A sunset over water built entirely from the word OLLIN repeated in a grid, the letters large and cream-colored in the sun, amber along the horizon, and small and dark in the sky and sea" width="560">

```swift
for cell in glyphMosaic(of: picture, columns: 60) {
    fill(Color(hue: cell.brightness, saturation: 0.6, brightness: 1))
    drawText(String(cell.character), at: cell.center)
}
```

<a name="sets"></a>

#### Character sets

Any string is a character set, and the measured ramp orders it by ink. Three curated sets ship as `GlyphSet` statics:

- **`GlyphSet.technical`** is the default, a set of geometric and technical marks. It runs from dots through crosses, fine grids, checkered squares, quadrant blocks, and braille textures, ending in the solid blocks. At its best in the bundled bitmap font, which covers every mark.
- **`GlyphSet.classic`** is the traditional letterform ramp `.:-=+*#%@` for the typewriter look, at home in any outline font.
- **`GlyphSet.blocks`** is block elements only, for a chunky mosaic with no recognizable characters. Pair it with `glyphScale: 1` to tile it seamlessly.

The measured ramp is what makes custom sets easy. A set like `"·+x▚█"` works, and so does one that tops out below solid. Drop the blocks and shades, and the brightest cells stay discrete marks with gutters, which is often the better look.

<a name="notes"></a>

#### Practical notes

- **It re-reads the image every call**, so a mosaic over a live painting or a video frame animates for free. The ramp itself is measured once per font and character set, then cached.
- **The empty floor is deliberate.** A cell whose ink target falls below half the sparsest glyph's coverage draws nothing. Shadows read as true voids rather than a field of dots.
- **Brightness is perceptual.** Cells average their pixels, then map through the same transfer the eye expects, so midtones land midway up the ramp. Transparency carries no ink in either mapping.
- **Texture-backed images have no CPU pixels.** A video frame or camera image reads through its `snapshot()` first, like every CPU image pass.
- **Bitmap fonts count lit pixels exactly.** Outline fonts integrate the filled glyph area, and stroke fonts for plotters take pen travel. Each kind is consistent within itself, and the ramp normalizes to its densest member.

---

Related: [`Text`](./Text.md) (fonts, `drawText`, text as geometry), [`Images`](./Images.md) (the pixel access it samples), [`Stippling`](../Generators/Stippling.md) (tone from free dots instead of a glyph grid), [`Pixel sorting`](./PixelSorting.md) (another image-as-input transform).
