#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Pixel sorting`</sup>

---

## Pixel sorting

**`Image.pixelSorted`** rearranges runs of an image's own pixels along rows or columns, sorted by brightness, hue, or saturation. Nothing is invented or recolored. The pixels just change places, which is what gives the technique its molten, streaked reading. The technique was invented by Kim Asendorf, and the interval model here is his. A brightness window decides which stretches of pixels form a sortable run, so shadows and highlights hold their ground while the midtones pour.

<img src="../../Guide/Images/09-Pictures/SortedPixels.jpg" alt="The sunset beside a version with its columns sorted: the sky bands reorganize into a dome around the sun, the water smears into vertical streaks, and the sun and horizon stay intact" width="680">

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

A copy of the image with threshold-bounded runs sorted along `direction` (`.vertical` streaks fall, `.horizontal` streaks pour sideways). Pixels whose brightness falls inside `threshold` form the runs. Each run reorders by `key`, ascending, or descending with `reversed`. The keys are `.brightness`, `.hue`, and `.saturation`. Widen the window to `0...1` to sort whole rows or columns.

```swift
let melted = picture.pixelSorted(.vertical, threshold: 0.2 ... 0.75)
```

The classic treatment sorts twice, once per axis:

```swift
let glitched = picture.pixelSorted(.vertical).pixelSorted(.horizontal)
```

<a name="looks"></a>

#### Getting the classic looks

- **Falling curtains.** `.vertical` with a midtone window. If a smooth gradient barely changes, that's because it was already sorted. Add `reversed: true` to invert it dramatically, or sort by `.hue` so the order comes from somewhere else.
- **Jagged teeth.** The signature comb edge comes from run boundaries landing differently in every column. Texture drives it: grain, clouds, stars, anything that breaks the window at varying heights. A perfectly clean gradient sorts invisibly.
- **Protected features.** Anything outside the window never moves. Keep the window's floor above your shadows and its ceiling below your highlights and the composition's anchors survive the melt.
- **Color chaos.** `by: .hue` inside a wide window reorders by the color wheel. Sorting `by: .saturation` pushes gray toward one end and vivid toward the other.

<a name="notes"></a>

#### Practical notes

- **It's CPU work at full resolution.** A one-off sort of a big image is `setup()` work. For a sorted image every frame, keep the source a few hundred pixels on a side and draw it scaled up.
- **Deterministic.** The same image and parameters produce the same result, byte for byte, with position breaking ties. Sorted images are snapshot- and recipe-safe.
- **Alpha rides its pixel.** A translucent pixel moves with its transparency attached. Brightness reads the straight, un-premultiplied color, and a fully transparent pixel reads as black.
- **Texture-backed images return themselves unchanged**, because they hold no CPU pixels. Read a video frame through its `snapshot()` first.

---

Related: [`Images`](./Images.md) (the `Image` type and pixel access), [`Glyph mosaic`](./GlyphMosaic.md) and [`Single line`](../Generators/SingleLine.md) (the other image-as-input renderings), [`Dithering`](./Color.md#dithering) (a different rearrangement of tone), [`Effects`](./Effects.md) (GPU filters, for per-frame full-canvas work).
