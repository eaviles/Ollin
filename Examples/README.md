#### <sup>[Ollin](../README.md) → Examples</sup>

---

## Ollin examples

Small, runnable sketches that double as a learning path, openFrameworks-style. Each example is one self-contained `@main` file showing a single idea, maintained and versioned with the API (they always build against current Ollin).

### Layout

Examples are grouped into **category** folders, and each example gets its own folder inside its category (one example = one executable target, since SwiftPM allows a single `@main` per target). The sketch file is always `Sketch.swift`, at `Examples/<Category>/<Name>/Sketch.swift`, so the folder name is the example's identity and the folder also holds the sketch's own resources (fonts, images, shaders). A category that has grown large can group its sketches one level deeper, at `Examples/<Category>/<Group>/<Name>/Sketch.swift`: `3D/` is grouped by topic this way, and `Recreations/` by artist, with the group joining the target name (`Example-<Category>-<Group>-<Name>`). Each category has its own README listing the sketches inside:

| Category | What's inside |
|---|---|
| [3D](3D/) | the 3D mode: meshes, camera, materials, lighting, environments, raymarched SDFs, depth feeds |
| [Audio](Audio/) | sound-reactive sketches (`import OllinAudio`) |
| [Basic](Basic/) | the smallest starting point |
| [Color](Color/) | palettes, colormaps, and color over time |
| [Compute](Compute/) | GPU compute — a million particles, and reaction-diffusion / texture simulations |
| [Data](Data/) | drawing from a file: CSV tables and JSON documents |
| [Effects](Effects/) | layered effects — GPU filters, feedback, generators, and the `compose { }` stack |
| [Export](Export/) | saving a sketch out — raster frame grab, vector SVG, and plotter hatching |
| [Images](Images/) | loading, drawing, tinting, and authoring images, plus glyph mosaics, pixel sorting, single-line renderings, and slit scan |
| [Input](Input/) | mouse-driven sketches |
| [Integration](Integration/) | talking to other apps and gear — OSC, MIDI, Syphon (`import OllinOSC` / `OllinMIDI` / `OllinSyphon`) |
| [Live](Live/) | tunable `@Param` knobs under OllinLive |
| [Motion](Motion/) | animation driven by `time` |
| [Patterns](Patterns/) | generative patterns: grids, tessellations, rule-based repetition |
| [Physics](Physics/) | simulated motion (`import OllinPhysics`) |
| [Randomness](Randomness/) | `random`, `noise`, and scatter |
| [Rendering](Rendering/) | how the frame composites — blending, accumulation, HDR tone-mapping, sandpainting |
| [Shaders](Shaders/) | writing your own GPU code: user shaders inline and from files, and fluent `Visual` chains |
| [Shapes](Shapes/) | the shape-drawing vocabulary: primitives, stroke and hollow modes, booleans, and SDF combinators |
| [Simulation](Simulation/) | systems evolving on the GPU: sim fields (`simField`), artificial life, particle fluids and soft bodies |
| [Text](Text/) | drawing text — bitmap, outline, and stroke fonts over one `drawText` |
| [Video](Video/) | recorded footage as drawing material (`import OllinVideo`) |
| [Vision](Vision/) | the camera plus on-device perception (`import OllinVision`) |
| [Recreations](Recreations/) | homages to past computer artists, by artist |

### Running

The examples are a package of their own, so run them from this directory. Each
one is a target prefixed `Example-`:

```sh
cd Examples
swift run Example-Basic-HelloCircle
swift run Example-Motion-Breathing
```

(Run `swift run` with no argument to list every runnable target.) From the repo
root instead, name the package: `swift run --package-path Examples Example-Basic-HelloCircle`.

The commands in the per-category READMEs below assume you are in this directory.
They live here because SwiftPM builds every target of a package, so keeping 350
sketch executables in the root package meant `swift test` linked all of them.

Or browse them all in one window, from the repo root:

```sh
swift run OllinExamples
```

The example list sits on the left, grouped like the folders, with a filter bar at the bottom; the arrow keys walk it. Click a sketch and it compiles and runs in the middle, with an inspector of live stats and `@Param` knobs docked on the right. Both sidebars collapse from the title bar.

### Adding an example

1. Create `Examples/<Category>/<Name>/Sketch.swift` with an `@main final class <Name>: Sketch { … }`. No `OllinApp.run(...)` line; `Sketch.main()` boots it for you.
2. Add a matching `.executableTarget(name: "Example-<Category>-<Name>", dependencies: ["Ollin"], path: "Examples/<Category>/<Name>")` in `Package.swift`.
3. Add a row to the category's `README.md` (and a new category gets its own `README.md` plus a row in the table above).

Convention: a feature isn't considered done until it has an example, and every example must compile. If a sketch is awkward to write, treat that as a signal that the API needs work rather than the example.

### Recreations

`Recreations/` is a special section: sketches that **recreate the work of past computer artists**, organized by artist, inspired by SFPC's [Recreating the Past](https://sfpc.io/recreatingthepast-spring2020/) class. Each one is a homage after the artist, not a reproduction and not endorsed by them, with a short per-artist `README.md` introducing them. Their targets are namespaced by artist:

```sh
swift run Example-Recreations-VeraMolnar-Interruptions
```

See [`Recreations/README.md`](Recreations/) for the full idea.

### Attribution & sources

Examples often *port* a sketch from elsewhere. When one does, credit it and respect its license:

- Add a header at the top of `Sketch.swift` naming the source:

  ```swift
  //  Ported from "<sketch>" by <author> — <url>
  //  Original license: <license>. Reworked for Ollin's API (Swift; Vector2/polyline).
  ```

- **Only port sources whose license permits redistribution under MIT:** MIT, BSD, Apache-2.0, CC0/public domain, or CC-BY (with credit). For GPL/LGPL, CC-BY-NC, or CC-BY-SA sources, rewrite the sketch as original work using the source only as inspiration, and credit it as "inspired by" instead.

An original sketch (no specific source) needs no header, but a one-line "inspired by …" note is welcome when something sparked it.

A sketch drawn from the maintainer's own work is credited by **serial number** — naming the author and S/N, not the private sketchbook it came from. Use `// Ported from @eaviles's sketch 2025.003.` for a faithful port, or `// Based on elements of @eaviles's sketch 2023.023.` for a reduced or partial derivation — each followed by `Reworked for Ollin's API.`

For a **recreation** of a named artist's work (see `Recreations/`), also credit the artist in the header and the per-artist `README.md`, framed as a homage after them, not a reproduction, and not endorsed by the artist or their estate.
