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
- [A field that culls itself](#meshfield) - `MeshField`, a retained world the GPU trims per copy
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

<a id="meshfield"></a>
### A field that culls itself

`drawMesh(_:instances:)` re-records its placement list every frame, which is what makes a field wave. For a *world*, most of which never changes and most of which the camera can't see, a **`MeshField`** goes further. Place copies of any number of meshes into it once; draw it with one call forever. Each frame a compute pass tests every copy against the camera and writes the surviving draws itself, so copies behind the camera or beyond the far plane cost (almost) nothing, and the CPU never touches a copy again.

```swift
let field = MeshField()

override func setup() {
    field.place(stone, at: stoneSpots)      // [MeshInstance], like drawMesh
    field.place(pine, at: pineSpots)
    field.place(boulder, at: boulderSpots)
}

override func draw() {
    camera(Camera3D(eye: eye, target: ahead, far: 110))
    drawMeshField(field)                    // one call for the whole world
}
```

A field is retained, like a `Batch`: build it in `setup()` and hold it. Its surface colors bake when a mesh is placed (the mesh material's base color times its per-vertex colors, tinted per copy by `MeshInstance.color`); the draw-time `fill` does not tint a field. The transform stack still moves the whole field as a unit, the current `material(_:)` finish shades it, and its copies cast into the shadow maps *uncculled*, so a tree behind the camera still throws its shadow into view. Draw a field once per frame; a second draw is skipped with a note.

Culling is on by default and must never change the picture, only the work: a culled copy was outside the view by definition. `field.cullingEnabled = false` draws every copy regardless, which is the honest way to feel the difference (the `MeshField` example wires it to a knob). The mechanics, for the curious: a GPU pass tests each copy's bounding sphere against the view frustum, compacts the survivors per mesh, and writes one indirect draw per mesh kind, so the CPU issues one draw per *kind of thing*, never per copy. The shadow pass gets the same treatment against the light's own frustum, so a caster behind the camera still shadows the view while everything outside the map is skipped.

As a reference point, the example's 240,000-copy plain, lit, shadowed, and fogged at 1080² on an M2: 18.5 ms of GPU per frame with culling on, 50.8 ms with it off, a 2.7x win, and the CPU record cost of the one `drawMeshField` call rounds to zero. `Scripts/benchmark.sh field` reproduces it on your machine.

<a id="applies"></a>
### What applies to a copy

Everything the solid lit path does. That means `fill` and per-vertex mesh colors, every `material(_:)` finish including physically based, lights and `lightingPreset`, shadows received, image-based lighting and the procedural sky, global illumination, fog and aerial perspective, clipping, blend modes, and `depth(at:)` compositing. Instanced copies also cast into the directional/spot shadow map and the point-light shadow cube.

Copies drawn from an `[MeshInstance]` list also reach the ray-traced passes. They show in a ray-traced reflection. They cast a ray-traced point or area shadow, and they bounce light in global illumination. Each copy carries its own placement and its own `color` there. A copy costs a matrix rather than a triangle list, so a field of them is cheap to trace.

Not yet, by design (each lands with a later slice of the GPU-driven tier):

- **Textures and surface maps.** A textured mesh draws untextured; its base color still tints. Wireframe and matcap fall back to the solid look, with a one-time note.
- **The ray-traced passes, for the two GPU-held forms.** The compute-buffer form and `MeshField` stay out of the traced scene. One keeps its placements on the GPU. The other holds far too many to hand over one at a time each frame. Their copies still *receive* reflections and bounce light. They still cast into the shadow map and the cube. On a ray-tracing GPU a point light's caster set is traced, so those two forms cast no point shadow there.
- **The path-traced export.** `--path-traced` takes the plain meshes alone, because its material tables are per geometry and a copy carries none of its own.
- **The screen-space pre-passes.** Contact shadows, ambient-occlusion normals, and subsurface scattering skip the copies.
- **Motion vectors.** Copies are not `withMotion` movers; temporal anti-aliasing covers them through its depth reprojection instead.

<a id="notes"></a>
### Notes

- A copy field is one batch and never merges with its neighbors, so draw order against other geometry is exactly call order, and the depth buffer sorts the 3D.
- `makeBatch { }` refuses an instanced draw (like plain meshes: a retained copy would silently lose its shadows). Draw the field where the batch is drawn.
- Spatial export records the `[MeshInstance]` form as one mesh per placement, exactly like a loop of `drawMesh` calls. The GPU-buffer form can't be exported (the placements live on the GPU) and says so once.
- SVG export skips meshes entirely, instanced or not: a shaded solid has no vector outline.
- A `MeshField` exports spatially like a loop of `drawMesh` calls (its placements stay on the CPU for exactly this). The not-yet list above applies to fields too, and under a point light on a ray-tracing GPU a field's copies do not cast (the caster set is traced there).
- The [`InstancedMesh`](../../Examples/Rendering/InstancedMesh/Sketch.swift) example draws 12,000 wave-riding pillars with a knob that flips between the instanced path and a per-copy `drawMesh` loop. The cost difference shows live in the inspector.
- The [`MeshField`](../../Examples/Rendering/MeshField/Sketch.swift) example scatters 240,000 solids across a foggy plain and flies through them, with a knob that turns the culling off. The picture stays the same; the frame rate does not.
