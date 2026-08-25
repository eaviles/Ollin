# CSpectralData: vendored spectral color data

Data tables for Ollin's spectral color support (`Spectrum`, paint mixing, and
the spectral filters). All arrays sample 380 nm to 780 nm inclusive in 5 nm
steps (81 values):

- `ollin_spectral_basis_{r,g,b}`: the three BT.709 spectral primaries from
  Agatha Mallett and Cem Yuksel, *Spectral Primary Decomposition for Rendering
  with sRGB Reflectance* (Eurographics Symposium on Rendering, 2019). A
  reflectance spectrum for a linear sRGB triple is
  `r * basis_r + g * basis_g + b * basis_b`; the basis is a partition of unity
  (the three curves sum to 1 at every wavelength), so white is a flat spectrum
  of 1 and the input color is reproduced exactly under D65.
- `ollin_spectral_{x,y,z}bar`: the CIE 1931 2° standard observer.
- `ollin_spectral_d65`: the CIE D65 illuminant, relative spectral power.

## Provenance

- **Upstream:** https://github.com/geometrian/simple-spectral, the reference
  implementation published with the paper, by its first author.
- **Commit:** `4b36e4d055d84c35e35549c4fbda1906ce060e7d` (2020-07-19).
- **Files taken:** `data/cie1931-basis-bt709-380+5+780.csv`,
  `data/cie1931-xyzbar-380+5+780.csv`, and rows 380-780 of
  `data/d65-300+5+780.csv`. Values are verbatim; the only transformation is
  reformatting the CSV columns as C arrays (`Source/ollin_spectral_data.c`).
- **License:** MIT, full text in [`LICENSE`](LICENSE).

## How Ollin uses it

`Spectrum` (in `Sources/Ollin/Color/`) reads these arrays once and derives
everything else on the CPU: the illuminant-weighted observer, and the measured
basis-to-XYZ matrix whose inverse makes a color-to-spectrum-to-color round trip
exact to floating-point rounding. GPU passes never see the tables; they receive
a small set of per-wavelength-tap constants cooked from them per frame setup.
The C symbols stay off Ollin's public surface.
