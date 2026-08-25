// Spectral data tables for Ollin's spectral color support.
//
// Data source: the reference implementation for Mallett & Yuksel,
// "Spectral Primary Decomposition for Rendering with sRGB Reflectance"
// (EGSR 2019), https://github.com/geometrian/simple-spectral (MIT).
// Values are verbatim from that repository's data/ CSV files, reformatted
// as C arrays; see this directory's README.md for provenance and LICENSE
// for the license text.
//
// All arrays sample 380 nm to 780 nm inclusive, in 5 nm steps (81 values):
//   - ollin_spectral_basis_{r,g,b}: the three BT.709 spectral primaries.
//     A reflectance spectrum for linear sRGB (r, g, b) is
//     r * basis_r + g * basis_g + b * basis_b; the basis is a partition of
//     unity, so (1, 1, 1) gives a flat spectrum of 1.
//   - ollin_spectral_{x,y,z}bar: the CIE 1931 2-degree standard observer.
//   - ollin_spectral_d65: the CIE D65 illuminant, relative spectral power.

#ifndef OLLIN_SPECTRAL_DATA_H
#define OLLIN_SPECTRAL_DATA_H

#define OLLIN_SPECTRAL_SAMPLE_COUNT 81
#define OLLIN_SPECTRAL_LAMBDA_MIN 380.0
#define OLLIN_SPECTRAL_LAMBDA_STEP 5.0

extern const double ollin_spectral_basis_r[OLLIN_SPECTRAL_SAMPLE_COUNT];
extern const double ollin_spectral_basis_g[OLLIN_SPECTRAL_SAMPLE_COUNT];
extern const double ollin_spectral_basis_b[OLLIN_SPECTRAL_SAMPLE_COUNT];
extern const double ollin_spectral_xbar[OLLIN_SPECTRAL_SAMPLE_COUNT];
extern const double ollin_spectral_ybar[OLLIN_SPECTRAL_SAMPLE_COUNT];
extern const double ollin_spectral_zbar[OLLIN_SPECTRAL_SAMPLE_COUNT];
extern const double ollin_spectral_d65[OLLIN_SPECTRAL_SAMPLE_COUNT];

#endif
