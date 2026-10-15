# CHosekWilkie: vendored Hosek-Wilkie sky model (RGB path and solar radiance)

This directory contains the coefficient dataset and configuration code of the
**Hosek-Wilkie analytic sky-dome model**, used by Ollin's procedural-sky
environment (`Environment.sky(...)`). The model turns a `(turbidity, ground
albedo, sun elevation)` triple into per-channel sky coefficients on the CPU
(the step that needs the dataset); Ollin's own Metal shader then evaluates the
sky radiance per texel from those coefficients. The model's solar radiance
function gives the sun's beam for the same turbidity and elevation, which Ollin
integrates over the solar disc and the CIE observer for the light the sky's sun
casts. It is wrapped behind Ollin's own
API (`ollin_hosek_rgb_configs`, `ollin_hosek_solar_irradiance`); the upstream `arhosek_*` symbols are not part of
Ollin's public surface.

This is bundled third-party source, not an Ollin-authored component. Its license
is separate from Ollin's MIT license (see the repo-root `THIRD-PARTY-NOTICES.md`).

## Provenance

- **Upstream:** https://github.com/mmp/pbrt-v3 (`src/ext`), the widely mirrored
  reference implementation by Lukas Hosek and Alexander Wilkie (Charles
  University), v1.4a.
- **Papers:** "An Analytic Model for Full Spectral Sky-Dome Radiance"
  (SIGGRAPH 2012) and "Adding a Solar-Radiance Function to the Hosek-Wilkie
  Skylight Model" (IEEE CG&A 2013).
- **Date:** 2026-06-25 (the RGB path); 2026-10-14 (the solar radiance function
  and its datasets, from the same upstream files)
- **License:** 3-clause BSD, © 2012-2013 Lukas Hosek and Alexander Wilkie (see
  `LICENSE`).

## What is vendored, and the one modification

- `Source/ArHosekSkyModel.h`: the upstream header, **verbatim** (BSD + the
  per-file attribution comment intact).
- `Source/ArHosekSkyModelData_RGB.h`: the upstream RGB coefficient dataset,
  **verbatim**.
- `Source/ArHosekSkyModel.c`: the upstream source **trimmed to the RGB path
  and the solar radiance function**. The spectral and CIE-XYZ sky-dome models,
  the alien-world functions, and their (large) coefficient datasets were
  removed. The six RGB functions and the two solar-radiance internals
  (`arhosekskymodel_sr_internal`, `arhosekskymodel_solar_radiance_internal2`)
  that remain are reproduced byte-for-byte from the original; the
  BSD/attribution header is kept intact, and a `NOTE (Ollin)` block records the
  trim. The trim keeps the bundle small (the unused spectral sky dataset dwarfs
  the RGB one) and is permitted by the BSD license (modification, with the
  notice retained).
- `Source/ArHosekSkyModelData_Solar.h`: the upstream
  `ArHosekSkyModelData_Spectral.h` **trimmed to its solar-radiance and
  limb-darkening datasets** (`solarDataset320` through `limbDarkeningDatasets`,
  the end of the upstream file), reproduced byte-for-byte, with the upstream
  license and attribution comment kept and a `NOTE (Ollin)` block recording the
  trim. Added 2026-10-14 from the same upstream file set.

The following are **Ollin's own** thin adapter, not upstream:

- `Include/ollin_hosek_bridge.h`, `Source/ollin_hosek_bridge.c`: flatten the
  per-channel configuration so Swift needn't traverse the upstream state struct's
  fixed-size C arrays, and integrate the solar radiance function over the solar
  disc (four Gauss-Legendre nodes in the limb-darkening cosine, exact for the
  model's fifth-order limb polynomial). This is the only public header of the
  module.

## Updating

Re-fetch the upstream files, re-apply the RGB and solar trim to the `.c` and
the solar trim to the spectral dataset (or re-run the extraction the original
commits used), and update the date above. Keep the license header and the
`NOTE (Ollin)` block.
