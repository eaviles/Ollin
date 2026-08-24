#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Single line`</sup>

---

## Single line

**`singleLine`** connects a set of points into one continuous tour. That is the TSP-art rendering of an image: [stipple](./Stippling.md) a picture, tour the dots, and the one unbroken line reads as the picture. Dark regions pull the line into tight meanders, and light regions let it stride. The technique is Bosch and Kaplan's TSP art. The tour here is a nearest-neighbor construction polished by 2-opt, which also removes the crossings that would muddy the tone.

```
  the stipple                 singleLine(through: dots)

   ·  · ·  ·                    ┌──┐ ┌───┐
  · ····· ·          →          │ ┌┘─┘┐ ─┘│
   ·· · ··                      └─┘└──┘───┘
                                one closed loop, no crossings
```

The output is a plain `Contour`, so it feeds `drawPolyline`, `drawCurve` for the smoothed reading, [hatching and SVG export](../Output/Export.md), and shape sampling. A single closed line is the friendliest thing a pen plotter can be handed.

<img src="../../Guide/Images/09-Pictures/PictureAsLines.jpg" alt="Three panels: a stipple of the sunset with a clear void where the sun is, the same dots joined into one maze-like unbroken tour, and the same dots joined into branching tree chains" width="680">

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

The one-call form: stipple `image` with `count` dots, then tour them. The image is stretched over `bounds`, which is the whole canvas by default. Pass a `Rectangle(fitting:in:)` of the image's size to keep its aspect. Driven by the seeded `random`, so [`seed`](./Random.md#seed) reproduces the drawing exactly.

```swift
let line = singleLine(of: picture, points: 4000, in: frame)
noFill()
stroke(.black)
drawPolyline(line.points, closed: line.isClosed)
```

`cutoff` rounds bright grays up to paper. Pixels lighter than it place no dots, so light regions stay genuinely empty instead of collecting a thin wandering thread. Lower it for high-key images, and raise it toward `1` to let faint tone back in.

<a name="points"></a>

#### singleLine (through points)

```swift
singleLine(through points: [Vector2], closed: Bool = true) -> Contour
```

The tour itself, over any points: a stipple, a [blue-noise scatter](./BlueNoise.md), cluster centers, hand-placed anchors. `closed` returns to the start, the classic reading. An open tour instead cuts the longest edge and walks end to end, which suits a plotter path with a natural start and finish.

```swift
let tour = singleLine(through: dots, closed: false)
drawCurve(tour.points)              // the smoothed reading
```

Deterministic given the points, and pure CPU: thousands of points are comfortable, hundreds of thousands are not.

<a name="notes"></a>

#### Practical notes

- **Tour once, hold the contour.** Nearest-neighbor plus 2-opt sweeps the tour repeatedly, so it is `setup()` work. Animate the reveal by drawing a growing prefix of the points, not the tour.
- **Contrast is the real control.** The line's tone range comes from dot density, and the tour flattens contrast a little. A punchy source image with real darks reads far better than a soft gray one. The `cutoff` keeps the paper clean at the other end.
- **Counts to start from.** Around 2,000 points sketches a subject, and 4,000 to 8,000 carries a portrait. More points cost more tour time, quadratic-ish.
- **Line weight belongs to you.** Draw thin for the engraving look, or resample and vary weight along the path. `Contour.resampled(spacing:)` evens the vertices first.

---

Related: [`Stippling`](./Stippling.md) (the placement half), [`Blue noise`](./BlueNoise.md) (even scatter to tour), [`Pixel sorting`](../Drawing/PixelSorting.md) and [`Glyph mosaic`](../Drawing/GlyphMosaic.md) (the other image-as-input renderings), [`Export`](../Output/Export.md) (SVG and the plotter path).
