#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Instanced meshes`</sup>

---

## Instanced meshes

Drawing one mesh is cheap. Drawing the *same* mesh a thousand times with a loop of `drawMesh` calls is not. Every call re-expands the mesh's triangles on the CPU, every frame, once per copy. Instancing removes that loop. `drawMesh(_:instances:)` uploads the mesh once and hands the GPU a list of placements. The GPU puts every copy where it goes. A field of thousands costs one draw call and one small array.

```swift
override func draw() {
    background(.black)
    camera(Camera3D(eye: Vector3(0, 6, 14), target: .zero))
    directionalLight(.white, direction: Vector3(-0.5, -0.85, -0.35))
    castShadows()

    let rock = Mesh.box(width: 0.4, height: 0.4, depth: 0.4)
    var copies: [MeshInstance] = []
    for i in 0 ..< 5_000 {
        let a = Double(i) / 5_000 * .tau * 8
        copies.append(MeshInstance(position: Vector3(cos(a) * Double(i) * 0.002, 0.2, sin(a) * Double(i) * 0.002),
                                   rotation: Vector3(0, a, 0),
                                   scale: 0.5 + noise(Double(i) * 0.1)))
    }
    drawMesh(rock, instances: copies)
}
```

Copies shade exactly like solid meshes. They take the current `fill`, the `material(_:)` finish (physically based included), the scene's lights, image-based lighting, global illumination, and fog. They both cast into and receive the shadow maps. Rebuilding the instance list every frame is normal and cheap. That is how a field moves.

As a reference point, take a 12,400-pillar field, lit and shadowed, at 1080² in a release build on an M2. The per-copy `drawMesh` loop costs ~12.0 ms of CPU per frame just to record. The instanced call records the same field in ~0.23 ms, a 53x drop. The GPU time is the same either way, because the copies still rasterize and shade. That is the point. Instancing removes the CPU loop, not the picture. `Scripts/benchmark.sh instancing` reproduces the measurement on your machine.

### Contents

- [MeshInstance](#meshinstance) - one copy's placement
- [Instances from a compute kernel](#compute) - GPU-resident placements
- [What applies to a copy](#applies)
- [Notes](#notes)

<a id="meshinstance"></a>
### MeshInstance

One copy's placement. It says where the copy sits, how it turns, how it scales, and an optional tint.

```swift
MeshInstance(position: Vector3(2, 0, -1),          // world units (applied first)
             rotation: Vector3(0, .pi / 4, 0),     // Euler radians: x, then y, then z
             scale: Vector3(1, 3, 1),              // per axis (applied last); or one Double
             color: Color(hue: 0.6, saturation: 0.5, brightness: 1))
```

The transform reads like the calls it replaces. The copy is placed as if you had written `translate(position)`, then `rotateX`/`rotateY`/`rotateZ` in that order, then `scale`. Every field has a neutral default, so `MeshInstance(position: p)` is a plain unrotated copy. The `color` multiplies the surface color, which is the current `fill` times the mesh material's base color. `nil` leaves it unchanged.

The whole field still rides the 3D transform stack. A `translate` or `rotate` before the draw moves every copy together, and each instance's transform composes on top.

<a id="compute"></a>
### Instances from a compute kernel

For placements a simulation owns, keep them on the GPU. A kernel writes a `ComputeBuffer<OllinMeshInstance>` each frame, and the copies draw without the positions ever visiting the CPU. GPU particles and point clouds work the same way.

```swift
let placements = ComputeBuffer<OllinMeshInstance>(count: 100_000)

override func draw() {
    camera(Camera3D(eye: Vector3(0, 8, 20), target: .zero))
    compute(swirl, over: placements)             // a kernel moves the copies
    drawMesh(rock, instances: placements)        // count defaults to the buffer's
}
```

`OllinMeshInstance` is the raw GPU struct: a `model` matrix (local to world) and a `color` multiplier. Import `COllinShaders` to name it in a kernel-writing sketch. The matrices are absolute world space. The transform stack is not composed on top, because the kernel owns the placement. The shader derives the normal transform from the matrix itself. So a kernel fills only those two fields, and non-uniform scale still lights correctly.

<a id="applies"></a>
### What applies to a copy

Everything the solid lit path does. That means `fill` and per-vertex mesh colors, every `material(_:)` finish including physically based, lights and `lightingPreset`, shadows received, image-based lighting and the procedural sky, global illumination, fog and aerial perspective, clipping, blend modes, and `depth(at:)` compositing. Instanced copies also cast into the directional/spot shadow map and the point-light shadow cube.

Not yet, by design (each lands with a later slice of the GPU-driven tier):

- **Textures and surface maps.** A textured mesh draws untextured; its base color still tints. Wireframe and matcap fall back to the solid look, with a one-time note.
- **The ray-traced passes.** Ray-traced reflections and ray-traced point shadows do not see the copies (a copy still *receives* reflections of the plain-mesh scene). On a ray-tracing GPU a point light's caster set is traced, so instanced copies only cast for a point light on GPUs using the cube path.
- **The screen-space pre-passes.** Contact shadows, ambient-occlusion normals, and subsurface scattering skip the copies.
- **Motion vectors.** Copies are not `withMotion` movers; temporal anti-aliasing covers them through its depth reprojection instead.

<a id="notes"></a>
### Notes

- A copy field is one batch and never merges with its neighbours, so draw order against other geometry is exactly call order, and the depth buffer sorts the 3D.
- `makeBatch { }` refuses an instanced draw (like plain meshes: a retained copy would silently lose its shadows). Draw the field where the batch is drawn.
- Spatial export records the `[MeshInstance]` form as one mesh per placement, exactly like a loop of `drawMesh` calls. The GPU-buffer form can't be exported (the placements live on the GPU) and says so once.
- SVG export skips meshes entirely, instanced or not: a shaded solid has no vector outline.
- The [`InstancedMesh`](../../Examples/Rendering/InstancedMesh/Sketch.swift) example draws 12,000 wave-riding pillars with a knob that flips between the instanced path and a per-copy `drawMesh` loop. The cost difference shows live in the inspector.
