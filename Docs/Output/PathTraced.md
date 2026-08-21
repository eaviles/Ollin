#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Path-traced export`</sup>

---

## Path-traced export

Tune the scene live, then render it offline. `--path-traced` switches the still, sequence, and video exports to an offline path tracer. Instead of rasterizing, it follows light paths through the 3D scene, spending seconds per frame on a look the live pipeline cannot reach in a frame budget. The sketch is unchanged. The live window stays the fast raster viewfinder, and the flag is the film back.

```sh
swift run Example-3D-Effects-PathTraced                                # tune live
swift run Example-3D-Effects-PathTraced --export out.png --path-traced 512
swift run Example-3D-Effects-PathTraced --export-video out.mp4 --seconds 4 --path-traced 256
```

The number is how many light paths each pixel traces. More samples make a smoother image, and the cost is linear. Know it before you wait for it. On an M2 at 1080x1080 the example scene takes 83 s at 512, 157 s at 1024, 296 s at 2048, and 589 s at 4096.

Left off, the count follows `--render-quality`: 64, 256, or 4096 for performance, default, and detail. **The detail tier is a final render, so name a count for anything else.** It is the leave-it-running setting, about ten minutes for one still on the machine above. A *sequence* multiplies that by every frame, which is days rather than hours. The video example below names 256 for that reason. A progress line reports a still's render, and a sequence keeps its usual per-frame line. It needs a ray-tracing GPU, which every Apple-silicon Mac has. Elsewhere the export prints a note and renders the raster pipeline.

### What the traced frame adds

- **Physically soft shadows.** An area light's shadow sharpens at contact and melts with distance, because the tracer samples the panel's real surface.
- **Color bleeding.** A red sphere on a white floor stains the floor red. Bounce light carries color everywhere it lands, at any number of bounces.
- **Mirror in mirror.** Every polished surface reflects the scene, including other reflections, to the full path depth (`--pt-depth`, default 8).
- **Real glass.** A `.glass(...)` material refracts the actual scene: light bends through a solid body by its index of refraction, an `attenuationColor` tints it along the interior path, and a thin pane passes the view straight through behind its reflection. Frosted glass roughens both. And the shadow follows: light reaches the floor *through* a glass object, tinted by its color, instead of stopping at an opaque silhouette.
- **Emissive surfaces are lights.** A mesh with an emissive material does not just glow, it lights its surroundings: the tracer samples glowing surfaces directly, the way it samples an area light's panel, so a neon bar throws smooth, soft-shadowed light instead of waiting for lucky bounces.
- **Textures travel with the light.** A traced hit reads the mesh's base-color texture at the hit point, so a textured floor shows its picture in a mirror, keeps it through a glass sphere, and bleeds its colors onto neighbors.
- **The surface maps travel too.** A normal map bends the traced shading the way it bends the raster's, so its relief shows in reflections and in bounce light. A metallic-roughness map varies the finish across the surface, and an occlusion map dims the environment's light in its crevices. An emissive map shapes where a glowing mesh emits, including the light it throws on the room. A triplanar texture (and its normal map) projects at a traced hit exactly as it does live.
- **A real lens.** `Camera3D.aperture` (a thin-lens radius, world units) and `Camera3D.focusDistance` give the traced camera depth of field. The live view ignores both and stays pinhole-sharp while you frame. `focusDistance` left `nil` focuses on the camera's `target`.

```swift
var cam = Camera3D(eye: Vector3(0, 1.5, 8), target: .zero)
cam.aperture = 0.12          // 0 (the default) is a pinhole
cam.focusDistance = 7.4      // nil focuses on `target`
camera(cam)
```

The scene needs no other change: the same lights, materials, environment, and camera the raster path draws are what the tracer reads, in the same units, so the traced frame reads as the same picture with the light finished.

