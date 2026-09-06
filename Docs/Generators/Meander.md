#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Meander`</sup>

---

## Meander

`Meander` is a river centerline that migrates sideways over time. As it migrates, bends deepen and slide downstream, and loops pinch off into crescent oxbow lakes. It also records its past positions as scars beside the water. Curvature drives the migration, and each point drifts perpendicular to the line. The curvature at that point pushes it, and the curvature a little way upstream pushes it more strongly. That upstream push is what makes a bend both grow and travel.

Like [differential growth](./DifferentialGrowth.md), `Meander` is a **stateful stepper**. You build one, hold it, and advance it each frame. It is seeded, so the same seed runs the same river. Everything it produces is ordinary geometry (`centerline`, `oxbows`, `scars`). That geometry is ready for stroking, filling, the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export.

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

`Meander` is a class that you create once, usually with the `line` factory, and step in `draw()`. `centerline` is the river as it is now, and `contour` wraps the same points as an open `Contour`.

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

`step()` advances one step. `step(n)` runs `n` steps at once. The `line` factory starts with a gently wavy channel: a few long sine components at seeded phases, tapered to nothing at the pinned ends. From there the migration shapes the channel, so the river forms a wave train first, then deepening loops, then cutoffs. `sinuosity` reports how bent the river is now, measured as the length along the water divided by the straight distance between the ends. Over a long run that value rises and drops in a saw-tooth pattern, because each cutoff sheds a loop.

To start from your own path, build the stepper directly from a point list: `Meander(centerline: myPoints, seed: 7, width: 24)`. The points are in flow order, so index 0 is upstream, and the upstream influence follows that direction.

<a name="mechanism"></a>

#### What a step does

Each call to `step()` does five things.

1. **Measures curvature** along the centerline.
2. **Drifts every point** perpendicular to the line. The drift rate blends two terms. One is the local curvature, with a negative weight. The other is an exponentially weighted average of the curvature upstream, over about `memoryLength`. The upstream term dominates, which is what makes bends grow *and* slide downstream. The largest drift is clamped to a fraction of `spacing`, so a sharp bend cannot step over its own resolution.
3. **Cuts off pinched loops.** Where two reaches come within `cutoffDistance` of each other, the loop between them becomes an `Oxbow`. The channel then reconnects along the short path. Ollin measures that distance across the land, and a guard stops a bend's own flanks from counting.
4. **Resamples** the centerline at an even `spacing` through an interpolating spline. Resampling along straight segments would remove a little curvature at every step, and curvature is what drives the migration.
5. **Ages the oxbows** and **records a scar**. Each oxbow shrinks toward its center by `oxbowShrink` per step, and is deleted once it is smaller than the channel width. A scar is recorded every `recordEvery` steps.

<a name="history"></a>

#### Oxbows and scars

- `oxbows` is the array of lakes cut off so far, oldest first. Each `Oxbow` carries its `points` and its `age` in steps. Stroke those points at the channel width and they draw a crescent lake along the old channel.
- `scars` is the array of past centerlines. One is recorded every `recordEvery` steps, and the array is capped at `maxScars`. `recordEvery` defaults to 0, which records nothing. Draw the scars under the channel and together they map every position the river has held.

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

Every default is derived from `width`, so setting only the channel width scales the whole river together. You can set every parameter below on the factory, and as `var`s on the instance:

| Parameter | Effect |
| --- | --- |
| `width` | the channel width, the length scale that every other default is derived from |
| `migrationRate` | the drift per step (default `width / 4`); a higher value migrates faster |
| `memoryLength` | how far upstream the curvature still pushes a point (default `width * 1.5`); a longer value stretches the bends |
| `spacing` | the resample spacing (default `width / 4`); a finer spacing follows tighter bends |
| `cutoffDistance` | how close two reaches may come before the loop between them cuts off (default `width * 2`) |
| `fixedEnds` | the number of points pinned at each end (default 3), so the river stays anchored |
| `oxbowShrink` | the fraction of its size a lake loses per step |
| `recordEvery` / `maxScars` | how often a scar is recorded, and the most scars kept |

The migration is deterministic, so all the randomness is in the seeded starting waves. A run still changes as it goes on. It starts as a regular wave train, then forms deepening irregular loops, then reaches a steady state where growth and cutoffs balance. So the picture you get depends on both the seed *and the frame you stop at*. See the `Meander` example.

---

Related: [`Differential growth`](./DifferentialGrowth.md) (the other stateful line stepper), [`Geometry`](../Drawing/Geometry.md) (the `Contour` type and the shape booleans the river's geometry feeds), [`Noise & fields`](./Noise.md) (the seeded randomness underneath).
