#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Physics</sup>

---

## Physics

Sketches whose motion comes from simulation. Physics lives in a separate library (add `import OllinPhysics`) built around one `World` with two sides: a **soft** Verlet side of particles and the springs between them, and a **rigid** side of bodies, colliders, and joints, both sharing the world's gravity, container, bounce, and drag. Build the world in `setup()`, `step` it each frame, and draw from its particles and bodies. See the [Physics reference](../../Docs/Simulation/Physics.md). (These are the 2D world; for rigid bodies inside the 3D scene, see the [3D physics examples](../3D/README.md#physics).) The 3D group keeps the same scenarios under their own names ([`3D/Physics/Stack`](../3D/Physics/Stack/), [`Tumble`](../3D/Physics/Tumble/), and [`Chain`](../3D/Physics/Chain/)) on the 3D engine; here the first two are folded into the one `RigidBodies` sketch below.

| Example | What it shows |
|---|---|
| [Packing](Packing/Sketch.swift) | 256 discs of mixed sizes drifting weightlessly, bouncing off the walls and each other, each drawn as a slowly spinning crosshair token; the spin reacts to each disc's own speed. The headline for `World.particlesCollide`: a pairwise disk-collision pass with no gravity and `drag = 0` for perpetual motion (`World`, `Particle`, `collisions`). Scene composition after @eaviles's sketch 2025.037; the physics is Ollin's own. |
| [Blobs](Blobs/Sketch.swift) | soft-body blobs built from springs (a hub with spokes out to a ring of rim particles, plus springs around the rim) dropping under a slowly tilting gravity, squishing against the floor and each other, and rendered as smooth filled `drawCurve` outlines. The springs-and-collision showcase (`World`, `Spring`, `connect`, collisions). |
| [RigidBodies](RigidBodies/Sketch.swift) | a pyramid of rigid crates that stacks, leans, and topples, beside a rain of assorted shapes (boxes, disks, capsules, and random convex polygons) piling up against the floor; click fires a heavy ball that knocks the stack into the heap, space clears and rebuilds. The rigid-body showcase: orientation and resting contact the particle side can't do, every form one `addBody` with a different `Collider`, each drawn straight from its `position`/`angle` (`addBody`, `Collider`, `Body`). |
| [Chain](Chain/Sketch.swift) | hanging chains of capsule links hinged by free-swinging revolute joints, ending in heavy balls; click a link to grab and fling it (a cursor-drag mouse joint), click again to let go, space resets. The joints showcase (`connect`, `JointKind.revolute`, `grab`). |
| [Joints](Joints/Sketch.swift) | all four joint kinds side by side, one labeled rig each, hung from static anchors: a revolute pendulum, a distance ball on a springy rope, a weld tee that swings as one rigid piece, and a prismatic slider that can only travel its rail. Click a piece to grab and fling it, space resets (`JointKind`, `Body.kind = .static`). |
| [Forces](Forces/Sketch.swift) | the force API in one windy yard: a gust leans on every loose shape through `applyForce` so leaves skitter where crates shuffle, a click kicks the nearest shape with `applyImpulse`, a paddle spun by `applyTorque` bats what drifts through, and a kinematic sweeper plows the floor unstoppably. A pinned lattice tints its springs by `Spring.strain`, and `World.pixelsPerMeter` rides a knob (`applyForce`, `applyImpulse`, `applyTorque`, `Spring.pin()`). |

Run one with `swift run Example-Physics-<Name>`, e.g. `swift run Example-Physics-Packing`.
