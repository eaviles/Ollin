#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Single line`</sup>

---

## Single line

**`singleLine`** connects a set of points into one continuous tour. That is how an image becomes TSP art: [stipple](./Stippling.md) a picture, tour the dots, and the one unbroken line reads as the picture. Dark regions pull the line into tight meanders, and light regions let it take long steps. The technique is Bosch and Kaplan's TSP art. The tour here starts as a nearest-neighbor construction and is then improved by 2-opt, which also removes the crossings that would muddy the tone.

The output is a plain `Contour`, so it works with `drawPolyline`, `drawCurve` for the smoothed reading, [hatching and SVG export](../Output/Export.md), and shape sampling. A single closed line is also the easiest thing to hand to a pen plotter.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/PictureAsLines-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/PictureAsLines.jpg" alt="Three panels: a stipple of the sunset with a clear void where the sun is, the same dots joined into one maze-like unbroken tour, and the same dots joined into the branching chains of a spanning tree" width="680">
</picture>

The third panel joins the same dots with [`spanningTree`](./SpanningTree.md) instead. It links every dot by the shortest set of edges and breaks the result into a few branching chains, so the picture reads as veins rather than as one maze.

### Contents

- [singleLine (an image)](#image)
- [singleLine (through points)](#points)
- [Practical notes](#notes)

<a name="image"></a>

#### singleLine (an image)

```swift
singleLine(of image: Image,
           points count: Int,
           in bounds: Rectangle? = nil,
           iterations: Int = 40,
           cutoff: Double = 0.85,
           closed: Bool = true) -> Contour
```

This is the one-call form. It stipples `image` with `count` dots and then tours them. The image is stretched over `bounds`, which is the whole canvas by default. To keep the image's aspect ratio, pass a `Rectangle(fitting:in:)` of the image's size. The call is driven by the seeded `random`, so [`seed`](./Random.md#seed) reproduces the drawing exactly.

```swift
let line = singleLine(of: picture, points: 4000, in: frame)
noFill()
stroke(.black)
drawPolyline(line.points, closed: line.isClosed)
```

`cutoff` rounds bright grays up to plain paper. Pixels lighter than `cutoff` place no dots, so light regions stay empty instead of collecting a thin wandering thread. Lower it for high-key images, and raise it toward `1` to let faint tone back in.

<a name="points"></a>

#### singleLine (through points)

```swift
singleLine(through points: [Vector2], closed: Bool = true) -> Contour
```

This form runs the tour on its own, over any points you have: a stipple, a [blue-noise scatter](./BlueNoise.md), cluster centers, or hand-placed anchors. With `closed`, the line returns to its start, which is the classic reading. An open tour cuts the longest edge instead and walks end to end, which suits a plotter path with a natural start and finish.

```swift
let tour = singleLine(through: dots, closed: false)
drawCurve(tour.points)              // the smoothed reading
```

The result is deterministic for a given set of points, and the work runs entirely on the CPU. Thousands of points are comfortable, and hundreds of thousands are not.

<a name="notes"></a>

#### Practical notes

- **Tour once, then hold the contour.** Nearest-neighbor plus 2-opt sweeps the tour repeatedly, so it is `setup()` work. To animate the reveal, draw a growing prefix of the points rather than tour again.
- **Contrast is the real control.** The line's tone range comes from dot density, and the tour flattens contrast a little. A high-contrast source image with real darks reads far better than a soft gray one. At the light end, `cutoff` keeps the paper clean.
- **Counts to start from.** Around 2,000 points sketches a subject, and 4,000 to 8,000 carries a portrait. More points cost more tour time, roughly quadratic.
- **The line weight is yours to choose.** Draw thin for the engraving look, or resample and vary the weight along the path. `Contour.resampled(spacing:)` spaces the vertices evenly first.

---

Related: [`Stippling`](./Stippling.md) (places the dots), [`Blue noise`](./BlueNoise.md) (an even scatter to tour), [`Pixel sorting`](../Drawing/PixelSorting.md) and [`Glyph mosaic`](../Drawing/GlyphMosaic.md) (the other renderings that take an image as input), [`Export`](../Output/Export.md) (SVG and the plotter path).
