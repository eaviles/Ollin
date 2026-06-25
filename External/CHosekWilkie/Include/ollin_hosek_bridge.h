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

#endif /* OLLIN_HOSEK_BRIDGE_H */
