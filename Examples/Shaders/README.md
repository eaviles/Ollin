#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Shaders</sup>

---

## Shaders

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
