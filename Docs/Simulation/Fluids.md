#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Fluids & soft bodies`</sup>

---

## Fluids & soft bodies

Two GPU particle-dynamics systems ship with `import Ollin`. The first is **`ParticleFluid`**, tens of thousands of particles that pour, splash, and settle like water. The second is **`SoftBodies`**, squishy blobs that squash on impact and spring back. Both live inside a walled box, run on the [`SpatialHash`](../Shaders/Compute.md#spatialhash) neighbor search, and respond to a mouse `pull`/`push`. Both follow the same shape as the [artificial-life sims](./ArtificialLife.md), building in `setup()` and updating and drawing in `draw()`.

The shared caveat applies here too: neighbor sums are GPU-race-ordered and the systems are chaotic, so runs are **not** reproducible frame-for-frame. Seed for a repeatable starting layout, not a pixel-identical video.

<img src="../../Guide/Images/20-ParticleSimulations/FluidAndBlobs.jpg" alt="Two dark panels. Left, a blue particle fluid mid-slosh, a wave climbing the left wall over a churning cavity. Right, nine soft bodies in orange, green, blue, red, purple, and cyan piled at the bottom of a box, squashing flat where they press against each other" width="680">

### Contents

- [Particle fluid](#particle-fluid)
- [Soft bodies](#soft-bodies)
- [Grabbing and splashing](#interaction)

<a id="particle-fluid"></a>
### Particle fluid

Smoothed-particle hydrodynamics runs in three steps (Müller, Charypar & Gross 2003). Each particle measures how crowded it is. Crowding becomes pressure, and pressure pushes neighbors apart with equal-and-opposite forces. A second, sharper, always-repulsive *near-pressure* keeps particles from clumping (Clavet, Beaudoin & Poulin 2005). It gives the free surface its bead-and-filament tension, so drops look like drops. The fluid seeds as a hanging block, so the first seconds are a dam break.

```swift
var fluid: ParticleFluid!

override func setup() {
    fluid = makeParticleFluid(count: 26_000, radius: 12)
}

override func draw() {
    background(.black)
    if mouseIsPressed { fluid.pull(at: Vector2(mouseX, mouseY)) }
    blendMode(.add)
    updateParticleFluid(fluid)
    drawParticles(fluid)
}
```

Three things are fixed at build. `count` is how many particles there are. `radius` is the interaction range, which is the fluid's resolution and, through the derived `spacing`, its packing. `bounds` is the box, and it defaults to the canvas. The liquid itself is live:

| Knob | Meaning | Default |
| --- | --- | --- |
| `gravity` | pull in points/s²; tilt or zero it | `(0, 1500)` |
| `stiffness` | pressure strength (resistance to squeezing); higher wants more `substeps` | 240 000 |
| `nearStiffness` | the anti-clump / surface-tension pressure | 150 000 |
| `viscosity` | neighborhood velocity smoothing per substep (0…1); higher is syrupy | 0.12 |
| `bounce` | fraction of normal velocity kept at a wall (0…1) | 0.25 |
| `substeps` | fixed substeps per frame (2…8) | 4 |
| `colorSlow` / `colorFast` / `speedForFastColor` | the speed tint ramp | blue → ice, 1 100 pt/s |
| `restDensity` | target density relative to the seeded packing | 1 |

Particles draw as discs through `drawParticles(fluid)` (additive blending reads as light through water). For a continuous liquid surface, draw them into a layer and threshold a blur (`makeRenderTarget(...)` + `.gaussianBlur(radius:)` + `.threshold(value:softness:)`), the classic metaball trick.

Example: `Examples/Simulation/ParticleFluid`.

<a id="soft-bodies"></a>
### Soft bodies

Meshless shape matching drives this one (Müller, Heidelberger, Teschner & Gross 2005). Each body is a cloud of particles that remembers its rest shape. Every substep it finds the rotation that best maps the rest layout onto its current one. Then it steers each particle back toward its spot. That one pull is the entire elasticity model, so there are no springs to tune and nothing can blow up. A fully crushed blob springs back. Bodies collide with each other through inelastic contacts in the neighbor hash, and they tumble into piles.

```swift
var blobs: SoftBodies!

override func setup() {
    blobs = makeSoftBodies(bodies: 12, radius: 80)
}

override func draw() {
    background(.black)
    if mouseIsPressed { blobs.pull(at: Vector2(mouseX, mouseY)) }
    updateSoftBodies(blobs)
    drawParticles(blobs)
}
```

Blobs scatter (separated) in the upper part of the box, each varying around `radius`, one hue per body. The knobs:

| Knob | Meaning | Default |
| --- | --- | --- |
| `squish` | how firmly a body holds its shape, 0…1 (low = jelly, high = rubber) | 0.3 |
| `gravity` | pull in points/s² | `(0, 1600)` |
| `bounce` | wall liveliness (0…1) | 0.35 |
| `damping` | fraction of velocity kept per second; lower settles piles faster | 0.4 |
| `collisionStrength` | how hard touching bodies push apart, points/s² | 35 000 |
| `substeps` | fixed substeps per frame (2…8) | 4 |

Example: `Examples/Simulation/SoftBodies`.

<a id="interaction"></a>
### Grabbing and splashing

Both systems take a one-frame interaction you re-issue every frame while a drag is held:

```swift
if mouseIsPressed { fluid.pull(at: Vector2(mouseX, mouseY)) }        // grab
override func keyPressed() { fluid.push(at: Vector2(mouseX, mouseY)) } // splash
```

`pull(at:strength:radius:)` fades gravity inside its radius and damps swirl. Held fluid then hangs at the cursor instead of orbiting or streaming down. `push` is the same force outward, and `strength` is an acceleration in points/s².

### Notes

- **Credits.** The SPH model (Müller et al. 2003), the near-pressure term (Clavet et al. 2005), and shape matching (Müller et al. 2005) are reimplemented from the published papers and credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).
- **Substeps are the stability budget.** Both systems run fixed substeps against a clamped frame clock, and a particle never moves more than about half its interaction radius per substep, so a hitch can't detonate the sim. Raising `stiffness` far beyond the default wants a couple more substeps.
- **Cost.** Each substep rebuilds the neighbor hash and runs the interaction passes, so cost scales with `count × substeps` (times neighbor density). The fluid example's 26 000 particles at 4 substeps run in real time on Apple silicon.
