// Ollin's adapter over the vendored Hosek-Wilkie RGB model. See the header for the
// contract. This file is Ollin's own code; the model it calls into
// (ArHosekSkyModel.c / ArHosekSkyModelData_RGB.h) is the vendored upstream under its
// own 3-clause BSD license (see ../LICENSE and ../README.md).

#include "ollin_hosek_bridge.h"
#include "ArHosekSkyModel.h"

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
