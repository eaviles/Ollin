#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Raymarching</sup>

---

## Raymarching

This group covers the 3D SDF combinators: distance fields that merge, sphere-traced beside the meshes.

| [![RaymarchedCastShadow](https://media.ollin.art/examples/3D/Raymarching/RaymarchedCastShadow/still-640.jpg)](RaymarchedCastShadow/) | [![RaymarchedClay](https://media.ollin.art/examples/3D/Raymarching/RaymarchedClay/still-640.jpg)](RaymarchedClay/) | [![RaymarchedDetailing](https://media.ollin.art/examples/3D/Raymarching/RaymarchedDetailing/still-640.jpg)](RaymarchedDetailing/) | [![RaymarchedDistort](https://media.ollin.art/examples/3D/Raymarching/RaymarchedDistort/still-640.jpg)](RaymarchedDistort/) |
|---|---|---|---|
| [RaymarchedCastShadow](RaymarchedCastShadow/) | [RaymarchedClay](RaymarchedClay/) | [RaymarchedDetailing](RaymarchedDetailing/) | [RaymarchedDistort](RaymarchedDistort/) |
| [![RaymarchedDomain](https://media.ollin.art/examples/3D/Raymarching/RaymarchedDomain/still-640.jpg)](RaymarchedDomain/) | [![RaymarchedEnvironment](https://media.ollin.art/examples/3D/Raymarching/RaymarchedEnvironment/still-640.jpg)](RaymarchedEnvironment/) | [![RaymarchedFractals](https://media.ollin.art/examples/3D/Raymarching/RaymarchedFractals/still-640.jpg)](RaymarchedFractals/) | [![RaymarchedGradient](https://media.ollin.art/examples/3D/Raymarching/RaymarchedGradient/still-640.jpg)](RaymarchedGradient/) |
| [RaymarchedDomain](RaymarchedDomain/) | [RaymarchedEnvironment](RaymarchedEnvironment/) | [RaymarchedFractals](RaymarchedFractals/) | [RaymarchedGradient](RaymarchedGradient/) |
| [![RaymarchedJoinery](https://media.ollin.art/examples/3D/Raymarching/RaymarchedJoinery/still-640.jpg)](RaymarchedJoinery/) | [![RaymarchedPlane](https://media.ollin.art/examples/3D/Raymarching/RaymarchedPlane/still-640.jpg)](RaymarchedPlane/) | [![RaymarchedRadial](https://media.ollin.art/examples/3D/Raymarching/RaymarchedRadial/still-640.jpg)](RaymarchedRadial/) | [![RaymarchedReceiveShadow](https://media.ollin.art/examples/3D/Raymarching/RaymarchedReceiveShadow/still-640.jpg)](RaymarchedReceiveShadow/) |
| [RaymarchedJoinery](RaymarchedJoinery/) | [RaymarchedPlane](RaymarchedPlane/) | [RaymarchedRadial](RaymarchedRadial/) | [RaymarchedReceiveShadow](RaymarchedReceiveShadow/) |
| [![RaymarchedSDF](https://media.ollin.art/examples/3D/Raymarching/RaymarchedSDF/still-640.jpg)](RaymarchedSDF/) | [![RaymarchedSculpt](https://media.ollin.art/examples/3D/Raymarching/RaymarchedSculpt/still-640.jpg)](RaymarchedSculpt/) | [![RaymarchedShadow](https://media.ollin.art/examples/3D/Raymarching/RaymarchedShadow/still-640.jpg)](RaymarchedShadow/) | [![RaymarchedShapes](https://media.ollin.art/examples/3D/Raymarching/RaymarchedShapes/still-640.jpg)](RaymarchedShapes/) |
| [RaymarchedSDF](RaymarchedSDF/) | [RaymarchedSculpt](RaymarchedSculpt/) | [RaymarchedShadow](RaymarchedShadow/) | [RaymarchedShapes](RaymarchedShapes/) |
| [![RaymarchedStretch](https://media.ollin.art/examples/3D/Raymarching/RaymarchedStretch/still-640.jpg)](RaymarchedStretch/) |  |  |  |
| [RaymarchedStretch](RaymarchedStretch/) |  |  |  |

| Sketch | What it shows |
| --- | --- |
| [RaymarchedSDF](RaymarchedSDF/) | The 3D SDF combinators sphere-traced as one surface. Spheres melt together by smooth-union, and their colors blend through the seam. One sphere orbits, and a bite is carved out by subtraction. |
| [RaymarchedShapes](RaymarchedShapes/) | The raymarched primitive catalog beyond the first four (rounded box, cylinder, cone, octahedron, ellipsoid). Each is a field traced into the shared depth buffer. |
| [RaymarchedSculpt](RaymarchedSculpt/) | The scoped block form. Inside `smoothUnion(k:) { … }`, bare mesh calls (`drawSphere`, `drawCapsule`, `drawCone`, …) are captured as fields and melt into one traced surface. |
| [RaymarchedDomain](RaymarchedDomain/) | Domain operators. `repeated(spacing:count:)` tiles a unit cell into a finite lattice, and `mirrored(x:y:z:)` folds one built lobe into a symmetric form. The whole thing stays one surface. |
| [RaymarchedRadial](RaymarchedRadial/) | Polar repetition. `repeatedRadially` folds one wedge into an evenly spaced rosette around an axis, with no draw cost per copy. |
| [RaymarchedPlane](RaymarchedPlane/) | The infinite plane leaf. An unbounded ground is merged into the field and marched to the far plane, and it catches the shapes' soft shadows. |
| [RaymarchedStretch](RaymarchedStretch/) | Per-axis sizing. `stretched` is exact elongation, so a sphere becomes a capsule. Beside it, `scaled(x:y:z:)` is a true non-uniform scale, marched conservatively. |
| [RaymarchedGradient](RaymarchedGradient/) | Gradient paint on a merged field. A gradient `fill` paints the whole sphere-traced surface, sampled at each hit's projected screen position. |
| [RaymarchedEnvironment](RaymarchedEnvironment/) | Raymarched fields lit by an environment. They get the same image-based lighting and traced reflections the meshes get. |
| [RaymarchedShadow](RaymarchedShadow/) | A field shadowing itself under `castShadows()`. A soft penumbra is marched toward the light and evaluated as part of the surface shading. |
| [RaymarchedCastShadow](RaymarchedCastShadow/) | A field casting a shadow onto meshes under a directional or point light (any key switches). Either the field renders into the 2D shadow map, or the lit mesh fragments march the field inline toward the light. |
| [RaymarchedReceiveShadow](RaymarchedReceiveShadow/) | A field receiving a mesh's cast shadow under a directional or point light (any key switches). The traced surface samples the 2D map, the shadow cube, or the acceleration structure at its hit. |
| [RaymarchedClay](RaymarchedClay/) | The sculpt block. The combine mode and melt amount are held as state, so a form reads top to bottom like working clay. |
| [RaymarchedJoinery](RaymarchedJoinery/) | Machined joints and hardware: chamfered and stepped unions, a hanging chain, a capped-torus hook. |
| [RaymarchedDetailing](RaymarchedDetailing/) | The detailing ops: fluted seams, engraved rings, grooved bands, beading, and a pipe bead left hanging where two bodies crossed. |
| [RaymarchedDistort](RaymarchedDistort/) | The sculpting distortions: twisted, bent, displaced, and roughened, one plinth each. |
| [RaymarchedFractals](RaymarchedFractals/) | The fractal leaves: a Mandelbulb, a Menger sponge, and a Mandelbox. Each is a distance estimate that the same sphere tracer draws. A menu picks one, and the bulb's power, the sponge's depth, and the box's scale are each a parameter of their own. |

Run one with `swift run Example-3D-Raymarching-<Name>`, for example `swift run Example-3D-Raymarching-RaymarchedSDF`.
