#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Swarm`</sup>

---

## Swarm

A crowd of steering creatures on the GPU. `Swarm` speaks the same behavior vocabulary as the CPU [`Vehicle`](../Generators/Steering.md) and [`Boids`](../Generators/Boids.md), but runs it over the [`SpatialHash`](../Shaders/Compute.md#spatialhash) neighbor search, so a flock is tens or hundreds of thousands of agents rather than a few hundred. It ships with `import Ollin`, no satellite needed.

Every behavior is a **weight**, and a weight of zero is a behavior that is off. One swarm is a flock, a crowd chasing the cursor, or a field of aimless wanderers depending on which numbers you set.

### Contents

- [Making one](#making-one)
- [The behaviors](#behaviors)
- [Knobs](#knobs)
- [Choosing the numbers](#choosing)
- [Seeing the movement](#trails)
- [Notes](#notes)

<a id="making-one"></a>
### Making one

```swift
var flock: Swarm!

override func setup() {
    background(.black); noClear()
    flock = swarm(count: 30_000, perceptionRadius: 16)
    flock.separation = 1.5
    flock.alignment = 1.5
    flock.cohesion = 0.8
}

override func draw() {
    background(.black)
    blendMode(.add)
    updateSwarm(flock)
    drawParticles(flock)
}
```

`swarm(count:perceptionRadius:colors:size:bounds:seed:)` builds one over the whole canvas by default, seeded from the sketch's `variation`. `count` and `perceptionRadius` are fixed at build; everything else is a live property you can set any frame or bind to a `@Param`.

The world is a **torus**: an agent that leaves one edge comes back at the opposite one, and neighbors are found across the seam too, so there are no edges for a flock to pile up against.

<a id="behaviors"></a>
### The behaviors

Each one works out a *desired velocity* and returns the difference from the velocity the agent already has. The weighted sum is capped at `maxForce` and drives the agent, whose speed is capped at `maxSpeed`.

| Behavior | What it does | Needs neighbors |
| --- | --- | --- |
| `separation` | steers away from whoever is inside `separationRadius` | yes |
| `alignment` | steers toward the average heading of the neighbors it can see | yes |
| `cohesion` | steers toward the middle of them | yes |
| `seek` | steers at `target` | no |
| `flee` | steers away from `target` | no |
| `arrive` | steers at `target` but slows to a stop over `slowingRadius` | no |
| `wander` | roams, turning by a random walk rather than jittering on the spot | no |
| `flow` | follows a swirling flow field, `flowScale` sizing its eddies | no |

Turning the three flocking rules on at once gives the classic flocking model. Turning only `flow` on gives streamlines through a field. Turning only `wander` on gives a crowd of independent roamers.

**`flee` is not `seek` with a negative weight.** Fleeing means wanting to travel *away* at full speed, which is a different desired velocity, not the opposite force. Both exist for that reason.

**Pursuit and evasion are not separate behaviors** because they do not need to be: pursuit is `seek` aimed at where the quarry *will* be. Lead the target yourself and `seek` becomes pursuit:

```swift
flock.target = prey.position + prey.velocity * 0.4   // where it will be in 0.4s
flock.seek = 2
```

<a id="knobs"></a>
### Knobs

| Knob | Meaning | Default |
| --- | --- | --- |
| `target` | the point `seek` / `flee` / `arrive` steer by | `.zero` |
| `maxSpeed` | top speed, points per second | 190 |
| `minSpeed` | slowest an agent may travel; 0 lets it stop | 0 |
| `maxForce` | strongest steering force, points per second squared | 620 |
| `separationRadius` | how close is too close (clamped to `perceptionRadius`) | 14 |
| `viewAngle` | field of view in radians; `.tau` sees all the way round | 4.6 |
| `slowingRadius` | where `arrive` begins to ramp down | 140 |
| `wanderRadius` | how far the roaming can swing | 26 |
| `wanderDistance` | how far ahead the wander circle sits; larger is a lazier arc | 62 |
| `wanderRate` | how fast the wander walk turns, radians per second | 5.5 |
| `flowScale` | flow-field frequency; smaller is broader swirls | 0.0022 |
| `flowLookAhead` | how far ahead the field is read | 40 |

Speeds and forces are **per second** here, where the CPU `Vehicle`'s are per step, so a swarm keeps its pace whatever the frame rate.

<a id="choosing"></a>
### Choosing the numbers

Three of them are tied to each other, and a swarm that looks wrong is usually one of these rather than a weight:

- **`perceptionRadius` sets how many others an agent sees**, which is `count · π · radius² / canvas area`. Around twenty works. Far more and every agent is averaging over most of the swarm, so alignment and cohesion pull toward the same global mean and the structure washes out.
- **`separationRadius` should be one or two times the mean spacing** between agents (roughly `√(area / count)`). Much larger and every agent is permanently shoving everyone, which flattens the swarm into an even gas.
- **The turning circle is `maxSpeed² / maxForce`.** Make it a few times `perceptionRadius`. Much tighter and agents orbit inside their own neighborhood instead of travelling; much wider and they cannot answer their neighbors before leaving them behind. An agent should also take several frames to cross its perception radius.

**`minSpeed` is the fix for a swarm that sets solid.** With the plain steering model an agent pushed at from every side simply stops, and in a crowd the stalled ones become a wall the rest jam against, so the whole thing freezes into a fixed pattern. A floor on speed keeps it flowing, on the grounds that a bird cannot hover. It is off by default because stopping is what the published model does.

<a id="trails"></a>
### Seeing the movement

A single frame of a swarm shows you where everyone *is*, which is a density picture and not a movement one. Agents typically move a few points per frame, so their marks overlap and nothing reads as direction. Lay a translucent sheet over an accumulating canvas instead, and each agent draws its own recent path:

```swift
override func setup() {
    background(.black); noClear()
    ...
}

override func draw() {
    blendMode(.normal)
    noStroke()
    fill(Color(white: 0.02, alpha: 0.16))
    drawRect(0, 0, width, height)     // fade what is already there
    blendMode(.add)
    updateSwarm(flock)
    drawParticles(flock)
}
```

Use a rectangle, not `background(_:)`: while [accumulating](../Drawing/Accumulation.md), `background(_:)` *wipes* the canvas however little alpha its color carries, so it leaves no trail at all.

<a id="notes"></a>
### Notes

- **Speed.** Measured on an M2 at 1080², release build: 30,000 flocking agents draw at 60 fps; 120,000 (each seeing about 80 others) run at 34. The neighbor search is the cost, and it grows with how many neighbors each agent has, not just with `count`. A swarm with none of the three flocking weights on **skips the neighbor sort entirely**, so a million wandering or seeking agents step at 60 fps, and what limits them is drawing a million marks rather than steering them.
- **Not frame-exact.** Like the other systems built on `SpatialHash`, the within-cell order of the neighbor sort is set by a GPU atomic race, and flocking is chaotic, so a run is not reproducible frame-for-frame across machines or exports. Seed it for a repeatable *starting* layout, not an identical video.
- **A dense swarm organizes into lanes and cells.** Filling the canvas at high density with all three flocking rules on gives bands, vortices, and a labyrinth of streams rather than separate flocks in open space. That is what the rules actually do at that density, not a fault. For distinct flocks, use fewer agents relative to the canvas.
- **`viewAngle` leaves a blind spot behind each agent** by default, which is what keeps a flock from folding back through itself. Widen it to `.tau` for all-round vision.

Example: `Examples/Simulation/Swarm`.
