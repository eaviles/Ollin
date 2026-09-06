#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Flow fields`</sup>

---

## Flow fields

A **flow field** gives a direction at every point of the plane. You can trace *streamlines* through it, which are curves that follow the flow, or *advect* particles and strokes along it. The direction comes from an `angle` function, so you can build a field from noise, from a formula, or from anything else you write. Streamlines are ordinary point lists, so they feed stroking, the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export.

<img src="../../Guide/Images/14-FieldsAndFlow/Compass.jpg" alt="A grid of small pale needles on a dark canvas, each tipped with a gold dot, their directions changing smoothly across the canvas so currents and swirls show in the pattern" width="560">

### Contents

- [Building a field](#build)
- [Streamlines](#streamlines)
- [Advecting particles](#advect)

<a name="build"></a>

#### Building a field

The `flowField` and `curlField` sketch sugar build a field from the seeded Perlin noise. Both are reproducible under [`seed`](./Random.md#seed).

```swift
flowField(scale: Double = 0.002, turns: Double = 1, z: Double = 0) -> FlowField
curlField(scale: Double = 0.003, z: Double = 0) -> FlowField
```

- `flowField` maps the noise to an angle. A smaller `scale` gives a smoother field, and `turns` widens the range of directions.
- `curlField` points along the divergence-free *curl* of the noise, so its streamlines are smooth, sourceless swirls.
- `z` is the noise slice. Animate it for a field that drifts over time.

You can also build a field from your own angle function:

```swift
let field = FlowField { p in atan2(p.y - 540, p.x - 540) + .pi / 2 }   // a vortex around the center
```

`flowField` and `curlField` capture the sketch's noise, so trace streamlines from the field and hold *those* rather than storing the field itself.

<a name="streamlines"></a>

#### Streamlines

```swift
field.streamline(from: Vector2, stepLength: Double = 4, steps: Int = 200, bounds: Rectangle? = nil) -> [Vector2]
field.streamlines(from seeds: [Vector2], stepLength: Double = 4, steps: Int = 200,
                  bounds: Rectangle? = nil, separation: Double? = nil) -> [[Vector2]]
```

`streamline` steps through a seed point both forward and backward, so the seed sits in the middle of the curve. It stops after `steps` in each direction, or earlier if the curve leaves `bounds`. `streamlines` traces one curve from each seed.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/14-FieldsAndFlow/TraceSteps-dark.jpg">
  <img src="../../Guide/Images/14-FieldsAndFlow/TraceSteps.jpg" alt="A paper diagram of faint field needles with one walk drawn through them: an orange start dot, then black dots connected by arrows stepping along the flow, following a faint fine line traced through the same field" width="680">
</picture>

Pass a `separation` and the lines are traced **evenly spaced**. A line stops when it comes within `separation` of one already traced, and a seed too close to an existing line is skipped. The curves then fan out without crossing, which is the flow-field look. Seed the field densely, with a [blue-noise](./BlueNoise.md) set for example, and let the separation thin it out.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/14-FieldsAndFlow/EvenSpacing-dark.jpg">
  <img src="../../Guide/Images/14-FieldsAndFlow/EvenSpacing.jpg" alt="Two panels of streamlines through the same field: on the left free lines cross and bunch into dense ropes; on the right evenly spaced lines stop before touching and read as combed fibers" width="680">
</picture>

```swift
seed(3)
let field = flowField(scale: 0.0016)
let seeds = poissonDisk(radius: 10)
noFill(); strokeWeight(3); strokeCap(.round)
for line in field.streamlines(from: seeds, stepLength: 4, steps: 220, bounds: bounds, separation: 14) {
    stroke(.white); drawPolyline(line)
}
```

Trace the lines once and hold them. You can then animate their color or width to get motion without tracing again. See the `Streamlines` example.

<a name="advect"></a>

#### Advecting particles

```swift
field.advected(_ points: [Vector2], stepLength: Double = 2) -> [Vector2]
```

`advected` steps a set of points one move along the field. Call it each frame for particles or strokes drifting through the flow. Pair it with accumulation (`noClear()`) and the trails paint the field over time:

```swift
override func setup() { noClear() }
override func draw() {
    let field = curlField(scale: 0.004)
    let next = field.advected(particles, stepLength: 2)
    for (a, b) in zip(particles, next) { stroke(.white); drawLine(a, b) }
    particles = next.map { bounds.contains($0) ? $0 : Vector2(random(0, width), random(0, height)) }
}
```

---

Related: [`Noise`](./Noise.md) (the Perlin and curl noise the fields are built from), [`Blue noise`](./BlueNoise.md) (the even seed set the streamlines fan out from), [`Geometry`](../Drawing/Geometry.md) (the shape booleans and stroking the lines feed).
