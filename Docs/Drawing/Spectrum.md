#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Spectrum`</sup>

---

## Spectral color

A `Color` is three numbers chosen for the eye. A `Spectrum` is the physical curve those numbers stand in for: visible light sampled from 380 to 780 nm, in 5 nm steps. Some things only work out right on the curve, and this page is the door to them: pigments that mix like paint (yellow and blue meeting in green), light filtered through colored glass, the pure hue of one wavelength, the glow of a heated body, and the three spectral GPU effects (a measured thin film, a diffraction grating, and paint mixing between layers).

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

The reading is *reflectance in daylight*: `color.spectrum` builds the smooth reflectance curve that reproduces the color exactly when lit by the standard daylight illuminant, and the conversion back lights the curve the same way. The round trip is exact, so passing a color through a spectrum and back changes nothing. White is a flat curve of 1, black a flat 0, and every in-gamut color sits between them. A spectrum a display can't reach (a pure spectral line) comes back with the components below the display's gamut clipped to 0; components above 1 survive, the same headroom every `Color` carries.

Under the hood a color's curve is a blend of three fixed basis spectra, one per display primary, from the published spectral primary decomposition for sRGB; the data and technique are credited under [Influences & attribution](../../ATTRIBUTION.md#color).

<a name="paint"></a>

### Mixing like paint

```swift
Color.mix(a, b, 0.5, in: .paint)          // pigment-wise, beside .rgb/.oklab/...
ink.mixed(with: other, 0.3, in: .paint)
spectrumA.mixedAsPaint(with: spectrumB, 0.5) // the typed form
Ramp([.yellow, .blue], in: .paint)           // a gradient through green
```

`.paint` joins the [`ColorSpace`](Color.md#mixing) menu: each color becomes its reflectance spectrum and the two mix the way scattering pigments do (the Kubelka-Munk model), wavelength by wavelength. Yellow and blue meet in green rather than gray, complementary pairs mix into real darks, and every mix darkens a little the way paint does, because pigments absorb and never brighten each other. A `Ramp` in `.paint` gives gradients the same behavior, so a two-color gradient travels through the hue a painter would get.

Two honest edges of the model: mixing is between *surfaces*, so components above 1 (HDR) read as full reflectance, and a very dark, saturated paint acts like a strong absorber, dragging a mix toward its own darkness, exactly as a near-black blue does on a real palette.

<a name="filtering"></a>

### Filtering light

```swift
(glass.spectrum * light.spectrum).color   // colored light through colored glass
spectrum * 0.5                            // dim it evenly
spectrumA + spectrumB                     // light on top of light
```

`*` between two spectra is filtering: each wavelength keeps the product of what both would pass, which is subtractive mixing. Yellow glass over cyan glass passes green. `+` adds light, and the scalar forms scale it.

<a name="physical"></a>

### Wavelength and blackbody

```swift
Color(wavelength: 550)         // the pure hue of one wavelength (nm)
Spectrum(wavelength: 590, width: 20)
Color(.blackbody(1800))        // candle orange
Spectrum.blackbody(6500)       // daylight-ish white
```

`Color(wavelength:)` is the spectral locus: 450 nm blue, 550 green, 590 yellow, 650 red, scaled to full brightness (a single wavelength runs past what a display can show, so this is the nearest displayable hue). Sweep 400 to 700 for a physical rainbow. `Spectrum.blackbody(_:)` is the relative glow of a body heated to that temperature (Planck's law): 1800 K candle, 3200 K lamp, 6500 K daylight, 12000 K sky.

<a name="effects"></a>

### The spectral effects

Three GPU operations work per wavelength rather than per channel, integrating over a `quality`-sized set of wavelength taps. They live in the effects catalog; each entry there has the full story:

- [`.thinFilm(amount:thickness:variation:ior:scale:shift:quality:)`](Effects.md#filter) washes a layer with a *measured* interference film: `thickness` is real nanometers, so the colors arrive in the true film color order, thin runs clear, and a thick film crowds into pastel. (The styled sibling is `.iridescence`.)
- [`.diffraction(amount:angle:orders:falloff:quality:)`](Effects.md#filter) streaks bright content into rainbow-split grating orders, each order's reach growing with wavelength, so red lands farther than blue.
- [`.paintMix(amount:quality:)`](Effects.md#combined) blends two layers the way this page's `.paint` mixing blends two colors, per pixel, gated by the aux layer's coverage: a wash laid over a field.

```swift
drawImage(field.combined(with: wash, .paintMix(amount: 0.5)).image, 0, 0)
drawImage(scene.filtered(.thinFilm(thickness: 430, shift: time * 0.25)).image, 0, 0)
```

The `Effects/SoapFilm` example runs the film and the grating live, and the `Color/Mixing` example draws `.paint` beside the other mixing spaces, band by band.

Related: [Color](Color.md) for the mixing spaces, ramps, and palettes this page extends; [Layered effects](Effects.md) for the full filter and combine catalog; [Influences & attribution](../../ATTRIBUTION.md#color) for the techniques and the bundled data behind the curves.
