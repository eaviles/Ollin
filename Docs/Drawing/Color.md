#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Color`</sup>

---

## Color

`Color` is an RGBA color with `Double` components in `0...1`. Most of the types below map a single number to a `Color` through the same `color(at:)` call — `Ramp`, `CosinePalette`, and `Colormap` smoothly, the discrete `Palette` in steps — which is the usual way to drive color from a value or from time.

### Contents

- [Color](#color)
- [OKLab, OKLCH, OKHSL](#oklab)
- [Mixing](#mixing)
- [Ramp](#ramp)
- [Gradient paint](#gradient)
- [Palette](#palette)
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

**Hex** comes in two forms. The integer form is the one for literals in code — compile-checked, nothing to parse, never optional. An integer carries no digit count (`0xFFF` and `0x000FFF` are the same value), so it's always six digits of RGB, with alpha as its own parameter:

```swift
background(Color(hex: 0x14171C))
fill(Color(hex: 0xFF0066, alpha: 0.5))
```

The string form takes the full grammar — `"#RGB"`, `"#RGBA"`, `"#RRGGBB"`, `"#RRGGBBAA"`, the `#` optional, case-insensitive — and returns an optional, so a string from a file or the network fails cleanly instead of trapping:

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

<a name="oklab"></a>

### OKLab, OKLCH, OKHSL

Three views of one perceptual model, each a small value type that converts to and from `Color` (alpha stays on the `Color`):

```swift
OKLab(l:a:b:)     OKLab(_ color: Color)     Color(_ lab: OKLab, alpha: Double = 1)
OKLCH(l:c:h:)     OKLCH(_ color: Color)     Color(_ lch: OKLCH, alpha: Double = 1)
OKHSL(h:s:l:)     OKHSL(_ color: Color)     Color(_ hsl: OKHSL, alpha: Double = 1)
```

- **`OKLab`** is the workhorse for color *math*: `l` is perceived lightness in `0...1`, `a` runs green → red and `b` runs blue → yellow. Mixing through it comes out visually even.
- **`OKLCH`** is OKLab in polar form — lightness, chroma, hue — the space for hue and chroma *dials*: turning `h` leaves lightness and colorfulness alone. The maximum displayable chroma depends on hue and lightness, so a dialed-up `c` can ask for colors the screen can't show; converting to `Color` maps those back by reducing chroma at constant lightness and hue, so the color stays itself, just as vivid as sRGB allows.
- **`OKHSL`** squeezes the same model into the sRGB gamut: `s` and `l` run `0...1` and every combination is displayable — the space for *generated* color ("random hue, same perceived lightness").

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

Interpolates between two colors in a chosen space: `.rgb`, `.hsb`, `.oklab` (the default — perceptually even), `.oklch` (holds hue identity, arcs through chroma), or `.okhsl`. `t` clamps to `0...1` and alpha interpolates linearly. In the polar spaces hue takes the shortest way around the wheel, and an achromatic endpoint (gray, black, white) adopts the other color's hue, so a fade to white doesn't detour through unrelated hues.

```swift
let warm = Color(hex: 0xFF5500)
let cool = Color(hex: 0x0066FF)
fill(Color.mix(warm, cool, t: sin(time) * 0.5 + 0.5))
```

The `Mixing` example draws the same two colors mixed in all five spaces, band by band. The OKLab family and the gamut mapping are credited under [Influences & attribution](../../ATTRIBUTION.md#color).

<a name="ramp"></a>

### `Ramp`

A gradient built from a list of colors — spread evenly, or placed with explicit stops — sampled with `color(at:)`. Interpolation runs through a chosen `ColorSpace` (OKLab by default, which blends evenly), and `t` clamps to the ends. Two stops sharing a position make a hard edge.

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

Each factory takes a `Ramp` or a plain `[Color]` list (spread evenly, mixed in OKLab by default — pass `in:` for another space). Coordinates are in drawing space, so a gradient rides the transform stack with the shapes it paints, and one gradient laid across many shapes shades them coherently. `t` clamps at the ends, and alpha rides the ramp — fading a radial gradient to `.clear` makes a soft-edged glow.

`.alongPath` follows what it paints: on `drawLine`, `drawBezier`, `drawPolyline`, and stroked `drawShape` contours the ramp runs start → end by arc length (each contour runs its own 0…1); on a region shape — including its fill — it sweeps once around the shape's center, starting at 12 o'clock and turning clockwise, so a ring outline becomes a color wheel. A cyclic ramp (matching end colors) hides the seam where the sweep wraps.

`Paint` carries either kind as one value when you want a variable that's "a color or a gradient":

```swift
let paint: Paint = beat > 0 ? .gradient(.radial(center: c, radius: r, heat)) : .color(.white)
fill(paint)
```

The analytic SDF shapes (circles, rects, stars, lines, …) evaluate gradients per pixel, so they're exact at any size. The tessellated shapes (`drawPolygon`, `drawShape`, elliptical arcs, outline text) shade across their vertices instead: gradient strokes subdivide automatically so ramps track the path, but a fill is only sampled at its outline points — a radial gradient centered *inside* a large polygon won't show its bullseye there. Where that matters, prefer an SDF shape. Vector export maps linear and radial gradients to native SVG gradients; an along-path stroke exports as short solid runs, and an along-path fill falls back to the ramp's midpoint color.

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

Perceptual colormaps: smooth, perceptually-even ramps that map a value in `0...1` to color, the standard choice for turning a number (a height, a density, a field value) into legible color. `color(at:)` linearly interpolates the 256-entry table and clamps `t`.

```swift
let t = noise(x * 0.01, y * 0.01)            // 0...1
fill(Colormap.magma.color(at: t))
```

Eight cases: `viridis`, `magma`, `inferno`, `plasma`, `cividis`, `turbo`, `rocket`, `mako`. The `Colormaps` example shows all eight. Data origins (matplotlib, Google, seaborn) are credited under [Influences & attribution](../../ATTRIBUTION.md#color).
