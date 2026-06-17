#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Compute`</sup>

---

## Compute & GPU particles

A compute shader is a small program that runs on the GPU over a grid of data — one thread per element, all at once. Ollin uses it for the workloads creative coding most wants and the CPU can't reach, in two shapes:

- **Buffers** — *hundreds of thousands to millions of particles*, each updated and drawn on the GPU so the data never round-trips through the CPU. The engine behind the depth-of-field "sandpainting" look — faint particles summed as light — at counts a `draw()` loop could never iterate. The headline is [`Particles`](#particles).
- **Textures** — *ping-pong simulations over a 2-D field*: reaction-diffusion, cellular automata, fluid, and image kernels. Each cell reads its neighbours and writes the next state, every frame, on the GPU; the result draws like any image. The headline is [`Simulation`](#simulation).

Both write the per-element update as a short snippet of Metal — Ollin generates the kernel, owns the double-buffering, and renders the result — over one typed core ([`ComputeKernel`](#computekernel), [`ComputeBuffer`](#computebuffer), [`ComputeTexture`](#computetexture), [`compute`](#compute)) you can drop to for full control.

> Compute kernels are written in **Metal Shading Language (MSL)** — a C++-like GPU language. You can write them inline as a Swift string, or keep them in their own [**`.metal` file**](#metalfile) for editor highlighting and checking. Ollin compiles them at runtime, so editing a kernel hot-reloads with the sketch. The snippets below are MSL, not Swift.

### Contents

- [Particles — a GPU particle system in a few lines](#particles)
- [The kernel snippet](#snippet) — what's in scope
- [The prelude](#prelude) — hashing, noise, curl, disc sampling
- [Custom live parameters](#custom)
- [Texture kernels & simulations](#textures) — `Simulation`, `ComputeTexture`
- [Kernels in a `.metal` file](#metalfile)
- [The typed core](#core) — `ComputeKernel`, `ComputeBuffer`, `compute`
- [Notes](#notes)

<a id="particles"></a>
### Particles

`Particles` is a GPU particle system. Give it a count and a per-particle update written as a Metal **body snippet**; step it and draw it from `draw()`:

```swift
import Ollin

@main
final class Flow: Sketch {
    lazy var sand = Particles(count: 1_000_000, step: """
        if (life <= 0.0) {                       // (re)spawn the dead
            position = hash22(float2(float(id), float(u.frameCount))) * u.resolution;
            life = 1.0;
        }
        position += curlNoise(position * 0.002 + u.time * 0.05) * 80.0 * u.dt;
        life -= u.dt;
        color = float4(0.6, 0.8, 1.0, 0.4);
        size = 1.4;
    """)

    override func setup() { toneMap(.aces) }

    override func draw() {
        background(.black)
        blendMode(.add)         // particles sum as light
        updateParticles(sand)   // one GPU simulation step
        drawParticles(sand)     // a million additive discs
    }
}
```

- **`updateParticles(_:)`** records the simulation step — the kernel runs once over every particle, on the GPU, before the frame is drawn.
- **`drawParticles(_:)`** draws the particles as additive sub-pixel discs (the same area-conserving coverage [`drawCircle`](./Drawing.md) uses, so a million tiny jittered marks fade by area instead of flickering). They composite under the active [`blendMode`](./Drawing.md#blendmode) and in draw order with everything else — draw particles, then switch to `.normal` and draw a caption over them.

That's the whole loop. For the sandpainting look, pair it with [`blendMode(.add)`](./Drawing.md#blendmode), [`noClear()`](./Accumulation.md), and [`toneMap`](./HDR.md) — particles sum as light into a float buffer that tone-maps to a glow. See `Examples/Compute/CurlField` and `Examples/Basic/DepthOfField`.

<a id="snippet"></a>
### The kernel snippet

In the `step:` snippet these per-particle fields are **locals you read and write**:

| Local | Type | Meaning |
| --- | --- | --- |
| `position` | `float2` | canvas position, points (top-left origin, y-down) |
| `velocity` | `float2` | your sim's velocity (the built-in renderer ignores it) |
| `color` | `float4` | straight RGBA, sRGB tones (alpha fades / weights the light) |
| `size` | `float` | on-screen disc diameter, points |
| `life` | `float` | a lifetime you manage (the renderer ignores it) |
| `seedA`, `seedB` | `float` | free scratch (a respawn counter, a per-particle seed) |

And these are **read-only**:

- `id` — this particle's index (`uint`).
- `u` — the per-frame constants: `u.time`, `u.dt`, `u.frameCount`, `u.resolution`, `u.mouse`, `u.particleCount`.
- `custom` — a `float4` of [live parameters](#custom) you pass to `updateParticles`.

Particles start zeroed, so `life` begins at 0 — the `if (life <= 0.0)` spawn pattern above seeds every particle on the first frame.

<a id="prelude"></a>
### The prelude

Every kernel gets a set of helpers for free (written from the published techniques — Dave Hoskins' hashing, the Book of Shaders value noise, the standard curl-of-a-potential):

- `hash11`/`hash21`/`hash31` → `float`, `hash22` → `float2`, `hash33` → `float3` — fast hashes for randomness.
- `valueNoise(float2)` / `valueNoise(float3)` → `float`, and `fbm(float2)` — smooth value noise.
- `curlNoise(float2)` → `float2` — a divergence-free flow field; particles advected by it swirl without clumping.
- `discSample(float2 seed)` → `float2` — a point in the unit disc, uniform over its *area* (the right scatter for energy-conserving bokeh).
- `srgbToLinear(float3)` — if you need linear color.

<a id="custom"></a>
### Custom live parameters

Pass up to four live floats per step — a focal distance, a strength, a mouse-driven knob — and read them as `custom.x`…`custom.w`:

```swift
let focus = mouseIsPressed ? Float(map(mouseX, 0, width, -1, 1)) : 0
updateParticles(sand, custom: SIMD4(focus, 0, 0, 0))
```

```metal
// in the snippet:
float defocus = abs(depth - custom.x);
```

<a id="textures"></a>
### Texture kernels & simulations

Where `Particles` evolves a *buffer*, [`Simulation`](#simulation) evolves a *2-D texture* — a field where every cell reads its neighbours and writes the next state each frame. It's the engine for reaction-diffusion, cellular automata, fluid, and any "ping-pong" sim.

<a id="simulation"></a>
#### Simulation

Give it a size and a per-cell update written as a Metal **body snippet**; step it from `draw()` and draw its `image`:

```swift
import Ollin

@main
final class RD: Sketch {
    lazy var field = Simulation(width: 512, height: 512, subSteps: 12, step: """
        // Gray-Scott reaction-diffusion: chemical A in .r, B in .g.
        float2 lap = -value.xy
            + 0.20 * (tap(-1,0).xy + tap(1,0).xy + tap(0,-1).xy + tap(0,1).xy)
            + 0.05 * (tap(-1,-1).xy + tap(1,-1).xy + tap(-1,1).xy + tap(1,1).xy);
        float a = value.x, b = value.y, reaction = a * b * b;
        float feed = 0.037, kill = 0.06;
        a += 1.0 * lap.x - reaction + feed * (1.0 - a);
        b += 0.5 * lap.y + reaction - (kill + feed) * b;
        result = float4(clamp(a, 0.0, 1.0), clamp(b, 0.0, 1.0), 0.0, 1.0);
    """)

    let seed = ComputeKernel(entry: "seed", """
        kernel void seed(texture2d<float, access::write> dst [[texture(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
            float b = (hash21(float2(gid)) > 0.5 && gid.x > 240 && gid.x < 270) ? 1.0 : 0.0;
            dst.write(float4(1.0, b, 0.0, 1.0), gid);
        }
    """)
    private var seeded = false

    override func draw() {
        if !seeded { compute(seed, writing: field.current); seeded = true }   // initial state
        updateSimulation(field)                                               // one frame of sim
        drawImage(field.image, in: Rectangle(x: 0, y: 0, width: width, height: height))
    }
}
```

- **`updateSimulation(_:custom:)`** records the sim — `subSteps` kernel iterations run, on the GPU, before the frame is drawn. `custom` passes up to four live floats the snippet reads as `custom.x…w`.
- **`field.image`** wraps the current field as an [`Image`](./Drawing.md) for `drawImage` — it composites in draw order, rides the transform stack, and takes `tint`, like any image. Its texels are treated as **linear** color; author sRGB tones through `srgbToLinear` in the kernel.

In the `step:` snippet these are in scope:

| Name | Type | Meaning |
| --- | --- | --- |
| `value` | `float4` | this cell's current value (read) |
| `result` | `float4` | what to write, pre-set to `value` (write) |
| `tap(dx, dy)` | `float4` | the source field at integer offset `(dx, dy)`, **toroidal** (edges wrap) — for neighbour stencils |
| `gid` | `uint2` | this cell's coordinate |
| `size` | `uint2` | the field's size in texels |
| `u`, `custom` | — | per-frame constants and live knobs, read-only (as for particles) |

Fresh fields start **zeroed**, so seed a sim's initial state with a one-shot `compute(_:writing: sim.current)` on the first frame (the `seeded` flag above). For a full custom kernel signature, pass `Simulation(width:height:kernel:)`.

<a id="computetexture"></a>
#### ComputeTexture

The storage behind a sim — a persistent, GPU-resident 2-D texture a kernel reads and writes. Like a [`ComputeBuffer`](#computebuffer), it's allocated lazily (constructible with no device) and starts zeroed; draw it with its `image`:

```swift
let tex = ComputeTexture(width: 512, height: 512)                 // .rgba16Float by default
let single = ComputeTexture(width: 256, height: 256, format: .r32Float)
```

Run a kernel that **writes** a texture (one thread per texel; the write texture binds at `texture(0)`), or **reads one and writes another** (ping-pong, `texture(0)` → `texture(1)`):

```swift
// Generate / seed — kernel takes texture2d<…, access::write> [[texture(0)]]:
compute(generator, writing: tex)

// Transform — kernel takes read [[texture(0)]] + write [[texture(1)]]:
compute(blur, reading: src, writing: dst)
```

For a field the render path also reads each frame, drive a [`PingPongTexture`](#computetexture) pair (two textures swapped each step) — or just use `Simulation`, which owns one for you.

`ComputeTexture.snapshot()` reads the float texels back to the CPU (tests/debugging; float formats only).

<a id="metalfile"></a>
### Kernels in a `.metal` file

Inline strings are terse, but an editor can't highlight or check them. For anything substantial, keep the kernel in its own **`.metal` file** — real Metal syntax highlighting and checking — and load it with `ComputeKernel(entry:resource:in:)`:

```swift
// Kernels.metal (bundled as a .copy resource on the sketch's target):
//   kernel void blur(texture2d<float, access::read>  src [[texture(0)]],
//                    texture2d<float, access::write> dst [[texture(1)]],
//                    uint2 gid [[thread_position_in_grid]]) { … }

let blur = ComputeKernel(entry: "blur", resource: "Kernels", in: .module)!
```

The shared types and the [prelude](#prelude) are still spliced in, so the file references `OllinComputeUniforms` / `hash22` / `curlNoise` / … and writes no `#include`s. One file can hold any number of kernels — load each by its `entry` name (they share one compile). Pass `in: .module` explicitly (a default would resolve to *Ollin's* bundle, not yours), and list the file as a `.copy` resource on your target. There's also `ComputeKernel(entry:contentsOf:)` for an arbitrary file URL. See `Examples/Compute/ReactionDiffusion`, which keeps its seed and colorize passes in `Kernels.metal`.

<a id="core"></a>
### The typed core

`Particles` and `Simulation` are sugar over a public core you can use directly for custom particle layouts, custom texture formats, or non-particle compute (simulations over your own structs).

<a id="computekernel"></a>
#### ComputeKernel

A Metal `kernel` function plus its entry name. Write no `#include`s — the shared types and the prelude are spliced in for you:

```swift
let sim = ComputeKernel(entry: "step", """
    kernel void step(device const MyParticle *inBuf  [[buffer(0)]],
                     device MyParticle       *outBuf [[buffer(1)]],
                     constant OllinComputeUniforms &u [[buffer(10)]],
                     uint i [[thread_position_in_grid]]) {
        if (i >= u.particleCount) { return; }
        MyParticle p = inBuf[i];
        // … your update …
        outBuf[i] = p;
    }
""")
```

Bind your own buffers at indices **0…9**; index **10** is the standard `OllinComputeUniforms`, index **11** is `custom`/params. The compiled pipeline is cached by the source's hash, so re-creating the same kernel value each frame is free.

<a id="computebuffer"></a>
#### ComputeBuffer

A persistent, typed GPU buffer — the storage a kernel reads and writes each frame. The Metal buffer is allocated lazily (like an `Image`'s texture), so a `ComputeBuffer` is constructible anywhere. Fresh buffers start zeroed; seed one with initial CPU contents via `init(_:)`.

```swift
let buffer = ComputeBuffer<MyParticle>(count: 500_000)
let seeded = ComputeBuffer<MyParticle>(initialParticles)   // uploaded once
```

For a buffer the render path reads each frame, use a [`PingPong`](#computebuffer) pair (two buffers swapped each step) so the GPU can overlap one frame's render with the next step.

<a id="compute"></a>
#### compute

Record a dispatch:

```swift
// In place — one buffer, read and written:
compute(sim, over: buffer)

// Ping-pong — read one, write the other (swap between frames):
compute(sim, reading: pp.read, writing: pp.write)
pp.advance()

// Textures — write one (texture 0), or read one and write another (0 → 1):
compute(generator, writing: tex)
compute(transform, reading: src, writing: dst)
```

Draw a `ComputeBuffer<OllinParticle>` directly with `drawParticles(_ buffer:)`; for a custom struct, draw it with your own geometry (read the buffer in your own shader, or copy positions out). Draw a `ComputeTexture` with its `image` (a texture-backed [`Image`](./Drawing.md)).

<a id="notes"></a>
### Notes

- **`OllinParticle`** is the built-in particle struct (`position`, `velocity`, `color`, `size`, `life`, two scratch floats). `drawParticles` reads `position`/`color`/`size` from it. A custom struct that wants the built-in renderer must place those fields at the same offsets, or render itself.
- **Ping-pong, not in place, for simulation.** When a buffer or texture is both written by the kernel and read by the render path each frame, drive it as a `PingPong` / `PingPongTexture` pair (`Particles` and `Simulation` do this for you). In-place `compute(_:over:)` is for scratch work the render path doesn't also read that frame.
- **A `ComputeTexture` draws as linear color.** Its texels feed the render pipeline as linear values (the format the renderer composites in). Author display colors in a kernel through `srgbToLinear` (from the [prelude](#prelude)) and keep alpha at 1 for opaque, predictable compositing. Storage is `.shared` (unified memory) with `.shaderRead`+`.shaderWrite` usage.
- **Determinism.** GPU floating-point results are deterministic on a given device but can differ across GPUs (reassociation), so compute renders aren't pinned to exact reference images.
- **It's Metal.** Kernels are MSL, compiled at runtime. A syntax error prints to the console and the dispatch is skipped (the frame still renders), so a broken kernel shows as missing particles rather than a crash.

Compute is a core capability — it ships with `import Ollin`, no satellite needed.
