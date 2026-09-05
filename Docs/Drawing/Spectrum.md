#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Spectrum`</sup>

---

## Spectral color

A `Color` is three numbers chosen for the eye. A `Spectrum` is the physical curve those numbers stand in for. It holds visible light sampled from 380 to 780 nm, in 5 nm steps. Some things only work out right on the curve, and this page covers them. Pigments mix like paint, so yellow and blue meet in green. Colored glass filters the light that passes through it. You also get the pure hue of one wavelength and the glow of a heated body. The page ends with the three spectral GPU effects: a measured thin film, a diffraction grating, and paint mixing between layers.

### Contents

- [Spectrum](#spectrum)
- [Mixing like paint](#paint)
- [Filtering light](#filtering)
- [Wavelength and blackbody](#physical)
- [The spectral effects](#effects)

<a name="spectrum"></a>

### `Spectrum`

```swift
someColor.spectrum                 // the reflectance curve behind a color
spectrum.color                     // and back: the color it shows in daylight
Color(spectrum, alpha: 0.5)        // the initializer form; alpha rides along
Spectrum(samples: values)          // raw: 81 samples, 380...780 nm
spectrum.intensity(at: 550)        // interpolated between the 5 nm grid points
Spectrum.white                     // flat 1
Spectrum.black                     // flat 0
```

Read a curve as *reflectance in daylight*. `color.spectrum` builds the smooth reflectance curve that reproduces the color exactly under the standard daylight illuminant. The conversion back lights the curve the same way. The round trip is exact, so passing a color through a spectrum and back changes nothing. White is a flat curve of 1, black is a flat 0, and every in-gamut color sits between them. A spectrum a display cannot reach, such as a pure spectral line, comes back with the components below the display's gamut clipped to 0. Components above 1 survive, which is the same headroom every `Color` carries.

Inside, a color's curve is a blend of three fixed basis spectra, one per display primary. They come from the published spectral primary decomposition for sRGB. The data and the technique are credited under [Influences & attribution](../../ATTRIBUTION.md#color).

<a name="paint"></a>

### Mixing like paint

```swift
Color.mix(a, b, 0.5, in: .paint)          // pigment-wise, beside .rgb/.oklab/...
ink.mixed(with: other, 0.3, in: .paint)
spectrumA.mixedAsPaint(with: spectrumB, 0.5) // the typed form
Ramp([.yellow, .blue], in: .paint)           // a gradient through green
```

`.paint` is one more entry on the [`ColorSpace`](Color.md#mixing) menu. Each color becomes its reflectance spectrum, and the two mix wavelength by wavelength the way scattering pigments do, through the Kubelka-Munk model. Yellow and blue meet in green rather than gray, and complementary pairs mix into real darks. Every mix also darkens a little the way paint does, because pigments absorb light and never brighten each other. A `Ramp` in `.paint` gives gradients the same behavior, so a two-color gradient travels through the hue a painter would get.

The model has two edges worth knowing. Mixing is between *surfaces*, so components above 1 (HDR) read as full reflectance. A very dark, saturated paint acts as a strong absorber, so it drags a mix toward its own darkness. A near-black blue does exactly the same on a real palette.

<a name="filtering"></a>

### Filtering light

```swift
(glass.spectrum * light.spectrum).color   // colored light through colored glass
spectrum * 0.5                            // dim it evenly
spectrumA + spectrumB                     // light on top of light
```

`*` between two spectra filters one through the other. Each wavelength keeps the product of what both would pass, which is subtractive mixing. Yellow glass over cyan glass passes green. `+` adds light, and the scalar forms scale it.

<a name="physical"></a>

### Wavelength and blackbody

```swift
Color(wavelength: 550)         // the pure hue of one wavelength (nm)
Spectrum(wavelength: 590, width: 20)
Color(.blackbody(1800))        // candle orange
Spectrum.blackbody(6500)       // daylight-ish white
```

`Color(wavelength:)` gives the spectral locus, scaled to full brightness: 450 nm is blue, 550 green, 590 yellow, and 650 red. A single wavelength runs past what a display can show, so you get the nearest displayable hue. Sweep 400 to 700 for a physical rainbow. `Spectrum.blackbody(_:)` is the relative glow of a body heated to that temperature, from Planck's law. Useful temperatures are 1800 K for a candle, 3200 K for a lamp, 6500 K for daylight, and 12000 K for sky.

<a name="effects"></a>

### The spectral effects

Three GPU operations work per wavelength rather than per channel. Each one integrates over a set of wavelength taps sized by `quality`. They live in the effects catalog, and each entry there has the full story:

- [`.thinFilm(amount:thickness:variation:ior:scale:shift:quality:)`](Effects.md#filter) washes a layer with a *measured* interference film. `thickness` is in real nanometers, so the colors arrive in the true film color order. A thin film runs clear, and a thick one crowds into pastel. The styled sibling is `.iridescence`.
- [`.diffraction(amount:angle:orders:falloff:quality:)`](Effects.md#filter) streaks bright content into rainbow-split grating orders. Each order's reach grows with wavelength, so red lands farther than blue.
- [`.paintMix(amount:quality:)`](Effects.md#combined) blends two layers per pixel, the way `.paint` mixing on this page blends two colors. The aux layer's coverage gates the blend, so it works like a wash laid over a field.

```swift
drawImage(field.combined(with: wash, .paintMix(amount: 0.5)).image, 0, 0)
drawImage(scene.filtered(.thinFilm(thickness: 430, shift: time * 0.25)).image, 0, 0)
```

The `Effects/SoapFilm` example runs the film and the grating live. The `Color/Mixing` example draws `.paint` beside the other mixing spaces, band by band. The `Effects/PigmentMix` example lays one yellow wash over one blue field, combined both ways at once.

Related: the mixing spaces, ramps, and palettes this page extends are in [Color](Color.md). The full filter and combine catalog is in [Layered effects](Effects.md). The techniques and the bundled data behind the curves are credited under [Influences & attribution](../../ATTRIBUTION.md#color).
