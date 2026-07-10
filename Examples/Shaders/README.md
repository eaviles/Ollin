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
| [HelloShader](HelloShader/Sketch.swift) | the smallest user shader: a trigonometric plasma as a `generate(.shader(...))` source, colored by the library's cosine `palette` |
| [ShaderFilter](ShaderFilter/Sketch.swift) | a shader as a one-input filter: draw a scene into a layer, re-sample it with a wave and posterize (`sample(info, uv)`) |
| [ShaderBlend](ShaderBlend/Sketch.swift) | a shader as a two-input combine: an animated diagonal wipe whose seam ripples (`sample` + `sampleAux`) |
| [ShaderFile](ShaderFile/Sketch.swift) | a shader loaded from a `.metal` file beside the sketch (`Shader(resource:in:)`); under OllinLive it hot-reloads on save, no swiftc pass |
| [VisualSynth](VisualSynth/Sketch.swift) | the fluent `Visual` chain surface: source, warps, color moves, and modulations compiling into one GPU pass, every number animatable without a recompile |
| [DomainWarp](DomainWarp/Sketch.swift) | domain warping opened up: the fbm field displaces its own coordinates twice (the shader library's `warpedFbm`, written out by hand), the intermediate displacements tinting the marble |
