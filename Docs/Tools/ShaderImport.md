# Bringing a shader over

There is an enormous amount of GLSL out there. Shadertoy alone holds tens of thousands of fragment shaders. Most are the same shape: one `mainImage` function that gets a pixel position and returns a color. A handful of values arrive each frame.

Ollin's own [user-shader path](../Shaders/Shaders.md) is nearly that shape already. It asks for `shade(uv, info)`, works in Metal, and measures the canvas from the top-left corner. `ollin new --from-shader` closes the gap. It translates the shader and writes a project around it.

```sh
ollin new Plasma --from-shader plasma.glsl
```

You get a folder that builds and runs, with the translated shader in `imported.metal` beside the sketch:

```
Plasma/
  Package.swift
  Sources/Plasma/Sketch.swift
  Sources/Plasma/imported.metal
```

The shader is **source you now own**. Edit it and keep what works. Under [OllinLive](../../README.md#live-reload) a saved `.metal` file reloads on its own, with no Swift build in between.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/17-YourFirstShader/ImportedShader-dark.jpg">
  <img src="../../Guide/Images/17-YourFirstShader/ImportedShader.jpg" alt="Left, a nine-line GLSL shader as pasted, with mod, iResolution and iTime picked out in dark ink. Right, the ring pattern it draws once translated, tiling evenly across the whole frame" width="680">
</picture>

## Where the shader comes from

Three ways, all doing the same thing once the code is in hand.

```sh
ollin new Plasma --from-shader plasma.glsl        # a file
pbpaste | ollin new Plasma --from-shader -        # what you just copied
ollin new Plasma --from-shader https://www.shadertoy.com/view/XXXXXX
```

The last one needs a key of your own. The site serves shaders through its published interface, not the page you are looking at:

```sh
export SHADERTOY_API_KEY=yourkey     # ask for one in your profile on the site
```

Two things about that route. The site only serves a shader marked public *and* shared through the API, so plenty will not come back. Only the image pass arrives; a shader built on several buffers needs the rest by hand.

Without a key, open the shader, copy the code, and pass a file. Nothing is lost.

## Licenses

**A shader belongs to whoever wrote it.** Shadertoy's default license is CC BY-NC-SA 3.0. Many authors set their own terms in a comment at the top.

So the translated file keeps a header naming the shader, its author, and the address it came from. It says plainly that the terms travel with it. Leave that header where it is, and read the terms before publishing.

Nothing is bundled with Ollin. The command translates what *you* hand it.

## What the sketch looks like

How many inputs the shader reads decides what it becomes, which is the same rule the user-shader path already uses.

A shader that reads nothing is a **generator**:

```swift
override func draw() {
    drawImage(generate(imported).image, 0, 0)
}
```

One that reads `iChannel0` is a **filter** over a layer. The sketch draws something into that layer for it to work on. Two channels make it a **combine** over a pair. What gets drawn into those layers is ordinary sketch code, written out in full so it is the obvious first thing to change.

## What is translated

Most of it is a rename, and the file keeps your spacing, your blank lines, and your comments, so the result reads like the shader you pasted.

| GLSL | Metal |
|---|---|
| `vec2` `vec3` `vec4`, `mat3`, `ivec2` | `float2` `float3` `float4`, `float3x3`, `int2` |
| `mainImage(out vec4, in vec2)` | `shade(float2 uv, ShaderInfo info)` around it |
| `iTime`, `iTimeDelta`, `iFrame` | `info.time`, `info.deltaTime`, `int(info.frame)` |
| `iResolution.xy`, `iMouse` | `info.resolution.xy`, `ollin_mouse(info)` |
| `texture(iChannel0, uv)` | `sample(info, ollin_channel_uv(uv))` |
| `atan(y, x)` | `atan2(y, x)` |
| `lessThan(a, b)`, `not(a)` | `(a < b)`, `!(a)` |
| `inversesqrt`, `dFdx`, `roundEven` | `rsqrt`, `dfdx`, `rint` |
| `out float x` in a parameter list | `thread float &x` |
| `MyStruct(a, b)` | `MyStruct{a, b}` |
| `const float K = 1.0;` at file scope | `constant float K = 1.0;` |

Three of these are worth a sentence each, because they change what you see rather than whether it builds.

**`mod` is not `fmod`.** GLSL takes the floor of the quotient and Metal truncates it, so the two disagree whenever either side is negative. Tiling a plane that reaches left of or below the origin is what this kind of shader does first. So the translation writes the flooring form out rather than calling the built-in. On a plain tiled ramp the difference is over half the canvas.

**The vertical axis turns over.** A texture is measured from its bottom edge and an Ollin layer from its top, so a layer read flips the coordinate on the way in. Without it every imported filter arrives upside down.

**The values the site supplies are globals, and Metal has none.** Any function may read `iTime`, so `info` travels as a parameter instead. It reaches only the functions that read one and the functions that call those. Helpers that do arithmetic alone, such as the distance functions and the noise, are untouched.

## What is not

Whatever cannot be carried over is written into the file as a comment. A `NOTE(ollin)` marks something translated that you should know about. A `TODO(ollin)` marks something left for you, and the shader will not compile until you deal with it. The command prints the same list before it writes anything.

The usual ones:

- **Several passes.** Only the image pass comes over. A shader built on Buffer A through D needs those wired up as [layers](../Drawing/Effects.md) by hand.
- **More than two inputs.** A shader here reads at most two layers.
- **A texture the shader declares itself.** Draw into a render target and pass it in as a layer.
- **A variable at file scope the shader writes to.** Metal has nowhere to put one. Make it `constant` if it never changes, or make it a local and pass it along.
- **`texelFetch`.** A layer read takes a fraction, not a whole-number texel position. Divide by the resolution and sample.
- **`iDate` and `iSampleRate`.** Only the seconds field of the date carries a value, and the sample rate is a fixed 44100, since this pass draws rather than making sound.
- **The mouse button.** `iMouse` reports its position in both halves, because Ollin does not keep the place of the last click. Read `mouseIsPressed` in the sketch and pass it in as a param.
- **A 4x4 matrix inverse.** The 2x2 and 3x3 cases are supplied; the 4x4 needs writing.

An older shader written around `main` with `gl_FragCoord` and `gl_FragColor` is reshaped into the same form and works too.

## Once it runs

It is Metal now, so the rest of the framework is open to it. [Ollin's shader library](../Shaders/ShaderLibrary.md) is spliced in already, so `palette`, the noise, the hashes and the `sd*` distance functions are all callable. `param(info, i)` reads values from the sketch, which is how a knob reaches the shader. The whole [layered-effects](../Drawing/Effects.md) tier composes around it.

If the shader is small enough to keep in the Swift file, ask for one loose file and it travels inline:

```sh
ollin new plasma.swift --from-shader plasma.glsl
```

## See also

- [Shaders](../Shaders/Shaders.md) - the contract this translates into, and what `ShaderInfo` carries
- [The shader library](../Shaders/ShaderLibrary.md) - what is callable from inside a shader
- [Project generator](ProjectGenerator.md) - the other ways to start a project
- [Layered effects](../Drawing/Effects.md) - render targets, filters, and combines
