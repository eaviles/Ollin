#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Differential growth`</sup>

---

## Differential growth

A line of connected nodes grows and folds into organic, brain-coral structure. On each step, three forces nudge every node, and an edge that stretches too far splits into new nodes. The line therefore gets longer and buckles, the way a leaf margin, a coral, or a convoluted cortex does.

Unlike the one-shot generators, [circle packing](./Packing.md) and [L-systems](./LSystem.md), this is a **stateful stepper**. You build a `DifferentialGrowth` once, hold it, and advance it each frame. It is seeded, so the same seed grows the same form. The evolving line is ordinary geometry (`nodes` and `contour`), so it feeds stroking, filling, the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export.

### Contents

- [Building and stepping](#step)
- [Seed factories: ring and line](#factories)
- [Tuning the forces](#tuning)

<a name="step"></a>

#### Building and stepping

`DifferentialGrowth` is a class. You create it once, usually with the `ring` or `line` factory below, and then step it in `draw()`. `nodes` is the current line, and `contour` wraps that line as a `Contour`.

```swift
final class Coral: Sketch {
    // Built once, seeded, held across frames:
    let growth = DifferentialGrowth.ring(center: Vector2(540, 540), radius: 70,
                                         count: 40, seed: 7, maxNodes: 6000)

    override func draw() {
        growth.step(4)                      // a few sub-steps per frame
        background(.black)
        noFill(); stroke(.white); strokeWeight(2); strokeJoin(.round)
        drawPolyline(growth.nodes, closed: true)
    }
}
```

`step()` advances one step, and `step(n)` runs `n` steps at once, so more steps per frame grow the form faster. The form evolves through `draw()`, so it animates on its own. A small ring at the start becomes a dense coral as it runs. For a still image at a chosen moment, export a specific `--frame`.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/13-GrowingThings/GrowthStrip-dark.jpg">
  <img src="../../Guide/Images/13-GrowingThings/GrowthStrip.jpg" alt="Five small panels showing the same ring at step 0, 80, 180, 320, and 500: a circle wobbles, then folds into a dense meandering coral-like blob" width="680">
</picture>

<a name="factories"></a>

#### Seed factories: ring and line

Two starting shapes are built in. Both take the same tuning parameters, which are described below.

```swift
DifferentialGrowth.ring(center: Vector2, radius: Double, count: Int = 24, seed: UInt64 = 0, …) -> DifferentialGrowth
DifferentialGrowth.line(from: Vector2, to: Vector2, count: Int = 8, seed: UInt64 = 0, …) -> DifferentialGrowth
```

- `ring` seeds a closed circle that buckles into folds as it grows. This is the classic differential-growth shape.
- `line` seeds a straight open line with its endpoints pinned, so it grows into a meandering folded ribbon between them.

To grow from your own outline, build the stepper directly from a point list with `DifferentialGrowth(nodes: myPoints, closed: true, seed: 7)`.

<a name="tuning"></a>

#### Tuning the forces

A handful of parameters set the look. You can pass each one to a factory, and each one is also a `var` on the instance.

| Parameter | Effect |
| --- | --- |
| `maxSegmentLength` | an edge longer than this splits and inserts a node. Smaller values give finer, denser folds |
| `repulsionRadius` | how far a node's push reaches. Larger values give looser, rounder folds |
| `attraction` | pull toward the path-neighbors, which holds the line together |
| `repulsion` | push from nearby nodes, which drives the buckling |
| `alignment` | pull toward the neighbors' midpoint, which smooths the curve |
| `jitter` | a small random nudge each step, so a symmetric ring breaks and folds |
| `growthRate` | extra nodes added at random edges each step, for faster and more asymmetric growth |
| `maxNodes` | a ceiling on the node count. Growth stops and the line settles once it is reached |
| `bounds` | an optional rectangle the nodes stay inside |

Repulsion is broad-phased through a uniform spatial hash, so the cost stays close to linear in the node count. See the `DifferentialGrowth` example.

---

Related: [`Circle packing`](./Packing.md) and [`L-systems`](./LSystem.md), the one-shot generative-geometry siblings; [`Geometry`](../Drawing/Geometry.md), the `Contour` type and the shape booleans the line feeds; [`Physics`](../Simulation/Physics.md), the other stateful, stepped simulation.
