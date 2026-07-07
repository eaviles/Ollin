#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `SpaceColonization`</sup>

---

## Space colonization

**Space colonization** grows branching structure toward a scattered set of attraction points: every step, each remaining attractor pulls on the single closest branch node within reach, pulled nodes grow one step toward the average of their pulls, and attractors a branch reaches are consumed (the classic venation-and-branching growth model). Veins, roots, lightning, and trees come from the same loop; what changes is where you scatter the attractors and where you plant the roots.

`SpaceColonization` is a stateful stepper you hold and `step()` each frame (or run to completion with `grow()`). The algorithm draws no random numbers, so the same attractors and roots always grow the same structure; scatter the attractors with a seeded generator and the whole piece is reproducible.

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
- [Drawing it: segments and thickness](#drawing)
- [Shaping the result](#shaping)

<a name="building"></a>

#### Building a growth

```swift
SpaceColonization(attractors: [Vector2], roots: [Vector2],
                  influenceRadius: Double = 120, killRadius: Double = 24,
                  stepLength: Double = 12, maxNodes: Int = 6000)
```

The three distances want a relationship: `stepLength` smaller than `killRadius` (a branch can otherwise step right past the attractor it's chasing), and `killRadius` well below `influenceRadius`. Smaller `stepLength` gives smoother, denser curves; larger `influenceRadius` lets branches reach across open space toward far attractors.

[`poissonDisk`](./BlueNoise.md) is the natural attractor source (even coverage with no clumps), but any point set works: sample a `Shape`'s interior for growth that fills a silhouette, or a circle's rim for a radial burst.

<a name="stepping"></a>

#### Stepping and finishing

`step()` advances one growth round; `step(_:)` several; `grow()` runs to the end. `isFinished` turns true when every reachable attractor is consumed and nothing can grow further (attractors outside every branch's reach are left standing, and the growth still terminates). `nodes` and `attractors` are the live state, so a sketch can draw the un-reached attractors as waiting seeds.

<a name="drawing"></a>

#### Drawing it: segments and thickness

Each `Node` carries its `position` and the index of its `parent`, so the structure is a tree. `segments` flattens it to `(parent, child)` line pairs for `drawLine`, hatching, or SVG export. For organic weight, `thicknesses(leafWidth:exponent:)` runs the pipe model: every tip gets `leafWidth`, and a parent's width aggregates its children's (raised to `exponent`, then re-rooted), so trunks are thick and twigs are hairline:

```swift
let widths = growth.thicknesses(leafWidth: 1.4, exponent: 2.2)
for (i, node) in growth.nodes.enumerated() {
    guard let parent = node.parent else { continue }
    strokeWeight(widths[i])
    drawLine(growth.nodes[parent].position, node.position)
}
```

<a name="shaping"></a>

#### Shaping the result

- **Leaf venation:** attractors from `poissonDisk` over the canvas, one root at the bottom edge (the `Patterns/Venation` example).
- **A tree:** attractors scattered in a crown-shaped region up top, the root at the ground; thin `influenceRadius` keeps branches from shortcutting across the trunk.
- **Lightning or roots:** attractors in a tall band below the root; raise `stepLength` for jaggedness.
- **Several plants:** multiple `roots`; each attractor feeds whichever structure gets there first, so neighbors negotiate territory.

---

Related: [`Blue noise`](./BlueNoise.md) (the attractor scatter), [`Diffusion-limited aggregation`](./DiffusionLimitedAggregation.md) (dendrites by random walkers instead of pulls), [`L-systems`](./LSystem.md) (branching by grammar instead of space), [`Differential growth`](./DifferentialGrowth.md) (the other stateful grower).
