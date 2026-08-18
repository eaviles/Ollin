#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Path-traced export`</sup>

---

## Path-traced export

Tune the scene live, then render it offline. `--path-traced` switches the still, sequence, and video exports to an offline path tracer. Instead of rasterizing, it follows light paths through the 3D scene, spending seconds per frame on a look the live pipeline cannot reach in a frame budget. The sketch is unchanged. The live window stays the fast raster viewfinder, and the flag is the film back.

```sh
swift run Example-3D-Effects-PathTraced                                # tune live
swift run Example-3D-Effects-PathTraced --export out.png --path-traced 512
swift run Example-3D-Effects-PathTraced --export-video out.mp4 --seconds 4 --path-traced 256
```

The number is how many light paths each pixel traces. More samples make a smoother image and take linearly longer. Left off, the count follows `--render-quality` (64, 256, or 512 for performance, default, and detail). A progress line reports a still's render, and a sequence keeps its usual per-frame line. It needs a ray-tracing GPU, which every Apple-silicon Mac has. Elsewhere the export prints a note and renders the raster pipeline.

### What the traced frame adds

- **Physically soft shadows.** An area light's shadow sharpens at contact and melts with distance, because the tracer samples the panel's real surface.
- **Color bleeding.** A red sphere on a white floor stains the floor red. Bounce light carries color everywhere it lands, at any number of bounces.
- **Mirror in mirror.** Every polished surface reflects the scene, including other reflections, to the full path depth (`--pt-depth`, default 8).
- **Emissive surfaces glow onto the scene.** A mesh with an emissive material lights its surroundings through the same bounces.
- **A real lens.** `Camera3D.aperture` (a thin-lens radius, world units) and `Camera3D.focusDistance` give the traced camera depth of field. The live view ignores both and stays pinhole-sharp while you frame. `focusDistance` left `nil` focuses on the camera's `target`.

```swift
var cam = Camera3D(eye: Vector3(0, 1.5, 8), target: .zero)
cam.aperture = 0.12          // 0 (the default) is a pinhole
cam.focusDistance = 7.4      // nil focuses on `target`
camera(cam)
```

The scene needs no other change: the same lights, materials, environment, and camera the raster path draws are what the tracer reads, in the same units, so the traced frame reads as the same picture with the light finished.

### What stays raster

The trace covers the solid 3D meshes. Everything else keeps its ordinary pipeline and composites with the traced layer by depth, in draw order:

- 2D drawing, before and after the 3D content.
- Wireframe meshes, the ground grid, and matcap meshes. A matcap is the unlit stylized finish, so a glowing prop drawn over an area light keeps its glow and never blocks the light's rays.
- Point clouds, strand fields, raymarched SDF fields, instanced meshes, and mesh fields.

The contact sheets, the vector exports (SVG and PDF), and the benchmark keep the raster path outright.

### What the traced frame does not carry yet

- **Transmission renders opaque.** A glass material traces as its opaque dielectric base for now. The raster pipeline remains the way to show glass.
- **Textures stay on the raster side.** A traced hit reads the mesh's baked vertex color and material factors, not its image maps. A heavily textured mesh reads flat in reflections and bounces.
- **The layered lobes simplify.** Clearcoat, sheen, iridescence, anisotropy, and subsurface trace as their metallic-roughness base. Toon, gooch, and the standard finish trace as matte surfaces with their raster brightness.
- **Volumetric shafts and caustics stay raster features.** Height fog and aerial perspective do apply to the traced frame along the eye's path.

### Determinism and the programmatic surface

Sampling is a pure function of pixel, sample index, and bounce, so the same command renders the same bytes, and a video export cannot flicker. Set the mode in code with the same options the flag carries:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 512, maxDepth: 8)
OllinApp.export(sketch, to: "out.png", frame: 120)
OllinApp.pathTracedExport = nil
```

### See also

- [`Export`](./Export.md) for the full export flag surface the mode rides on.
- [`3D`](../3D/README.md) for the camera, lights, materials, and environments the tracer reads.
