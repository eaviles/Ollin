#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Meander`</sup>

---

## Meander

A river centerline that migrates sideways over time: bends deepen and slide downstream, loops pinch off into crescent oxbow lakes, and the recorded past piles up as scars beside the water. The engine is curvature: each point drifts perpendicular to the line, pushed by the curvature there and, more strongly, by the curvature a little way upstream. That upstream push is what makes a bend both grow and travel.

Like [differential growth](./DifferentialGrowth.md), this is a **stateful stepper**: you build a `Meander` once, hold it, and advance it each frame. It's seeded, so the same seed runs the same river. Everything it produces is ordinary geometry (`centerline`, `oxbows`, `scars`), ready for stroking, filling, the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/13-GrowingThings/WanderingRiver-dark.jpg">
  <img src="../../Guide/Images/13-GrowingThings/WanderingRiver.jpg" alt="Two panels: left, an S-shaped channel with an orange arrow pointing away from the outside of a bend, labeled the outside is eaten away, and a second arrow along the flow labeled and the bend slides downstream; right, a wandering dark blue river over faded terracotta and sage ribbons of its old positions, with a pale crescent lake beside it" width="680">
</picture>

### Contents

- [Building and stepping](#step)
- [What a step does](#mechanism)
- [Oxbows and scars](#history)
- [Tuning the river](#tuning)

<a name="step"></a>

#### Building and stepping

`Meander` is a class you create once (usually with the `line` factory) and step in `draw()`. `centerline` is the river now; `contour` wraps it as an open `Contour`.

```swift
final class River: Sketch {
    // Built once, seeded, held across frames. Starting far off-canvas makes
    // the canvas a window on the middle of a longer river.
    let river = Meander.line(from: Vector2(-700, 620), to: Vector2(1160, 480),
                             seed: 7, width: 26, recordEvery: 40)

    override func draw() {
        river.step(2)
        background(Color(hex: 0xF2ECDD))
        noFill(); stroke(Color(hex: 0x2C4A6E)); strokeWeight(river.width)
        drawPolyline(river.centerline)
    }
}
```

`step()` advances one step. `step(n)` runs `n` at once. The line factory seeds a gently wavy channel (a few long sine components at seeded phases, tapered to nothing at the pinned ends). The migration takes it from there: a wave train first, then deepening loops, then cutoffs. `sinuosity` reports how bent the river currently is: its length along the water divided by the straight distance between its ends. Over a long run it saw-tooths, because each cutoff sheds a loop.

To start from your own path, build the stepper directly from a point list: `Meander(centerline: myPoints, seed: 7, width: 24)`. Points are in flow order: index 0 is upstream, and "upstream influence" follows that direction.

<a name="mechanism"></a>

#### What a step does

Each `step()`:

1. **Measures curvature** along the centerline.
2. **Drifts every point** perpendicular to the line. The rate blends the local curvature (negative weight) with an exponentially weighted average of the curvature upstream, over about `memoryLength`. The upstream term dominates, which is what makes bends grow *and* slide downstream. The largest drift is clamped to a fraction of `spacing`, so a sharp bend cannot step over its own resolution.
3. **Cuts off pinched loops.** Where two reaches come within `cutoffDistance` of each other, the loop between them becomes an `Oxbow` and the channel reconnects on the short path. The distance is measured across the land, with a guard so a bend's own flanks never count.
4. **Resamples** the centerline at an even `spacing` through an interpolating spline (straight-segment resampling would shave a little curvature off every step, and curvature is the engine).
5. **Ages the oxbows** (each shrinks toward its center by `oxbowShrink` per step and is deleted once smaller than the channel width) and **records a scar** every `recordEvery` steps.

<a name="history"></a>

#### Oxbows and scars

- `oxbows` is the array of lakes cut off so far, oldest first. Each `Oxbow` carries its `points` (stroked at channel width, it reads as a crescent lake along the old channel) and its `age` in steps.
- `scars` is the array of past centerlines, recorded every `recordEvery` steps (0, the default, records nothing) and capped at `maxScars`. Drawn under the channel, they make the classic map-of-everywhere-the-river-has-been.

```swift
let inks = [Color(hex: 0xC26D3F), Color(hex: 0x8A9B68), Color(hex: 0xC7A94F)]
noFill()
strokeWeight(river.width * 0.7)
for (index, scar) in river.scars.enumerated() {
    let recency = Double(index + 1) / Double(river.scars.count)
    stroke(inks[index % inks.count].withAlpha(0.08 + 0.2 * recency))
    drawPolyline(scar)
}
stroke(Color(hex: 0x7FA8C9).withAlpha(0.8))
strokeWeight(river.width * 0.8)
for oxbow in river.oxbows {
    drawPolyline(oxbow.points)
}
```

<a name="tuning"></a>

#### Tuning the river

The defaults hang off `width`, so setting just the channel width gives a coherent river. All are settable on the factory and as `var`s on the instance:

| Parameter | Effect |
| --- | --- |
| `width` | the channel width, the length scale everything else defaults from |
| `migrationRate` | drift per step (default `width / 4`); higher migrates faster |
| `memoryLength` | how far upstream curvature still pushes a point (default `width * 1.5`); longer stretches the bends |
| `spacing` | the resample spacing (default `width / 4`); finer follows tighter bends |
| `cutoffDistance` | how close two reaches may come before the loop between them cuts off (default `width * 2`) |
| `fixedEnds` | points pinned at each end (default 3), so the river stays anchored |
| `oxbowShrink` | the fraction of its size a lake loses per step |
| `recordEvery` / `maxScars` | the scar cadence and ceiling |

The migration is deterministic. All the randomness is in the seeded starting waves. A run's character changes over its life: a regular wave train, then deepening irregular loops, then a steady state where growth and cutoffs balance. So both the seed *and the frame you stop at* pick the picture. See the `Meander` example.

---

Related: [`Differential growth`](./DifferentialGrowth.md) (the other stateful line stepper), [`Geometry`](../Drawing/Geometry.md) (the `Contour` type and the shape booleans the river feeds), [`Noise & fields`](./Noise.md) (the seeded randomness underneath).
