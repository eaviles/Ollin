#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Flow fields`</sup>

---

## Flow fields

A **flow field** gives a direction at every point of the plane. Trace *streamlines* through it (curves that follow the flow) or *advect* particles and strokes along it. The direction comes from an `angle` function, so a field can be built from noise, a formula, or anything you like, and streamlines are ordinary point lists, so they feed stroking, the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export.

```
  the field: a direction per point        streamlines follow the flow

    →  →  ↗  ↑  ↖                            ___----‾‾‾‾
    →  ↗  ↑  ↖  ←              →            /    ___---
    ↗  ↑  ↖  ←  ↙                          |  __-
    ↑  ↖  ←  ↙  ↓                           ‾‾
```

### Contents

- [Building a field](#build)
- [Streamlines](#streamlines)
- [Advecting particles](#advect)

<a name="build"></a>

#### Building a field

The `flowField` and `curlField` sketch sugar build a field from the seeded Perlin noise; both are reproducible under [`seed`](./Random.md#seed).

```swift
flowField(scale: Double = 0.002, turns: Double = 1, z: Double = 0) -> FlowField
curlField(scale: Double = 0.003, z: Double = 0) -> FlowField
```

- `flowField` maps the noise to an angle (smaller `scale` is smoother, `turns` widens the range of directions).
- `curlField` points along the divergence-free *curl* of the noise, so streamlines read as smooth, sourceless swirls.
- `z` is the noise slice; animate it for a field that drifts over time.

Or build one from your own angle function:

```swift
let field = FlowField { p in atan2(p.y - 540, p.x - 540) + .pi / 2 }   // a vortex around the center
```

Because `flowField`/`curlField` capture the sketch's noise, trace streamlines from the field and hold *those* rather than storing the field itself.

<a name="streamlines"></a>

#### Streamlines

```swift
field.streamline(from: Vector2, stepLength: Double = 4, steps: Int = 200, bounds: Rectangle? = nil) -> [Vector2]
field.streamlines(from seeds: [Vector2], stepLength: Double = 4, steps: Int = 200,
                  bounds: Rectangle? = nil, separation: Double? = nil) -> [[Vector2]]
```

`streamline` steps through a seed point both forward and backward (so the seed sits in the middle of the curve), stopping after `steps` each way or when it leaves `bounds`. `streamlines` traces one from each seed.

Pass a `separation` and the lines are traced **evenly spaced**: a line stops when it comes within `separation` of one already traced, and seeds too close to an existing line are skipped, so the curves fan out without crossing (the flow-field look). Seed it densely (a [blue-noise](./BlueNoise.md) set works well) and let the separation thin it out.

```swift
seed(3)
let field = flowField(scale: 0.0016)
let seeds = poissonDisk(radius: 10)
noFill(); strokeWeight(3); strokeCap(.round)
for line in field.streamlines(from: seeds, stepLength: 4, steps: 220, bounds: bounds, separation: 14) {
    stroke(.white); drawPolyline(line)
}
```

Trace once and hold the lines; animate their color or width to move without re-tracing. See the `Streamlines` example.

<a name="advect"></a>

#### Advecting particles

```swift
field.advected(_ points: [Vector2], stepLength: Double = 2) -> [Vector2]
```

Step a set of points one move along the field each frame, for particles or strokes drifting through the flow. Paired with accumulation (`noClear()`), the trails paint the field over time:

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

Related: [`Noise`](./Noise.md) (the Perlin and curl noise the fields are built from), [`Blue noise`](./BlueNoise.md) (the even seed set streamlines fan out from), [`Geometry`](../Drawing/Geometry.md) (the shape booleans and stroking the lines feed).
