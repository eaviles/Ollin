#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Articulated & chaotic motion`</sup>

---

## Articulated & chaotic motion

Three CPU motion systems you hold on the sketch and drive each frame: an inverse-kinematics chain that reaches (tentacles, limbs, ropes), the double pendulum (the classic chaos machine), and a gravitational n-body simulation (orbits, galaxies, collisions). All three are deterministic, with no hidden randomness and fixed iteration orders, and the n-body factories roll from a seed, so a run replays exactly and a fixed-frame export reproduces.

They pair naturally with the rest of the family. The [strange attractors](../Drawing/Attractors.md) are the *baked-orbit* side of chaos (build once, draw the path), while `DoublePendulum` and `NBody` are the *live* side you advance and watch. The [`@Sprung` damped spring](../Helpers/Animation.md#sprung) is the third member of the motion-helper family beside them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/11-ForcesAndPhysics/Articulated-dark.jpg">
  <img src="../../Guide/Images/11-ForcesAndPhysics/Articulated.jpg" alt="Three panels: a segmented chain curving so its tip touches a small ringed target while its base stays planted, a double pendulum's two arms with the looping tangle its far bob has traced, and a disk of hundreds of short streaks circling a heavy orange center" width="680">
</picture>

### Contents

- [Quick start](#quick-start)
- [`IKChain`: chains that reach](#ik)
- [`DoublePendulum`: chaos from two arms](#pendulum)
- [`NBody`: gravity at scale](#nbody)

<a name="quick-start"></a>

### Quick start

A tentacle that follows the mouse:

```swift
let arm = IKChain(from: Vector2(540, 1040), segments: 14, length: 36)

override func draw() {
    background(.white)
    arm.reach(toward: Vector2(mouseX, mouseY))
    noFill()
    stroke(.black)
    strokeWeight(6)
    drawPolyline(arm.joints)
}
```

A double pendulum tracing its second bob:

```swift
let pendulum = DoublePendulum()
var trail: [Vector2] = []

override func draw() {
    background(.white)
    pendulum.advance()
    withState {
        translate(width / 2, height / 3)
        trail.append(pendulum.bob2)
        stroke(Color.black.withAlpha(0.4)); strokeWeight(2)
        if trail.count > 1 { drawPolyline(trail) }
        stroke(.black); strokeWeight(4)
        drawLine(.zero, pendulum.bob1)
        drawLine(pendulum.bob1, pendulum.bob2)
    }
}
```

A spinning toy galaxy:

```swift
let galaxy = NBody.disk(count: 2000, center: Vector2(540, 540), radius: 380)

override func draw() {
    background(.black)
    galaxy.advance()
    noStroke()
    fill(.white)
    for p in galaxy.positions { drawCircle(center: p, radius: 2) }
}
```

<a name="ik"></a>

### `IKChain`: chains that reach

An `IKChain` is a run of rigid segments joined end to end. Make one from explicit points (`IKChain(joints:)`, segment lengths captured from the spacing) or laid out straight (`IKChain(from:segments:length:angle:)`), then move it with one of two verbs:

- **`reach(toward:)`** keeps the base planted and bends the chain so the tip strains for the target. This is the limb move. It returns whether the tip landed within `tolerance` (targets can be out of reach, or made unreachable by stiffness), and takes optional `iterations:` (default 10) and `tolerance:` (default 1) parameters. A target beyond the chain's `totalLength` stretches it dead straight toward the target in one pass.
- **`drag(to:)`** pins the *tip* to the target and lets everything trail after it, base included. This is the rope move, cheap enough to call every frame with no iteration count.

`moveBase(to:)` carries the whole pose rigidly to a new anchor (a chain mounted on a moving creature). Read `joints` to draw (a `drawPolyline` is the simplest body), plus `tip`, `base`, `lengths`, and `totalLength`.

Solving is warm-started from the current pose each call, so a chain moves coherently frame to frame instead of snapping between solutions.

**Two solvers, one aesthetic choice.** `chain.solver` picks how `reach` thinks:

- **`.fabrik`** (the default) alternates a tip-to-base and a base-to-tip pass, re-placing each joint at its segment length. Motion spreads evenly along the chain, so poses come out smooth and plant-like.
- **`.ccd`** swings one joint at a time to aim the tip, sweeping from the tip's joint down to the base. It favors the joints near the tip, so the chain whips and curls. `maxTurn` (radians per joint per sweep) damps the swing for smoother, kink-free motion.

Both honor **`maxBend`**, the stiffness limit, which is the largest angle a segment may fold against its neighbor, enforced at every interior joint during solving (never patched afterward, so segment lengths stay exact). Low values make stiff rods and spines, and `nil` (the default) bends freely. Stiffness can put a reachable target out of reach, in which case the solve settles as close as it can and reports `false` rather than spinning.

The [InverseKinematics example](../../Examples/Motion/InverseKinematics/Sketch.swift) plants five tentacles under a swimming lure with both parameters live.

<a name="pendulum"></a>

### `DoublePendulum`: chaos from two arms

Two point masses on rigid arms, swinging under gravity, which is the simplest system with genuinely chaotic motion. Configure it at creation (`length1`/`length2` in canvas units, `mass1`/`mass2`, starting `angle1`/`angle2` in radians measured from hanging straight down, optional starting velocities, and `gravity`, whose default treats 100 canvas units as a meter), then `advance()` it each frame.

Read positions through **`bob1`** and **`bob2`**, both relative to the pivot with y pointing down, so drawing is a `translate` to the pivot and two lines. `bob2` is the point worth tracing, because all the drama lives at the end of the second arm.

`advance(by:)` defaults to one 60 fps frame and splits the interval into fixed substeps sized so the integration holds energy steady (the `energy` property is the check, and it stays put to a hair). Two consequences worth knowing:

- **Determinism:** calling `advance()` with the default every frame makes the whole run a pure function of the starting angles. The same start replays the same chaos, while a start a ten-thousandth of a radian away diverges into a completely different dance within seconds. That sensitivity is the classic demonstration, and the [DoublePendulum example](../../Examples/Motion/DoublePendulum/Sketch.swift) draws it as a 24-pendulum fan.
- Passing a live `deltaTime` follows the wall clock instead, at the cost of exact reproducibility. For exports and snapshots, keep the default.

<a name="nbody"></a>

### `NBody`: gravity at scale

Every body pulls on every other, and that one rule makes orbits, spiral shear, tidal tails, and mergers. `NBody` holds a public `bodies` array (`NBody.Body`, with `position`, `velocity`, and `mass`) you may mutate freely between steps, and `step()` advances the whole system.

Three parameters shape the physics:

- **`gravity`** (default `1`) is the gravitational constant, the one pace parameter.
- **`theta`** (default `0.7`) is the accuracy dial for the far field. Forces run through a quadtree, where clumps of distant bodies act as single points when their region looks smaller than `theta` times its distance, which is what makes a few thousand bodies cheap. Use `0` for the exact all-pairs sum, `0.5` when accuracy shows, and `1` for fast and loose.
- **`softening`** (default `4`) caps how hard a close encounter pulls, so near-collisions swing through smoothly instead of slingshotting to infinity. A few pixels, about the typical body spacing, reads well.

The integrator is the standard leapfrog for gravity, which holds orbital energy bounded over long runs instead of letting orbits slowly decay, and it costs one force pass per step. Keep the interval fixed frame to frame (the default is one 60 fps frame), because that fixedness is part of what keeps orbits stable.

Two seeded factories stage the classic scenes:

- **`NBody.disk(count:center:radius:...)`** builds a spinning disk around a heavy central body (`bodies[0]`), each light body started on the circular orbit its radius calls for. `spin` flips the direction, `jitter` roughens the orbits, and `velocity` drifts the whole disk, which is how you stage a two-galaxy encounter. Build two disks, then append one's `bodies` to the other's.
- **`NBody.cluster(count:center:radius:...)`** scatters motionless bodies that collapse, swing through, and puff into a bound swarm.

Read `positions` for drawing and `centerOfMass` to keep a camera or `translate` anchored on drifting action. The [NBody example](../../Examples/Motion/NBody/Sketch.swift) stages two galaxies on a bound grazing orbit, where small additive points make the arms glow as they cross.
