#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Variations`</sup>

---

## Variations

A seeded sketch is a *generator*: one number decides which of its many possible pieces you're looking at. Ollin gives that number a name, `variation`, shows it while the sketch runs, embeds it in every export, and hands you the tools to explore the space it indexes: step to the next seed, roll a random one, proof a whole range as a contact sheet, then re-render the keeper at full resolution.

Nothing here changes what a sketch draws. It changes how you find the one you want to keep.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/04-Randomness/SeedSheet-dark.jpg">
  <img src="../../Guide/Images/04-Randomness/SeedSheet.jpg" alt="Nine tiles, each a small constellation of orange dots joined by faint lines, labeled seed 1 through seed 9, every tile a distinctly different arrangement" width="560">
</picture>

### Contents

- [Every sketch has a variation](#every-sketch-has-a-variation)
- [Pinning a variation](#pinning-a-variation)
- [Exploring while the sketch runs](#exploring-while-the-sketch-runs)
- [Contact sheets: proof a whole range](#contact-sheets-proof-a-whole-range)
- [Re-rendering a keeper](#re-rendering-a-keeper)
- [Writing a sketch worth exploring](#writing-a-sketch-worth-exploring)

---

### Every sketch has a variation

When a sketch is created it rolls one number, its `variation`, and seeds both `random()` and `noise()` from it. So an unseeded sketch still looks different every run, the way it always has, but that run is no longer lost: the number that produced it is readable.

```swift
override func draw() {
    drawCaption("Variation \(variation)")   // the seed this run grew from
}
```

The number is small on purpose (1 through 99,999), so it's easy to read off the screen, say out loud, and type back in.

Because both generators start from it, every export records it as a single `seed` in its [reproduction recipe](../Output/Export.md#reproducibility-metadata):

```json
{"tool":"Ollin","seed":27157,"git":"d146303","frame":0,"fps":60}
```

### Pinning a variation

`seed(_:)` moves the whole sketch to a chosen variation:

```swift
override func setup() {
    seed(42)        // this sketch is always variation 42
}
```

A sketch that does this reproduces one piece forever, which is what you want once you've found the composition you're after. Leave it out and the sketch keeps rolling.

`randomSeed(_:)` and `noiseSeed(_:)` still reseed one generator each without claiming the whole run, so `variation` keeps naming the seed the sketch was born on.

### Exploring while the sketch runs

Every host that shows an inspector (the live host's sidebar, the performance host, the examples gallery, and the standalone `⌘/` panel) shows a **Variation** card:

```
┌──────────────────────────────────────┐
│  Seed        ‹    27157    ›    ⚄    │
└──────────────────────────────────────┘
```

- `‹` and `›` step to the neighboring seed.
- `⚄` rolls a random one.
- Click the number to type a seed and jump straight to it.

Each move restarts the sketch in place at that seed: `setup()` runs again, the clock returns to zero, and any accumulated canvas is cleared, while your `@Param` knob values stay exactly where you left them. In the live host, a seed you navigated to **carries across a hot reload**, the same way a tuned knob does, so editing the code doesn't reshuffle the composition you were working on.

A sketch that pins its own seed in `setup()` reproduces that one variation no matter what the card says. That's by design: the sketch's own decision wins.

### Contact sheets: proof a whole range

The reason to have seeds at all is to cull them. `--export-grid` renders one frame at each of a run of seeds and tiles them into a single labeled proof sheet:

```sh
swift run --package-path Examples Example-Randomness-Variations --export-grid sheet.png --seeds 25
```

```
--export-grid <path.png>   the sheet to write
--seeds N                  how many variations (default 16)
--seed FIRST               the first seed (default 1); seeds run consecutively
--columns C                grid columns (default: the squarest fit)
--tile PX                  each thumbnail's width (default 320)
--frame N                  which frame of the sketch to render (default 0)
--fps F                    the clock rate that frame is timed against
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/06-GridsAndRepetition/ViewBoxSheet-dark.jpg">
  <img src="../../Guide/Images/06-GridsAndRepetition/ViewBoxSheet.jpg" alt="Six boxes on one canvas in two rows of three, each holding the same ring-of-petals piece under a different seed, each with its own colored wash" width="680">
</picture>

Each tile is a fresh instance of the sketch, seeded before `setup()` runs, so a stateful sketch can't leak from one tile into the next. The sheet's own PNG carries the seed list in its recipe.

The same thing from code, when you're driving the render yourself:

```swift
OllinApp.exportContactSheet({ MySketch() }, to: "sheet.png", seeds: Array(1...25))

// Or keep the image and composite it yourself:
let sheet: CGImage? = OllinApp.contactSheet(of: { MySketch() }, seeds: [3, 17, 92])
```

### Re-rendering a keeper

`--seed N` reseeds the sketch before `setup()` on **every** export path, so a variation you found on a sheet or in the inspector comes back at full resolution, as a video, or as vector art:

```sh
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --seed 10
swift run --package-path Examples Example-Randomness-Variations --export-svg keeper.svg --seed 10
swift run --package-path Examples Example-Randomness-Variations --export-video keeper.mp4 --seconds 6 --seed 10
```

Same seed, same pixels, every time. That's the whole loop: roll a sheet, pick a keeper, render it big.

### Writing a sketch worth exploring

A sketch rewards seed exploration when the seed decides *composition*, not just jitter. The practical rule: make the choices that matter in `setup()`, where the seeded generators run once, and let `draw()` animate what `setup()` decided.

```swift
override func setup() {
    let palette = randomChoice(palettes)     // which colors this piece uses
    let spacing = random(70, 130) * scale    // how dense it is
    discs = poissonDisk(in: field, radius: spacing).map { … }
}
```

Now every seed is a different piece rather than the same piece slightly shaken. Compare `Examples/Randomness/Variations` (a whole composition per seed) with `Examples/Randomness/RandomBand` (the same band, re-jittered).

Because [`random`](../Generators/Random.md) and [`noise`](../Generators/Noise.md) are both seeded from `variation`, anything built on them (the scatter helpers, `poissonDisk`, the L-systems, flow fields, packing, boids) rides along automatically.

### See also

- [`Random`](../Generators/Random.md) - the seeded generator behind `variation`, and `seed`/`randomSeed`/`noiseSeed`
- [`Export`](../Output/Export.md) - the export flags `--seed` applies to, and the reproduction recipe every file carries
- [`Parameters`](../Helpers/Parameters.md) - the `@Param` knobs that sit beside the Variation card, and carry across reloads the same way
