#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Seam carving`</sup>

---

## Seam carving

**`Image.seamCarved`** changes a picture's proportions by taking away the paths that carry the least, instead of squeezing every pixel by the same amount. A *seam* is a connected run of pixels, one per row, that walks from the top edge to the bottom. Remove the cheapest one and the picture is a pixel narrower while whatever mattered in it keeps its shape. Do it three hundred times and a wide picture becomes a tall one with its subjects still the right shape. The technique is Shai Avidan and Ariel Shamir's; the default cost is the forward energy of Michael Rubinstein, Ariel Shamir, and Shai Avidan.

```
  the picture              a seam                 what is left

  ░░░░▓▓▓▓░░░░             ░░░·▓▓▓▓░░░░           ░░░▓▓▓▓░░░░
  ░░░░▓▓▓▓░░░░      →      ░░░·▓▓▓▓░░░░     →     ░░░▓▓▓▓░░░░
  ░░░░▓▓▓▓░░░░             ░░·░▓▓▓▓░░░░           ░░░▓▓▓▓░░░░
  ░░░░▓▓▓▓░░░░             ░░·░▓▓▓▓░░░░           ░░░▓▓▓▓░░░░

  one pixel per row, and never more than one step
  sideways from the row above: that is the whole rule
```

<img src="../../Guide/Images/09-Pictures/CarvedNarrower.jpg" alt="The sunset at its own width, squeezed to 70% where the sun becomes a visible oval, and carved to 70% where the sun stays round because it was marked to hold" width="680">

### Contents

