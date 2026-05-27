#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Color`</sup>

---

### Color

`Color` is an RGBA color with `Double` components in `0...1`. Palettes and colormaps below both map a single number to a `Color`, which is the usual way to drive color from a value or from time.

### Example

```swift
fill(Color(red: 0.2, green: 0.5, blue: 0.9))
fill(Palette.sunset.color(at: time * 0.1))
fill(Colormap.viridis.color(at: t))
```

### Contents

- [Color](#color)
- [Palette](#palette)
- [Colormap](#colormap)

<a name="color"></a>

### `Color`

```swift
Color(red: Double, green: Double, blue: Double, alpha: Double = 1)
Color(white: Double, alpha: Double = 1)
```

Named constants: `.white`, `.black`, `.gray`, `.red`, `.green`, `.blue`, `.clear`.

<a name="palette"></a>

### `Palette`

A cyclic color gradient from Inigo Quilez's cosine formula: each channel is `a + b · cos(2π · (c · t + d))`. Build one from four `(r, g, b)` coefficient triples (center, amplitude, frequency, phase), then sample it.

```swift
let p = Palette(a: (0.5, 0.5, 0.5), b: (0.5, 0.5, 0.5),
                c: (1.0, 1.0, 1.0), d: (0.0, 0.10, 0.20))
let c = p.color(at: t)        // t cycles; 0 and 1 meet for the defaults
```

Seven presets ship built in (Quilez's example palettes), named for how each reads:

`.rainbow`, `.dusk`, `.blush`, `.meadow`, `.sunset`, `.neon`, `.melon`.

The `Palettes` example sweeps all seven. The formula is credited under [Influences & attribution](../README.md#influences--attribution).

<a name="colormap"></a>

### `Colormap`

Perceptual colormaps: smooth, perceptually-even ramps that map a value in `0...1` to color, the standard choice for turning a number (a height, a density, a field value) into legible color. `color(at:)` linearly interpolates the 256-entry table and clamps `t`.

```swift
fill(Colormap.magma.color(at: t))
```

Eight cases: `viridis`, `magma`, `inferno`, `plasma`, `cividis`, `turbo`, `rocket`, `mako`. The `Colormaps` example shows all eight. Data origins (matplotlib, Google, seaborn) are credited under [Influences & attribution](../README.md#influences--attribution).
