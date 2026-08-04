#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Physics</sup>

---

## Physics

Sketches whose motion comes from simulation. Physics lives in a separate library (add `import OllinPhysics`) built around one `World` with two sides: a **soft** Verlet side of particles and the springs between them, and a **rigid** side of bodies, colliders, and joints, both sharing the world's gravity, container, bounce, and drag. Build the world in `setup()`, `step` it each frame, and draw from its particles and bodies. See the [Physics reference](../../Docs/Simulation/Physics.md). (These are the 2D world; for rigid bodies inside the 3D scene, see the [3D physics examples](../3D/README.md#physics).)

| Example | What it shows |
|---|---|
| [Packing](Packing/Sketch.swift) | 256 discs of mixed sizes drifting weightlessly, bouncing off the walls and each other, each drawn as a slowly spinning crosshair token; the spin reacts to each disc's own speed. The headline for `World.collisions`: a pairwise disk-collision pass with no gravity and `drag = 0` for perpetual motion (`World`, `Particle`, `collisions`). Scene composition after @eaviles's sketch 2025.037; the physics is Ollin's own. |
| [Blobs](Blobs/Sketch.swift) | soft-body blobs built from springs (a hub with spokes out to a ring of rim particles, plus springs around the rim) dropping under a slowly tilting gravity, squishing against the floor and each other, and rendered as smooth filled `drawCurve` outlines. The springs-and-collision showcase (`World`, `Spring`, `connect`, collisions). |
| [Stack](Stack/Sketch.swift) | a pyramid of rigid boxes that stacks, leans, and topples; click to fire a heavy ball at it, space rebuilds. The rigid-body showcase: orientation and resting contact the particle side can't do, every box drawn straight from its `position`/`angle` (`addBody`, `Collider.box`, `Body`). |
| [Tumble](Tumble/Sketch.swift) | a heap of assorted rigid shapes (boxes, disks, capsules, and random convex polygons) raining down and piling up against the floor; click dumps a burst at the cursor, space clears. The mixed-collider showcase: every form is one `addBody` with a different `Collider`. |
| [Chain](Chain/Sketch.swift) | hanging chains of capsule links hinged by free-swinging revolute joints, ending in heavy balls; click a link to grab and fling it (a cursor-drag mouse joint), click again to let go, space resets. The joints showcase (`connect`, `JointKind.revolute`, `grab`). |

Run one with `swift run Example-Physics-<Name>`, e.g. `swift run Example-Physics-Packing`.
