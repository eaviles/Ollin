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

## Platform scope

Apple platforms only, by design. macOS is the focus today; iOS, tvOS, and visionOS are in scope as *future* targets (see the Swift Playgrounds / iOS follow-up and the 3D & visionOS follow-up). Linux and Windows are explicitly out of scope — not now, not later — so don't add cross-platform abstractions for them: lean on Metal, AppKit/UIKit, and SwiftUI freely. "No Linux/Windows" is not "macOS-only"; keep Apple-platform portability in mind (the `#if canImport(AppKit)`/`#if canImport(UIKit)` seams) so the iOS/visionOS work later isn't a retrofit.

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

There's a second tier of influence worth distinguishing from the conceptual one. Where p5.js / OPENRNDR / openFrameworks shaped the *API and ideas*, two peer Swift+Metal frameworks were read for *engineering approach* on the same platform: **swifty-creatives** (Apache-2.0, Processing-style immediate-mode) and **AsyncGraphics** (MIT, GPU image/video compositing). They were studied, not ported — specific lessons are noted inline through this file (shader build, pipeline cache, SDF circle, iOS seam, easing, snapshot testing). Same rules apply: credit them in the README and commits, never in `.swift` comments, and write our own implementation. The public credit lives in the README's Influences & attribution. (PixelKit is AsyncGraphics's older node-graph predecessor; cite AsyncGraphics instead.)

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
  Build-time validation and zero startup cost need the built-in shaders compiled
  ahead of time. `loadLibrary` already prefers a precompiled `Bundle.module`
  metallib *before* the source path, so a precompiled lib slots in with no API
  change; runtime compilation stays for dynamic shaders. Two facts settle *how*
  to produce it (both verified on this toolchain — Swift 6.3, macOS):
    - **`swift run` does not compile loose `.metal`.** Dropping a `.metal` in
      the target as plain undeclared source only earns a `found 1 file(s) which
      are unhandled` warning; no metallib is produced and
      `makeDefaultLibrary(bundle: .module)` throws "no default library." That
      auto-compile is an *Xcode*-build-system behavior — which is how peer
      frameworks ship 100+ loose `.metal` files with no plugin, but it does not
      carry over to Ollin's `swift run` workflow. (And `.process(...)`/`.copy`
      on a `.metal` just copies it as *source*, never compiles it.)
    - **A precompiled `default.metallib` shipped as a `.copy` resource loads
      fine.** `xcrun metal` + `xcrun metallib` produce a `default.metallib`;
      `.copy`-listed in the target, it's found by `makeDefaultLibrary(bundle:
      .module)`. So under `swift run` the path is a SwiftPM build-tool plugin
      that runs that compile and emits the metallib as a resource. (Playgrounds
      plugin support is unreliable — see the iOS follow-up — so keep runtime
      source compilation too; never go plugin-*only*.)
- **A user-supplied shader-library seam is cheap.** Resolve the active library
  as `customMetalLibrary ?? defaultMetalLibrary` so a user can drop in their own
  compiled library without touching the built-ins; pairs with the runtime-source
  loader for hot-reload. (Both peer Swift+Metal frameworks expose exactly this.)
- **Cache pipelines; don't grow `init`.** `MetalRenderer.init` builds one
  `MTLRenderPipelineState` inline. A new pipeline (textured quads, a new blend
  mode, compute) should be a cache lookup, not more code in the constructor.
  Key the cache on a `Hashable` descriptor struct (shader, blend mode, MSAA
  sample count, pixel format), not a flat enum: pipeline variants are
  *combinations* of those axes, and a struct key captures the product without an
  enum case per combination. Folding blend mode into that descriptor also keeps
  it a pipeline *parameter* — one pipeline factory — rather than a whole renderer
  subclass per blend mode (the trap a peer framework fell into).
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
  specialization, not a replacement for general fills. A worked reference for
  this exact technique — distance-to-center, analytic edge AA, a separate edge
  color for stroke — exists in AsyncGraphics's circle fragment shader (MIT).
  Study the approach; write our own, don't copy it.
- **MSAA caps anti-aliasing at 4×.** Fine for now; SDF coverage (above) is the
  upgrade path when thin strokes or large zoom reveal the limit.

Seam already in place: `MetalRenderer` builds pipelines through an enum-keyed
cache (`Pipeline` + `makePipeline(_:)`), so instanced/SDF pipelines slot in as
new cases instead of more `init` code. Once variants multiply across blend mode
× MSAA × pixel format, migrate that enum key to a `Hashable` descriptor struct
(see *Cache pipelines* above) rather than enumerating the product by hand.

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
  `line`, `polyline` (open stroked paths), and convex `polygon`; a per-frame transform stack
  (`translate`/`rotate`/`scale`, scoped via `isolated { }`); `Vector2` and
  `Rectangle` geometry value types; `Color` value
  type with named constants (`.white`, `.black`, …) plus a cosine-gradient
  `Palette` (iq's formula); `map`/`dist` math helpers, seedable `random`/`noise`
  (incl. `randomGaussian` and `curlNoise` flow fields) and `Double.tau`; a maintained `Examples/` set,
  including a `Recreations/` section (recreating past computer artists); headless
  single-frame PNG export (`--export` / `OllinApp.export`, off-screen MSAA render);
  live reload (`swift run OllinLive <file>`) that recompiles + hot-swaps a sketch
  on save and live-reloads `Shaders.metal` (with a `--keep-clock` flag and an
  `onReload()` lifecycle hook; see the live-reload section).
- **Next, in priority order:** more primitives (`ellipse`); the vector
  `Shape`/`Contour` type — concave fills via a real triangulator (convex
  `polygon` already landed); stroke joins/caps for fat lines; the
  extension/lifecycle seam; easing/animation helpers. For easing, a clean shape
  to borrow is a property wrapper holding a value + target that eases toward the
  target each frame (`linear`/`easeOut`); swifty-creatives' `@SCAnimatable` is a
  small worked reference.

## Follow-up: Swift Playgrounds & iOS (not started)

Worth pursuing — the Swift Playgrounds app (Mac/iPad) App Projects (`.swiftpm`) are the closest Swift gets to the p5.js "open the editor and type, see it move" onboarding, and the same work unlocks iPad sketching and embedding in any SwiftUI app. On-brand for the "learn it in an afternoon" goal.

- **The architecture is already most of the way there.** `SketchView` is a SwiftUI-embeddable view, cleanly separated from the macOS-only `OllinApp.run` (which owns `NSApplication`). Embedding in someone else's SwiftUI `App` — what a Playgrounds App Project needs — is exactly that seam.
- **The blocker is iOS support.** Playgrounds App Projects build *iOS* apps, but Ollin only declares `.macOS(.v14)`. To make it importable: add `.iOS(...)` to `Package.swift`; make `SketchView` conditional (`NSViewRepresentable`/`AppKit` vs `UIViewRepresentable`/`UIKit` via `#if canImport(AppKit)` / `#if canImport(UIKit)`); guard `OllinApp.run` behind `#if os(macOS)`. The Metal renderer (`Metal`/`MetalKit`/`simd`) is already portable. A working reference for this exact seam: swifty-creatives compiles for macOS/iOS/tvOS/visionOS from one source using a `ViewRepresentable` typealias (`NSViewRepresentable`/`UIViewRepresentable`) with `#if os(...)`-guarded `makeNSView`/`makeUIView` — worth reading when we do this.
- **Keep shaders Playgrounds-safe.** Swift Playgrounds' support for SwiftPM build-tool plugins is unreliable, so do not go plugin-*only* for shaders — keep runtime source compilation as a first-class loader (see [Shaders & the Metal back end](#shaders--the-metal-back-end)).
- **Onboarding nicety:** ship a ready-made `.swiftpm` starter (Ollin pre-wired + a `HelloCircle`) so users don't hand-add the package URL.
- **Caveats:** the Playgrounds sandbox restricts file I/O (matters for the export roadmap items, not for drawing); package-dependency UX is finicky; prefer the Swift Playgrounds app's App Projects over the semi-deprecated Xcode Playgrounds. iOS changes can't be verified in this environment — they need `xcodebuild -destination` with the iOS SDK on a Mac.

