#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Pursuit`</sup>

---

## Pursuit

Each runner heads straight at the runner it was told to chase, and the paths they leave behind are the drawing. Put a runner on each corner of a polygon, tell each one to chase the next, and start them together. No runner travels in a straight line, because every target is moving too. The ring shrinks and turns at the same time, so the runners meet in the middle.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/PursuitDogs-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/PursuitDogs.jpg" alt="Two-panel diagram. Left: four dogs at the corners of a square, faint chase lines filling it, and four identical spirals curling into the middle, one of them orange. Right: a quarry running straight up a faint line while an orange curve sweeps in from the right and meets it" width="680">
</picture>

Nothing here is random, so the same start always runs the same chase. What comes out is ordinary geometry. You can stroke it, fill it, combine it with the [shape booleans](../Drawing/Geometry.md), hatch it, and export it as SVG.

### Contents

- [Building a chase](#build)
- [What a step does](#step)
- [Four facts that are exact](#laws)
- [A quarry that runs straight](#straight)
- [Tuning the chase](#tuning)
- [What comes out](#output)

<a name="build"></a>

#### Building a chase

`Pursuit` is a class you build once and then step. Take a few steps a frame to watch the chase draw itself, or work out the whole chase at once with `run()`.

```swift
final class Spirals: Sketch {
    let chase = Pursuit.ring(sides: 6, center: Vector2(540, 540), radius: 420)

    override func setup() {
        chase.recordEvery = 10   // keep the chase lines along the way
        chase.run()              // the whole chase, worked out once
    }

    override func draw() {
        background(Color(hex: 0x11131A))
        noFill()
        stroke(Color.white.withAlpha(0.15)); strokeWeight(1)
        for line in chase.web { drawPolyline(line.points) }
        stroke(Color(hex: 0xE0724A)); strokeWeight(3)
        for trail in chase.trails { drawPolyline(trail.points) }
    }
}
```

`ring(sides:center:radius:)` builds the classic figure. `chasing:` says how many places around the ring the target sits, and 1 is the classic value. Half of `sides` sends every runner straight at the one opposite it, so there is no spiral at all.

For any other arrangement, build the runners yourself. Each runner names the index of the runner it follows, and a runner that follows nobody holds its heading and runs straight.

```swift
let chase = Pursuit(runners: [.holding(Vector2(0, 1), from: Vector2(300, 200), speed: 0.5),
                              .chasing(0, from: Vector2(700, 200))],
                    stepSize: 2)
```

<a name="step"></a>

#### What a step does

`step()` moves every runner once, and `step(_:)` takes several steps. One step does three things, in this order:

1. Every runner that follows another turns to face it. With no `maxTurn` set it turns on the spot, which gives the classic curve.
2. Every runner moves `speed * stepSize` along its heading. **They all move at the same moment**, from the positions they held before the step. That is what keeps a ring a ring. It is also the whole difference between this figure and a lopsided one.
3. A runner within `catchDistance` of its target lands on it, stops, and reports `hasArrived`. A runner never runs past the one it caught, no matter how long its stride.

`run(limit:)` steps until every chaser has arrived, or until it reaches the limit. `isFinished` tells you whether every chaser arrived.

<a name="laws"></a>

#### Four facts that are exact

The ring is worth knowing because you can work out so much about it in advance. In the table below, `s` stands for `sin(chasing * pi / sides)`.

| | |
|---|---|
| The shape holds | the ring is a regular polygon at every step, only smaller and turned |
| The path | each path is a logarithmic spiral. The angle between a runner's path and the line to the center never changes, and stays at `90 - chasing * 180 / sides` degrees |
| The distance | a runner starting `radius` from the center covers `radius / s` before it arrives. On a square that is exactly one side of the square |
| The shrink | one step takes the ring from `r` to `sqrt(r * r - 2 * d * r * s + d * d)`, where `d` is the stride |

The last row explains a chase that looks like it has stalled. A runner covers a fixed distance per step, so it overshoots the turn a little every time. That means it can never come nearer the center than `d * cos(chasing * pi / sides)`. The gap between neighbors falls to one stride at the circle of radius `d / (2 * s)`, and the chase stops making progress there. `catchDistance` defaults to two strides, so the chase ends one ring earlier.

This is also why a drawn total comes out slightly over the distance the law gives. A smaller `stepSize` draws a finer curve and a closer number.

<a name="straight"></a>

#### A quarry that runs straight

The other classic case is a fast runner chasing a quarry that crosses in front of it. Write the quarry as a runner that follows nobody:

```swift
let gap = 300.0, k = 0.5     // the quarry's speed, against the pursuer's 1
let chase = Pursuit(runners: [.holding(Vector2(0, 1), from: .zero, speed: k),
                              .chasing(0, from: Vector2(gap, 0))],
                    stepSize: 0.5)
chase.run()
```

From a square-on start the pursuer covers `gap / (1 - k * k)` before the catch, and the quarry covers `gap * k / (1 - k * k)`. At a `k` of 1 or more the quarry is never caught, because the gap closes to half its starting size and stops there.

<a name="tuning"></a>

#### Tuning the chase

| Parameter | What it does |
|---|---|
| `stepSize` | how far a runner of speed 1 covers per step. Smaller steps draw a finer curve, take more steps, and land closer to the law |
| `catchDistance` | how close counts as arrived. The default is two strides. A runner's own stride is the lower limit, so a runner never runs past its target |
| `maxTurn` | the most a runner may turn in one step, in radians. `nil` lets it turn on the spot. A value makes a runner swing wide, and it can overshoot. 0 makes a runner that cannot turn at all |
| `recordEvery` | record the chase lines into `web` every this many steps. 0 records none |
| `Runner.speed` | a multiple of `stepSize`, so one runner can be faster or slower than another |
| `Runner.chases` | the index of the runner it follows. `nil`, its own index, or an index nobody holds all mean it runs straight |

<a name="output"></a>

#### What comes out

| | |
|---|---|
| `trails` | each runner's path so far, as an open `Contour`. This is the drawing |
| `web` | the chase lines recorded along the way, one two-point `Contour` each. The first one is the line-up you began with |
| `links` | the chase lines as they stand now. On a ring these are the sides of the polygon |
| `runners` | the runners themselves: `position`, `heading`, `trail`, `distanceTraveled`, `hasArrived` |

All of it is plain geometry. You can stroke `trails` directly, hatch it, and cut it with the booleans. It also goes to a pen plotter, which draws a chase the way it was always drawn, as one continuous line per runner.

### See also

- [`Steering`](./Steering.md) - seek, flee, arrive, and wander, the same idea written as forces on an agent that has momentum
- [`Boids`](./Boids.md) - a whole flock, where each bird answers to its neighbors rather than to one target
- [`Meander`](./Meander.md) - another stateful stepper that produces a line
- [`Curves`](../Drawing/Curves.md) - the classic curves you can write down in closed form

### Where this comes from

Pierre Bouguer first studied the chase curve in 1732, in a paper about one ship pursuing another. Edouard Lucas asked the ring question in 1877, and Henri Brocard answered it. The paths are logarithmic spirals, and they meet in one point. This implementation is written from the published results, and it is credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

### Example

[`Examples/Patterns/Pursuit`](../../Examples/Patterns/Pursuit/Sketch.swift) draws the ring while it runs. The recorded chase lines sit under it, and the distance is measured against the law.
