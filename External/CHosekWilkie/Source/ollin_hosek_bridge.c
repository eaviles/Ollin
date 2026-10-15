// Ollin's adapter over the vendored Hosek-Wilkie RGB model. See the header for the
// contract. This file is Ollin's own code; the model it calls into
// (ArHosekSkyModel.c and its RGB and solar datasets) is the vendored upstream under its
// own 3-clause BSD license (see ../LICENSE and ../README.md).

#include "ollin_hosek_bridge.h"
#include "ArHosekSkyModel.h"
#include <math.h>

// The upstream solar function and the model's terrestrial sun, from ArHosekSkyModel.c.
double arhosekskymodel_solar_radiance_internal2(ArHosekSkyModelState *state,
                                                double wavelength, double elevation,
                                                double gamma);
#define OLLIN_HOSEK_PI 3.141592653589793
#define OLLIN_HOSEK_SOLAR_RADIUS ((0.51 * OLLIN_HOSEK_PI / 180.0) / 2.0)

void ollin_hosek_rgb_configs(double turbidity, double albedo, double elevation,
                             double out_configs[27], double out_radiances[3]) {
    ArHosekSkyModelState *state =
        arhosek_rgb_skymodelstate_alloc_init(turbidity, albedo, elevation);
    for (int channel = 0; channel < 3; ++channel) {
        for (int i = 0; i < 9; ++i) {
            out_configs[channel * 9 + i] = state->configs[channel][i];
        }
        out_radiances[channel] = state->radiances[channel];
    }
    arhosekskymodelstate_free(state);
}

// The disc integral. A point on the disc sits at the cosine mu = sqrt(1 - sin^2(gamma)
// / sin^2(r)) the model's limb darkening is written in, and in mu the solid angle is
// 2 pi sin^2(r) mu / cos(gamma) dmu, so four Gauss-Legendre nodes on [0, 1] integrate
// the fifth-order limb polynomial exactly (1 / cos(gamma) departs from 1 by under 1e-5
// across the sun). Only the turbidity, the radius, and the emission correction are read
// from the state by the solar function, so those are all that is set.
double ollin_hosek_solar_irradiance(double turbidity, double elevation,
                                    double wavelength) {
    ArHosekSkyModelState state;
    state.turbidity = turbidity;
    state.solar_radius = OLLIN_HOSEK_SOLAR_RADIUS;
    for (int i = 0; i < 11; ++i) state.emission_correction_factor_sun[i] = 1.0;
    static const double nodes[4] = { 0.0694318442029737, 0.3300094782075719,
                                     0.6699905217924281, 0.9305681557970263 };
    static const double weights[4] = { 0.1739274225687269, 0.3260725774312731,
                                       0.3260725774312731, 0.1739274225687269 };
    const double sinR = sin(state.solar_radius);
    double sum = 0.0;
    for (int i = 0; i < 4; ++i) {
        double mu = nodes[i];
        double gamma = asin(sinR * sqrt(1.0 - mu * mu));
        double radiance = arhosekskymodel_solar_radiance_internal2(&state, wavelength,
                                                                   elevation, gamma);
        sum += weights[i] * radiance * mu / cos(gamma);
    }
    return 2.0 * OLLIN_HOSEK_PI * sinR * sinR * sum;
}
