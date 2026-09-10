#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Color</sup>

---

## Color

These examples cover palettes, colormaps, and color driven by a value or by time.

| [![ColorVision](https://media.ollin.art/examples/Color/ColorVision/still-640.jpg?v=576f2f37)](ColorVision/) | [![ColorWaves](https://media.ollin.art/examples/Color/ColorWaves/still-640.jpg?v=c29d2429)](ColorWaves/) | [![Colormaps](https://media.ollin.art/examples/Color/Colormaps/still-640.jpg?v=4e06b898)](Colormaps/) | [![Dithering](https://media.ollin.art/examples/Color/Dithering/still-640.jpg?v=0d647cc9)](Dithering/) |
|---|---|---|---|
| [ColorVision](ColorVision/) | [ColorWaves](ColorWaves/) | [Colormaps](Colormaps/) | [Dithering](Dithering/) |
| [![Gradients](https://media.ollin.art/examples/Color/Gradients/still-640.jpg?v=ce8739f0)](Gradients/) | [![HSBWheel](https://media.ollin.art/examples/Color/HSBWheel/still-640.jpg?v=ec947957)](HSBWheel/) | [![Harmonies](https://media.ollin.art/examples/Color/Harmonies/still-640.jpg?v=4908872e)](Harmonies/) | [![Mixing](https://media.ollin.art/examples/Color/Mixing/still-640.jpg?v=9d733025)](Mixing/) |
| [Gradients](Gradients/) | [HSBWheel](HSBWheel/) | [Harmonies](Harmonies/) | [Mixing](Mixing/) |
| [![PaletteFile](https://media.ollin.art/examples/Color/PaletteFile/still-640.jpg?v=baf88afa)](PaletteFile/) | [![PaletteFromImage](https://media.ollin.art/examples/Color/PaletteFromImage/still-640.jpg?v=3f3d36fc)](PaletteFromImage/) | [![PrintSeparation](https://media.ollin.art/examples/Color/PrintSeparation/still-640.jpg?v=4aad09ce)](PrintSeparation/) | [![SoftProof](https://media.ollin.art/examples/Color/SoftProof/still-640.jpg?v=768b9eef)](SoftProof/) |
| [PaletteFile](PaletteFile/) | [PaletteFromImage](PaletteFromImage/) | [PrintSeparation](PrintSeparation/) | [SoftProof](SoftProof/) |
| [![Swatchbook](https://media.ollin.art/examples/Color/Swatchbook/still-640.jpg?v=581862c5)](Swatchbook/) |  |  |  |
| [Swatchbook](Swatchbook/) |  |  |  |

| Example | What it shows |
|---|---|
| [Colormaps](Colormaps/Sketch.swift) | the eight perceptual `Colormap` ramps drawn as horizontal bands that map a value to a color, with the seven cosine-gradient `CosinePalette` presets scrolling in a labeled section below |
| [ColorVision](ColorVision/Sketch.swift) | a photograph of woven blankets and two palettes shown four ways, with a bar that marks every pair of colors that merge, and `Filter.colorVision` applied to the whole canvas when a parameter turns it on |
| [ColorWaves](ColorWaves/Sketch.swift) | a row of circles colored by a sine wave, with the circles flowing back and forth with `time` |
| [Dithering](Dithering/Sketch.swift) | a bundled photograph reduced to four extracted colors in six ways: plain nearest-color, ordered Bayer, blue noise, and three error-diffusion kernels |
| [Gradients](Gradients/Sketch.swift) | gradient paint used throughout: a linear gradient for the sky, a radial gradient for the sun, ramps along the path of a Bézier and a polyline, a conic sweep around a ring, and per-vertex shading on a star and a curved shape |
| [Harmonies](Harmonies/Sketch.swift) | a base color that drifts, with its complementary, split-complementary, triadic, and analogous palettes, plus the analogous set drawn as a `Ramp` |
| [HSBWheel](HSBWheel/Sketch.swift) | a turning HSB color wheel, with hue running around the wheel and saturation growing outward, over a backdrop colored from a hex literal |
| [Mixing](Mixing/Sketch.swift) | the same two colors mixed in RGB, HSB, OKLab, OKLCH, OKHSL, and paint (Kubelka-Munk over spectra), one band per space, with each band's midpoint read back through `hue`, `saturation`, and `brightness` |
| [PaletteFile](PaletteFile/Sketch.swift) | palettes read from disk: a CSV file that holds six palettes, and a file with one hex color per line that holds one palette, loaded with no format declared |
| [PaletteFromImage](PaletteFromImage/Sketch.swift) | a palette built by clustering a bundled photograph's pixels, a woman before a wall of marigolds, most-used color first |
| [PrintSeparation](PrintSeparation/Sketch.swift) | a sunrise poster split into three spot-ink printing masters, with a halftoned overprint preview and a view parameter that switches between them |
| [SoftProof](SoftProof/Sketch.swift) | a poster converted into a press profile and back before it is printed, so the colors the ink cannot reproduce show up changed on screen, next to the gamut check and the process plates |
| [Swatchbook](Swatchbook/Sketch.swift) | the built-in qualitative `Palette` sets drawn as labeled swatch rows, with a highlight driven by a wrapping index |

Run one with `swift run Example-Color-<Name>`, for example `swift run Example-Color-Colormaps`.