**Which lights throw.** The tracer follows the light itself, so it needs no [`castShadows()`](../3D/3D.md#shadows). Every light in the frame throws, and the raster's four-caster cap does not apply. A light still declines with `castsShadow: false`, and the export honors it, so the fill and rim of a [`lightingPreset(_:)`](../3D/3D.md#lights) rig throw nothing here either. In the raster that flag is a cost dial too, since each caster is a pass over the scene. Here it only decides the picture, and the picture it decides is the one you framed.

### What stays raster

The trace covers the solid 3D meshes. Everything else keeps its ordinary pipeline and composites with the traced layer by depth, in draw order:

- 2D drawing, before and after the 3D content.
- Wireframe meshes, the ground grid, and matcap meshes. A matcap is the unlit stylized finish, so a glowing prop drawn over an area light keeps its glow and never blocks the light's rays.
- Point clouds, strand fields, raymarched SDF fields, instanced meshes, and mesh fields.

The contact sheets, the vector exports (SVG and PDF), and the benchmark keep the raster path outright.

### What the traced frame does not carry yet

- **Height, detail, and decals stay raster refinements.** A height map's parallax relief, the tiled detail pair, and projected decals apply in the raster view only; a traced hit reads the flat surface at its plain uv. The occlusion map dims the environment's share at a hit (the raster's own convention); light carried surface to surface is real traced transport, occluded by the actual geometry.
- **The layered lobes simplify.** Clearcoat, sheen, iridescence, anisotropy, and subsurface trace as their metallic-roughness base. Toon, gooch, and the standard finish trace as matte surfaces with their raster brightness.
- **Glass shadows are tinted, not focused.** Light through glass reaches a shadow as a straight, tinted pass; the bent, bunched-up bright lines of a real caustic stay with the live [`caustics()`](../3D/Caustics.md) feature.
- **Volumetric shafts stay raster features.** Height fog and aerial perspective do apply to the traced frame along the eye's path.

### The grain filter

What is left of the error in a traced render shows as grain. Sampling it away costs the square: four times the paths halve it. `--denoise` filters the finished render instead, for a fraction of a second of work. It is off unless you ask for it, so the plain flag always renders the estimate the tracer arrived at.

The filter is told about the surface separately from the light. While it traces, the tracer records the first surface each pixel hit: its own color, the direction it faces, and how far away it is. The light is then divided by that color, filtered, and multiplied back. So a texture, a painted pattern, or a silhouette is never blurred. Only the light on it is.

Its strength is measured rather than set. The tracer records the spread of each pixel's own samples, and the filter blends across a pixel only as far as that spread allows. A thin render is smoothed hard, a nearly converged one only a little, and there is no dial to get wrong per scene.

It also does not trade the picture for smoothness. The example scene was measured against an 8192-sample render. The filtered frame sits closer to it than the raw frame at every count tried. At 64 samples the error falls from 17.6 to 9.1, and at 2048 from 5.5 to 3.9. Read as samples, 64 filtered ones land where about 240 raw ones would. At 2048 they land where about 4000 would. That saves five minutes of tracing on an M2.

```sh
swift run Example-3D-Effects-PathTraced --export out.png --path-traced 64            # the raw estimate
swift run Example-3D-Effects-PathTraced --export out.png --path-traced 64 --denoise  # filtered
```

On a sequence it steadies the picture rather than shaking it. The filter runs on each frame by itself. But most of what separates two consecutive raw frames is grain, so filtering brings them closer together. On the example scene's moving camera at 48 samples, the difference between one frame and the next falls from 2.85 to 1.21.

Two things to know about it:

- **A real sparkle reads softer.** A rough metal catching a small bright source produces true glitter, and the filter cannot tell that from grain. Where the sparkle is the subject, leave the filter off and raise the sample count.
- **One sample has nothing to measure.** `--path-traced 1` has no spread to read, so the filter does not run.

### Determinism and the programmatic surface

Sampling is a pure function of pixel, sample index, and bounce. The filter is a pure function of what the sampling left behind. So the same command renders the same bytes, and a video export cannot flicker. Set the mode in code with the same options the flag carries:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 512, maxDepth: 8, denoise: true)  // the flag's `--denoise`
OllinApp.export(sketch, to: "out.png", frame: 120)
OllinApp.pathTracedExport = nil
```

### See also

- [`Export`](./Export.md) for the full export flag surface the mode rides on.
- [`3D`](../3D/README.md) for the camera, lights, materials, and environments the tracer reads.
