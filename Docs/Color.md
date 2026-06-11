#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Color`</sup>

---

## Color

`Color` is an RGBA color with `Double` components in `0...1`. Palettes and colormaps below both map a single number to a `Color`, which is the usual way to drive color from a value or from time.

### Contents

- [Color](#color)
- [OKLab, OKLCH, OKHSL](#oklab)
- [Mixing](#mixing)
- [Palette](#palette)
- [Colormap](#colormap)

<a name="color"></a>

### `Color`

```swift
Color(red: Double, green: Double, blue: Double, alpha: Double = 1)
Color(white: Double, alpha: Double = 1)
Color(hex: UInt32, alpha: Double = 1)     // 24-bit RGB: Color(hex: 0xFF0066)
Color(hex: String)                        // "#RGB" "#RGBA" "#RRGGBB" "#RRGGBBAA" → Color?
Color(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1)
```

Named constants: `.white`, `.black`, `.gray`, `.red`, `.green`, `.blue`, `.clear`.

```swift
background(.white)
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

<a name="oklab"></a>

### OKLab, OKLCH, OKHSL

Three views of one perceptual model, each a small value type that converts to and from `Color` (alpha stays on the `Color`):

```swift
OKLab(l:a:b:)     OKLab(_ color: Color)     Color(_ lab: OKLab, alpha: 1)
OKLCH(l:c:h:)     OKLCH(_ color: Color)     Color(_ lch: OKLCH, alpha: 1)
OKHSL(h:s:l:)     OKHSL(_ color: Color)     Color(_ hsl: OKHSL, alpha: 1)
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

The `Mixing` example draws the same two colors mixed in all five spaces, band by band. The OKLab family and the gamut mapping are credited under [Influences & attribution](../README.md#influences--attribution).

### `Palette`

A cyclic color gradient from Inigo Quilez's cosine formula: each channel is `a + b · cos(2π · (c · t + d))`. Build one from four `(r, g, b)` coefficient triples (center, amplitude, frequency, phase), then sample it.

```swift
let p = Palette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                c: (1.0, 1.0, 1.0), d: (0.0, 0.10, 0.20))
let c = p.color(at: t)        // t cycles; 0 and 1 meet for the defaults
```

Seven presets ship built in (Quilez's example palettes), named for how each reads:

`.rainbow`, `.dusk`, `.blush`, `.meadow`, `.sunset`, `.neon`, `.melon`.

```swift
fill(Palette.sunset.color(at: time * 0.1))   // drift through the ramp over time
```

The `Palettes` example sweeps all seven. The formula is credited under [Influences & attribution](../README.md#influences--attribution).

<a name="colormap"></a>

### `Colormap`

Perceptual colormaps: smooth, perceptually-even ramps that map a value in `0...1` to color, the standard choice for turning a number (a height, a density, a field value) into legible color. `color(at:)` linearly interpolates the 256-entry table and clamps `t`.

```swift
let t = noise(x * 0.01, y * 0.01)            // 0...1
fill(Colormap.magma.color(at: t))
```

Eight cases: `viridis`, `magma`, `inferno`, `plasma`, `cividis`, `turbo`, `rocket`, `mako`. The `Colormaps` example shows all eight. Data origins (matplotlib, Google, seaborn) are credited under [Influences & attribution](../README.md#influences--attribution).
