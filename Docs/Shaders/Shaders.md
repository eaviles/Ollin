#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Shaders](./README.md) → `Shaders`</sup>

---

## User-supplied shaders

Write your own **fragment shader** and run it through Ollin's effect graph. You supply a small Metal function, and Ollin wraps it into a full GPU pass. You get the speed of a hand-written shader without writing the pipeline boilerplate, and you get clear errors when something doesn't compile.

```swift
let plasma = Shader("""
float4 shade(float2 uv, ShaderInfo info) {
    float2 p = (uv * 2.0 - 1.0) * 6.0;
    float fx = cos(p.x) * cos(p.y);
    float fy = sin(p.x) * sin(p.y);
    float v = 0.5 + 0.5 * sin((fx * fx + fy * fy) * 6.28318 + info.time);
    float3 col = palette(v, float3(0.5), float3(0.5),
                         float3(1.0), float3(0.0, 0.33, 0.67));   // a library helper
    return float4(col, 1.0);
}
""")

override func draw() {
    drawImage(generate(plasma).image, 0, 0)   // run it as a full-canvas source layer
}
```

### Contents

- [The contract: `shade(uv, info)`](#the-contract)
- [Generator, filter, combine](#generator-filter-combine)
- [`ShaderInfo` and params](#shaderinfo-and-params)
- [The shader library](#the-shader-library)
- [Inline source or a `.metal` file](#inline-source-or-a-metal-file)
- [Pulling in another file](#pulling-in-another-file)
- [Errors](#errors)

---

## The contract

Your shader defines one function:

```metal
float4 shade(float2 uv, ShaderInfo info) { ... }
```

- **`uv`** runs `0…1` across the layer from a **top-left origin**, so `(0,0)` is the top left and `(1,1)` is the bottom right. That is the same orientation as the rest of the canvas. A shader ported from a bottom-left convention needs `uv.y = 1.0 - uv.y`.
- **`info`** carries the per-frame values: `info.time`, `info.deltaTime`, `info.frame`, `info.resolution` (the layer size in pixels), `info.mouse` (in points), and your `params` (see below).
- **Return** a straight (non-premultiplied) **sRGB** color in `0…1`. Ollin converts it to the premultiplied linear color that a layer composites in, so `float4(0.5, 0.5, 0.5, 1.0)` reads as mid-gray on screen.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/17-YourFirstShader/UVSpace-dark.jpg">
  <img src="../../Guide/Images/17-YourFirstShader/UVSpace.jpg" alt="The uv gradient annotated: (0,0) at the top left, (1,0) top right, (0,1) bottom left, (1,1) bottom right, with the center marked (0.5, 0.5)" width="680">
</picture>

Ollin generates the surrounding Metal fragment for you, along with a fullscreen vertex, and calls `shade` once per pixel.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/17-YourFirstShader/PixelGrid-dark.jpg">
  <img src="../../Guide/Images/17-YourFirstShader/PixelGrid.jpg" alt="Two panels evaluating the same glow function: coarsely on the left, where each grid cell shows one answer, and at full pixel resolution on the right where the answers fuse into a smooth image" width="680">
</picture>

---

## Generator, filter, combine

How many input layers your shader reads decides what kind of pass it is. Each kind is a different entry point into the same effect graph:

| Inputs | Kind | How you run it | Read inputs with |
| --- | --- | --- | --- |
| none | **generator** | `generate(shader)` or `generate(.shader(shader))` | (no input) |
| one | **filter** | `layer.filtered(.shader(shader))` | `sample(info, uv)` |
| two | **combine** | `a.combined(with: b, .shader(shader))` | `sample(info, uv)`, `sampleAux(info, uv)` |

A generator paints from math alone, like the plasma above. A filter transforms a layer you drew. A combine reads two layers at once, which is how you write a blend or a warp of your own in the shader. All three return a [`RenderTarget`](../Drawing/Effects.md), so you can draw it with `.image`, filter it again, or feed it into another effect.

`sample` and `sampleAux` read a layer as a straight sRGB color, which is the space your shader works in. When a layer holds *data* rather than a picture, read it with **`sampleRaw(info, uv)`** instead, and use **`sampleAuxRaw`** for a combine's second input. Both hand back the stored values with no color conversion at all. A [measured distance field](../Drawing/DistanceFields.md) is the case to reach for them. Its red channel is a distance in pixels and runs negative, and its green and blue are the two halves of a direction. None of that survives being read as a color.

---

## `ShaderInfo` and params

As well as the per-frame fields, you can pass your own floats and read them with `param(info, i)`:

```swift
let warp = Shader(metalSource, params: [0.3, 1.2, 6.0])
```

```metal
float4 shade(float2 uv, ShaderInfo info) {
    float strength = param(info, 0);   // 0.3
    float scale    = param(info, 1);   // 1.2
    ...
}
```

You can pass up to 64 floats, and `info.paramCount` is how many you passed. Drive them from a [`@Param`](../Helpers/Parameters.md) parameter to tune a shader while it runs.

---

## The shader library

Ollin's shader library is spliced into every user shader, so you can call these helpers inside `shade` with no import. They are the same helpers Ollin's own shaders use, written from the published techniques and credited in the README's *Techniques* list.

| Group | Helpers |
| --- | --- |
| **always there** | `srgbToLinear` / `linearToSrgb` / `unipolar` / `bipolar` / `perceptualCoverage`. These are spliced whatever you ask for, because the generated fragment reads them. |
| **color** | `luma`, `palette(t, a, b, c, d)` (cosine gradient), `linearToOklab` / `oklabToLinear` / `oklabToOklch` / `oklchToOklab` |
| **hash** | `hash12`, `hash22`, `hash33` |
| **noise** | `valueNoise`, `fbm`, `gradientNoise`, `simplexNoise`, `worley` / `worley2`, `ridgedFbm`, `turbulence`, `warpedFbm`, `curlNoise` |
| **sdf** | `smin(a, b, k)` (smooth minimum) plus the 2D distance catalog (`sdEllipse`, `sdRoundBox`, `sdSegment`, `sdStar`, `sdHeart`, `sdBezier`, …) |
| **domain** | `rotate2D`, `pmod` / `pmod2` (repeat), `mirror`, `pmodPolar` (radial fold) |

See the **[shader library reference](./ShaderLibrary.md)** for every function with its full signature.

By default the whole library is spliced. Unused helpers are removed as dead code, so on the GPU the choice costs nothing. It only affects *compile* time, which matters when many shaders compile or hot-reload at once. To trim the set, pass an explicit `Modules` set:

```swift
let s = Shader(metalSource, using: [.noise, .domain])   // splice only these sections
```

---

## Inline source or a `.metal` file

The body can be an inline Swift string, which is the simplest form. It hot-reloads with the sketch under [OllinLive](../../README.md), so you edit the string, save, and the sketch recompiles with the new shader. The body can also be a `.metal` resource file beside your sketch:

```swift
let s = Shader(resource: "warp", in: .module)   // reads warp.metal from the sketch's bundle
```

`in:` is required, because it can't default to Ollin's own bundle. Under OllinLive the file hot-reloads too: edit the `.metal`, save, and it recompiles in place without restarting the sketch. The file is re-read on every change, so a line-accurate error in the `.metal` shows in the overlay just as an inline one does.

---

## Pulling in another file

Once two shaders want the same helper, write it once and include it:

```metal
#include "helpers.metal"

float4 shade(float2 uv, ShaderInfo info) {
    return sample(info, swirl(uv, param(info, 0)));   // swirl lives in helpers.metal
}
```

The path is relative to the file that names it, so a helper sitting beside the shader is named by its file name alone. An inline Swift string resolves the same way, against the folder of the `.swift` file it is written in. A [compute kernel](./Compute.md) can include a file too, so one helper file serves both.

The rules are short:

- **A file is read once**, however many times it is named. Two shaders that both include the same helper therefore do not define it twice.
- **A mistake inside an included file is reported against that file, at its own line**. An include is only worth having if the error still points at the file you would edit.
- A file that is not there, or a loop of files that include each other, is **reported before the compiler is asked**. Otherwise the compiler would answer with a pile of undeclared identifiers that point away from the real mistake.

Ollin's own shader library needs no include, because it is already spliced into every shader (see [The shader library](#the-shader-library) above). `#include <angle>` forms are left for the compiler, so `<metal_stdlib>` still works if you want a file that also compiles on its own.

Under OllinLive, an edit to the helper reloads the shaders that read it. Working on the helper is the same loop as working on the shader.

### Reading a library from somewhere else

A path that starts with `/` or `~` is taken as it is. A shader can therefore read a shader library cloned anywhere on the machine:

```metal
#include "~/Developer/References/lygia/generative/snoise.msl"
```

Whatever that file includes then resolves from where the file sits. Most shader libraries use that form between their own files, so one line brings in the whole chain. Two things stay yours to check. First, the file has to be Metal, since a `.glsl` will not compile whatever it is called. Second, **the terms of that library travel with the files you include**. Ollin neither ships nor depends on any of them.

---

## Errors

A shader that doesn't compile is reported at **the file and line you wrote it in**. That is the sketch's own `.swift` for an inline string, or the `.metal` file for a resource. The report prints the offending line with a caret under it, so the location is real and an IDE can jump straight to it. The frame keeps running with the broken pass skipped, so a typo never crashes the sketch.

```
/Users/you/Sketches/Plasma.swift:23:5: error: use of undeclared identifier 'vec4'; did you mean 'vec'?
    vec4 v = 0.5 + 0.5 * sin(...);
    ^~~~
```

For an inline string, the line number assumes the canonical form, with the opening `"""` on the `Shader(` call line. A one-line shader may read one line off, which still lands within sight of the mistake.

In a plain `swift run`, the message goes to the terminal. In [OllinLive](../../README.md), it appears in the on-screen error overlay and clears when you fix it.

To try a shader without launching a sketch at all, hand the file to [`ollin check`](../Tools/ShaderCheck.md). It compiles the shader on this machine's GPU and prints the same errors at the same lines.

---

### See also

- [Checking a shader](../Tools/ShaderCheck.md): compile a `.metal` file from the command line and see what it reads
- [Layered effects](../Drawing/Effects.md): the off-screen layers, filters, and `compose { }` your shader plugs into
- [Compute & GPU particles](./Compute.md): runtime-compiled compute kernels, the sibling page for buffer and texture work
- [SDF combinators](../Drawing/Combinators.md): compose signed-distance fields without writing raw shader code
- [Parameters](../Helpers/Parameters.md): `@Param` parameters to drive a shader's `params` live
