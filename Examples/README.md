#### <sup>[Ollin](../README.md) → Examples</sup>

---

## Ollin examples

Small, runnable sketches that double as a learning path, openFrameworks-style. Each example is one self-contained `@main` file showing a single idea, maintained and versioned with the API (they always build against current Ollin).

### Layout

Examples are grouped into **category** folders, and each example gets its own folder inside its category (one example = one executable target, because SwiftPM allows a single `@main` entry point per target). The sketch file is always named `Sketch.swift`, and the example's identity lives in the folder name, so the filename stays generic instead of repeating it. The folder is also each sketch's home for its own resources: fonts, images, and shaders sit alongside `Sketch.swift`.

```
Examples/
  Basic/
    HelloCircle/Sketch.swift   — a still circle: the smallest program
  Motion/
    Breathing/Sketch.swift     — the same circle, animated via `time`
    SineSweep/Sketch.swift     — a circle swept across the canvas by `sin(time)`
    Orbits/Sketch.swift        — ten circles orbiting the center at rising speeds
    Trail/Sketch.swift         — a Lissajous point traced by a 600-segment polyline
    FlowField/Sketch.swift     — a `curlNoise` flow field: short lines follow the divergence-free curl, drifting with `time`
  Color/
    ColorWaves/Sketch.swift    — a row of sin-colored circles flowing with `time`
    Palettes/Sketch.swift      — seven cosine-gradient `Palette` presets, each swept across the canvas and scrolled
    Colormaps/Sketch.swift     — the eight perceptual `Colormap` ramps as horizontal bands (value → color)
  Patterns/
    DotGrid/Sketch.swift       — a grid of black/white dots woven by a modulo rule
    WarpGrid/Sketch.swift      — a checkerboard of rects warped under the mouse (`drawRect`)
    EnergyGrid/Sketch.swift    — columns sized by a moving "energy" share (`translate`, `drawRect`)
  Randomness/
    NoiseField/Sketch.swift    — an 80×80 grid shaded by 3D Perlin `noise`, scrubbed by the mouse
    RandomBand/Sketch.swift    — a band of dots jittered by `random` (jagged); re-rolls with the mouse
    Gaussian/Sketch.swift      — 2000 dots a frame placed by `randomGaussian`: the bell curve made visible
    Ring/Sketch.swift          — dots scattered in an annulus by `ring()`, `scale`-relative so it holds its proportion
    NoiseWave/Sketch.swift     — a wave of dots offset by `signedNoise` (smooth); the noise counterpart
  Input/
    RepelGrid/Sketch.swift     — a grid of dots that flee the cursor (`mouseX`/`mouseY`)
  Live/
    Parameters/Sketch.swift    — tunable `@Param` knobs that become live inspector sliders under OllinLive
  Recreations/                 — recreating past computer artists, by artist
    VeraMolnar/Interruptions/Sketch.swift  — after Vera Molnár (`withState`, `drawLine`, `random`, `noise`)
    VeraMolnar/DesOrdres/Sketch.swift      — after Molnár's "(Dés)Ordres" (1974); concentric squares, ~5% disorder (`drawRect(center:)`)
    BridgetRiley/Fragment3/Sketch.swift    — after Riley's "Fragment 3" (1965); black/white chevron Op-art (`drawPolygon`, `noLoop`)
```

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
