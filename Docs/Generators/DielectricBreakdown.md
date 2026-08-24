#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `DielectricBreakdown`</sup>

---

## Dielectric breakdown

**Dielectric breakdown** grows lightning. The discharge is held at one voltage and the surroundings at another, and the electric field between them is solved over a lattice. Every empty cell touching the discharge is a candidate, and one grows per step with probability proportional to the local field raised to `eta`. That one exponent picks the regime. Low `eta` grows a furry, even bush; near `2` it grows the sparse, jagged branches of lightning and the Lichtenberg figures burned into wood and acrylic.

<img src="../../Guide/Images/13-GrowingThings/VoltageChooses.jpg" alt="Two panels: left, a young lattice discharge inside a violet wash of its solved field, its frontier dotted in orange with the dots large at the tips and missing in the crevices; right, a sparse jagged discharge with its main channels drawn thick" width="680">

`DielectricBreakdown` is a stateful stepper you hold, like the other growth models. `step()` adds one site, `step(_:)` a batch per frame, `grow()` runs until the arc connects. It's seeded, so the same seed grows the same figure.

```swift
let bolt = DielectricBreakdown(seeds: [center], in: bounds, seed: 7)

override func draw() {
    bolt.step(6)
    background(.black)
    stroke(.white)
    for (a, b) in bolt.segments { drawLine(a, b) }
}
```

### Contents

- [Building a discharge](#building)
- [Growing it](#growing)
- [Drawing it](#drawing)
- [Reading the field](#field)

<a name="building"></a>

#### Building a discharge

```swift
DielectricBreakdown(seeds: [Vector2], in bounds: Rectangle, resolution: Int = 140,
                    eta: Double = 1.7, ground: Ground = .border,
                    maxSites: Int = 3000, seed: UInt64 = 0)
```

`seeds` are where the discharge starts, snapped to lattice cells. One center point grows a radial Lichtenberg figure; a row along the top grows lightning reaching down. `ground` is the far electrode it grows toward. `.border` is the rim of `bounds`, the classic radial figure. `.points(_:)` lays specific cells at full potential instead, a wire or a plate or one far point, and the rim then insulates. `resolution` is the lattice's cell count across the width; finer lattices give finer filaments and cost more per step. `eta` is the character knob: `1` is the aggregation regime, around `2` the lightning regime, higher values approach a single channel.

<a name="growing"></a>

#### Growing it

`step()` solves nothing you have to see: the field is relaxed a little on every step, the candidates are weighed by `field^eta`, one grows. `step(_:)` grows a batch per frame, and a handful per frame reads as the discharge feeling its way. `grow()` runs until the figure arcs to ground, fills its room, or hits `maxSites`; `isFinished` says which end you reached. Sites arrive in growth order and carry a `parent` link.

<a name="drawing"></a>

#### Drawing it

```swift
bolt.positions                                  // [Vector2], for drawCircles
bolt.segments                                   // [(Vector2, Vector2)], site to parent
bolt.branches()                                 // [Contour], whole channels, tip to fork
bolt.thicknesses(tipWidth: 1.2, exponent: 2.0)  // [Double], indexed like sites
```

`segments` is the plain skeleton. `branches()` returns whole channel polylines: each runs from a seed or a fork out to a tip, and every edge lands in exactly one channel. Channels stroke as continuous filaments and take [`smoothed(iterations:)`](../Drawing/Curves.md#smoothing) well for the plotter path. `thicknesses(tipWidth:exponent:)` is the pipe model: tips carry `tipWidth` and channels thicken toward the seed, the way a real discharge brightens its main channel. The `Patterns/Lichtenberg` example draws the widths under an additive halo.

<a name="field"></a>

#### Reading the field

```swift
bolt.potential(at: point) -> Double   // 0 on the discharge, 1 at ground
```

The solved field is worth drawing in its own right. Sample it over a grid for a glow that hugs the figure, feed it to [`isolines`](./Isolines.md) for equipotential contour lines, or drive color by it. A candidate's growth weight is exactly this value raised to `eta`. The picture of the field is also the picture of where the discharge will strike next.

---

Related: [`DiffusionLimitedAggregation`](./DiffusionLimitedAggregation.md) is the walker-built cousin, and `eta: 1` grows the same family of shapes; [`SpaceColonization`](./SpaceColonization.md) grows toward declared targets rather than a solved field; [`CrackGrowth`](./CrackGrowth.md) grows by collision.
