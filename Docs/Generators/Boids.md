#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Flocking`</sup>

---

## Flocking (boids)

A **flock of boids** is many simple agents whose local rules produce lifelike flocking: coherent groups that swirl, split, and regroup with no leader. Each boid steers by three forces over the neighbors it can see, and the emergent motion falls out (Reynolds' classic model).

- **Separation** steers away from crowding neighbors.
- **Alignment** steers toward the average heading of nearby boids.
- **Cohesion** steers toward the average position of nearby boids.

<img src="../../Guide/Images/12-FlocksAndSwarms/RuleSeparation.jpg" alt="Diagram of one dark boid inside a faint circle labeled personal space, three gray neighbors pressing in, and an orange arrow labeled away from the crowd pointing out of the crush" width="680">

<img src="../../Guide/Images/12-FlocksAndSwarms/RuleAlignment.jpg" alt="Diagram of one dark boid among gray neighbors inside a faint circle labeled what it can see, each neighbor with its own small heading arrow, and an orange arrow showing the average heading the boid turns toward" width="680">

<img src="../../Guide/Images/12-FlocksAndSwarms/RuleCohesion.jpg" alt="Diagram of one dark boid inside a faint circle, gray neighbors clustered to one side, an orange ringed dot at their center of the group, and an orange arrow from the boid toward it" width="680">

`Boids` is a stateful simulation you hold and `step()` each frame. `positions`, `velocities`, and `heading(_:)` are the live state you draw however you like. Seed it for a reproducible flock.

### Contents

- [Building and stepping](#step)
- [Tuning the flock](#tuning)
- [Following a flow field](#flow)

<a name="step"></a>

#### Building and stepping

```swift
Boids(count: Int, in bounds: Rectangle, seed: UInt64 = 0,
      maxSpeed: Double = 3, maxForce: Double = 0.12,
      perceptionRadius: Double = 50, separationRadius: Double = 22, margin: Double = 60)
```

The flock is placed at random inside `bounds` and steers back inward as it nears an edge (within `margin`). Step it in `draw()` and read the state to draw each boid; `drawBoids` draws a triangle per boid pointing along its heading with the current `fill`.

```swift
final class Flock: Sketch {
    let flock = Boids(count: 500, in: bounds, seed: 7)

    override func draw() {
        flock.step()
        background(.black); fill(.white)
        drawBoids(flock, size: 10)
    }
}
```

For per-boid color (a common touch is to tint by heading, so boids traveling the same way share a color), draw the triangles yourself from `positions[i]` and `heading(i)`. See the `Flocking` example.

<a name="tuning"></a>

#### Tuning the flock

The look is set by the weights and radii, all `var`s on the instance:

| Parameter | Effect |
| --- | --- |
| `separation` / `alignment` / `cohesion` | the weight of each rule (raise `separation` for looser flocks, `cohesion` for tighter ones) |
| `perceptionRadius` | how far a boid sees others for alignment and cohesion |
| `separationRadius` | the closer range within which boids push apart |
| `maxSpeed` | the top speed a boid travels |
| `maxForce` | the sharpest turn a boid can make (lower is smoother, more sluggish) |
| `margin` | how far from an edge a boid starts turning back |

<img src="../../Guide/Images/12-FlocksAndSwarms/RuleMix.jpg" alt="Three panels of small dark triangles. Separation only: an even scatter pointing every way. Plus alignment: one loose school all pointing the same way. Plus cohesion: three tight flocks gathered apart from each other" width="680">

Neighbor lookups are broad-phased through a uniform spatial hash, so the cost stays close to linear in the flock size.

<a name="flow"></a>

#### Following a flow field

Set `field` (and a `fieldStrength`) to make the flock also follow a [`FlowField`](./FlowField.md), so the flock drifts along the flow while still flocking:

```swift
let flock = Boids(count: 500, in: bounds, seed: 7)
flock.field = curlField(scale: 0.003)
flock.fieldStrength = 0.6
```

---

Related: [`Flow fields`](./FlowField.md) (the field a flock can follow), [`Differential growth`](./DifferentialGrowth.md) (the other stateful, stepped generator), [`Physics`](../Simulation/Physics.md) (force-driven motion with collisions and joints).
