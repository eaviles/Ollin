#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Why a run repeats`</sup>

---

## Why a run repeats

A sketch that draws something worth keeping has to be able to draw it again. Ollin's answer is that a run comes from two things you can write down: its seed, and the frame it is on. Hold both, and the picture comes back.

### One seed for the whole run

When a sketch is created it rolls one small number, its [`variation`](../Core/Variations.md), and seeds both `random()` and `noise()` from it. An unseeded sketch still looks different every run, but the run is no longer lost. The number behind it is on screen, in the export, and short enough to type back in. `seed(42)` in `setup()` pins a sketch to one variation forever.

Every export writes that number into the file, beside the knob values and the commit it ran at. A picture carries the recipe that makes it again.

### One clock the export controls

In the window the clock follows real time, so a slow frame is a longer step and the motion stays honest. Every export drives the clock at a fixed step instead, so frame *n* lands on the same time value whatever the render cost. A sequence that took ten minutes to write plays back at the rate you asked for, and rendering it twice gives the same frames.

### What breaks it

- **Reading the system clock.** `Date()` and its relatives change every run. Use `time`, `deltaTime`, and `frameCount`.
- **Swift's own dice.** `Double.random(in:)` and an array's `shuffled()` do not come from the seed. Ollin's `random(...)`, `randomGaussian()`, and `shuffled(_:)` do.
- **Live input.** The mouse, a camera, a microphone, a controller, a network feed. None of it repeats. A [take](../Core/Replay.md) records the run's inputs so the performance can be played back exactly.
- **Order that is not fixed.** Iterating a `Set` or a `Dictionary` visits in an order Swift is free to change, and results gathered from concurrent work arrive in the order they finish. Sort before you draw.

### What it buys

A reproducible sketch can be explored rather than only made. Step and roll the seed to find a composition, proof a range as a contact sheet (`--export-grid`), then render the keeper at print size with `--seed`. Ollin's own rendering is guarded the same way: reference images that only match because a frame renders identically twice.

### Read next

- [`Variations`](../Core/Variations.md) - the seed as a first-class value: stepping, rolling, contact sheets, re-rendering a keeper.
- [`Random`](../Generators/Random.md) - the seeded generators, and the sketch-wide seed they share.
- [`Export`](../Output/Export.md) - the fixed-step drive, and the recipe every file carries.
- [`Replay`](../Core/Replay.md) - keeping a run that depended on live input.
- [Guide, Chapter 4](../../Guide/04-Randomness.md) - randomness taught as a chapter.