## Live reload — edit code, see it render (shipped via `OllinLive`)

The headline creative-coding feature, and it's built. `swift run OllinLive <path/to/Sketch.swift>` opens a window, watches the file, and on save recompiles *just that sketch* into a `.dylib` and hot-swaps it into the running loop — the window never closes. This is the Olive / canvas-sketch model (a persistent host owns the window; the sketch is the swappable unit), chosen over InjectionIII because that needs an external app and is finicky on the terminal `swift run` workflow Ollin lives in. Code is in `Sources/OllinLive/` (`main`, `SketchLoader`, `FileWatcher`, `LiveSession`, plus `--selftest`/`--watchtest` headless smoke tests); the runner-side swap is `SketchRunner.reload(to:)` in `SketchView.swift`.

How it works, and the load-bearing decisions (most are cheap-to-forget, expensive-to-rediscover):

- **Host + swappable sketch dylib.** `OllinApp.boot(_:)` (split out of `run`) builds the window/runner *without* starting the run loop, so OllinLive wires a watcher to `SketchRunner.reload(to:)` and then runs. `SketchRunner.sketch` is a `var`; the loop already calls `sketch.performDraw()` through the instance, so swapping the var means the next frame runs new code.
- **`-undefined dynamic_lookup`, not a dynamic Ollin product.** The sketch dylib compiles with `-I <bin>/Modules` (to type-check `import Ollin`) and `-undefined dynamic_lookup` with *no* `-lOllin`; the host links `-Xlinker -export_dynamic` so the dylib's Ollin symbols resolve against the host at `dlopen`. One copy of `Sketch`, so the loaded object casts as `Ollin.Sketch`. **A `.dynamic` Ollin product does not fix this** — SwiftPM still links the target statically into the executable, giving two copies and a failed cast (verified the hard way). Each load uses a unique `-module-name` so repeated reloads of the same class don't collide in the objc runtime.
- **A generated factory shim.** The loader regexes the `class …: Sketch` name and compiles a sibling `@_cdecl("ollin_make_sketch")` file alongside the user's source, so the user file is untouched and its `@main` is harmless (it compiles fine under `-emit-library`).
- **FSEvents on the *directory*.** Editors save atomically (temp file + rename), which breaks fd-based watches; `FileWatcher` watches directories with `kFSEventStreamCreateFlagUseCFTypes | …FileEvents` (the UseCFTypes flag is required or the path-array cast crashes), debounced ~150ms. It dispatches by extension: `.swift` → recompile + swap; `.metal` → `MetalRenderer.reloadLibrary(source:)` (live shader reload — what used to be "Tier 1," now folded in, and active only when run from the repo); image assets → re-run `setup()` (a forward hook; image *loading* isn't a feature yet).
- **Resilience + threading.** Recompile runs off the main thread (the window keeps drawing the old sketch); the swap is marshaled to the main queue. A compile error is printed and the running sketch is left alone — a typo never closes the window. `MetalRenderer.reloadLibrary` builds the new pipelines before committing, so a bad shader edit can't blank the renderer.
- **State on reload: fresh restart by default; `--keep-clock` to continue.** `reload(to:keepClock:)` re-instantiates and re-runs `setup()`; by default it resets `time`/`frameCount`, and `--keep-clock` carries them forward (offsets `startTime` so `time` continues, copies `frameCount`) so an animation's phase doesn't jump. Either way instance state resets (fresh instance). `Sketch.onReload()` (lifecycle hook) fires once after the post-reload setup (never on first launch). Matches Olive/canvas-sketch.
- **Keep `Sketch`/`draw()` `open`** (already true) — the dylib subclass must override them; never `final`.

Window title: `"Ollin - <SketchName>"` (plain hyphen, not a middot). @eaviles ruled out FPS-in-the-title (the oF idiom); live FPS belongs in the GUI panel below, not the title bar.

Still open:

- **GUI / parameter knobs (the old "Tier 3").** Tune a live sketch with sliders, and surface live FPS here (the oF idiom, deliberately kept out of the title bar). Clean split: a typed parameter model in the `Ollin` core (a `@Param`-style wrapper / registry, à la OPENRNDR `@DoubleParameter`) and a SwiftUI inspector panel in the OllinLive host. The host owning the panel is the point — knob values *persist across reloads* (re-applied by name to the fresh instance). Ties to the extension/lifecycle seam. OllinLive's window is still plain `contentView = MTKView`; recompose it as a split/side-panel layout when this lands.

## Follow-up: layered effects & compositing (not started)

A direction @eaviles wants on the radar: OPENRNDR-style effects that compose in *layers* — draw into off-screen targets, run filters (blur, bloom, feedback, color grades) over them, and composite the results with blend modes. This is the natural home for post-processing, and it rhymes with the extension seam (effects are "after draw" passes) and with user-supplied shaders (each effect is a fragment shader over a texture).

- **The plumbing is partly here.** The `--export` path already renders off-screen into a texture (MSAA → resolve). A render target a sketch can draw *into* and then sample is the same capability surfaced as API — that's the seam to build on, not a new substrate.
- **Shape to aim for.** A render-target / layer value type (a texture you draw into), a `Filter` notion (a fragment shader from one texture to another, with parameters), and composite-with-blend-mode. Blend mode wants to be a pipeline parameter in the `Hashable` pipeline descriptor (see [Shaders & the Metal back end](#shaders--the-metal-back-end)), not a renderer subclass.
- **Swift+Metal reference.** AsyncGraphics is the concrete study here: its `Graphic` *is* an `MTLTexture`, effects are functions returning new graphics, and it ships blend modes + a stack/layout layer model. The API paradigm (async, immutable) differs from Ollin's immediate-mode loop, so borrow the compositing/effects *architecture*, not the call shape. OPENRNDR's `Filter` / `compose {}` / `RenderTarget` is the conceptual model.
- **Bigger than a primitive.** This touches the renderer (multiple render passes, target management) and the extension seam at once. Design it deliberately when the seam lands; don't bolt it on.

## Follow-up: offline frame-sequence export (not started)

Single-frame PNG export already works (`--export`, off-screen MSAA render). The next step is exporting a whole *sequence* — the thing that turns an animated sketch into a video.

- **The load-bearing idea: decouple the simulation clock from wall-clock.** In the live loop, `time`/`deltaTime`/`frameCount` track real time at the display refresh rate (60fps respected). In *export* mode they don't: advance them by a fixed step (`deltaTime = 1/exportFPS`, `time = frameCount / exportFPS`) for each rendered frame, regardless of how long that frame takes to render. @eaviles is explicit that export is offline — taking 10–15 minutes of wall-clock to render a sequence is fine, as long as the frames assemble into a smooth 60fps video.
- **So export mode is a fixed-timestep, deterministic render.** Constant `deltaTime`, no wall-clock reads, seeded `random`/`noise` (already deterministic), so frame N is identical every run. Anything in a sketch that reads real time instead of `time` would break determinism — the API should keep `time` the obvious thing to reach for.
- **Output.** Numbered PNGs (`frame_00001.png …`) for a frame range or a duration × fps, written from the same off-screen MSAA render path `--export` uses. Optional ffmpeg assembly to mp4/mov at the target fps, or just emit frames and let the user run ffmpeg. GIF later.
- **Where it hangs.** Drive it from the frame-grab lifecycle hook (the extension seam) over a headless render loop that steps the fixed clock, renders, writes, repeats — no window, no vsync.

## Follow-up: 3D mode & visionOS (eventual; 2D stays primary)

2D is the focus now and stays the default — Ollin is a 2D creative-coding framework first. But @eaviles wants a 3D mode eventually, with visionOS support, so keep the back end from foreclosing it.

- **What 3D needs.** A camera (perspective/ortho) feeding view + projection matrices; a depth buffer (`depth32Float[_stencil8]`) plus depth-stencil state in the pipeline; the CTM stack generalized from 2D affine to `f4x4`; a `Vector3` and 3D primitives (box, sphere, mesh/`.obj`). The Hashable pipeline descriptor already anticipated this — it carries a `depth` axis (see [Shaders & the Metal back end](#shaders--the-metal-back-end)), so a depth-tested pipeline is a new descriptor, not a new renderer.
- **visionOS is a different render loop.** Immersive rendering doesn't use `MTKView`/`SketchRunner.draw(in:)`; it uses CompositorServices (`LayerRenderer`) driven by a manual render thread, plus ARKit world tracking. Keep the per-frame loop behind a seam that either an `MTKViewDelegate` or a visionOS layer renderer can drive, rather than assuming `MTKView` everywhere.
- **Reference.** swifty-creatives is the concrete study: it ships both a normal `MTKView` renderer and a visionOS `RendererBase` with a manual `renderLoop()` over `LayerRenderer`, and it's 3D-first (camera, depth, box/3D-text). Borrow the structure — camera + depth pipeline + dual render loop — and write our own.
- **Don't 3D-tax the 2D path.** Most sketches stay 2D; don't make every draw call pay for a depth buffer or perspective divide. 3D is a mode you opt into, not a cost the 2D core carries. (Apple-only either way — see [Platform scope](#platform-scope).)
- **Caveat:** visionOS is unverifiable in this environment without the visionOS SDK plus simulator or device.

## Follow-up: ship an `Examples/` folder (sample projects) (underway)

Ship a curated `Examples/` directory of small, runnable sample projects in the Ollin repo itself, openFrameworks-style. These are the "learn it in an afternoon" on-ramp and the showroom — distinct from a personal sketchbook: examples are *maintained and versioned with the API* (they must always build against current Ollin), whereas throwaway sketches are not.

**Status (built so far):** the set is live — per-example folder + generic `Sketch.swift`, single-file `@main` via `Sketch.main()`, category folders (`Basic`/`Motion`/`Color`/`Patterns`/`Input`), and a `Recreations/` section organized **by artist** (recreating past computer artists as homages *after* them, SFPC-inspired; see `Examples/Recreations/README.md`). Each new feature ships with an example. The main piece left is CI compile-testing.

- **Layout: organized by topic, openFrameworks-style.** Group by feature so they read as a learning path — e.g. `hello`, `primitives`, `color`, `motion-and-time`, `transforms`, `shapes-contours`, `shaders`, `export`. Number or prefix for ordering. Each example is one minimal, focused sketch — show one idea well.
- **File convention: per-example folder, generic `Sketch.swift`.** Each example lives in `Examples/<Category>/<Name>/` and its file is always named `Sketch.swift` (openFrameworks `ofApp.cpp`-style) rather than `<Name>.swift` — the example's identity lives in the folder name, not a repeated filename. The per-example folder is also each sketch's home for its own assets (fonts, images, shaders sit alongside `Sketch.swift`), which is the reason not to flatten the layout. (The public-facing version of this note in `Examples/README.md` omits the `ofApp.cpp` reference.)
- **Mechanism: the single-file `@main` sketch.** SwiftPM allows only one entry point per executable target, so each example is its own small executable target (likely generated/scripted as the set grows — don't hand-maintain dozens of target stanzas). Make a sketch file self-contained by adding `static func main()` to `Sketch` on the core (`extension Sketch { static func main() { OllinApp.run(Self()) } }`, needs a `required init`), so an example is just `@main final class HelloCircle: Sketch { … }` with zero boilerplate. Build it once on the core so any single-file sketch flow (examples, scripting, embedding) can reuse it.
- **Convention: a feature isn't done until it has an example.** Each new primitive/capability ships with an example. Examples are also a forcing function for API quality — if the example is awkward to write, the API needs work (the p5-ergonomics test).
- **Examples are compile-tested docs.** Build every example in the macOS CI (see the open-source prep) so they never rot — this is the main argument for keeping them in-repo and current.
- **Next level: render-correctness snapshot testing.** Compile-testing proves an example *builds*; image-snapshot tests prove it *renders the same*. The off-screen MSAA render behind `--export` is the hard prerequisite, and it already exists — so this is cheap to reach. The shape: a frame-grab lifecycle hook (the extension seam) returns the rendered texture, and a test compares it against a committed reference image, per primitive. A peer Swift+Metal framework does exactly this (per-primitive snapshot tests via a `afterCommit(texture:)` hook gated behind `#if canImport(XCTest)`, using pointfree's swift-snapshot-testing) — a concrete model. Design the frame-grab hook with this in mind.
- **Reuse the same samples elsewhere.** Examples can seed the Swift Playgrounds `.swiftpm` starter (see the Swift Playgrounds follow-up) and serve as starter templates for new sketches. Author once.
