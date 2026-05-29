#### <sup>[Ollin](../README.md) → Examples</sup>

---

## Ollin examples

Small, runnable sketches that double as a learning path, openFrameworks-style. Each example is one self-contained `@main` file showing a single idea, maintained and versioned with the API (they always build against current Ollin).

### Layout

Examples are grouped into **category** folders, and each example gets its own folder inside its category (one example = one executable target, since SwiftPM allows a single `@main` per target). The sketch file is always `Sketch.swift`, at `Examples/<Category>/<Name>/Sketch.swift`, so the folder name is the example's identity and the folder also holds the sketch's own resources (fonts, images, shaders). Each category has its own README listing the sketches inside:

| Category | What's inside |
|---|---|
| [Basic](Basic/) | the smallest starting point |
| [Motion](Motion/) | animation driven by `time` |
| [Color](Color/) | palettes, colormaps, and color over time |
| [Patterns](Patterns/) | grids and rule-based repetition |
| [Randomness](Randomness/) | `random`, `noise`, and scatter |
| [Input](Input/) | mouse-driven sketches |
| [Live](Live/) | tunable `@Param` knobs under OllinLive |
| [Recreations](Recreations/) | homages to past computer artists, by artist |

### Running

Each example is its own target, prefixed `Example-`:

```sh
swift run Example-HelloCircle
swift run Example-Breathing
```

(Run `swift run` with no argument to list every runnable target.)

Or browse them all in one window:

```sh
swift run OllinExamples
```

A sidebar lists every example; click one and it compiles and renders on the right.

### Adding an example

1. Create `Examples/<Category>/<Name>/Sketch.swift` with an `@main final class <Name>: Sketch { … }`. No `OllinApp.run(...)` line; `Sketch.main()` boots it for you.
2. Add a matching `.executableTarget(name: "Example-<Name>", dependencies: ["Ollin"], path: "Examples/<Category>/<Name>")` in `Package.swift`.
3. Add a row to the category's `README.md` (and a new category gets its own `README.md` plus a row in the table above).

Convention: a feature isn't considered done until it has an example, and every example must compile. If a sketch is awkward to write, treat that as a signal that the API needs work rather than the example.

### Recreations

`Recreations/` is a special section: sketches that **recreate the work of past computer artists**, organized by artist, inspired by SFPC's [Recreating the Past](https://sfpc.io/recreatingthepast-spring2020/) class. Each one is a homage after the artist, not a reproduction and not endorsed by them, with a short per-artist `README.md` introducing them. Their targets are namespaced by artist:

```sh
swift run Example-VeraMolnar-Interruptions
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

For a **recreation** of a named artist's work (see `Recreations/`), also credit the artist in the header and the per-artist `README.md`, framed as a homage after them, not a reproduction, and not endorsed by the artist or their estate.
