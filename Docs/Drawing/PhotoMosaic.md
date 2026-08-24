#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Photo mosaic`</sup>

---

## Photo mosaic

**`Image.mosaic(of:columns:rows:)`** rebuilds a picture out of many smaller pictures, one per cell of a grid. Each cell of the target is averaged, and the picture whose own average is nearest goes there. Stand back and the cells add up to the target; step forward and every cell is a picture of its own.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/PicturesFromPictures-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/PicturesFromPictures.jpg" alt="Three panels: a soft target picture of two lit blobs, the same picture rebuilt as a grid of small colored tiles, and seven of those cells enlarged so each is visibly its own little picture of dots, bars and triangles" width="680">
</picture>

```swift
let mosaic = portrait.mosaic(of: library, columns: 48, rows: 48)
drawMosaic(mosaic, of: library, in: bounds)
```

The averaging happens in **linear light**, which is the only way it can be right. A cell that is half black and half white is middle gray at 0.5 in linear light, and that writes back out as about 0.74 in sRGB. Averaging the sRGB numbers instead answers 0.5, a full quarter too dark, and the mosaic comes out with its lights gone. The same rule decides which picture is nearest.

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

The average color of a picture, or of a rectangle of it, worked out in linear light. The rectangle is in pixels and is clamped to the picture.

**Transparent pixels count for nothing rather than for black**, so a cut-out shape averages the shape's own color. The alpha that comes back says how much of the region was really there, which is the honest way to ask "how much of this cell is covered".

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

Each picture's own average is worked out once, so a large library costs one pass over each picture, and the match itself is one pass over the target.

**`maxUses`** limits how often one picture may be used. Cells are filled in reading order, so the limit is spent by the cells that ask first, and a cell that finds nothing left falls back to the nearest picture regardless: every cell gets a picture. That is the honest simple rule. For a library much smaller than the grid, leave it alone and let the repeats happen.

<a name="drawing"></a>

#### Drawing it

```swift
drawMosaic(_ mosaic: PhotoMosaic, of pictures: [Image],
           in bounds: Rectangle? = nil, tint: Double = 0)
```

Each cell's picture, cropped to fill its cell. **`tint`** mixes each cell toward the color it stands for, which is the usual way a mosaic is made to read from further off: 0 leaves the pictures alone, 1 paints flat color, and a third of the way is where most mosaics live.

The mosaic is a list of placements rather than a new picture, so drawing it yourself is just as easy, and that is the way to reach for a per-cell rotation, a gap between cells, or a different fit:

```swift
for tile in mosaic.tiles {
    drawImage(library[tile.picture], in: mosaic.frame(of: tile, in: bounds), fit: .cover)
}
```

<a name="notes"></a>

#### Practical notes

- **The target needs range.** A picture that is mostly one flat dark takes the one nearest picture and repeats it everywhere. A target that varies across the frame is what makes the library work, and `uses(of:)` says how many pictures actually got used.
- **The library needs range too**, and in the same places: pictures spread over the colors the target has, not over the colors that look nice in a row.
- **Cell count against library size** is the whole feel of the thing. More cells means a better likeness and more repeats; fewer means every cell is legible.
- `fit: .cover` crops each picture to its cell, which keeps proportions. `.stretch` uses every pixel and squashes.
- Everything here is CPU work at the pictures' own resolution. Build the mosaic in `setup()` unless the target is small.

Example: `Images/PhotoMosaic`. Guide: [Chapter 9](../../Guide/09-Pictures.md).

---

#### Where this comes from

The photographic mosaic was patented by Robert Silvers in 1996 out of work at the MIT Media Lab, though the idea of building one picture from many smaller ones is older than photography. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Glyph mosaic](./GlyphMosaic.md): the same cell-by-cell rebuild with characters instead of pictures
- [Halftone](./Halftone.md): and with dots, area-exact, on a rotated screen
- [Color](./Color.md): the `Color` type, mixing, and why linear light is where averages belong
