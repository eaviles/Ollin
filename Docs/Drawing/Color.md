#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Color`</sup>

---

## Color

`Color` is an RGBA color with `Double` components in `0...1`. Most of the types below map a single number to a `Color` through the same `color(at:)` call (`Ramp`, `CosinePalette`, and `Colormap` smoothly, the discrete `Palette` in steps), which is the usual way to drive color from a value or from time.

### Contents

- [Color](#color)
- [OKLab, OKLCH, OKHSL](#oklab)
- [Mixing](#mixing)
- [Ramp](#ramp)
- [Gradient paint](#gradient)
- [Palette](#palette)
- [Loading palettes from a file](#palette-files)
- [Extracting a palette from an image](#palette-extraction)
- [Dithering an image to a palette](#dithering)
- [CosinePalette](#cosinepalette)
- [Colormap](#colormap)

<a name="color"></a>

### `Color`

```swift
Color(red: Double, green: Double, blue: Double, alpha: Double = 1)
Color(white: Double, alpha: Double = 1)
Color(hex: UInt32, alpha: Double = 1)     // 24-bit RGB: Color(hex: 0xFF0066)
Color(hex: String)                        // "#RGB" "#RGBA" "#RRGGBB" "#RRGGBBAA" → Color?
Color(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1)
Color(kelvin: Double, alpha: Double = 1)  // blackbody color temperature
```

Named constants come in two tiers. The essentials are `.white`, `.black`, `.gray`, `.clear`, and the additive primaries `.red`, `.green`, `.blue` (so `green` is pure `(0, 1, 0)`). A fuller set fills in around them, with names and exact sRGB values from the [CSS Color Module Level 4](https://www.w3.org/TR/css-color-4/#named-colors) `<named-color>` list, so common colors read by name:

`.yellow` `.cyan` `.magenta` `.orange` `.purple` `.pink` `.brown` · `.crimson` `.tomato` `.coral` `.salmon` `.gold` · `.darkGreen` `.forestGreen` `.seaGreen` `.olive` `.teal` `.turquoise` · `.navy` `.royalBlue` `.steelBlue` `.skyBlue` `.indigo` · `.violet` `.orchid` `.plum` `.lavender` `.maroon` · `.tan` `.khaki` `.beige` `.ivory` `.silver` `.lightGray` `.darkGray` `.slateGray`

(CSS pins `green` to a darker `#008000`; Ollin keeps `green` as the pure primary, so reach for `.darkGreen` or `.forestGreen` for the deeper tone.)

```swift
background(.white)
fill(.coral)
fill(Color(red: 0.2, green: 0.5, blue: 0.9))
stroke(Color(white: 0.1))
```

**Hex** comes in two forms. The integer form is the one for literals in code: compile-checked, nothing to parse, never optional. An integer carries no digit count (`0xFFF` and `0x000FFF` are the same value), so it's always six digits of RGB, with alpha as its own parameter:

```swift
background(Color(hex: 0x14171C))
fill(Color(hex: 0xFF0066, alpha: 0.5))
```

The string form takes the full grammar (`"#RGB"`, `"#RGBA"`, `"#RRGGBB"`, `"#RRGGBBAA"`, the `#` optional, case-insensitive) and returns an optional, so a string from a file or the network fails cleanly instead of trapping:

```swift
let brand = Color(hex: "#ff0066")!        // a literal you know is well-formed
if let c = Color(hex: userString) { fill(c) }
```

**Hue, saturation, brightness** are each in `0...1`. Hue wraps (1.2 reads as 0.2), so it can run on `time` or any other unbounded value without bookkeeping; saturation and brightness clamp. The `HSBWheel` example draws the classic wheel with it:

```swift
fill(Color(hue: time * 0.1, saturation: 0.8, brightness: 1))   // cycle the rainbow
```

**Color temperature** names light the way a photographer does. `Color(kelvin:)` takes a blackbody temperature, warm (orange) at the low end, cool (blue) at the high end, neutral white around 6600. It's an ordinary sRGB `Color`, so it drops into `fill`, `background`, or a `Light`'s color; the 3D [lighting presets](../3D/3D.md#lights) use it so a rig reads as the temperatures it really is. `kelvin` clamps to `1000...40000`.

```swift
directionalLight(Color(kelvin: 5600), direction: Vector3(-0.5, -0.8, -0.4))  // daylight key
fill(Color(kelvin: 3200))                                                    // warm tungsten
```

**Two component helpers** round out the type. `withAlpha(_:)` is the everyday fade: the same color at a different opacity, the original untouched. `luminance` is the color's perceived brightness in `0...1`, the Rec. 709 weighted sum of the linearized components, so green counts most and blue least, the way the eye weighs them; it's the handle for image-driven work (sample a pixel with [`Image`](Images.md#pixels)'s subscript, then size or choose marks by `pixel.luminance`).

```swift
fill(ink.withAlpha(0.3))                  // a translucent version of a held color
let size = cell * image[x, y].luminance   // marks scaled by perceived brightness
```

<a name="oklab"></a>

### OKLab, OKLCH, OKHSL

Three views of one perceptual model, each a small value type that converts to and from `Color` (alpha stays on the `Color`):

```swift
OKLab(l:a:b:)     OKLab(_ color: Color)     Color(_ lab: OKLab, alpha: Double = 1)
OKLCH(l:c:h:)     OKLCH(_ color: Color)     Color(_ lch: OKLCH, alpha: Double = 1)
OKHSL(h:s:l:)     OKHSL(_ color: Color)     Color(_ hsl: OKHSL, alpha: Double = 1)
```

- **`OKLab`** is the workhorse for color *math*: `l` is perceived lightness in `0...1`, `a` runs green → red and `b` runs blue → yellow. Mixing through it comes out visually even.
- **`OKLCH`** is OKLab in polar form (lightness, chroma, hue), the space for hue and chroma *dials*: turning `h` leaves lightness and colorfulness alone. The maximum displayable chroma depends on hue and lightness, so a dialed-up `c` can ask for colors the screen can't show; converting to `Color` maps those back by reducing chroma at constant lightness and hue, so the color stays itself, just as vivid as sRGB allows.
- **`OKHSL`** squeezes the same model into the sRGB gamut: `s` and `l` run `0...1` and every combination is displayable. It is the space for *generated* color ("random hue, same perceived lightness").

Hue is a turn in `0...1` everywhere, like the HSB initializer, and wraps the same way.

```swift
// Twelve hues that genuinely read as the same lightness:
for i in 0..<12 {
    fill(Color(OKHSL(h: Double(i) / 12, s: 0.9, l: 0.65)))
    drawCircle(60 + Double(i) * 80, height / 2, 30)
}

var lch = OKLCH(brand)
lch.h += 0.5                 // the complementary hue, same lightness and chroma
let complement = Color(lch)
```

<a name="mixing"></a>

### Mixing

```swift
Color.mix(_ a: Color, _ b: Color, t: Double, in: ColorSpace = .oklab) -> Color
```

Interpolates between two colors in a chosen space: `.rgb`, `.hsb`, `.oklab` (the default, perceptually even), `.oklch` (holds hue identity, arcs through chroma), or `.okhsl`. `t` clamps to `0...1` and alpha interpolates linearly. In the polar spaces hue takes the shortest way around the wheel, and an achromatic endpoint (gray, black, white) adopts the other color's hue, so a fade to white doesn't detour through unrelated hues.

```swift
let warm = Color(hex: 0xFF5500)
let cool = Color(hex: 0x0066FF)
fill(Color.mix(warm, cool, t: sin(time) * 0.5 + 0.5))
```

The `Mixing` example draws the same two colors mixed in all five spaces, band by band. The OKLab family and the gamut mapping are credited under [Influences & attribution](../../ATTRIBUTION.md#color).

<a name="ramp"></a>

### `Ramp`

A gradient built from a list of colors, spread evenly or placed with explicit stops, sampled with `color(at:)`. Interpolation runs through a chosen `ColorSpace` (OKLab by default, which blends evenly), and `t` clamps to the ends. Two stops sharing a position make a hard edge.

```swift
let heat = Ramp([.black, .red, Color(hex: 0xFFCC00), .white])
fill(heat.color(at: energy))

let sky = Ramp(stops: [(0, Color(hex: 0x0B1A40)),
                       (0.8, Color(hex: 0x3C6DD0)),
                       (1, Color(hex: 0xFFD9A0))], in: .oklch)
```

<a name="gradient"></a>

### Gradient paint

A `Ramp` becomes paint through `Gradient`: `fill(_:)` and `stroke(_:)` take a gradient anywhere they take a color, on every shape. The gradient is a `Ramp` laid over the canvas by one of three geometries:

```swift
fill(.linear(from: Vector2(0, 0), to: Vector2(0, height), sky))   // start → end
fill(.radial(center: sun, radius: 260, [.white, .clear]))         // center → radius
stroke(.alongPath(heat))                                          // along the stroke
```

Each factory takes a `Ramp` or a plain `[Color]` list (spread evenly, mixed in OKLab by default; pass `in:` for another space). Coordinates are in drawing space, so a gradient rides the transform stack with the shapes it paints, and one gradient laid across many shapes shades them coherently. `t` clamps at the ends, and alpha rides the ramp, so fading a radial gradient to `.clear` makes a soft-edged glow.

`.alongPath` follows what it paints: on `drawLine`, `drawBezier`, `drawPolyline`, and stroked `drawShape` contours the ramp runs start → end by arc length (each contour runs its own 0…1); on a region shape, including its fill, it sweeps once around the shape's center, starting at 12 o'clock and turning clockwise, so a ring outline becomes a color wheel. A cyclic ramp (matching end colors) hides the seam where the sweep wraps.

`Paint` carries either kind as one value when you want a variable that's "a color or a gradient":

```swift
let paint: Paint = beat > 0 ? .gradient(.radial(center: c, radius: r, heat)) : .color(.white)
fill(paint)
```

The analytic SDF shapes (circles, rects, stars, lines, …) evaluate gradients per pixel, so they're exact at any size. The tessellated shapes (`drawPolygon`, `drawShape`, elliptical arcs, outline text) shade across their vertices instead: gradient strokes subdivide automatically so ramps track the path, but a fill is only sampled at its outline points, so a radial gradient centered *inside* a large polygon won't show its bullseye there. Where that matters, prefer an SDF shape. Vector export maps linear and radial gradients to native SVG gradients; an along-path stroke exports as short solid runs, and an along-path fill falls back to the ramp's midpoint color.

<a name="palette"></a>

### `Palette`

A discrete set of colors carried as a unit. `palette[i]` wraps in both directions (so any counter cycles it), `color(at:)` quantizes `0...1` into equal bands (a noise value picks a swatch), and `ramp(in:)` turns the set into a smooth interpolating `Ramp`.

```swift
let p = Palette(.red, Color(hex: 0x1B9E77), .white)
fill(p[frameCount / 30])                   // step through, wrapping
fill(p.color(at: noise(x * 0.01)))         // band-quantized
fill(p.ramp(in: .oklch).color(at: t))      // smooth
```

**Harmonies** build a palette from one base color, computed in OKLCH so the companions hold the base's lightness and chroma:

```swift
Palette.complementary(of: base)                         // base + opposite
Palette.splitComplementary(of: base, spread: 1.0 / 12)  // base + the pair flanking its opposite
Palette.triadic(of: base)                               // thirds of the wheel
Palette.analogous(of: base, count: 3, spread: 1.0 / 12) // neighbours centered on base
```

**Built-in sets**: the eight ColorBrewer qualitative palettes ship as data: `.set1`, `.set2`, `.set3`, `.paired`, `.pastel1`, `.pastel2`, `.dark2`, `.accent` (credited under [Influences & attribution](../../ATTRIBUTION.md#color)).

The `Harmonies` example follows a drifting base color through all four builders; `Swatchbook` lays out the built-in sets.

<a name="palette-files"></a>

### Loading palettes from a file

Palettes you collect elsewhere load with one call. `loadPalettes` returns every palette in a file, in file order; `loadPalette` returns the first. A file holding a single palette reads as a one-element array, so `loadPalettes` is the form to reach for when you don't know which you have.

```swift
let sets = loadPalettes("1000.json")     // many
let one  = loadPalette("sunset.hex")     // the first, or nil

// From the sketch's own bundle. `in:` has no default: a default would
// resolve to Ollin's bundle rather than yours.
let bundled = loadPalettes(resource: "palettes", withExtension: "csv", in: .module)
```

Five layouts read, and `.auto` picks between them by looking at the bytes:

| Format | Shape | Reads as |
|---|---|---|
| hex per line | `#69d2e7` on each line | one palette |
| CSV | `#69d2e7,#a7dbd8,#e0e4cc` per line | one palette per line |
| TSV | the same, tab separated | one palette per line |
| JSON | `[["#69d2e7", …], …]`, or a flat `["#69d2e7", …]`, or `[{"colors": […]}, …]` | many, or one |
| ASE | Adobe Swatch Exchange | one palette per swatch group |

The text formats share a parser, because they differ only in what separates the colors on a line. That has two consequences worth knowing. A file whose every line holds exactly one color is read as a single palette rather than a stack of one-color palettes, which is what makes hex-per-line work with no format argument. And a line that yields no colors at all is skipped, so a CSV header row or a line of prose falls away on its own.

Hex tokens survive the punctuation they pick up in the wild: surrounding quotes from a CSV cell, an `0x` prefix, and the `#RGB` / `#RGBA` / `#RRGGBB` / `#RRGGBBAA` digit forms `Color(hex:)` accepts.

Name a `PaletteFormat` when the guess goes wrong:

```swift
loadPalettes("swatches.txt", format: .hexLines)   // one palette, even with commas on a line
loadPalettes("grid.csv", format: .csv)
```

**ASE** files map swatch groups onto palettes, in document order. Colors that sit outside any group collect into a palette of their own. RGB, Gray, CMYK, and LAB swatches all decode (CMYK through the plain conversion, LAB through CIELAB on the D50 white point these files are written against). A truncated or malformed file yields an empty array rather than trapping, as every loader here does.

**Where to find palettes.** Ollin ships the loader, and bundles only palette data whose license permits it (the ColorBrewer sets above), the same way the bitmap-font loader ships beside one permissively licensed default rather than a library of fonts. A good source of ready-made palettes is [nice-color-palettes](https://github.com/Experience-Monks/nice-color-palettes), whose `100.json` / `1000.json` are exactly the JSON array-of-arrays shape above, so `curl` one into your sketch folder and `loadPalettes` reads it as is. Note that its palettes are scraped from COLOURlovers, whose default license is CC BY-NC-SA, which is why Ollin doesn't redistribute them: the MIT license on that repository covers its code, not the palette data. Fetching the file for your own work is your call to make; bundling it into an MIT framework is not.

That set is worth knowing for a second reason. Because so many people reached for it, its first palette (`#69d2e7`, `#a7dbd8`, `#e0e4cc`, `#f38630`, `#fa6900`) turns up in an enormous amount of generative art. If you want your work to look like itself, that is an argument for extracting a palette from an image you chose, or curating your own.

The `PaletteFile` example loads a CSV of six palettes and a hex-per-line file, side by side.

<a name="palette-extraction"></a>

### Extracting a palette from an image

The colors a picture is made of are usually a better palette than any list someone else curated.

```swift
let photo = loadImage("beach.jpg")!
let p = Palette(extractedFrom: photo, count: 5)
fill(p[0])                                     // the color the photo is mostly made of
```

The colors come back **most-used first**, so `p[0]` is the one you would name if asked. Clustering runs in OKLab rather than sRGB, because distance in sRGB is not distance to the eye: sRGB clusters split greens nobody can tell apart and merge blues everybody can.

It is **fully deterministic**. The same image, `count`, and `seed` always give the same palette, so an extracted palette is safe to snapshot and to carry in an export's recipe. Pass a different `seed` to shake the clustering out of a local minimum when a result looks off:

```swift
Palette(extractedFrom: photo, count: 6, seed: 3)
extractPalette(from: photo, count: 6)          // the same thing, as a bare call
```

Three behaviors to expect. Transparent pixels are ignored. An image with fewer distinct colors than `count` yields only the colors it has, rather than inventing filler. And a texture-backed image (a video frame, a Syphon feed) has no readable pixels, so it yields an empty palette; call `snapshot()` on the feed first.

Extraction is setup-time work, not per-frame work. A large image is sampled on an even grid rather than read whole, so cost is bounded, but clustering still runs Lloyd's algorithm over the samples. Extract in `setup()` and hold the result.

The `PaletteFromImage` example paints an image from five known colors and then recovers them from the pixels alone.

<a name="dithering"></a>

### Dithering an image to a palette

Extraction pulls the colors out of a picture. Dithering puts the picture back together in them.

```swift
let photo = loadImage("beach.jpg")!
let p = Palette(extractedFrom: photo, count: 6)
let poster = photo.dithered(.floydSteinberg, to: p)

drawImage(poster, in: bounds)
```

Snapping each pixel to its nearest palette color on its own gives flat bands where the picture was smooth. Dithering trades those bands for texture: it scatters the two colors that bracket each tone so the eye, blurring them together at normal viewing distance, reads the tone that was there before. Fewer colors, same picture.

The methods come in two families.

**Threshold maps** decide each pixel by its position alone, from a repeating tile. Each pixel dithers between the two palette colors whose mix best reproduces it: every pair is considered and scored perceptually, with a preference for quiet, low-contrast pairs, so a gray field near a saturated palette color mixes the colors that average to gray instead of tinting toward the loud neighbor.

- `.ordered(size:)` uses a Bayer matrix, `size` cells across (a power of two in `2...16`). It lays down the visible crosshatch of retro graphics. Larger sizes are finer and less obviously patterned.
- `.blueNoise` uses a 64×64 tile with no structure in it, giving an even, pattern-free grain. The tile is generated on first use and repeats seamlessly.

**Error diffusion** quantizes a pixel and pushes the leftover error onto the neighbors it has not reached yet, so each mistake is paid back nearby. It cannot run on the GPU (each pixel depends on the one before it), and it gives the organic, scattered look.

| Method | Character |
|---|---|
| `.floydSteinberg` | The classic. Four taps, sharp and detailed. |
| `.jarvisJudiceNinke` | Twelve taps over three rows. Smoother, softens fine detail. |
| `.stucki` | The Jarvis layout retuned. Cleaner, slightly sharper. |
| `.atkinson` | Passes on only three quarters of the error, so highlights and shadows blow out to clean white and black. |
| `.burkes` | Stucki without its bottom row. Fast, and close to it. |
| `.sierra`, `.twoRowSierra`, `.sierraLite` | Three rows, two rows, and the cheapest diffusion worth having. |

`.none` skips the dithering and just snaps to the nearest color, which is how you show someone what dithering is for.

There is a second form that quantizes to evenly spaced steps per channel instead of to a palette, the posterizing one:

```swift
photo.dithered(.atkinson, levels: 2)           // 8 colors: black, white, the primaries
photo.dithered(.ordered(size: 8), levels: 4)   // 64
```

Two knobs, each ignored by the family it does not apply to. `amount` (`0...1`) scales the grain of the threshold maps: at `1` they hold the image's tone exactly, and at `0` they band like `.none`. `serpentine` (on by default) reverses every other row of an error-diffusion scan, which breaks up the directional streaks a straight left-to-right pass leaves behind.

Dithering is per-pixel CPU work, like extraction. Do it in `setup()` and hold the result. Alpha passes through untouched, and a fully transparent pixel passes no error to its neighbors, so a cutout's invisible background never bleeds into the subject's edge. A texture-backed image (a video frame, a Syphon feed, an effects layer) has no readable pixels and comes back unchanged, so call `snapshot()` on it first. It is fully deterministic: the same image, method, and palette always give the same pixels, so a dithered result is safe to snapshot and to export.

If what you want is a cheap real-time dither over a whole layer rather than an exact quantization of an image, reach for the `.dither` and `.ditherDuo` [filters](Effects.md) instead. They run on the GPU, and they are a different tool.

The `Dithering` example reduces one painted gradient to four extracted colors six ways, side by side.

<a name="cosinepalette"></a>

### `CosinePalette`

A cyclic color gradient from Inigo Quilez's cosine formula: each channel is `a + b · cos(2π · (c · t + d))`. Build one from four `(r, g, b)` coefficient triples (center, amplitude, frequency, phase), then sample it.

```swift
let p = CosinePalette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                      c: (1.0, 1.0, 1.0), d: (0.0, 0.10, 0.20))
let c = p.color(at: t)        // t cycles; 0 and 1 meet for the defaults
```

Seven presets ship built in (Quilez's example palettes), named for how each reads:

`.rainbow`, `.dusk`, `.blush`, `.meadow`, `.sunset`, `.neon`, `.melon`.

```swift
fill(CosinePalette.sunset.color(at: time * 0.1))   // drift through the ramp over time
```

The `Palettes` example sweeps all seven. The formula is credited under [Influences & attribution](../../ATTRIBUTION.md#color).

<a name="colormap"></a>

### `Colormap`

Perceptual colormaps: smooth, perceptually even ramps that map a value in `0...1` to color, the standard choice for turning a number (a height, a density, a field value) into legible color. `color(at:)` linearly interpolates the 256-entry table and clamps `t`.

```swift
let t = noise(x * 0.01, y * 0.01)            // 0...1
fill(Colormap.magma.color(at: t))
```

Eight cases: `viridis`, `magma`, `inferno`, `plasma`, `cividis`, `turbo`, `rocket`, `mako`. The `Colormaps` example shows all eight. Data origins (matplotlib, Google, seaborn) are credited under [Influences & attribution](../../ATTRIBUTION.md#color).
