#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Simulation</sup>

---

## Simulation

- [`Physics`](./Physics.md) - `import OllinPhysics` for a `World` you step each frame so motion comes from simulation: a soft Verlet side (particles, springs, disk collisions) and a rigid side (bodies, colliders, joints, backed by Box2D)
- [`Physics3D`](./Physics3D.md) - rigid bodies inside the 3D scene: a `World3D` of stacking, tumbling, swinging `Body3D`s (backed by Jolt) with joints, mouse grabbing through the camera, and `withBody` drawing
- [`Swarm`](./Swarm.md) - the steering behaviors at GPU scale: separation, alignment, cohesion, seek, flee, arrive, wander, and flow following as weights, over the `SpatialHash` neighbor search
- [`Artificial life`](./ArtificialLife.md) - three emergent-behavior systems on the GPU: `ParticleLife` (attraction/repulsion matrices), `PPS` (one turning rule that grows cells), and `Physarum` (slime-mold trail networks), the first two over the `SpatialHash` neighbor search
- [`Fluids & soft bodies`](./Fluids.md) - GPU particle dynamics in a walled box: `ParticleFluid` (smoothed-particle hydrodynamics that pours, splashes, and settles) and `SoftBodies` (shape-matched jelly blobs that squash and recover), both mouse-grabbable
- [`Watercolor`](./Watercolor.md) - wet paint on rough paper: the classic three-layer wash simulation with real pigments (density, staining, granulation) and Kubelka-Munk optical glazing; edge darkening, dry-brush, backruns, and wet-in-wet flow all come out of the physics
- [`Articulated & chaotic motion`](./Motion.md) - CPU motion systems you step each frame: `IKChain` (inverse-kinematics tentacles and limbs, two solvers plus a stiffness limit), `DoublePendulum` (the classic chaos machine), and `NBody` (quadtree gravity for orbits, galaxies, and collisions)
