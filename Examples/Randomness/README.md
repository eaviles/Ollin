#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Randomness</sup>

---

## Randomness

`random`, Perlin `noise`, and the scatter helpers, all seedable for reproducible runs.

| Example | What it shows |
|---|---|
| [NoiseField](NoiseField/Sketch.swift) | an 80×80 grid shaded by 3D Perlin `noise`, scrubbed by the mouse |
| [RandomBand](RandomBand/Sketch.swift) | a band of dots jittered by `random` (jagged); re-rolls with the mouse |
| [Gaussian](Gaussian/Sketch.swift) | 2000 dots a frame placed by `randomGaussian`: the bell curve made visible |
| [Ring](Ring/Sketch.swift) | dots scattered in an annulus by `ring()`, `scale`-relative so it holds its proportion |
| [NoiseWave](NoiseWave/Sketch.swift) | a wave of dots offset by `signedNoise` (smooth); the noise counterpart |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-NoiseField`.
