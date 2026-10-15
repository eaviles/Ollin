#ifndef OLLIN_HOSEK_BRIDGE_H
#define OLLIN_HOSEK_BRIDGE_H

// Ollin's thin adapter over the vendored Hosek-Wilkie RGB sky model. The model's
// quality lives in a precomputed coefficient dataset; turning a (turbidity, ground
// albedo, sun elevation) triple into the per-channel sky configuration is the step
// that reads that dataset, and it runs once on the CPU. This function does exactly
// that and copies the result out flat, so the caller needn't traverse the upstream
// state struct's fixed-size C arrays. The per-texel sky radiance is then evaluated
// on the GPU from these coefficients (see ShaderIBL.metal: ollin_ibl_sky_gen).
//
// out_configs:   27 doubles = 3 channels (R,G,B) x 9 coefficients (channel-major:
//                out_configs[channel * 9 + i]).
// out_radiances:  3 doubles = the per-channel radiance scale (R, G, B).
//
// turbidity 1..10, albedo 0..1, elevation in radians above the horizon (0..pi/2).
void ollin_hosek_rgb_configs(double turbidity, double albedo, double elevation,
                             double out_configs[27], double out_radiances[3]);

// The sun's beam: the model's solar radiance function (published in spectral form
// only) integrated over the solar disc, so the result is the spectral irradiance the
// disc delivers to a surface facing it, in W / (m^2 * nm). The function varies across
// the disc with limb darkening, so one sample at its center would misstate the power;
// the integral is exact. The caller integrates the spectrum against the color-matching
// curves for a color in the sky's own unit.
//
// turbidity 1..10, elevation in radians above the horizon (0..pi/2), wavelength in
// nanometers within the model's range (320..720).
double ollin_hosek_solar_irradiance(double turbidity, double elevation,
                                    double wavelength);

#endif /* OLLIN_HOSEK_BRIDGE_H */
