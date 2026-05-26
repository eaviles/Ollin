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
- **Consistent point arguments.** A primitive that takes a point offers both a
  scalar form (`x:`/`y:`) and a `Vector2` form, with the `Vector2` label naming
  the anchor: `circle(center:)`, `rect(corner:)`/`rect(center:)`, `line`,
  `translate`. New point-taking primitives (`ellipse`, `point`, `triangle`, …)
  should follow the same pattern.

## Sourcing & attribution (load-bearing — it's the public face)

This project is built with AI and says so openly (see the README's "Built with AI" and "Influences & attribution" sections). Getting attribution and license-compatibility right is the thing that earns the creative-coding community's trust — treat it as first priority, not a side chore.

The framework is *inspired by* p5.js (LGPL-2.1), OPENRNDR (BSD-2-Clause), and openFrameworks (MIT): borrow their ideas and API vocabulary, write the implementation independently. **Never translate their source line-by-line** — a port of source is a derivative work that carries the original's license, and p5.js's LGPL is incompatible with Ollin shipping wholesale as MIT. "Inspired by" keeps Ollin MIT-clean; "ported from source" does not.

For ported *example sketches* (the iterate-by-porting workflow), provenance is per-sketch and must be honored:

- **Only port sketches whose license permits redistribution under MIT** — MIT, BSD, Apache-2.0, CC0/public domain, or CC-BY (with credit). For GPL/LGPL, CC-BY-NC, or CC-BY-SA sources, either get permission or rewrite the sketch as original work using the source only as inspiration (credit it as "inspired by").
- **Name the source in the file header** — the specific sketch, its author, a URL, and its license. Template lives in `Examples/README.md`.
- When unsure of a sketch's origin or license, **ask before committing it.** A trivial sketch (a plain dot grid) may fall below the copyright-originality bar, but crediting the inspiration is still the default.
- **Recreations** (`Examples/Recreations/`, organized by artist) credit the artist, framed as a homage *after* them (not a reproduction, not endorsed), plus the SFPC "Recreating the Past" class that inspired the section. Some are *ported* from a source sketch, so they also carry the code-lineage header (e.g. the Molnár ones, via the p5 repo); others are *original* Ollin interpretations built directly from the artwork, with no code lineage (e.g. the Riley one). Either way, name the artist and work and keep the homage framing. See `Examples/Recreations/README.md`.
- **Keep framework names out of code.** The influence story (p5.js / OPENRNDR / openFrameworks) lives in this file, the README, and commit messages — *not* in `.swift` comments. Don't write comparison asides like `// p5 default` or `/// like oF's ofNoise`; keep the information, drop the name. The one *exception* is the per-example attribution header, which credits the actual source lineage. Source littered with running comparisons reads like a port and undercuts the "independent implementation, inspired-by not copied" stance.

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

## Rendering performance (roadmap)

The drawing model is *immediate-mode GPU*: every frame `Drawer` tessellates
each primitive into one flat triangle array on the CPU, the renderer uploads it
to a reused buffer, and issues a single `drawPrimitives`. This is the right
shape — it's what NanoVG, Dear ImGui, and Processing's GL renderer do — so the
"low-level" look is the cost of a Metal core, not accidental complexity. Don't
trade it for Core Graphics / SwiftUI `Canvas` / SpriteKit: those are CPU
rasterizers or retained-mode scene graphs, and adopting one as the substrate
throws away the GPU + shader ceiling the whole vision rests on.

Where it caps out, and the levers — in priority order, all *iterations on this
pipeline, not rewrites*:

- **CPU tessellation is the first bottleneck, not the GPU.** Re-tessellating
  thousands of primitives every frame on the draw thread stalls long before the
  GPU breaks a sweat. Everything below attacks that cost.
- **Instancing is the biggest lever.** Upload one unit-circle mesh once and draw
  it N times with a per-instance buffer (center, radius, color) via
  `drawPrimitives(instanceCount:)`. CPU work per circle drops to a struct write;
  this is the "10,000 circles at 60fps" path. It's a new `Pipeline` case
  (`.instancedCircle`) plus a per-instance buffer — the cache seam already
  exists for exactly this.
- **SDF circles trade triangles for a fragment-shader formula — better quality
  *and* often faster.** One quad per circle; compute coverage from the distance
  to the center in the fragment shader. Crisp at any size, with fill + stroke +
  anti-aliasing handled analytically (no reliance on MSAA). It doesn't
  generalize to arbitrary polygons, so treat it as a circle/ellipse/rounded-rect
  specialization, not a replacement for general fills.
- **MSAA caps anti-aliasing at 4×.** Fine for now; SDF coverage (above) is the
  upgrade path when thin strokes or large zoom reveal the limit.

Seam already in place: `MetalRenderer` builds pipelines through an enum-keyed
cache (`Pipeline` + `makePipeline(_:)`), so instanced/SDF pipelines slot in as
new cases instead of more `init` code.

One thing to *not* hand-roll: when vector `Shape`/`Contour` arrives (concave
polygons, holes), use a real polygon triangulator — libtess2, the GLU
tessellator lineage Processing/p5 descend from — rather than a bespoke
ear-clipper. Convex shapes (circle, rect, ellipse) stay fine with the current
fan/strip math.

## Build, run, verify

```sh
swift run Example-HelloCircle   # boots an 800x800 window running an example
```

- **Requires macOS 14+ and a Metal-capable GPU.**
- **This cannot be compiled in the Linux web container** (no Swift toolchain,
  no Metal). Changes here are unverified until built on a Mac — say so
  explicitly rather than claiming a change works.

## Current state & roadmap

- **Today:** `Sketch` base class; temporal state (`frameCount`, `time`,
  `deltaTime`, `frameRate`); mouse input (`mouseX`/`mouseY`, `mousePressed()`); `Drawer` + Metal
  renderer (solid fills, stroked outlines, 4x MSAA); shapes are `circle`, `rect`,
  `line`, and `polyline` (open stroked paths); a per-frame transform stack
  (`translate`/`rotate`/`scale`, scoped via `isolated { }`); `Vector2` and
  `Rectangle` geometry value types; `Color` value
  type with named constants (`.white`, `.black`, …); `map`/`dist` math helpers,
  seedable `random`/`noise` and `Double.tau`; a maintained `Examples/` set,
  including a `Recreations/` section (recreating past computer artists).
- **Next, in priority order:** more primitives (`ellipse`); the
  vector `Shape`/`Contour` type (closed shapes + fills, which `polyline` folds
  into); stroke joins/caps for fat lines; the extension/lifecycle seam;
  easing/animation helpers.

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

## Follow-up: ship an `Examples/` folder (sample projects) (underway)

Ship a curated `Examples/` directory of small, runnable sample projects in the Ollin repo itself, openFrameworks-style. These are the "learn it in an afternoon" on-ramp and the showroom — distinct from a personal sketchbook: examples are *maintained and versioned with the API* (they must always build against current Ollin), whereas throwaway sketches are not.

**Status (built so far):** the set is live — per-example folder + generic `Sketch.swift`, single-file `@main` via `Sketch.main()`, category folders (`Basic`/`Motion`/`Color`/`Patterns`/`Input`), and a `Recreations/` section organized **by artist** (recreating past computer artists as homages *after* them, SFPC-inspired; see `Examples/Recreations/README.md`). Each new feature ships with an example. The main piece left is CI compile-testing.

- **Layout: organized by topic, openFrameworks-style.** Group by feature so they read as a learning path — e.g. `hello`, `primitives`, `color`, `motion-and-time`, `transforms`, `shapes-contours`, `shaders`, `export`. Number or prefix for ordering. Each example is one minimal, focused sketch — show one idea well.
- **File convention: per-example folder, generic `Sketch.swift`.** Each example lives in `Examples/<Category>/<Name>/` and its file is always named `Sketch.swift` (openFrameworks `ofApp.cpp`-style) rather than `<Name>.swift` — the example's identity lives in the folder name, not a repeated filename. The per-example folder is also each sketch's home for its own assets (fonts, images, shaders sit alongside `Sketch.swift`), which is the reason not to flatten the layout. (The public-facing version of this note in `Examples/README.md` omits the `ofApp.cpp` reference.)
- **Mechanism: the single-file `@main` sketch.** SwiftPM allows only one entry point per executable target, so each example is its own small executable target (likely generated/scripted as the set grows — don't hand-maintain dozens of target stanzas). Make a sketch file self-contained by adding `static func main()` to `Sketch` on the core (`extension Sketch { static func main() { OllinApp.run(Self()) } }`, needs a `required init`), so an example is just `@main final class HelloCircle: Sketch { … }` with zero boilerplate. Build it once on the core so any single-file sketch flow (examples, scripting, embedding) can reuse it.
- **Convention: a feature isn't done until it has an example.** Each new primitive/capability ships with an example. Examples are also a forcing function for API quality — if the example is awkward to write, the API needs work (the p5-ergonomics test).
- **Examples are compile-tested docs.** Build every example in the macOS CI (see the open-source prep) so they never rot — this is the main argument for keeping them in-repo and current.
- **Reuse the same samples elsewhere.** Examples can seed the Swift Playgrounds `.swiftpm` starter (see the Swift Playgrounds follow-up) and serve as starter templates for new sketches. Author once.
