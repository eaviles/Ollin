#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Shaders</sup>

---

## Shaders

| [![ComplexPlane](https://media.ollin.art/examples/Shaders/ComplexPlane/still-640.jpg?v=50d83a38)](ComplexPlane/) | [![DomainWarp](https://media.ollin.art/examples/Shaders/DomainWarp/still-640.jpg?v=9c7c951f)](DomainWarp/) | [![HelloShader](https://media.ollin.art/examples/Shaders/HelloShader/still-640.jpg?v=63468476)](HelloShader/) | [![ImaginaryLog](https://media.ollin.art/examples/Shaders/ImaginaryLog/still-640.jpg?v=5a1029c5)](ImaginaryLog/) |
|---|---|---|---|
| [ComplexPlane](ComplexPlane/) | [DomainWarp](DomainWarp/) | [HelloShader](HelloShader/) | [ImaginaryLog](ImaginaryLog/) |
| [![Meromorphic](https://media.ollin.art/examples/Shaders/Meromorphic/still-640.jpg?v=cddb858d)](Meromorphic/) | [![ShaderBlend](https://media.ollin.art/examples/Shaders/ShaderBlend/still-640.jpg?v=8a803d48)](ShaderBlend/) | [![ShaderFilter](https://media.ollin.art/examples/Shaders/ShaderFilter/still-640.jpg?v=2f2995ce)](ShaderFilter/) | [![VisualCatalog](https://media.ollin.art/examples/Shaders/VisualCatalog/still-640.jpg?v=45257941)](VisualCatalog/) |
| [Meromorphic](Meromorphic/) | [ShaderBlend](ShaderBlend/) | [ShaderFilter](ShaderFilter/) | [VisualCatalog](VisualCatalog/) |
| [![VisualSynth](https://media.ollin.art/examples/Shaders/VisualSynth/still-640.jpg?v=21aaaa70)](VisualSynth/) |  |  |  |
| [VisualSynth](VisualSynth/) |  |  |  |

These examples show how to write your own GPU code. A `Shader` is a `shade(uv, info)`
function. Ollin wraps it, compiles it, and runs it through the effect graph as a source,
a filter, or a two-input combine, with the whole shader library spliced in. A `Visual`
chain builds the same per-pixel program from chained Swift calls, so you do not need
to write Metal. See [Shaders](../../Docs/Shaders/Shaders.md),
the [shader library reference](../../Docs/Shaders/ShaderLibrary.md), and
[Visuals](../../Docs/Shaders/Visuals.md).

| Example | What it shows |
|---|---|
| [HelloShader](HelloShader/Sketch.swift) | the smallest user shader, written both ways: an inline `Shader("...")` plasma beside the same shader loaded from a `.metal` file with `Shader(resource:in:)`. The file version hot-reloads on save under OllinLive, with no swiftc pass |
| [ShaderFilter](ShaderFilter/Sketch.swift) | a shader as a one-input filter: it draws a scene into a layer, then re-samples the layer with a wave and posterizes it (`sample(info, uv)`) |
| [ShaderBlend](ShaderBlend/Sketch.swift) | a shader as a two-input combine: an animated diagonal wipe with a rippling seam (`sample` + `sampleAux`) |
| [VisualSynth](VisualSynth/Sketch.swift) | the `Visual` chain API: a source, warps, color moves, and modulations compile into one GPU pass, and every number can animate without a recompile |
| [VisualCatalog](VisualCatalog/Sketch.swift) | the `Visual` chain catalog on one switchable contact sheet: sources, warps, color adjustments, two-chain combines, and per-pixel modulations, chosen by a family parameter, with every tile labeled with the calls it chains |
| [DomainWarp](DomainWarp/Sketch.swift) | runtime shader parameters: `Shader(_, params:)` takes floats that MSL reads back as `param(info, n)`, which animates a hand-written domain-warp marble with no recompile |
| [ComplexPlane](ComplexPlane/Sketch.swift) | the shader library's `complex` module beside the CPU `Complex` value: a shader colors every pixel by the phase and size of the ratio of two moving points (`complexPlane`, `cdiv`, `domainColor`), and `draw()` works out the circles that ratio is made of and lays them over the layer, where they land on the shader's rulings |
| [ImaginaryLog](ImaginaryLog/Sketch.swift) | the imaginary part of a logarithm as a picture: `clog` of the ratio of two turning points through a cosine `palette` that never completes a cycle, so the branch cut between the points shows as a soft seam, and `draw()` can mark that segment with `Complex` |
| [Meromorphic](Meromorphic/Sketch.swift) | a ratio of two cubic polynomials built from six roots that `draw()` moves as `Complex` values, multiplied out with `cmul` and painted by the phase of its `clog` through a palette whose frequency is a parameter: tame at one, bands piling up around the poles when wild |