- [seamCarved](#carved)
- [Growing, not only shrinking](#growing)
- [Holding something still, and taking something out](#masks)
- [Any width, every frame: SeamMap](#map)
- [Seeing what it reads: seams and seamEnergy](#seeing)
- [Practical notes](#notes)

<a name="carved"></a>

#### seamCarved

```swift
image.seamCarved(toWidth: Int? = nil,
                 toHeight: Int? = nil,
                 energy: SeamEnergy = .forward,
                 protecting: Image? = nil,
                 discarding: Image? = nil) -> Image
```

A copy of the picture at the size asked for. Leave an axis out to keep it as it is; give both and the width carves first, then the height.

```swift
let narrow = picture.seamCarved(toWidth: 240)
let square = picture.seamCarved(toWidth: 400, toHeight: 400)
```

`energy` is how a seam's cost is measured:

- **`.forward`** (the default) is what the removal *adds* to the picture: the new edges that appear when the two sides close over the gap. It holds up better under heavy carving, because it refuses to make an edge that was not there before.
- **`.gradient`** is what the removal *takes away*: the edge strength already at each pixel. It is the original measure, and it is easier to reason about, because [`seamEnergy`](#seeing) draws you a picture of it.

<a name="growing"></a>

#### Growing, not only shrinking

Ask for a bigger size and the same seams are duplicated rather than removed. The added pixels spread over the whole picture instead of stretching one part of it, and each one is the average of the two it sits between.

```swift
let wide = picture.seamCarved(toWidth: 520)
```

A seam is only ever duplicated once, so a picture grows to at most twice its size on an axis. Ask for more than that and the target clamps.

<a name="masks"></a>

#### Holding something still, and taking something out

Two masks steer the carve. Both are pictures the same size as the one being carved. Both read a mark as *brightness times opacity*, so white on black and white on clear work equally well.

```swift
let held = picture.seamCarved(toWidth: 300, protecting: faceMask)
let gone = picture.seamCarved(toWidth: 300, discarding: signMask)
```

- **`protecting:`** puts a price on the marked pixels far above anything a picture can carry, so no seam crosses them. Use it for a face, a horizon, a line of type.
- **`discarding:`** does the opposite: it makes the marked pixels the cheapest thing in the picture, so every seam is drawn straight through them. Carve away as many seams as the marked thing is wide and it leaves the picture altogether. Carve the picture back up to its old width afterwards and the thing is gone with the size unchanged.

A mask of the wrong size is left out rather than half applied, with a note.

<a name="map"></a>

#### Any width, every frame: SeamMap

One seam costs a full pass over the picture, so carving a hundred of them is a hundred passes. That is `setup()` work. When the width has to change while the sketch runs, work the seams out once and read sizes back out of the map:

```swift
private var map: SeamMap?

override func setup() {
    map = picture.seamMap()
}

override func draw() {
    let width = Int(300 + sin(time) * 120)
    if let framed = map?.image(width) { drawImage(framed, in: canvasRectangle) }
}
```

```swift
image.seamMap(along: SeamDirection = .vertical,
              energy: SeamEnergy = .forward,
              protecting: Image? = nil,
              discarding: Image? = nil) -> SeamMap?
```

| On `SeamMap` | What it gives |
|---|---|
| `image(_ size: Int)` | The picture at `size` across the seams: the width for `.vertical` seams, the height for `.horizontal` ones. Sizes outside `sizes` clamp. |
| `sizes` | The range it can hand back: down to one pixel, up to twice the size. |
| `seam(_ index: Int)` | Seam number `index`, counting from the cheapest, as an open `Contour` in the picture's own pixel coordinates. |
| `size`, `width`, `height`, `direction` | The picture it was built from, and which way its seams run. |

<a name="seeing"></a>

#### Seeing what it reads: seams and seamEnergy

```swift
image.seams(_ count: Int,
            along: SeamDirection = .vertical,
            energy: SeamEnergy = .forward,
            protecting: Image? = nil,
            discarding: Image? = nil) -> [Contour]

image.seamEnergy(_ energy: SeamEnergy = .forward,
                 along: SeamDirection = .vertical) -> Image?
```

`seams` gives the first `count` seams the picture would give up, cheapest first, as open contours in its pixel coordinates. Draw them over the picture to show what is about to go, or send them to a plotter.

```swift
drawImage(picture, in: box)
withState {
    translate(box.corner)
    stroke(.red)
    for seam in picture.seams(40) { drawPolyline(seam.points) }
}
```

`seamEnergy` gives the cost as a gray picture: bright is expensive, and bright is what the seams walk around. It is the fastest way to understand why a carve went where it went.

<a name="notes"></a>

#### Practical notes

- **Texture is what survives; flat is what gives way.** A seam through the middle of a plain wall creates no new edge, so it costs nothing, and a plain object carves away like anything else. Photographs and painted pictures with grain hold their subjects well. If something flat has to stay, mark it with `protecting:`.
- **It is CPU work at the picture's own resolution.** A carve of `k` seams is `k` passes over the picture. Carve in `setup()`, keep the source a few hundred pixels on a side, and draw it scaled up. A `SeamMap` pays for every seam once and then reads any size back at once.
- **Deterministic.** The same picture and the same numbers give the same result, byte for byte; ties break on position. Carved pictures are snapshot- and recipe-safe.
- **Carve gently.** Taking away a quarter of the width is usually invisible. Taking away three quarters is a different picture, whatever the energy says, because at some point the only things left to remove are the things you wanted.
- **Both axes at once carve one after the other**, width first. That is the usual practice, not the best possible order; a picture that needs both can look better carved in two calls, in the order you choose.
- **Alpha rides its pixel.** Brightness reads the straight, un-premultiplied color, so a clear pixel reads as black, and a duplicated pixel averages transparency with its color.
- **Texture-backed images have no CPU pixels**, so they are handed straight back (or give `nil`, or an empty list) with a note. Read a video frame through its `snapshot()` first.

---

Related: [`Images`](./Images.md) (the `Image` type and pixel access), [`Pixel sorting`](./PixelSorting.md) and [`Halftone`](./Halftone.md) (the other things a picture can be put through), [`Measured distance fields`](./DistanceFields.md) (another reading taken off a picture), [`Effects`](./Effects.md) (GPU filters, for per-frame full-canvas work).
