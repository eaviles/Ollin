#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `DiffusionLimitedAggregation`</sup>

---

## Diffusion-limited aggregation

**Diffusion-limited aggregation** (DLA) grows the branching, dendritic clusters of frost, coral, and mineral deposits. Random walkers drift in from far away and freeze the moment they touch the cluster. Tips catch walkers before hollows ever see one, so arms grow wispy and gaps stay open. The shape is really the physics of the arrival order.

`DiffusionLimitedAggregation` is a stateful stepper you hold. `step()` walks one particle until it sticks, and `step(_:)` grows a batch per frame. It's seeded, so the same seed freezes the same cluster.

```swift
let cluster = DiffusionLimitedAggregation(seeds: [center], seed: 7)

override func draw() {
    cluster.step(12)
    background(.black)
    fill(.white)
    noStroke()
    drawCircles(cluster.positions, radius: 3)
}
```

### Contents

- [Building a cluster](#building)
- [Growing it](#growing)
- [Drawing it](#drawing)

<a name="building"></a>

#### Building a cluster

```swift
DiffusionLimitedAggregation(seeds: [Vector2], particleRadius: Double = 4,
                            stickiness: Double = 1, bounds: Rectangle? = nil,
                            maxParticles: Int = 20000, seed: UInt64 = 0)
```

`seeds` are the frozen starting particles, and their arrangement decides the shape. One center point grows a radial snowflake. A row of points along the bottom edge grows frost creeping up, and a ring grows inward and outward at once. `stickiness` is the density knob. At `1` a walker freezes on first contact, giving wispy, open fingers. Lower values let walkers slide deeper into the cluster before freezing, so it grows denser and rounder. `bounds` cages the walkers, and growth that reaches the cage crawls along it.

<a name="growing"></a>

#### Growing it

`step()` releases one walker and returns the new particle's index. It returns `nil` when the cluster hits `maxParticles`. `step(_:)` grows a batch, which is the usual per-frame call, and a dozen per frame reads as steady growth. The walker mechanics are handled internally and tuned off `particleRadius`. There is a spawn circle just outside the cluster, a far-drift respawn, long strides while far, and fine diffusion steps near.

<a name="drawing"></a>

#### Drawing it

`positions` is the frozen cluster for `drawCircles`. Each `Particle` also records the `parent` it stuck to. `segments` therefore gives the branching skeleton as line pairs, ready for stroking or SVG export, the dendrite as pen-plotter line-work. Arrival order is meaningful too, since `particles[i]` froze `i`-th. Tinting by index paints the growth history as rings, as the `Patterns/Dendrite` example does.

---

Related: [`Space colonization`](./SpaceColonization.md) (branching by attraction instead of chance), [`Differential growth`](./DifferentialGrowth.md), [`Random`](./Random.md) (the seeded randomness underneath).
