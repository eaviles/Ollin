# Ollin examples

Small, runnable sketches that double as a learning path — openFrameworks-style. Each example is one self-contained `@main` file showing a single idea, maintained and versioned with the API (they always build against current Ollin).

## Layout

Examples are grouped into **category** folders, and each example gets its own folder inside its category (one example = one executable target, because SwiftPM allows a single `@main` entry point per target). The sketch file is always named `Sketch.swift` — the example's identity lives in the folder name, so the filename stays generic instead of repeating it. The folder is also each sketch's home for its own resources: fonts, images, and shaders sit alongside `Sketch.swift`.

```
Examples/
  Basic/
    HelloCircle/Sketch.swift   — a still circle: the smallest program
  Motion/
    Breathing/Sketch.swift     — the same circle, animated via `time`
    SineSweep/Sketch.swift     — a circle swept across the canvas by `sin(time)`
    Orbits/Sketch.swift        — ten circles orbiting the center at rising speeds
    Trail/Sketch.swift         — a Lissajous point traced by a 600-segment polyline
  Color/
    ColorWaves/Sketch.swift    — a row of sin-colored circles flowing with `time`
  Patterns/
    DotGrid/Sketch.swift       — a grid of black/white dots woven by a modulo rule
  Input/
    RepelGrid/Sketch.swift     — a grid of dots that flee the cursor (`mouseX`/`mouseY`)
```

## Running

Each example is its own target, prefixed `Example-`:

```sh
swift run Example-HelloCircle
swift run Example-Breathing
```

(Run `swift run` with no argument to list every runnable target.)

## Adding an example

1. Create `Examples/<Category>/<Name>/Sketch.swift` with an `@main final class <Name>: Sketch { … }`. No `OllinApp.run(...)` line — `Sketch.main()` boots it for you.
2. Add a matching `.executableTarget(name: "Example-<Name>", dependencies: ["Ollin"], path: "Examples/<Category>/<Name>")` in `Package.swift`.

Convention: a feature isn't done until it has an example, and every example must compile. If a sketch is awkward to write, that's a signal the API needs work, not the example.

## Attribution & sources

Examples often *port* a sketch from elsewhere. When one does, credit it and respect its license:

- Add a header at the top of `Sketch.swift` naming the source:

  ```swift
  //  Ported from "<sketch>" by <author> — <url>
  //  Original license: <license>. Reworked for Ollin's API (Swift; Vector2/polyline).
  ```

- **Only port sources whose license permits redistribution under MIT** — MIT, BSD, Apache-2.0, CC0/public domain, or CC-BY (with credit). For GPL/LGPL, CC-BY-NC, or CC-BY-SA sources, rewrite the sketch as original work using the source only as inspiration, and credit it as "inspired by" instead.

An original sketch (no specific source) needs no header, but a one-line "inspired by …" note is welcome when something sparked it.
