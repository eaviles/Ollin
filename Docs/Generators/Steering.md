#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Steering`</sup>

---

## Steering behaviors

A **steering creature** moves with lifelike intent from one simple move: aim at full speed toward what you want, subtract the velocity you already have, and cap the turn. Every behavior is that move with a different idea of "what you want", so behaviors compose: weight the forces, sum them, and the creature balances its urges (Reynolds' autonomous-steering model, the single-creature side of [flocking](./Boids.md)).

`Vehicle` is a stateful creature you hold: each behavior method returns a force, `applyForce(_:)` accumulates the ones you choose, and `step()` moves. It's deterministic given its `seed` (only `wander` draws random numbers), so a seeded creature retraces the same path.

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

`maxSpeed` is the top speed; `maxForce` caps how sharply the creature can turn per step (low is smooth and sluggish, high snaps). The primitive is public:

```swift
creature.steer(toward: direction)   // aim at maxSpeed along direction, minus velocity, capped
```

<img src="../../Guide/Images/12-FlocksAndSwarms/SteeringMove.jpg" alt="Two-panel diagram. Left: a dot with a velocity arrow and a desired arrow pointing at a ring labeled the target. Right: the same arrows from one point, with an orange arrow labeled steer connecting the velocity's tip to the desired's tip" width="680">

`position`, `velocity`, and `heading` are the live state you draw however you like; `drawVehicle(_:size:)` draws a triangle pointing along the heading with the current `fill`.

<a name="behaviors"></a>

#### The behaviors

Each returns a force to pass to `applyForce(_:)`, scaled if you want it stronger or weaker:

| Behavior | What the creature wants |
| --- | --- |
| `seek(_ target:)` | reach the target at full speed |
| `flee(_ target:)` | get away from the target |
| `arrive(at:slowingRadius:)` | reach the target and *stop there* (speed ramps down inside the radius) |
| `pursue(_:velocity:)` / `pursue(_ other:)` | intercept a moving target by aiming where it will be |
| `evade(_:velocity:)` / `evade(_ other:)` | escape a moving threat by fleeing where it will be |
| `wander(radius:distance:jitter:)` | roam aimlessly (a jittered point on a circle projected ahead) |
| `follow(_ field:)` | move along a [`FlowField`](./FlowField.md) |
| `follow(path:radius:lookAhead:closed:)` | stay on a path corridor (below) |
| `separate(from:radius:)` | keep personal space from other vehicles |
| `contain(in:margin:)` | stay inside a rectangle (pushed back near the edges) |

<img src="../../Guide/Images/12-FlocksAndSwarms/ChaseDot.jpg" alt="Two curved trails sweep toward a white ring on a dark canvas. The teal trail bends in and stops at the ring; the coral trail swings past it and back through it in a line, its creature caught mid-swing" width="560">

`wander` is the one seeded behavior: small `jitter` drifts in long arcs, large is twitchy. Give each creature its own seed or they wander in lockstep.

<img src="../../Guide/Images/12-FlocksAndSwarms/WanderCircle.jpg" alt="Two-panel diagram. Left: a dot with a heading arrow, a faint circle ahead of it, an orange point on the circle's rim labeled the wandering target, and ghost points showing the jitter. Right: a long looping meander labeled what that produces" width="680">

<a name="path"></a>

#### Following a path

```swift
creature.follow(path: points, radius: 20, lookAhead: 50, closed: false)
```

The creature predicts its position `lookAhead` ahead; if the prediction strays more than `radius` off the polyline, it seeks a point further *along* the path, so it rejoins downstream instead of cutting straight back. Inside the corridor no force is returned. Pass `closed: true` for a loop (the walk-ahead wraps through the seam). Streamlines from a [flow field](./FlowField.md), a `Contour`'s points, or any point list work as the path.

<a name="combining"></a>

#### Combining behaviors

Weight by scaling each force, and let the caps resolve the conflict:

```swift
creature.applyForce(creature.follow(path: loop, closed: true))
creature.applyForce(creature.separate(from: troop, radius: 26) * 1.2)
creature.applyForce(creature.evade(threat) * 2)
creature.step()
```

For a whole flock with neighbor rules (separation, alignment, cohesion) use [`Boids`](./Boids.md), which runs the same steering move over a spatial hash; `Vehicle` is for the handful of creatures whose individual behavior you choreograph. See the `Motion/Steering` example (a path troop, wanderers, and a pursuer).

---

Related: [`Flocking (boids)`](./Boids.md) (the flock-scale sibling), [`Flow fields`](./FlowField.md) (fields a creature can follow), [`Physics`](../Simulation/Physics.md) (force-driven motion with collisions).
