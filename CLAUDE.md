# Ollin — guidance for development

Ollin is a creative-coding framework for Swift + Metal (macOS). This file
captures the design intent so work here stays coherent across sessions.

## Vision

**p5.js ergonomics on an OPENRNDR-grade core, with motion as the default.**

- The API people *type* should feel like p5: `setup()`/`draw()`, bare calls
  like `background(.white)`, `stroke(.black)`, `circle(x:y:radius:)`. That
  familiarity is the point — don't sacrifice it.
- The architecture they *grow into* should feel like OPENRNDR: typed value
  objects, an explicit `Drawer`, and composable geometry.
- `draw()` runs continuously at the display refresh rate. Animation is not
  opt-in — `radius: 120 + sin(time) * 40` just moves. `noLoop()` is the rare
  still-image escape hatch.

## The architecture rule (load-bearing)

**The bare p5-style API is sugar over a public, typed core. Never make the
facade the only path to a feature.**

- `Sketch`'s bare methods forward to an internal `Drawer` (see
  `Sources/Ollin/Sketch.swift`). Keep that split. Anything `circle(...)` can
  do, the `Drawer` should also do — with more control.
- The day a capability is reachable *only* through the bare API, the ceiling
  is capped. Build the feature on the core first, then add the sugar.

## Conventions

- **Typed value objects early.** Geometry and color are data you pass around,
  transform, and compose — not just immediate draw calls. Prefer adding
  `Vector2`, `Rectangle`, and a vector `Shape`/`Contour` type *before* the
  call sites multiply; retrofitting `x:y:` doubles into `Vector2` later is
  expensive.
- **Swift-idiomatic, not a literal p5 port.** Enums for modes (not `"CENTER"`
  strings), trailing-closure scoping (`isolated { }` / `pushStyle { }`) over
  leaky global state, value types, overloads. Borrow p5's feel, not its warts.
- **Plan an extension seam.** OPENRNDR's strength is `extend(...)`. Keep a
  lifecycle hook (before/after `draw`, frame-grab) so screenshots, an FPS HUD,
  GUI, or video export bolt on without bloating the core.
- Drawing methods live on `Sketch` (scoped to the instance), not true
  globals — keep it that way.

## Shaders & the Metal back end

The shader set is one `.metal` file today; it will grow. Decisions that are
cheap now and expensive to retrofit:

- **One source of truth for CPU↔GPU structs.** Types shared between Swift and
  MSL (`Uniforms`, `OllinVertex`) are currently defined in both places and kept
  in sync by hand (`// Mirrors Uniforms in Shaders.metal`). That silently
  corrupts memory the day a field's layout disagrees. The moment a *second*
  shared struct appears, move them into a shared C header (a small C target
  using `simd` types) that Swift imports and the `.metal` file `#include`s.
- **Runtime source compilation is a feature, keep it.** `loadLibrary` compiles
  `Shaders.metal` from source at runtime (`makeLibrary(source:)`). For a
  creative-coding framework that's the seam for shader hot-reload and
  user-supplied shaders later — don't rip it out. Its costs are startup time
  and *no build-time error checking*.
- **Add a precompiled `default.metallib` when those costs bite, don't replace.**
  A SwiftPM build-tool plugin that runs `metal`/`metallib` gives the built-in
  shaders build-time validation and zero startup cost. `loadLibrary` already
  prefers a precompiled `Bundle.module` metallib *before* the source path, so
  this slots in with no API change; runtime compilation stays for dynamic
  shaders. Note: SwiftPM's `.process(...)` resource rule copies the `.metal`
  as *source* — it does not compile it — which is why the plugin is the path.
- **Cache pipelines; don't grow `init`.** `MetalRenderer.init` builds one
  `MTLRenderPipelineState` inline. A new pipeline (textured quads, a new blend
  mode, compute) should be a new case in an enum-keyed pipeline cache, not more
  code in the constructor.
- **Don't hard-code the single-file assumption.** `loadLibrary` looks up
  `Shaders.metal` by name. As shaders multiply, keep one umbrella file that
  `#include`s the rest, or enumerate the `.metal` resources — decide before the
  second file lands.

## Build, run, verify

```sh
swift run OllinSketch   # boots an 800x800 window running the demo sketch
```

- **Requires macOS 14+ and a Metal-capable GPU.**
- **This cannot be compiled in the Linux web container** (no Swift toolchain,
  no Metal). Changes here are unverified until built on a Mac — say so
  explicitly rather than claiming a change works.

## Current state & roadmap

- **Today:** `Sketch` base class; temporal state (`frameCount`, `time`,
  `deltaTime`, `frameRate`); `Drawer` + Metal renderer (solid fills, stroked
  outlines, 4x MSAA); the only shape is `circle`; colors are named constants
  (`.white`, `.black`, …).
- **Next, in priority order:** `Vector2` and `Color` value types as the
  geometry currency; more primitives (`rect`, `line`, `ellipse`); vector
  `Shape`/`Contour`; the extension/lifecycle seam; easing/animation helpers.
