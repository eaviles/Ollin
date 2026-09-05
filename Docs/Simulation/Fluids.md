#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Fluids & soft bodies`</sup>

---

## Fluids & soft bodies

`import Ollin` gives you two GPU particle-dynamics systems. The first is **`ParticleFluid`**, tens of thousands of particles that pour, splash, and settle like water. The second is **`SoftBodies`**, soft blobs that squash on impact and spring back. Both systems live inside a walled box, both use the [`SpatialHash`](../Shaders/Compute.md#spatialhash) neighbor search, and both respond to a mouse `pull` or `push`. They follow the same pattern as the [artificial-life sims](./ArtificialLife.md), so you build the system in `setup()`, then update and draw it in `draw()`.

The caveat from those sims applies here too. The GPU sums neighbors in a race-dependent order, and both systems are chaotic, so two runs are **not** identical frame for frame. A seed gives you a repeatable starting layout, not a pixel-identical video.

<img src="../../Guide/Images/20-ParticleSimulations/FluidAndBlobs.jpg" alt="Two dark panels. Left, a blue particle fluid mid-slosh, a wave climbing the left wall over a churning cavity. Right, nine soft bodies in orange, green, blue, red, purple, and cyan piled at the bottom of a box, squashing flat where they press against each other" width="680">

### Contents

- [Particle fluid](#particle-fluid)
- [Soft bodies](#soft-bodies)
- [Grabbing and splashing](#interaction)

<a id="particle-fluid"></a>
### Particle fluid

The fluid is smoothed-particle hydrodynamics (Müller, Charypar & Gross 2003), which runs in three steps. First, each particle measures how crowded it is. Next, that crowding becomes pressure. Finally, the pressure pushes neighbors apart with equal and opposite forces. A second *near-pressure* term (Clavet, Beaudoin & Poulin 2005) is sharper and always repulsive, so it keeps particles from clumping. It also gives the free surface its tension, so the fluid forms beads and filaments, and drops look like drops. The fluid starts as a block hanging in the box, so the first seconds are a dam break.

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

Three values are fixed when you build the fluid. `count` is the number of particles. `radius` is the interaction range, which sets the fluid's resolution. The same `radius` sets the packing too, through the derived `spacing`. `bounds` is the box, and it defaults to the canvas. Every other property of the liquid is live, so you can change it while the sketch runs:

| Parameter | Meaning | Default |
| --- | --- | --- |
| `gravity` | pull in points/s²; tilt it or set it to zero | `(0, 1500)` |
| `stiffness` | pressure strength (resistance to squeezing); a higher value wants more `substeps` | 240 000 |
| `nearStiffness` | the pressure that prevents clumping and gives surface tension | 150 000 |
| `viscosity` | how much each substep smooths velocity across a neighborhood (0…1); a higher value flows like syrup | 0.12 |
| `bounce` | fraction of normal velocity kept at a wall (0…1) | 0.25 |
| `substeps` | fixed substeps per frame (2…8) | 4 |
| `colorSlow` / `colorFast` / `speedForFastColor` | the tint ramp from slow to fast particles | blue → ice, 1 100 pt/s |
| `restDensity` | target density relative to the seeded packing | 1 |

`drawParticles(fluid)` draws each particle as a disc. With additive blending, the result looks like light through water. For a continuous liquid surface, draw the particles into a layer, blur it, and threshold the blur (`makeRenderTarget(...)` + `.gaussianBlur(radius:)` + `.threshold(value:softness:)`). This is the classic metaball technique.

Example: `Examples/Simulation/ParticleFluid`.

<a id="soft-bodies"></a>
### Soft bodies

Soft bodies use meshless shape matching (Müller, Heidelberger, Teschner & Gross 2005). Each body is a cloud of particles that remembers its rest shape. Every substep, the body finds the rotation that best maps the rest layout onto its current layout. Then it pulls each particle back toward its spot. That one pull is the whole elasticity model, so there are no springs to tune, and the simulation cannot blow up. A fully crushed blob springs back. Bodies collide with each other through inelastic contacts found in the neighbor hash, so they tumble into piles.

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

The blobs start scattered in the upper part of the box, spaced apart from each other. Each blob's size varies around `radius`, and each body gets its own hue. The parameters:

| Parameter | Meaning | Default |
| --- | --- | --- |
| `squish` | how firmly a body holds its shape, 0…1 (low is jelly, high is rubber) | 0.3 |
| `gravity` | pull in points/s² | `(0, 1600)` |
| `bounce` | how much a body bounces off a wall (0…1) | 0.35 |
| `damping` | fraction of velocity kept per second; lower settles piles faster | 0.4 |
| `collisionStrength` | how hard touching bodies push apart, points/s² | 35 000 |
| `substeps` | fixed substeps per frame (2…8) | 4 |

Example: `Examples/Simulation/SoftBodies`.

<a id="interaction"></a>
### Grabbing and splashing

Both systems accept an interaction that lasts one frame. Call the method again on every frame while the mouse is held down:

```swift
if mouseIsPressed { fluid.pull(at: Vector2(mouseX, mouseY)) }        // grab
override func keyPressed() { fluid.push(at: Vector2(mouseX, mouseY)) } // splash
```

`pull(at:strength:radius:)` fades gravity out inside its radius and damps any swirl. The held fluid then hangs at the cursor instead of orbiting it or streaming down. `push` applies the same force outward. In both calls, `strength` is an acceleration in points/s².

### Notes

- **Credits.** Ollin reimplements three models from published papers, all credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md). They are the SPH model (Müller et al. 2003), the near-pressure term (Clavet et al. 2005), and shape matching (Müller et al. 2005).
- **Substeps are the stability budget.** Both systems run fixed substeps against a clamped frame clock. Because of that clamp, a particle never moves more than about half its interaction radius per substep. A hitch in the frame rate therefore cannot blow up the simulation. If you raise `stiffness` far beyond the default, add a couple more substeps.
- **Cost.** Each substep rebuilds the neighbor hash and runs the interaction passes. Cost therefore scales with `count × substeps`, multiplied by the neighbor density. The fluid example's 26 000 particles at 4 substeps run in real time on Apple silicon.
