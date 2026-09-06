#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Photo mosaic`</sup>

---

## Photo mosaic

**`Image.mosaic(of:columns:rows:)`** rebuilds a picture out of many smaller pictures, one per cell of a grid. It averages each cell of the target, then places the picture whose own average is nearest. From a distance the cells add up to the target. Up close, every cell is a picture of its own.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/PicturesFromPictures-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/PicturesFromPictures.jpg" alt="Three panels: a soft target picture of two lit blobs, the same picture rebuilt as a grid of small colored tiles, and seven of those cells enlarged so each is visibly its own little picture of dots, bars and triangles" width="680">
</picture>

```swift
let mosaic = portrait.mosaic(of: library, columns: 48, rows: 48)
drawMosaic(mosaic, of: library, in: bounds)
```

The averaging happens in **linear light**, because sRGB numbers do not average correctly. A cell that is half black and half white is middle gray at 0.5 in linear light. That value writes back out as about 0.74 in sRGB. Averaging the sRGB numbers instead gives 0.5, which is about a quarter too dark, so the mosaic loses its lights. Ollin also compares in linear light when it decides which picture is nearest.

### Contents

- [averageColor](#average)
- [mosaic](#mosaic)
- [Drawing it](#drawing)
- [Practical notes](#notes)

<a name="average"></a>

#### averageColor

```swift
Image.averageColor(in region: Rectangle? = nil) -> Color
```

Returns the average color of a picture, or of a rectangle of it, worked out in linear light. The rectangle is in pixels and is clamped to the picture.

**Transparent pixels count for nothing rather than for black**, so a cut-out shape averages the shape's own color. The alpha that comes back says how much of the region was covered, which is how you measure a cell's coverage.

<a name="mosaic"></a>

#### mosaic

```swift
Image.mosaic(of pictures: [Image], columns: Int, rows: Int,
             maxUses: Int? = nil) -> PhotoMosaic

struct PhotoMosaic {
    let columns: Int, rows: Int
    let tiles: [MosaicTile]                  // one per cell, in reading order
    func frame(of tile: MosaicTile, in bounds: Rectangle) -> Rectangle
    func uses(of pictures: Int) -> [Int]
}

struct MosaicTile {
    let column: Int, row: Int
    let picture: Int      // index into the pictures handed in
    let target: Color     // the average the cell had
}
```

Ollin works out each picture's own average once, so a large library costs one pass over each picture. The match itself is one pass over the target.

**`maxUses`** limits how often one picture may be used. Ollin fills the cells in reading order, so the earlier cells use up the limit first. A cell that finds nothing left falls back to the nearest picture regardless, so every cell gets a picture. For a library much smaller than the grid, leave `maxUses` alone and let the repeats happen.

<a name="drawing"></a>

#### Drawing it

```swift
drawMosaic(_ mosaic: PhotoMosaic, of pictures: [Image],
           in bounds: Rectangle? = nil, tint: Double = 0)
```

Draws each cell's picture, cropped to fill its cell. **`tint`** mixes each cell toward the color it stands for. This is the usual way to make a mosaic read from further off. A value of 0 leaves the pictures alone, and 1 paints flat color. Most mosaics use about a third.

The mosaic is a list of placements rather than a new picture, so you can draw it yourself. Do that when you want a per-cell rotation, a gap between cells, or a different fit:

```swift
for tile in mosaic.tiles {
    drawImage(library[tile.picture], in: mosaic.frame(of: tile, in: bounds), fit: .cover)
}
```

<a name="notes"></a>

#### Practical notes

- **The target needs range.** A target that is mostly one flat dark color takes the one nearest picture and repeats it everywhere. A target whose colors vary across the frame uses more of the library. `uses(of:)` returns one use count per picture, so counting its non-zero entries tells you how many of the library got used.
- **The library needs range too**, across the same colors the target has. Spread the pictures over those colors, rather than over colors that look good together.
- **Cell count against library size** decides how the mosaic reads. More cells means a better likeness and more repeats. Fewer cells means every cell is legible.
- `fit: .cover` crops each picture to its cell, which keeps proportions. `.stretch` uses every pixel and squashes the picture to fit the cell.
- Everything here is CPU work at the pictures' own resolution. Build the mosaic in `setup()` unless the target is small.

Example: `Images/PhotoMosaic`. Guide: [Chapter 9](../../Guide/09-Pictures.md).

---

#### Where this comes from

Robert Silvers patented the photographic mosaic in 1996, from work at the MIT Media Lab. The idea of building one picture from many smaller ones is older than photography, though. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Glyph mosaic](./GlyphMosaic.md): the same cell-by-cell rebuild with characters instead of pictures
- [Halftone](./Halftone.md): the same rebuild with area-exact dots on a rotated screen
- [Color](./Color.md): the `Color` type, mixing, and why averages belong in linear light
