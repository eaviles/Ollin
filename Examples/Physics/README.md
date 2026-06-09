#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Physics</sup>

---

## Physics

Sketches whose motion comes from simulation. Physics lives in a separate library — add `import OllinPhysics` — built around a Verlet `World` that holds particles and the springs between them, with optional gravity, a container, and disk collisions. Build the world in `setup()`, `step` it each frame, and draw from its particles. See the [Physics reference](../../Docs/Physics.md).

| Example | What it shows |
|---|---|
| [Packing](Packing/Sketch.swift) | 256 discs of mixed sizes drifting weightlessly, bouncing off the walls and each other, each drawn as a slowly spinning crosshair token — the spin reacts to each disc's own speed. The headline for `World.collisions`: a pairwise disk-collision pass with no gravity and `drag = 0` for perpetual motion (`World`, `Particle`, `collisions`). Scene composition after @eaviles's sketch 2025.037; the physics is Ollin's own. |
| [Blobs](Blobs/Sketch.swift) | soft-body blobs built from springs — a hub with spokes out to a ring of rim particles, plus springs around the rim — dropping under a slowly tilting gravity, squishing against the floor and each other, and rendered as smooth filled `drawCurve` outlines. The springs-and-collision showcase (`World`, `Spring`, `connect`, collisions). |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-Packing`.
