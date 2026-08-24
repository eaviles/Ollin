#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Random walks`</sup>

---

## Random walks

Paths built one random step at a time. The family has three members, and they make very different marks: `randomWalk` a dense local tangle that drifts slowly, `levyFlight` tight clusters strung together by rare jumps, `selfAvoidingWalk` one unbroken line that never crosses itself.

All three draw from the seeded `random`, so [`seed`](./Random.md#seed) reproduces the path. All three return plain `[Vector2]`, ready for `drawPolyline`, `Contour`, hatching, or [SVG export](../Output/Export.md).

<img src="../../Guide/Images/04-Randomness/WalkFamily.jpg" alt="Three panels from the same seed: a dense tangle pooling in one area, a set of tight clusters joined by long straight leaps, and an orange path on a grid that fills the square without ever crossing itself" width="680">

### Contents

- [randomWalk](#randomWalk)
- [levyFlight](#levyFlight)
- [selfAvoidingWalk](#selfAvoidingWalk)
- [Standalone (outside a sketch)](#standalone)

<a name="randomWalk"></a>

#### randomWalk

```swift
randomWalk(from start: Vector2? = nil,     // canvas center by default
           steps: Int,
           stepLength: Double) -> [Vector2]
```

The plain isotropic walk, where every step is the same length in a uniformly random direction. It's *diffusive*, so after N steps it has typically drifted only √N step lengths from home. That is exactly its charm, giving a dense, tangled scribble that stays local.

<img src="../../Guide/Images/04-Randomness/WalkVsJumps.jpg" alt="Two strips: fresh rolls per step produce a jagged hash of a line, while accumulated nudges produce a wandering path" width="680">

```swift
seed(3)
noFill(); stroke(.black); strokeWeight(1.5)
drawPolyline(randomWalk(steps: 4000, stepLength: 6))
```

Returns `steps + 1` points, beginning at `start`.

<a name="levyFlight"></a>

#### levyFlight

```swift
levyFlight(from start: Vector2? = nil,
           steps: Int,
           minStep: Double,
           maxStep: Double,
           exponent: Double = 2) -> [Vector2]
```

A walk whose step lengths follow a heavy-tailed **power law** p(l) ∝ l^(−exponent) on [`minStep`, `maxStep`]. Most steps are tiny and grind away inside a cluster, while rare enormous leaps start a new cluster somewhere else. It's how foraging animals search and how eyes scan a scene. As a mark it reads as islands of texture strung together by long strokes.

`exponent` sets the temperament. Near 1 the jumps dominate, near 3 it approaches an ordinary walk, and the default of 2 is the classic balance. `minStep` must be positive. The power law diverges at zero, so a floor is part of the definition.

A flight wanders wherever it likes, so fit the finished path to your frame by scaling the *points* rather than calling `scale()`. Take the minimum and maximum of the coordinates, then map. Using `scale()` would fatten the stroke as well. See the `LevyFlight` example.

<a name="selfAvoidingWalk"></a>

#### selfAvoidingWalk

```swift
selfAvoidingWalk(in bounds: Rectangle? = nil,
                 cellSize: Double,
                 from start: Vector2? = nil,   // snapped to the nearest cell
                 maxLength: Int? = nil) -> [Vector2]
```

One unbroken path over a `cellSize` lattice, centered in `bounds`, that never revisits a cell. A naive self-avoiding walk boxes itself in almost immediately. This one is grown depth-first with **backtracking**, retreating out of dead ends while the abandoned cells stay blocked. The line therefore winds long and dense, filling the frame like a maze made of a single stroke. That single-stroke property is what makes it a plotter favorite.

The longest path found is returned. Its points are cell centers, and each step is one orthogonal lattice move. Pass `maxLength` to stop as soon as the path reaches that many points.

```swift
seed(12)
let path = selfAvoidingWalk(cellSize: 30)
strokeCap(.round); strokeWeight(11)
for i in 1 ..< path.count {
    stroke(ramp.color(at: Double(i) / Double(path.count - 1)))
    drawLine(path[i - 1], path[i])   // hue along the walk's length
}
```

<a name="standalone"></a>

#### Standalone (outside a sketch)

The free functions take an explicit start/rectangle and rng:

```swift
var rng = SplitMix64(seed: 5)
let scribble = randomWalk(from: .init(0, 0), steps: 2000, stepLength: 4, using: &rng)
let flight = levyFlight(from: .init(0, 0), steps: 600, minStep: 4, maxStep: 400, using: &rng)
let thread = selfAvoidingWalk(in: bounds, cellSize: 24, using: &rng)
```

---

Related: [`Random`](./Random.md) (the seeded source they draw from), [`Diffusion-limited aggregation`](./DiffusionLimitedAggregation.md) (random walkers frozen into dendrites), [`Flow fields`](./FlowField.md) (paths steered by a field instead of chance), [`Low-discrepancy sampling`](./LowDiscrepancy.md) (points without a path).
