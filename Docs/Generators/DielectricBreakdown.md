#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `DielectricBreakdown`</sup>

---

## Dielectric breakdown

**Dielectric breakdown** grows lightning. The model holds the discharge at one voltage and the surroundings at another, then solves the electric field between them over a lattice. Every empty cell touching the discharge is a candidate. One candidate grows per step, with a probability proportional to the local field raised to `eta`. That one exponent picks the regime. A low `eta` grows a furry, even bush. Near `2` you get the sparse, jagged branches of lightning, and the Lichtenberg figures burned into wood and acrylic.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/13-GrowingThings/VoltageChooses-dark.jpg">
  <img src="../../Guide/Images/13-GrowingThings/VoltageChooses.jpg" alt="Two panels: left, a young lattice discharge inside a violet wash of its solved field, its frontier dotted in orange with the dots large at the tips and missing in the crevices; right, a sparse jagged discharge with its main channels drawn thick" width="680">
</picture>

`DielectricBreakdown` is a stateful stepper you hold on to, like the other growth models. `step()` adds one site, `step(_:)` adds a batch per frame, and `grow()` runs until the arc connects. The model is seeded, so the same seed grows the same figure.

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

`seeds` are the points where the discharge starts, snapped to lattice cells. One center point grows a radial Lichtenberg figure, and a row along the top grows lightning that reaches down. `ground` is the far electrode the discharge grows toward. `.border` puts ground on the rim of `bounds`, which gives the classic radial figure. `.points(_:)` instead holds specific cells at full potential, such as a wire, a plate, or one far point, and the rim then insulates. `resolution` is the lattice's cell count across the width, so a finer lattice gives finer filaments and costs more per step. `eta` is the character parameter. At `1` you get the aggregation regime, around `2` the lightning regime, and higher values approach a single channel.

<a name="growing"></a>

#### Growing it

`step()` does the solving for you. Each step relaxes the field a little, weighs the candidates by `field^eta`, and grows one of them. `step(_:)` grows a batch per frame, and a handful per frame looks like the discharge feeling its way. `grow()` runs until the figure arcs to ground, fills its room, or hits `maxSites`, and `isFinished` says which end you reached. Sites arrive in growth order and carry a `parent` link.

<a name="drawing"></a>

#### Drawing it

```swift
bolt.positions                                  // [Vector2], for drawCircles
bolt.segments                                   // [(Vector2, Vector2)], site to parent
bolt.branches()                                 // [Contour], whole channels, tip to fork
bolt.thicknesses(tipWidth: 1.2, exponent: 2.0)  // [Double], indexed like sites
```

`segments` gives you the plain skeleton. `branches()` returns whole channels as polylines. Each channel runs from a seed or a fork out to a tip, and every edge lands in exactly one channel. A channel strokes as one continuous filament, and it takes [`smoothed(iterations:)`](../Drawing/Curves.md#smoothing) well for the plotter path. `thicknesses(tipWidth:exponent:)` follows the pipe model. Tips carry `tipWidth`, and channels thicken toward the seed, the way a real discharge brightens its main channel. The `Patterns/Lichtenberg` example draws those widths under an additive halo.

<a name="field"></a>

#### Reading the field

```swift
bolt.potential(at: point) -> Double   // 0 on the discharge, 1 at ground
```

The solved field is worth drawing on its own. Sample it over a grid for a glow that follows the figure. Feed it to [`isolines`](./Isolines.md) for equipotential contour lines, or use it to drive color. A candidate's growth weight is exactly this value raised to `eta`. A picture of the field is therefore also a picture of where the discharge will strike next.

---

Related: [`DiffusionLimitedAggregation`](./DiffusionLimitedAggregation.md) builds the same kind of figure from random walkers, and `eta: 1` grows the same family of shapes. See also [`SpaceColonization`](./SpaceColonization.md), which grows toward targets you declare rather than a solved field, and [`CrackGrowth`](./CrackGrowth.md), which grows by collision.
