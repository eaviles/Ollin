#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Simulation</sup>

---

## Simulation

- [`Physics`](./Physics.md) - `import OllinPhysics` for a `World` you step each frame so motion comes from simulation: a soft Verlet side (particles, springs, disk collisions) and a rigid side (bodies, colliders, joints, backed by Box2D)
- [`Artificial life`](./ArtificialLife.md) - three emergent-behavior systems on the GPU: `ParticleLife` (attraction/repulsion matrices), `PPS` (one turning rule that grows cells), and `Physarum` (slime-mold trail networks), the first two over the `SpatialHash` neighbor search
- [`Fluids & soft bodies`](./Fluids.md) - GPU particle dynamics in a walled box: `ParticleFluid` (smoothed-particle hydrodynamics that pours, splashes, and settles) and `SoftBodies` (shape-matched jelly blobs that squash and recover), both mouse-grabbable
