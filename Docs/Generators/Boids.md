#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Flocking`</sup>

---

## Flocking (boids)

A **flock of boids** is a crowd of simple agents that each follow local rules. Those rules produce lifelike flocking, so you get coherent groups that swirl, split, and regroup with no leader. Each boid steers by three forces, applied over the neighbors it can see, and the flocking motion emerges from them. This is Reynolds' classic model.

- **Separation** steers away from crowding neighbors.
- **Alignment** steers toward the average heading of nearby boids.
- **Cohesion** steers toward the average position of nearby boids.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/RuleSeparation-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/RuleSeparation.jpg" alt="Diagram of one dark boid inside a faint circle labeled personal space, three gray neighbors pressing in, and an orange arrow labeled away from the crowd pointing out of the crush" width="680">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/RuleAlignment-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/RuleAlignment.jpg" alt="Diagram of one dark boid among gray neighbors inside a faint circle labeled what it can see, each neighbor with its own small heading arrow, and an orange arrow showing the average heading the boid turns toward" width="680">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/RuleCohesion-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/RuleCohesion.jpg" alt="Diagram of one dark boid inside a faint circle, gray neighbors clustered to one side, an orange ringed dot at their center of the group, and an orange arrow from the boid toward it" width="680">
</picture>

`Boids` is a stateful simulation, so you hold on to the instance and call `step()` on it each frame. Its live state is `positions`, `velocities`, and `heading(_:)`, which you draw however you like. Give it a seed to get a reproducible flock.

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

The flock starts at random positions inside `bounds`. A boid steers back inward once it comes within `margin` of an edge. Step the flock in `draw()`, then read its state to draw each boid. `drawBoids` does that for you, drawing one triangle per boid, pointing along that boid's heading and filled with the current `fill`.

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

To color each boid separately, draw the triangles yourself from `positions[i]` and `heading(i)`. A common choice is to tint by heading, so boids traveling the same way share a color. See the `Flocking` example.

<a name="tuning"></a>

#### Tuning the flock

The weights and the radii set the look, and all of them are `var`s on the instance:

| Parameter | Effect |
| --- | --- |
| `separation` / `alignment` / `cohesion` | the weight of each rule. Raise `separation` for looser flocks, and `cohesion` for tighter ones |
| `perceptionRadius` | how far a boid sees other boids for alignment and cohesion |
| `separationRadius` | the shorter range inside which boids push apart |
| `maxSpeed` | the top speed a boid travels at |
| `maxForce` | the sharpest turn a boid can make. A lower value turns more smoothly and more slowly |
| `margin` | how far from an edge a boid starts to turn back |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/RuleMix-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/RuleMix.jpg" alt="Three panels of small dark triangles. Separation only: an even scatter pointing every way. Plus alignment: one loose school all pointing the same way. Plus cohesion: three tight flocks gathered apart from each other" width="680">
</picture>

Neighbor lookups use a uniform spatial hash as their broad phase, so their cost stays close to linear in the flock size.

<a name="flow"></a>

#### Following a flow field

Set `field` and `fieldStrength` to make the flock follow a [`FlowField`](./FlowField.md) as well. The flock then drifts along the flow while it keeps flocking:

```swift
let flock = Boids(count: 500, in: bounds, seed: 7)
flock.field = curlField(scale: 0.003)
flock.fieldStrength = 0.6
```

---

Related: [`Flow fields`](./FlowField.md) (the field a flock can follow), [`Differential growth`](./DifferentialGrowth.md) (the other stateful, stepped generator), [`Physics`](../Simulation/Physics.md) (force-driven motion with collisions and joints).
