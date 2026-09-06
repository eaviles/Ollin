#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Steering`</sup>

---

## Steering behaviors

A **steering creature** moves as if it had intent, and one simple move is all that takes. Aim at full speed toward what you want, subtract the velocity you already have, then cap the turn. Every behavior is that same move with a different idea of what you want, so behaviors combine. Scale each force, add them together, and the creature balances the things it wants. This is Reynolds' autonomous-steering model, the single-creature side of [flocking](./Boids.md).

`Vehicle` is a creature you hold on to, and it keeps its own state. Each behavior method returns a force, `applyForce(_:)` adds up the ones you choose, and `step()` moves the creature. A `Vehicle` is deterministic for a given `seed`, because only `wander` draws random numbers, so a seeded creature retraces the same path.

```swift
let creature = Vehicle(at: center, seed: 1)

override func draw() {
    creature.applyForce(creature.wander())
    creature.applyForce(creature.contain(in: bounds) * 1.5)
    creature.step()
    fill(.white)
    drawVehicle(creature)
}
```

### Contents

- [The steering move](#move)
- [The behaviors](#behaviors)
- [Following a path](#path)
- [Combining behaviors](#combining)

<a name="move"></a>

#### The steering move

```swift
Vehicle(at: Vector2, velocity: Vector2 = .zero,
        maxSpeed: Double = 3, maxForce: Double = 0.12, seed: UInt64 = 0)
```

`maxSpeed` is the top speed. `maxForce` caps how sharply the creature can turn on each step, so a low value turns smoothly and slowly, and a high value snaps around. The steering move itself is public:

```swift
creature.steer(toward: direction)   // aim at maxSpeed along direction, minus velocity, capped
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/SteeringMove-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/SteeringMove.jpg" alt="Two-panel diagram. Left: a dot with a velocity arrow and a desired arrow pointing at a ring labeled the target. Right: the same arrows from one point, with an orange arrow labeled steer connecting the velocity's tip to the desired's tip" width="680">
</picture>

`position`, `velocity`, and `heading` are the live state, and you can draw them however you like. `drawVehicle(_:size:)` draws a triangle that points along the heading, using the current `fill`.

<a name="behaviors"></a>

#### The behaviors

Each behavior returns a force to pass to `applyForce(_:)`, and you scale that force to make it stronger or weaker.

| Behavior | What the creature wants |
| --- | --- |
| `seek(_ target:)` | reach the target at full speed |
| `flee(_ target:)` | get away from the target |
| `arrive(at:slowingRadius:)` | reach the target and *stop there* (speed ramps down inside the radius) |
| `pursue(_:velocity:)` / `pursue(_ other:)` | intercept a moving target by aiming where it will be |
| `evade(_:velocity:)` / `evade(_ other:)` | escape a moving threat by fleeing where it will be |
| `wander(radius:distance:jitter:)` | roam with no target, by seeking a jittered point on a circle projected ahead |
| `follow(_ field:)` | move along a [`FlowField`](./FlowField.md) |
| `follow(path:radius:lookAhead:closed:)` | stay inside a corridor along a path, described below |
| `separate(from:radius:)` | keep some space from the other vehicles |
| `contain(in:margin:)` | stay inside a rectangle (pushed back near the edges) |

<img src="../../Guide/Images/12-FlocksAndSwarms/ChaseDot.jpg" alt="Two curved trails sweep toward a white ring on a dark canvas. The teal trail bends in and stops at the ring; the coral trail swings past it and back through it in a line, its creature caught mid-swing" width="560">

`wander` is the one behavior that uses the seed. A small `jitter` drifts in long arcs, and a large one is twitchy. Give each creature its own seed, or they all wander the same way at the same time.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/WanderCircle-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/WanderCircle.jpg" alt="Two-panel diagram. Left: a dot with a heading arrow, a faint circle ahead of it, an orange point on the circle's rim labeled the wandering target, and ghost points showing the jitter. Right: a long looping meander labeled what that produces" width="680">
</picture>

<a name="path"></a>

#### Following a path

```swift
creature.follow(path: points, radius: 20, lookAhead: 50, closed: false)
```

The creature predicts its own position `lookAhead` ahead of where it is now. If that prediction strays more than `radius` off the polyline, the creature seeks a point further *along* the path. It rejoins the path ahead of itself, instead of cutting straight back. While the prediction stays inside the corridor, the behavior returns no force. Pass `closed: true` for a loop, and the walk ahead then wraps through the seam. The path can be streamlines from a [flow field](./FlowField.md), the points of a `Contour`, or any list of points.

<a name="combining"></a>

#### Combining behaviors

Scale each force to give it a weight, and let the caps resolve the conflict between them:

```swift
creature.applyForce(creature.follow(path: loop, closed: true))
creature.applyForce(creature.separate(from: troop, radius: 26) * 1.2)
creature.applyForce(creature.evade(threat) * 2)
creature.step()
```

For a whole flock with neighbor rules (separation, alignment, cohesion), use [`Boids`](./Boids.md), which runs the same steering move over a spatial hash. `Vehicle` is for the handful of creatures whose behavior you direct one by one. See the `Motion/Steering` example, which has a path troop, wanderers, and a pursuer.

---

Related: [`Flocking (boids)`](./Boids.md) (the same steering at flock scale), [`Flow fields`](./FlowField.md) (fields a creature can follow), [`Physics`](../Simulation/Physics.md) (force-driven motion with collisions).
