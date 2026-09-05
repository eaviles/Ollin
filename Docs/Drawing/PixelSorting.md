#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Pixel sorting`</sup>

---

## Pixel sorting

**`Image.pixelSorted`** rearranges runs of an image's own pixels along its rows or columns, sorted by brightness, hue, or saturation. It invents nothing and recolors nothing, so the pixels only change places. That is what gives the result its molten, streaked look. Kim Asendorf invented the technique, and the interval model used here is his. A brightness window decides which stretches of pixels form a sortable run. That keeps the shadows and the highlights where they are, and lets the midtones flow.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/SortedPixels-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/SortedPixels.jpg" alt="The sunset beside a version with its columns sorted: the sky bands reorganize into a dome around the sun, the water smears into vertical streaks, and the sun and horizon stay intact" width="680">
</picture>

### Contents

- [pixelSorted](#sorted)
- [Getting the classic looks](#looks)
- [Practical notes](#notes)

<a name="sorted"></a>

#### pixelSorted

```swift
image.pixelSorted(_ direction: PixelSortDirection = .vertical,
                  by key: PixelSortKey = .brightness,
                  threshold: ClosedRange<Double> = 0.25 ... 0.8,
                  reversed: Bool = false) -> Image
```

The call returns a copy of the image, with the runs that the threshold bounds sorted along `direction`. With `.vertical` the streaks fall, and with `.horizontal` they run sideways. Pixels whose brightness falls inside `threshold` form the runs. Each run is reordered by `key`, ascending by default, or descending when you pass `reversed: true`. The keys are `.brightness`, `.hue`, and `.saturation`. Widen the window to `0...1` to sort whole rows or columns.

```swift
let melted = picture.pixelSorted(.vertical, threshold: 0.2 ... 0.75)
```

The classic treatment sorts the image twice, once along each axis:

```swift
let glitched = picture.pixelSorted(.vertical).pixelSorted(.horizontal)
```

<a name="looks"></a>

#### Getting the classic looks

- **Falling curtains.** Use `.vertical` with a midtone window. If a smooth gradient barely changes, that is because it was already sorted. Add `reversed: true` to turn that order around, or sort by `.hue` so the order comes from another property.
- **Jagged teeth.** The comb edge comes from the run boundaries landing at a different place in every column. Texture is what drives it, so look for grain, clouds, stars, or anything else that breaks the window at varying heights. A perfectly clean gradient sorts with no visible change.
- **Protected features.** A pixel outside the window never moves. Keep the window's floor above your shadows and its ceiling below your highlights, and the anchors of the composition survive the sort.
- **Color chaos.** Passing `by: .hue` inside a wide window reorders the pixels by the color wheel. Sorting `by: .saturation` pushes the gray pixels toward one end of the run and the vivid ones toward the other.

<a name="notes"></a>

#### Practical notes

- **The sort runs on the CPU at full resolution.** Sort a big image once, in `setup()`. If you need a sorted image on every frame, keep the source a few hundred pixels on a side and draw it scaled up.
- **The result is deterministic.** The same image and the same parameters produce the same result, byte for byte, and position breaks ties. That makes a sorted image safe to use in a snapshot test and in a recipe.
- **Alpha moves with its pixel.** A translucent pixel keeps its transparency when it moves. Brightness is read from the straight, un-premultiplied color, and a fully transparent pixel reads as black.
- **A texture-backed image returns itself unchanged**, because it holds no CPU pixels. Read a video frame through its `snapshot()` first.

---

Related: [`Images`](./Images.md) (the `Image` type and pixel access), [`Glyph mosaic`](./GlyphMosaic.md) and [`Single line`](../Generators/SingleLine.md) (the other renderings that take an image as input), [`Dithering`](./Color.md#dithering) (another way to rearrange tone), [`Effects`](./Effects.md) (GPU filters, for full-canvas work on every frame).
