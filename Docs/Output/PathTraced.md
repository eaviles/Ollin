#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Path-traced export`</sup>

---

## Path-traced export

Tune the scene live, then render it offline. `--path-traced` switches the still, sequence, and video exports to an offline path tracer. Instead of rasterizing, the tracer follows light paths through the 3D scene. It spends seconds per frame on a look the live pipeline cannot reach inside a frame budget. The sketch itself does not change, so the live window stays the fast raster preview and the flag renders the finished frame.

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced                                # tune live
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 512
swift run --package-path Examples Example-3D-Effects-PathTraced --export-video out.mp4 --seconds 4 --path-traced 256
```

The number is how many light paths each pixel traces. More samples make a smoother image, and the cost grows in proportion to the count. Check the timings before you start a long render. On an M2 at 1080x1080 the example scene takes 83 s at 512 and 157 s at 1024. At 2048 it takes 296 s, and at 4096 it takes 589 s.

If you leave the count off, it follows `--render-quality`: 64 for performance, 256 for default, and 4096 for detail. One still at the detail tier takes about ten minutes on the machine above, so it is the setting you leave running. A *sequence* pays that cost on every frame, which means days rather than hours. The video example names 256 for that reason.

**The detail tier is a final render, so name a count for anything else.**

A still's render reports progress on one line, and a sequence keeps its usual per-frame line. The mode needs a ray-tracing GPU, which every Apple-silicon Mac has. On any other machine the export prints a note and renders with the raster pipeline.

### What the traced frame adds

- **Physically soft shadows.** The tracer samples the panel's real surface. So an area light's shadow is sharp at the contact point and softens with distance.
- **Color bleeding.** A red sphere on a white floor tints the floor red, because bounced light carries color everywhere it lands. It carries that color through any number of bounces.
- **Mirror in mirror.** Every polished surface reflects the scene, including the reflections in other surfaces. Reflections continue to the full path depth (`--pt-depth`, default 8).
- **Real glass.** A `.glass(...)` material refracts the real scene. Light bends through a solid body by its index of refraction, and an `attenuationColor` tints it along the path inside. A thin pane passes the view straight through behind its reflection. Frosted glass roughens both. The shadow follows the same rule, so light reaches the floor *through* a glass object, tinted by its color. It does not stop at an opaque silhouette.
- **Emissive surfaces are lights.** A mesh with an emissive material glows and also lights its surroundings. The tracer samples glowing surfaces directly, the way it samples an area light's panel. So a neon bar throws smooth light with soft shadows, instead of waiting for bounces that happen to find it.
- **Textures travel with the light.** A traced hit reads the mesh's base-color texture at the point it hits. So a textured floor shows its picture in a mirror, keeps it through a glass sphere, and bleeds its colors onto its neighbors.
- **The surface maps travel too.** A normal map bends the traced shading the way it bends the raster shading. Its relief then shows in reflections and in bounce light. A metallic-roughness map varies the finish across the surface, and an occlusion map dims the environment's light in the crevices. An emissive map sets where a glowing mesh emits, including the light it throws on the room. A triplanar texture projects at a traced hit exactly as it does live, and so does its normal map.
- **Copies are part of the scene.** They trace like the meshes they stand for, whichever of the three forms placed them. That covers an [instanced draw](../3D/Instancing.md), a placement buffer a kernel writes, or a retained [`MeshField`](../3D/Instancing.md#meshfield). Each copy carries its own placement, its own tint, and the finish of its own draw. So a field of pebbles casts shadows, shows up in mirrors, and bleeds color the way a hand-placed pebble does. A copy costs a matrix rather than a triangle list, so a large field is cheap to trace.
- **A real lens.** `Camera3D.aperture` (a thin-lens radius in world units) and `Camera3D.focusDistance` give the traced camera depth of field. The live view ignores both and stays pinhole-sharp while you frame the shot. If you leave `focusDistance` at `nil`, the camera focuses on its `target`.

```swift
var cam = Camera3D(eye: Vector3(0, 1.5, 8), target: .zero)
cam.aperture = 0.12          // 0 (the default) is a pinhole
cam.focusDistance = 7.4      // nil focuses on `target`
camera(cam)
```

The scene needs no other change. The tracer reads the same lights, materials, environment, and camera the raster path draws, in the same units. So the traced frame shows the same picture, with the light worked out in full.

**Which lights cast shadows.** The tracer follows the light itself, so it needs no [`castShadows()`](../3D/3D.md#shadows). Every light in the frame casts a shadow, and the raster path's four-caster cap does not apply. A light can still opt out with `castsShadow: false`, and the export honors that. So the fill and rim of a [`lightingPreset(_:)`](../3D/3D.md#lights) rig cast nothing here either. In the raster path that flag also controls cost, because each caster is another pass over the scene. Here it only decides the picture, so the export matches what you framed.

### What stays raster

The tracer covers the solid 3D meshes. Everything else keeps its ordinary pipeline, and it composites with the traced layer by depth, in draw order:

- 2D drawing, before and after the 3D content.
- Wireframe meshes, the ground grid, and matcap meshes. A matcap is the unlit stylized finish, so a glowing prop drawn over an area light keeps its glow and never blocks the light's rays.
- Point clouds, strand fields, and raymarched SDF fields.
- A [`MeshField`](../3D/Instancing.md#meshfield) over its `tracedCopyBudget`. That budget keeps a huge field out of the traced scene, by the same rule the live mirrors use. Its copies still draw here, but they draw rasterized.

The contact sheets, the vector exports (SVG and PDF), and the benchmark always use the raster path.

### What the traced frame does not carry yet

- **Height, detail, and decals stay raster refinements.** A traced hit reads the flat surface at its plain uv. So a height map's parallax relief, the tiled detail pair, and projected decals apply in the raster view only. The occlusion map dims the environment's share at a hit, which is the raster path's own convention. Light carried from surface to surface is real traced transport, blocked by the actual geometry.
- **The layered lobes simplify.** Clearcoat, sheen, iridescence, anisotropy, and subsurface all trace as their metallic-roughness base. Toon, gooch, and the standard finish trace as matte surfaces that keep their raster brightness.
- **A glowing copy is not sampled as a light.** The tracer aims at an emissive *mesh* as a light. An emissive *copy* glows, and its light still reaches the scene. But it arrives only through the paths that happen to find it, so it converges more slowly. The cause is the light table, which weighs each glowing triangle by its area in the world, and a copy's triangles are unplaced. For two of the three placement forms, the CPU never sees where a copy stands at all. So if a shape has to light the room, draw it with a plain `drawMesh` or use an area light.
- **Glass shadows are tinted, not focused.** Light through glass reaches a shadow as a straight, tinted pass. The bent, concentrated bright lines of a real caustic come from the live [`caustics()`](../3D/Caustics.md) feature instead.
- **Volumetric shafts stay raster features.** Height fog and aerial perspective do apply to the traced frame, along the eye's path.

### The grain filter

The error left over in a traced render shows as grain. Sampling it away costs the square, so four times the paths halve the grain. `--denoise` filters the finished render instead, which takes a fraction of a second. The filter is off unless you ask for it, so the plain flag always renders the estimate the tracer arrived at.

The filter reads the surface separately from the light. While it traces, the tracer records the first surface each pixel hit: its own color, the direction it faces, and how far away it is. The light is then divided by that color, filtered, and multiplied back. So a texture, a painted pattern, or a silhouette is never blurred, and only the light on it is.

The filter measures its own strength instead of taking a setting. The tracer records the spread of each pixel's own samples, and the filter blends across a pixel only as far as that spread allows. So a thin render is smoothed hard and a nearly converged one only a little, and there is no per-scene dial to get wrong.

The filter also does not trade the picture for smoothness. The example scene was measured against an 8192-sample render, and the filtered frame sits closer to it than the raw frame at every count tried. At 64 samples the error falls from 17.6 to 9.1, and at 2048 it falls from 5.5 to 3.9. Counted in samples, 64 filtered samples land where about 240 raw ones would, and 2048 filtered ones land where about 4000 would. That saves five minutes of tracing on an M2.

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 64            # the raw estimate
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 64 --denoise  # filtered
```

On a sequence the filter steadies the picture rather than making it flicker. It runs on each frame by itself, but most of what separates two consecutive raw frames is grain, so filtering brings them closer together. On the example scene's moving camera at 48 samples, the difference between one frame and the next falls from 2.85 to 1.21.

Two things to know about it:

- **A real sparkle reads softer.** A rough metal catching a small bright source makes true glitter, and the filter cannot tell that from grain. When the sparkle is the subject, leave the filter off and raise the sample count.
- **One sample has nothing to measure.** `--path-traced 1` has no spread to read, so the filter does not run.

### Determinism and the programmatic surface

Sampling is a pure function of the pixel, the sample index, and the bounce. The filter is a pure function of what the sampling left behind. So the same command renders the same bytes, and a video export cannot flicker. You can also set the mode in code, with the same options the flag carries:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 512, maxDepth: 8, denoise: true)  // the flag's `--denoise`
OllinApp.export(sketch, to: "out.png", frame: 120)
OllinApp.pathTracedExport = nil
```

### See also

- [`Export`](./Export.md) for the full set of export flags this mode builds on.
- [`3D`](../3D/README.md) for the camera, lights, materials, and environments the tracer reads.
