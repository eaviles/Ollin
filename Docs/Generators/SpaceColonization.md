#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `SpaceColonization`</sup>

---

## Space colonization

**Space colonization** grows a branching structure toward a scattered set of attraction points. On every step, each remaining attractor pulls on the single closest branch node within reach. A pulled node then grows one step toward the average of the pulls on it, and an attractor is consumed once a branch reaches it. That is the classic venation-and-branching growth model, so veins, roots, lightning, and trees all come out of the same loop. What changes is where you scatter the attractors and where you plant the roots.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/13-GrowingThings/ClaimingSpace-dark.jpg">
  <img src="../../Guide/Images/13-GrowingThings/ClaimingSpace.jpg" alt="Four panels of the same growth at step 6, 18, 40, and finished: ink veins spread from a bottom root into a field of orange dots, and the dots vanish as branches reach them" width="680">
</picture>

`SpaceColonization` keeps its own state, so you hold on to it and call `step()` each frame, or run it to the end with `grow()`. The algorithm draws no random numbers, which means the same attractors and roots always grow the same structure. Scatter the attractors with a seeded generator and the whole piece is reproducible.

```swift
seed(7)
let growth = SpaceColonization(attractors: poissonDisk(radius: 26),
                               roots: [Vector2(width / 2, height - 70)])

override func draw() {
    growth.step()
    background(.black)
    stroke(.white)
    for (a, b) in growth.segments { drawLine(a, b) }
}
```

### Contents

- [Building a growth](#building)
- [Stepping and finishing](#stepping)
- [Segments and thickness](#drawing)
- [Shaping the result](#shaping)

<a name="building"></a>

#### Building a growth

```swift
SpaceColonization(attractors: [Vector2], roots: [Vector2],
                  influenceRadius: Double = 120, killRadius: Double = 24,
                  stepLength: Double = 12, maxNodes: Int = 6000)
```

The three distances have to sit in a particular relationship. Keep `stepLength` smaller than `killRadius`, because otherwise a branch can step right past the attractor it is chasing. Keep `killRadius` well below `influenceRadius`. A smaller `stepLength` gives smoother, denser curves, and a larger `influenceRadius` lets branches reach across open space toward far attractors.

[`poissonDisk`](./BlueNoise.md) is the usual source of attractors, because it covers the area evenly and leaves no clumps. Any point set works. Sample a `Shape`'s interior for growth that fills a silhouette, or a circle's rim for a radial burst.

<a name="stepping"></a>

#### Stepping and finishing

`step()` advances one growth round, `step(_:)` advances several, and `grow()` runs to the end. `isFinished` turns true once every reachable attractor is consumed and nothing can grow further. Attractors that sit outside every branch's reach are left standing, and the growth still stops. `nodes` and `attractors` hold the live state, so a sketch can draw the attractors nothing has reached yet as waiting seeds.

<a name="drawing"></a>

#### Segments and thickness

Each `Node` carries its `position` and the index of its `parent`, so the structure is a tree. `segments` flattens that tree into `(parent, child)` line pairs for `drawLine`, hatching, or SVG export. To give the branches organic weight, `thicknesses(tipWidth:exponent:)` runs the pipe model. Every tip gets `tipWidth`, and a parent's width combines its children's widths, raised to `exponent` and then re-rooted. Trunks come out thick and twigs come out hairline:

```swift
let widths = growth.thicknesses(tipWidth: 1.4, exponent: 2.2)
for (i, node) in growth.nodes.enumerated() {
    guard let parent = node.parent else { continue }
    strokeWeight(widths[i])
    drawLine(growth.nodes[parent].position, node.position)
}
```

<a name="shaping"></a>

#### Shaping the result

- **Leaf venation:** attractors from `poissonDisk` over the canvas, and one root at the bottom edge (the `Patterns/Venation` example).
- **A tree:** attractors scattered in a crown-shaped region near the top, and the root at the ground. Keep `influenceRadius` small so branches do not shortcut across the trunk.
- **Lightning or roots:** attractors in a tall band below the root, and a raised `stepLength` for jagged lines.
- **Several plants:** more than one point in `roots`. Each attractor feeds whichever structure reaches it first, so the plants divide the space between them.

---

Related: [`Blue noise`](./BlueNoise.md) (the attractor scatter), [`Diffusion-limited aggregation`](./DiffusionLimitedAggregation.md) (dendrites from random walkers, not pulls), [`L-systems`](./LSystem.md) (branching from a grammar, not from space), [`Differential growth`](./DifferentialGrowth.md) (the other stateful grower).
