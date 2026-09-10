#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Randomness</sup>

---

## Randomness

`random`, Perlin `noise`, and the scatter helpers. All of them take a seed, so a run can be repeated exactly.

| [![Gaussian](https://media.ollin.art/examples/Randomness/Gaussian/still-640.jpg?v=40859ee8)](Gaussian/) | [![NoiseField](https://media.ollin.art/examples/Randomness/NoiseField/still-640.jpg?v=801ed839)](NoiseField/) | [![NoiseKinds](https://media.ollin.art/examples/Randomness/NoiseKinds/still-640.jpg?v=72d1a7b4)](NoiseKinds/) | [![NoiseWave](https://media.ollin.art/examples/Randomness/NoiseWave/still-640.jpg?v=286d2d6b)](NoiseWave/) |
|---|---|---|---|
| [Gaussian](Gaussian/) | [NoiseField](NoiseField/) | [NoiseKinds](NoiseKinds/) | [NoiseWave](NoiseWave/) |
| [![RandomBand](https://media.ollin.art/examples/Randomness/RandomBand/still-640.jpg?v=aa31e192)](RandomBand/) | [![Ring](https://media.ollin.art/examples/Randomness/Ring/still-640.jpg?v=6a3a3bb2)](Ring/) | [![TilingNoise](https://media.ollin.art/examples/Randomness/TilingNoise/still-640.jpg?v=d3c2a077)](TilingNoise/) | [![Variations](https://media.ollin.art/examples/Randomness/Variations/still-640.jpg?v=62068a6a)](Variations/) |
| [RandomBand](RandomBand/) | [Ring](Ring/) | [TilingNoise](TilingNoise/) | [Variations](Variations/) |
| [![Walk](https://media.ollin.art/examples/Randomness/Walk/still-640.jpg?v=eb2a85d6)](Walk/) |  |  |  |
| [Walk](Walk/) |  |  |  |

| Example | What it shows |
|---|---|
| [Gaussian](Gaussian/Sketch.swift) | 2000 dots a frame, placed by `randomGaussian`, so the bell curve becomes visible |
| [NoiseField](NoiseField/Sketch.swift) | an 80×80 grid shaded by 3D Perlin `noise`, and the mouse scrubs through the field |
| [NoiseKinds](NoiseKinds/Sketch.swift) | the noise kinds side by side on one seeded field: `simplexNoise`, `signedSimplexNoise` split at zero, `worley` with its feature and jitter exposed as parameters, and `turbulence` |
| [NoiseWave](NoiseWave/Sketch.swift) | a wave of dots offset by `signedNoise`, which is smooth, as the noise counterpart to RandomBand |
| [TilingNoise](TilingNoise/Sketch.swift) | one tile laid down nine times, once from `fbm` and once from `tilingFbm`, so you can see the seams and where they disappear |
| [RandomBand](RandomBand/Sketch.swift) | a band of dots jittered by `random`, which is jagged, and the mouse re-rolls it |
| [Ring](Ring/Sketch.swift) | dots scattered in an annulus by `ring()`, relative to `scale`, so the ring keeps its proportion |
| [Variations](Variations/Sketch.swift) | a whole composition per seed, which you explore from the inspector's Variation card and proof as a range with `--export-grid` |
| [Walk](Walk/Sketch.swift) | a seeded random walk that the clock reveals over time, and a click starts a fresh walk in a `randomChoice` color |

Run one with `swift run Example-Randomness-<Name>`, for example `swift run Example-Randomness-NoiseField`.
