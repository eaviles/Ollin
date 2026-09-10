#### <sup>[Ollin](../README.md) → Examples</sup>

---

## Ollin examples

The examples are small, runnable sketches. Together they form a learning path, in the style of openFrameworks. Each example is one self-contained `@main` file that shows a single idea. The examples are maintained and versioned with the API, so they always build against current Ollin.

### Layout

Examples are grouped into **category** folders, and each example gets its own folder inside its category. One example is one executable target, because SwiftPM allows only one `@main` per target. The sketch file is always `Sketch.swift`, at `Examples/<Category>/<Name>/Sketch.swift`. The folder name is therefore the example's identity, and the folder also holds the sketch's own resources (fonts, images, shaders). A category that has grown large can group its sketches one level deeper, at `Examples/<Category>/<Group>/<Name>/Sketch.swift`. `3D/` is grouped by topic this way, and `Recreations/` is grouped by artist. The group name also becomes part of the target name (`Example-<Category>-<Group>-<Name>`). Each category has its own README that lists the sketches inside it:

| [![3D](https://media.ollin.art/examples/3D/Geometry/Planet/still-640.jpg)](3D/) | [![Audio](https://media.ollin.art/examples/Audio/OwnSampler/still-640.jpg)](Audio/) | [![Basic](https://media.ollin.art/examples/Basic/Describing/still-640.jpg)](Basic/) | [![Color](https://media.ollin.art/examples/Color/HSBWheel/still-640.jpg)](Color/) |
|---|---|---|---|
| [3D](3D/) | [Audio](Audio/) | [Basic](Basic/) | [Color](Color/) |
| [![Compute](https://media.ollin.art/examples/Compute/ReactionDiffusion/still-640.jpg)](Compute/) | [![Effects](https://media.ollin.art/examples/Effects/Droste/still-640.jpg)](Effects/) | [![Export](https://media.ollin.art/examples/Export/Cutout/still-640.jpg)](Export/) | [![Images](https://media.ollin.art/examples/Images/PhotoMosaic/still-640.jpg)](Images/) |
| [Compute](Compute/) | [Effects](Effects/) | [Export](Export/) | [Images](Images/) |
| [![Motion](https://media.ollin.art/examples/Motion/Mandala/still-640.jpg)](Motion/) | [![Patterns](https://media.ollin.art/examples/Patterns/Truchet/still-640.jpg)](Patterns/) | [![Physics](https://media.ollin.art/examples/Physics/RigidBodies/still-640.jpg)](Physics/) | [![Randomness](https://media.ollin.art/examples/Randomness/Variations/still-640.jpg)](Randomness/) |
| [Motion](Motion/) | [Patterns](Patterns/) | [Physics](Physics/) | [Randomness](Randomness/) |
| [![Recreations](https://media.ollin.art/examples/Recreations/OsamuSato/Totem/still-640.jpg)](Recreations/) | [![Rendering](https://media.ollin.art/examples/Rendering/Grassland/still-640.jpg)](Rendering/) | [![Shaders](https://media.ollin.art/examples/Shaders/VisualSynth/still-640.jpg)](Shaders/) | [![Shapes](https://media.ollin.art/examples/Shapes/Primitives/still-640.jpg)](Shapes/) |
| [Recreations](Recreations/) | [Rendering](Rendering/) | [Shaders](Shaders/) | [Shapes](Shapes/) |
| [![Simulation](https://media.ollin.art/examples/Simulation/GrayScott/still-640.jpg)](Simulation/) | [![Text](https://media.ollin.art/examples/Text/TypeAsGeometry/still-640.jpg)](Text/) | [![Video](https://media.ollin.art/examples/Video/VideoPlayback/still-640.jpg)](Video/) | [![Web](https://media.ollin.art/examples/Web/BreathingRing/still-640.jpg)](Web/) |
| [Simulation](Simulation/) | [Text](Text/) | [Video](Video/) | [Web](Web/) |

| Category | What's inside |
|---|---|
| [3D](3D/) | the 3D mode: meshes, camera, materials, lighting, environments, raymarched SDFs, depth feeds |
| [Audio](Audio/) | sound-reactive sketches (`import OllinAudio`) |
| [Basic](Basic/) | the smallest starting point |
| [Color](Color/) | palettes, colormaps, and color over time |
| [Compute](Compute/) | GPU compute: a million particles, and reaction-diffusion / texture simulations |
| [Data](Data/) | drawing from data: CSV tables and JSON documents, a polled feed, a pushed stream, and the weather over a city |
| [Effects](Effects/) | layered effects: GPU filters, feedback, generators, and the `compose { }` stack |
| [Export](Export/) | saving a sketch out: raster frame grab, vector SVG, and plotter hatching |
| [Images](Images/) | loading, drawing, tinting, and authoring images, plus glyph mosaics, pixel sorting, single-line renderings, and slit scan |
| [Input](Input/) | mouse-driven sketches |
| [Installation](Installation/) | pieces left running unattended, on a wall or in a window |
| [Integration](Integration/) | connecting to other apps and hardware: OSC, MIDI, DMX lighting, Syphon (`import OllinOSC` / `OllinMIDI` / `OllinDMX` / `OllinSyphon`) |
| [Live](Live/) | tunable `@Param` parameters under OllinLive |
| [Motion](Motion/) | animation driven by `time` |
| [Patterns](Patterns/) | generative patterns: grids, tessellations, rule-based repetition |
| [Physics](Physics/) | simulated motion (`import OllinPhysics`) |
| [Randomness](Randomness/) | `random`, `noise`, and scatter |
| [Rendering](Rendering/) | how the frame composites: blending, accumulation, HDR tone mapping, sandpainting |
| [Shaders](Shaders/) | writing your own GPU code: user shaders inline and from files, and fluent `Visual` chains |
| [Shapes](Shapes/) | the shape-drawing vocabulary: primitives, stroke and hollow modes, booleans, and SDF combinators |
| [Simulation](Simulation/) | systems evolving on the GPU: sim fields (`simField`), artificial life, particle fluids and soft bodies |
| [Text](Text/) | drawing text: bitmap, outline, and stroke fonts over one `drawText` |
| [Video](Video/) | recorded footage as drawing material (`import OllinVideo`) |
| [Vision](Vision/) | the camera plus on-device perception (`import OllinVision`) |
| [Web](Web/) | sketches made for a web page, limited to what a browser supports |
| [Recreations](Recreations/) | homages to past computer artists, by artist |

### Running

The examples are a package of their own, so run them from this directory. Each
one is a target whose name starts with `Example-`:

```sh
cd Examples
swift run Example-Basic-HelloCircle
swift run Example-Motion-SineSweep
```

Run `swift run` with no argument to list every runnable target. To run an example
from the repo root instead, name the package: `swift run --package-path Examples Example-Basic-HelloCircle`.

The commands in each category's README assume you are in this directory.
The examples are a separate package because SwiftPM builds every target of a
package. When the 350 sketch executables were in the root package, that meant
every `swift test` linked all of them.

You can also browse them all in one window. From the repo root, run:

```sh
swift run OllinExamples
```

The example list is on the left, grouped like the folders, with a filter bar at the bottom. The arrow keys move through the list. When you click a sketch, it compiles and runs in the middle. An inspector with live stats and `@Param` parameters is docked on the right. Both sidebars collapse from the title bar.

### Adding an example

1. Create `Examples/<Category>/<Name>/Sketch.swift` with an `@main final class <Name>: Sketch { … }`. You do not need an `OllinApp.run(...)` line, because `Sketch.main()` starts the sketch for you.
2. Add one line, `example("<Category>/<Name>")`, to the targets list in `Examples/Package.swift`. The helper derives the target name from the folder path, so the two cannot drift apart. A sketch that needs a satellite library passes it as the second argument, and co-located assets go in `resources:`.
3. Add a row to the category's `README.md`. A new category also needs its own `README.md` and a row in the table above.

By convention, a feature is not done until it has an example, and every example must compile. If a sketch is awkward to write, treat that as a sign that the API needs work, not the example.

### Recreations

`Recreations/` is a special section. Its sketches **recreate the work of past computer artists**, and they are organized by artist. SFPC's [Recreating the Past](https://sfpc.io/recreatingthepast-spring2020/) class inspired the section. Each sketch is a homage after the artist, not a reproduction, and the artist has not endorsed it. A short per-artist `README.md` introduces each artist. Each target name includes the artist's name:

```sh
swift run Example-Recreations-VeraMolnar-Interruptions
```

See [`Recreations/README.md`](Recreations/) for the full explanation.

### Attribution & sources

An example often *ports* a sketch from somewhere else. When one does, credit the source and respect its license:

- Add a header at the top of `Sketch.swift` that names the source:

  ```swift
  //  Ported from "<sketch>" by <author> — <url>
  //  Original license: <license>. Reworked for Ollin's API (Swift; Vector2/polyline).
  ```

- **Only port sources whose license permits redistribution under MIT:** MIT, BSD, Apache-2.0, CC0/public domain, or CC-BY (with credit). For GPL/LGPL, CC-BY-NC, or CC-BY-SA sources, rewrite the sketch as original work and use the source only as inspiration. Then credit it as "inspired by" instead.

An original sketch with no specific source needs no header. When something inspired it, you can add a one-line "inspired by …" note.

A sketch based on the maintainer's own work is credited by **serial number**. The header names the author and the S/N, not the private sketchbook the sketch came from. Use `// Ported from @eaviles's sketch 2025.003.` for a faithful port, or `// Based on elements of @eaviles's sketch 2023.023.` for a sketch that takes only some elements from the original. In both cases, follow the line with `Reworked for Ollin's API.`

For a **recreation** of a named artist's work (see `Recreations/`), also credit the artist in the header and in the per-artist `README.md`. Frame the sketch as a homage after the artist, not a reproduction, and note that the artist or their estate has not endorsed it.
