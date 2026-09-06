#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Color</sup>

---

## Color

These examples cover palettes, colormaps, and color driven by a value or by time.

| Example | What it shows |
|---|---|
| [Colormaps](Colormaps/Sketch.swift) | the eight perceptual `Colormap` ramps drawn as horizontal bands that map a value to a color, with the seven cosine-gradient `CosinePalette` presets scrolling in a labeled section below |
| [ColorVision](ColorVision/Sketch.swift) | two palettes shown four ways, with a bar that marks every pair of colors that merge, and `Filter.colorVision` applied to the whole canvas when a parameter turns it on |
| [ColorWaves](ColorWaves/Sketch.swift) | a row of circles colored by a sine wave, with the circles flowing back and forth with `time` |
| [Dithering](Dithering/Sketch.swift) | one painted gradient reduced to four extracted colors in six ways: plain nearest-color, ordered Bayer, blue noise, and three error-diffusion kernels |
| [Gradients](Gradients/Sketch.swift) | gradient paint used throughout: a linear gradient for the sky, a radial gradient for the sun, ramps along the path of a Bézier and a polyline, a conic sweep around a ring, and per-vertex shading on a star and a curved shape |
| [Harmonies](Harmonies/Sketch.swift) | a base color that drifts, with its complementary, split-complementary, triadic, and analogous palettes, plus the analogous set drawn as a `Ramp` |
| [HSBWheel](HSBWheel/Sketch.swift) | a turning HSB color wheel, with hue running around the wheel and saturation growing outward, over a backdrop colored from a hex literal |
| [Mixing](Mixing/Sketch.swift) | the same two colors mixed in RGB, HSB, OKLab, OKLCH, OKHSL, and paint (Kubelka-Munk over spectra), one band per space, with each band's midpoint read back through `hue`, `saturation`, and `brightness` |
| [PaletteFile](PaletteFile/Sketch.swift) | palettes read from disk: a CSV file that holds six palettes, and a file with one hex color per line that holds one palette, loaded with no format declared |
| [PaletteFromImage](PaletteFromImage/Sketch.swift) | a palette built by clustering an image's pixels, which recovers the five colors the picture was painted with |
| [PrintSeparation](PrintSeparation/Sketch.swift) | a sunrise poster split into three spot-ink printing masters, with a halftoned overprint preview and a view parameter that switches between them |
| [SoftProof](SoftProof/Sketch.swift) | a poster converted into a press profile and back before it is printed, so the colors the ink cannot reproduce show up changed on screen, next to the gamut check and the process plates |
| [Swatchbook](Swatchbook/Sketch.swift) | the built-in qualitative `Palette` sets drawn as labeled swatch rows, with a highlight driven by a wrapping index |

Run one with `swift run Example-Color-<Name>`, for example `swift run Example-Color-Colormaps`.
