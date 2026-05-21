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

## Follow-up: Swift Playgrounds & iOS (not started)

Worth pursuing — the Swift Playgrounds app (Mac/iPad) App Projects (`.swiftpm`) are the closest Swift gets to the p5.js "open the editor and type, see it move" onboarding, and the same work unlocks iPad sketching and embedding in any SwiftUI app. On-brand for the "learn it in an afternoon" goal.

- **The architecture is already most of the way there.** `SketchView` is a SwiftUI-embeddable view, cleanly separated from the macOS-only `OllinApp.run` (which owns `NSApplication`). Embedding in someone else's SwiftUI `App` — what a Playgrounds App Project needs — is exactly that seam.
- **The blocker is iOS support.** Playgrounds App Projects build *iOS* apps, but Ollin only declares `.macOS(.v14)`. To make it importable: add `.iOS(...)` to `Package.swift`; make `SketchView` conditional (`NSViewRepresentable`/`AppKit` vs `UIViewRepresentable`/`UIKit` via `#if canImport(AppKit)` / `#if canImport(UIKit)`); guard `OllinApp.run` behind `#if os(macOS)`. The Metal renderer (`Metal`/`MetalKit`/`simd`) is already portable.
- **Keep shaders Playgrounds-safe.** Swift Playgrounds' support for SwiftPM build-tool plugins is unreliable, so do not go plugin-*only* for shaders — keep runtime source compilation as a first-class loader (see [Shaders & the Metal back end](#shaders--the-metal-back-end)).
- **Onboarding nicety:** ship a ready-made `.swiftpm` starter (Ollin pre-wired + a `HelloCircle`) so users don't hand-add the package URL.
- **Caveats:** the Playgrounds sandbox restricts file I/O (matters for the export roadmap items, not for drawing); package-dependency UX is finicky; prefer the Swift Playgrounds app's App Projects over the semi-deprecated Xcode Playgrounds. iOS changes can't be verified in this environment — they need `xcodebuild -destination` with the iOS SDK on a Mac.

## Follow-up: live reload — edit code, see it render (not started)

The headline creative-coding feature, and Ollin's loop is unusually well-suited: `SketchRunner.draw(in:)` runs every frame holding a *persistent* `Sketch` instance and re-calls `performDraw()`, so state (instance properties, `time`, `frameCount`, `setup()` resources) survives between frames. Swapping the body of `draw()` in the running process means the next frame just runs the new code with state intact — no re-run, no reset. Three tiers, cheapest first:

- **Tier 1 — live *shader* reload (nearly free; do first).** We already compile `Shaders.metal` from a bundled resource at runtime, so: file-watch it (`DispatchSource`/FSEvents), re-run `loadLibrary`, rebuild the pipeline, and the next frame uses the new shader. Self-contained, low-risk, on-brand. Cheap *because* of the runtime-compile decision (see [Shaders & the Metal back end](#shaders--the-metal-back-end)).
- **Tier 2 — live *Swift* reload (the real feature).** Use InjectionIII + the `Inject`/`HotReloading` SPM package: a watcher recompiles the changed `.swift` into a `.dylib`, `dlopen`s it, and interposes the new method bodies. A swapped `draw()` shows up next frame. Fits Ollin's persistent-instance loop perfectly.
- **Tier 3 — parameter live-tweak / GUI (complementary).** Sliders/values that mutate the running sketch with no recompile (OPENRNDR-style). Lighter, ties to the GUI item on the extension seam; not "change the code."

Prep to bake in now so Tier 2 isn't a retrofit:

- **A reload lifecycle hook (`onReload()`).** On injection you often want to optionally re-run `setup()` or reset the clock; `Inject` exposes `onInjection`. This lands exactly on the extension/lifecycle seam already on the roadmap — design that seam with reload in mind, don't bolt it on.
- **Keep `Sketch`/`draw()` `open` (already true) — never `final`.** Modern InjectionIII handles plain Swift via the debug-only `-Xlinker -interposable` flag, so `@objc dynamic` likely isn't needed — but validate that first.
- **Preserve the "loop re-calls `draw()` through the instance" model.** If a future change caches a closure to `draw` or snapshots it in the runner, injection breaks. The current `sketch.performDraw()`-every-frame call is what makes swapped code free.
- **Decide a state-reset policy:** instance state survives naturally; default to letting `time`/`frameCount` keep running, with an opt-in reset.
- **Caveats:** InjectionIII is debug-only, macOS/iOS, needs external tooling + build flags (smoothest in Xcode; terminal `swift run` is more DIY). Method-body edits are the sweet spot; changing stored-property layout or reallocating `setup()` GPU resources may need a relaunch. None of this is verifiable in this environment.
