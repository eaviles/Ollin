#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Compute`</sup>

---

## Compute & GPU particles

A compute shader is a small program that runs on the GPU over a buffer of data — one thread per element, all at once. Ollin uses it for the workload creative coding most wants and the CPU can't reach: **hundreds of thousands to millions of particles**, each updated and drawn on the GPU so the data never round-trips through the CPU. It's the engine behind the depth-of-field "sandpainting" look — faint particles summed as light — at counts a `draw()` loop could never iterate.

The headline is [`Particles`](#particles): you write the per-particle update as a short snippet of Metal, and Ollin generates the kernel, owns the double-buffering, and renders the result. Underneath sits a small typed core ([`ComputeKernel`](#computekernel), [`ComputeBuffer`](#computebuffer), [`compute`](#compute)) for full control.

> Compute kernels are written in **Metal Shading Language (MSL)** — a C++-like GPU language — as a string. Ollin compiles it at runtime, so editing a kernel hot-reloads with the sketch. The snippets below are MSL, not Swift.

### Contents

- [Particles — a GPU particle system in a few lines](#particles)
- [The kernel snippet](#snippet) — what's in scope
- [The prelude](#prelude) — hashing, noise, curl, disc sampling
- [Custom live parameters](#custom)
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

<a id="core"></a>
### The typed core

`Particles` is sugar over a public core you can use directly for custom particle layouts or non-particle compute (simulations over your own structs).

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

For a buffer the render path reads each frame, use a [`PingPong`](#notes) pair (two buffers swapped each step) so the GPU can overlap one frame's render with the next step.

<a id="compute"></a>
#### compute

Record a dispatch:

```swift
// In place — one buffer, read and written:
compute(sim, over: buffer)

// Ping-pong — read one, write the other (swap between frames):
compute(sim, reading: pp.read, writing: pp.write)
pp.advance()
```

Draw a `ComputeBuffer<OllinParticle>` directly with `drawParticles(_ buffer:)`; for a custom struct, draw it with your own geometry (read the buffer in your own shader, or copy positions out).

<a id="notes"></a>
### Notes

- **`OllinParticle`** is the built-in particle struct (`position`, `velocity`, `color`, `size`, `life`, two scratch floats). `drawParticles` reads `position`/`color`/`size` from it. A custom struct that wants the built-in renderer must place those fields at the same offsets, or render itself.
- **Ping-pong, not in place, for simulation.** When a buffer is both written by the kernel and read by the render path each frame, drive it as a `PingPong` pair (`Particles` does this for you). In-place `compute(_:over:)` is for scratch work the render path doesn't also read that frame.
- **Determinism.** GPU floating-point results are deterministic on a given device but can differ across GPUs (reassociation), so compute renders aren't pinned to exact reference images.
- **It's Metal.** Kernels are MSL, compiled at runtime. A syntax error prints to the console and the dispatch is skipped (the frame still renders), so a broken kernel shows as missing particles rather than a crash.

Compute is a core capability — it ships with `import Ollin`, no satellite needed.
