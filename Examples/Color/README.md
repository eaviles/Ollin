#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Color</sup>

---

## Color

Palettes, colormaps, and driving color from a value or from time.

| Example | What it shows |
|---|---|
| [Colormaps](Colormaps/Sketch.swift) | the eight perceptual `Colormap` ramps as horizontal bands (value → color) |
| [ColorWaves](ColorWaves/Sketch.swift) | a row of sin-colored circles flowing with `time` |
| [Dithering](Dithering/Sketch.swift) | one painted gradient reduced to four extracted colors six ways: plain nearest-color, ordered Bayer, blue noise, and three error-diffusion kernels |
| [Gradients](Gradients/Sketch.swift) | gradient paint everywhere: a linear sky, a radial sun, along-path ramps on a Bézier and a polyline, a conic ring sweep, and per-vertex shading on a star and a curved shape |
| [Harmonies](Harmonies/Sketch.swift) | a drifting base color and its complementary / split-complementary / triadic / analogous palettes, plus the analogous set as a `Ramp` |
| [HSBWheel](HSBWheel/Sketch.swift) | a turning HSB color wheel (hue around, saturation outward), over a hex-literal backdrop |
| [Mixing](Mixing/Sketch.swift) | the same two colors mixed in RGB, HSB, OKLab, OKLCH, and OKHSL, band by band |
| [PaletteFile](PaletteFile/Sketch.swift) | palettes read off disk: a CSV of six, and a hex-per-line file of one, with no format declared |
| [PaletteFromImage](PaletteFromImage/Sketch.swift) | a palette clustered out of an image's pixels, recovering the five colors the picture was painted with |
| [Palettes](Palettes/Sketch.swift) | seven cosine-gradient `CosinePalette` presets, each swept across the canvas and scrolled |
| [PrintSeparation](PrintSeparation/Sketch.swift) | a sunrise poster split into three spot-ink printing masters, with a halftoned overprint preview and a view knob to flip between them |
| [Swatchbook](Swatchbook/Sketch.swift) | the built-in qualitative `Palette` sets as labeled swatch rows, with a wrapping-index highlight |

Run one with `swift run Example-Color-<Name>`, e.g. `swift run Example-Color-Palettes`.
