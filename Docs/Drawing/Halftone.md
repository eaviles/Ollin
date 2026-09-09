#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Halftone`</sup>

---

## Halftone

**`drawHalftone`** rebuilds an image as the classic print dot screen. Round dots sit on a grid rotated to the traditional 45 degrees. Each dot is sized so its ink area matches the tone under its cell. Newspapers and screen prints have carried photographs this way for a century. It is the vector counterpart of the raster screening that [print separations](../Output/PrintSeparations.md) use. Because the sizing is area-exact, tone survives the screen, so a 30 percent gray becomes dots that cover 30 percent of their cells. In the shadows the dots overrun their cells and merge into the traditional checkered diamonds.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../Images/HalftoneScreen-dark.jpg">
  <img src="../Images/HalftoneScreen.jpg" alt="A photograph of an elderly woman in a yellow scarf beside the same picture as a halftone screen: black dots on cream, small on the lit cheek and swelling in the shadows of the scarf until they merge into checkered diamonds" width="680">
</picture>

### Contents

- [drawHalftone](#draw)
- [halftone (the data form)](#data)
- [Getting the classic looks](#looks)
- [Practical notes](#notes)

<a name="draw"></a>

#### drawHalftone

```swift
drawHalftone(_ image: Image,
             pitch: Double = 12,
             angle: Double = .pi / 4,
             in bounds: Rectangle? = nil,
             inverted: Bool = false,
             colored: Bool = false)
```

This one call draws the whole screen. `pitch` is the cell spacing in canvas units, and `angle` is the screen rotation. The classic single-ink screen sits at 45 degrees, because that is the angle where the eye notices the grid least. The image keeps its aspect inside `bounds`, which is the whole canvas by default. Dots draw with the current `fill` and `stroke`. Set `colored: true` and each dot is tinted with the average color under its cell instead.

```swift
fill(.black)
noStroke()
drawHalftone(picture, pitch: 14)
```

By default, dark regions get big dots, the way ink sits on paper. `inverted: true` sizes the dots by brightness instead, which gives you light marks on a dark canvas:

```swift
background(.black)
fill(.white)
drawHalftone(picture, pitch: 14, inverted: true)
```

<a name="data"></a>

#### halftone (the data form)

```swift
halftone(of image: Image,
         pitch: Double = 12,
         angle: Double = .pi / 4,
         in bounds: Rectangle? = nil,
         inverted: Bool = false) -> [HalftoneDot]
```

This form returns the screen as data, so you can draw the marks yourself. Each `HalftoneDot` carries its lattice `column` and `row` in the rotated screen, its `center` on the canvas, and its area-exact `radius`. It also carries the cell's ink `coverage`, from 0 for bare to 1 for solid, and the average `color` underneath. With those values you can swap the mark, jitter the grid, or keep only part of the tonal range:

```swift
for dot in halftone(of: picture, pitch: 16) {
    drawNgon(center: dot.center, radius: dot.radius, sides: 6)
}
```

Cells lighter than the printable minimum are left out, so highlights stay clean paper. That minimum is 2 percent coverage, the same cutoff the print separations apply. At the other end, coverage above 98 percent floods the cell. The radius then caps at `pitch / sqrt(2)`, the disk that reaches the cell corners.

<a name="looks"></a>

#### Getting the classic looks

- **Newsprint.** Use a black fill on a warm white canvas, a `pitch` of 10 to 16, and the default 45-degree angle. Smooth tonal ramps suit the screen best, because every step of a gradient lands on its own dot size.
- **The inverted poster.** Use `inverted: true` with a pale fill on a near-black canvas. It reads as light coming out of dark, the screen-print negative.
- **Pop-art color.** Use `colored: true` with a large `pitch`. The picture keeps its own palette, in fat separate dots.
- **The rosette.** Screen the same image several times at the conventional print angles of 45, 15, 75, and 0 degrees. Use one translucent ink per pass, so the overlap makes the traditional rosette instead of moire. For real spot-color work, split the image with [print separations](../Output/PrintSeparations.md) first, then screen each master.
- **Other marks.** The data form turns the screen into a layout you draw yourself. Draw glyphs at `radius`, rings, squares rotated by `coverage`, or anything else that can scale with the tone.

<a name="notes"></a>

#### Practical notes

- **The dots are real geometry.** They draw as circles through the analytic SDF path, and they carry through to the vector exports. `--export-svg` and `--export-pdf` write each dot as a true circle, which is what a pen plotter needs.
- **CPU work at the image's resolution.** The binning pass reads every source pixel once. A source a few hundred pixels across screens comfortably every frame, and the dot pass itself draws a few thousand circles.
- **Deterministic.** The screen is a pure function of the image, pitch, angle, and bounds. It consumes no rng, so a screen is safe in snapshots and in recipes.
- **Tone is measured in linear light.** Coverage is 1 minus linear luminance, times alpha. Stippling uses the same rule, because a dot's ink area maps physically to reflectance. Transparency carries no ink.
- **Texture-backed images return no dots**, because they hold no CPU pixels. To screen a video frame, read it through its `snapshot()` first.
- **For the pixel-space version** of the same look, filter a layer with `.halftone` or `.cmykHalftone` from the [effects catalog](./Effects.md). The GPU form is cheap per frame at any resolution, but it rasterizes, so it does not feed the plotter path.

---

Related: [`Images`](./Images.md) (the `Image` type and pixel access), [`Print separations`](../Output/PrintSeparations.md) (the raster screening and spot-color masters), [`Pixel sorting`](./PixelSorting.md), [`Glyph mosaic`](./GlyphMosaic.md) and [`Single line`](../Generators/SingleLine.md) (the other image-as-input renderings), [`Effects`](./Effects.md) (the GPU `.halftone` filter and the `.melt` design filter).
