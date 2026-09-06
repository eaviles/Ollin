#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Why a run repeats`</sup>

---

## Why a run repeats

A sketch that draws something worth keeping has to be able to draw it again. In Ollin a run comes from two things you can write down: its seed and the frame it is on. Keep both and the picture comes back.

### One seed for the whole run

When a sketch is created it picks one small number, its [`variation`](../Core/Variations.md), and seeds both `random()` and `noise()` from it. A sketch you have not seeded still looks different every run, but the run is no longer lost. The number behind it shows on screen, goes into the export, and is short enough to type back in. Call `seed(42)` in `setup()` to pin a sketch to one variation for good.

Every export writes that number into the file, beside the parameter values and the commit it ran at. So a picture carries the recipe that makes it again.

### One clock the export controls

In the window the clock follows real time, so a slow frame makes a longer step and the motion keeps its true speed. Every export drives the clock at a fixed step instead, so frame *n* gets the same time value whatever the render cost. That way a sequence that took ten minutes to write plays back at the rate you asked for. Rendering it twice gives the same frames.

### What breaks it

- **Reading the system clock.** `Date()` and calls like it give a different value every run, so use `time`, `deltaTime`, and `frameCount` instead.
- **Swift's own random calls.** `Double.random(in:)` and an array's `shuffled()` do not come from the seed. Ollin's `random(...)`, `randomGaussian()`, and `shuffled(_:)` do, so use those.
- **Live input.** The mouse, a camera, a microphone, a controller and a network feed all give something different each run. None of it repeats. A [take](../Core/Replay.md) records the run's inputs, which lets you play the performance back exactly.
- **Order that is not fixed.** Iterating a `Set` or a `Dictionary` visits the elements in an order Swift is free to change. Results gathered from concurrent work arrive in the order they finish. Sort before you draw.

### What it buys

A sketch that repeats is one you can explore, not one you only make once. Step and roll the seed to find a composition, then proof a range as a contact sheet with `--export-grid`. When you have a keeper, render it at print size with `--seed`. Ollin's own rendering is guarded the same way, by reference images that only match because a frame renders identically twice.

### Read next

- [`Variations`](../Core/Variations.md) - the seed as a value you work with: stepping, rolling, contact sheets, and re-rendering a keeper.
- [`Random`](../Generators/Random.md) - the seeded generators, and the sketch-wide seed they share.
- [`Export`](../Output/Export.md) - the fixed-step clock, and the recipe every file carries.
- [`Replay`](../Core/Replay.md) - keeping a run that depended on live input.
- [Guide, Chapter 4](../../Guide/04-Randomness.md) - randomness taught as a chapter.
