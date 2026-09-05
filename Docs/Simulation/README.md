#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Simulation</sup>

---

## Simulation

- [`Physics`](./Physics.md) - `import OllinPhysics` gives you a `World` that you step each frame, so motion comes from simulation. It has a soft Verlet side (particles, springs, disk collisions) and a rigid side (bodies, colliders, joints). The rigid side is backed by Box2D.
- [`Physics3D`](./Physics3D.md) - rigid bodies inside the 3D scene. A `World3D`, backed by Jolt, holds `Body3D`s that stack, tumble, and swing. It adds joints, mouse grabbing through the camera, and `withBody` drawing.
- [`Swarm`](./Swarm.md) - the steering behaviors at GPU scale. Separation, alignment, cohesion, seek, flee, arrive, wander, and flow following are each a weight, and they run over the `SpatialHash` neighbor search.
- [`Artificial life`](./ArtificialLife.md) - three emergent-behavior systems on the GPU: `ParticleLife` (attraction/repulsion matrices), `PPS` (one turning rule that grows cells), and `Physarum` (slime-mold trail networks). The first two run over the `SpatialHash` neighbor search.
- [`Evolution`](./Evolution.md) - populations that get better at something. `Evolution` breeds tens of thousands of GPU flights toward a target past obstacles, using tournament selection. `Population` breeds a handful of genomes that a person picks by eye.
- [`Fluids & soft bodies`](./Fluids.md) - GPU particle dynamics in a walled box. `ParticleFluid` is smoothed-particle hydrodynamics that pours, splashes, and settles. `SoftBodies` makes shape-matched jelly blobs that squash and recover. You can grab both with the mouse.
- [`Watercolor`](./Watercolor.md) - wet paint on rough paper. This is the classic three-layer wash simulation, with real pigments (density, staining, granulation) and Kubelka-Munk optical glazing. Edge darkening, dry-brush, backruns, and wet-in-wet flow all come out of the physics.
- [`Articulated & chaotic motion`](./Motion.md) - CPU motion systems that you step each frame. `IKChain` makes inverse-kinematics tentacles and limbs, with two solvers plus a stiffness limit. `DoublePendulum` is the classic example of chaotic motion. `NBody` is quadtree gravity for orbits, galaxies, and collisions.
