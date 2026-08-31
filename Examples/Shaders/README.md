#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Shaders</sup>

---

## Shaders

Writing your own GPU code: a `Shader` is a `shade(uv, info)` function Ollin wraps,
compiles, and runs through the effect graph as a source, a filter, or a two-input
combine, with the whole shader library spliced in. `Visual` chains build the same
per-pixel programs fluently, no Metal required. See [Shaders](../../Docs/Shaders/Shaders.md),
the [shader library reference](../../Docs/Shaders/ShaderLibrary.md), and
[Visuals](../../Docs/Shaders/Visuals.md).

| Example | What it shows |
|---|---|
| [HelloShader](HelloShader/Sketch.swift) | the smallest user shader, both ways in: an inline `Shader("...")` plasma beside the same contract loaded from a `.metal` file (`Shader(resource:in:)`), which hot-reloads on save under OllinLive, no swiftc pass |
| [ShaderFilter](ShaderFilter/Sketch.swift) | a shader as a one-input filter: draw a scene into a layer, re-sample it with a wave and posterize (`sample(info, uv)`) |
| [ShaderBlend](ShaderBlend/Sketch.swift) | a shader as a two-input combine: an animated diagonal wipe whose seam ripples (`sample` + `sampleAux`) |
| [VisualSynth](VisualSynth/Sketch.swift) | the fluent `Visual` chain surface: source, warps, color moves, and modulations compiling into one GPU pass, every number animatable without a recompile |
| [DomainWarp](DomainWarp/Sketch.swift) | runtime shader parameters: `Shader(_, params:)` floats read back in MSL as `param(info, n)`, animating a hand-written domain-warp marble with no recompile |
