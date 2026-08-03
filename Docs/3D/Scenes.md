#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Scenes`</sup>

---

## Scenes (structure-preserving import)

Bring a whole composed scene into a sketch, not just its geometry. Where [`loadMesh`](./3D.md#meshes-from-file) merges a file into one `Mesh` (the right thing for a prop you place yourself), **`loadScene`** keeps the file's *structure*: a tree of **named nodes**, each with its authored transform and an optional mesh, plus the **cameras** and **lights** the scene was authored with. Compose a layout in a 3D design tool, export glTF, and open the sketch on the exact framing and lighting you built there, while still reaching any node by name to drive it from `draw()`.

```swift
final class Stage: Sketch {
    var stage: Scene!

    override func setup() {
        stage = loadScene("Stage.gltf")
    }

    override func draw() {
        background(Color(hex: 0x0E1117))
        camera(stage.camera ?? .orbiting(radius: 6))   // the authored view
        for l in stage.lights { light(l) }             // the authored lighting
        stage["sculpture"]?.rotate(deltaTime, axis: .unitY)
        drawScene(stage)
    }
}
```

Everything decomposes into the core types you already use: `scene.camera` is a [`Camera3D`](./3D.md#the-camera) you pass to `camera(_:)`, `scene.lights` are [`Light`](./3D.md#lights)s you apply with `light(_:)`, and each node's `mesh` is an ordinary `Mesh`. `drawScene` is just a walk that composes each node's transform onto the 3D transform stack and calls `drawMesh`, so materials, shadows, reflections, and every other mesh feature apply unchanged, and `translate`/`rotate`/`scale` before `drawScene` move the whole scene.

### Contents

- [Loading](#loading) - `loadScene`, the formats, the mesh-only fallback
- [Drawing](#drawing) - `drawScene`, fill and materials
- [Reaching nodes](#nodes) - `node(_:)`, the subscript, animating a node
- [Playing authored animations](#animation) - `apply(_:at:)`, looping, one-shots
- [Skins and morph targets](#deforming) - bending meshes, blend shapes, `weights`
- [The authored camera](#cameras) - what carries over, and how
- [The authored lights](#lights) - the three punctual kinds, intensity normalization
- [Building a scene in code](#in-code) - `Scene` and `SceneNode` are plain values
- [Notes](#notes) - limitations and the fine print

<a id="loading"></a>
### Loading

```swift
let scene = loadScene("Stage.gltf")                            // path (Sketch sugar)
let scene = Scene(contentsOf: url)                             // URL
let scene = Scene(resource: "scene", extension: "gltf", in: .module)   // bundled
```

Structure comes from **`.gltf` / `.glb`** files: the node graph with names and per-node transforms, cameras (part of the core glTF spec), and lights (the standard punctual-lights extension, which most exporters write). Any other format `loadMesh` reads (`.obj`, `.usdz`, `.stl`, `.ply`, …) has no scene graph Ollin preserves, so it loads honestly as a **single-node scene**, the merged mesh on one node named after the file, with no cameras or lights. Every loader returns `nil` if the file can't be read or holds no geometry.

A multi-scene glTF loads its default scene. Exporting from Blender: the glTF exporter includes cameras and punctual lights when their export options are ticked (they're off by default in some versions).

<a id="drawing"></a>
### Drawing

`drawScene(_:)` draws every node's mesh at its authored place, composing transforms down the tree. Each node's mesh carries the file's **base-color material** (color + texture), which the current `fill` tints, so keep the default white fill to show the authored colors true, or set a fill to tint the whole scene. All the mesh machinery applies as if you'd called `drawMesh` yourself: lights and materials, `castShadows()`, ray-traced reflections, an `environment(_:)`, wireframe mode.

Nodes draw in document order, depth-first. A node with no mesh (a grouping node, a camera or light carrier) contributes only its transform.

<a id="nodes"></a>
### Reaching nodes

```swift
let lamp = stage.node("lamp")                       // a copy (nodes are values)
stage["lamp"]?.position += Vector3(0, 0.1, 0)       // mutate in place
stage["sculpture"]?.rotate(0.02, axis: .unitY)      // spin about its own pivot
stage["pedestal"]?.scale(by: 1.01)
```

`node(_:)` finds the first node with a name, searching depth-first, and returns a **copy**, `Scene` and `SceneNode` are value types. To change the scene you draw, mutate through the **subscript**, which writes back in place. `position` reads and writes the node's local translation; `rotate(_:axis:)` and `scale(by:)` compose *inside* the authored transform, so a node turns and grows about its own pivot, wherever its parents put it. Children ride along, that's what the tree is for.

`scene.bounds` is the world-space bounding box over every node's mesh with all transforms composed, handy for framing a camera around an arbitrary file.

<a id="animation"></a>
### Playing authored animations

A scene carries the keyframe animations its file was authored with, in `scene.animations` (find one by name with `scene.animation(_:)`). Each is a `SceneAnimation`: a name, a `duration` in seconds, and tracks that pose nodes by translation, rotation, and scale. **`apply(_:at:)`** samples one at a time of your choosing:

```swift
if let spin = stage.animation("spin") {
    stage.apply(spin, at: time.truncatingRemainder(dividingBy: spin.duration))   // loop
}
drawScene(stage)
```

The sketch's clock drives playback, so speed, looping, scrubbing, and playing backward are all just arithmetic on the `at:` time: wrap it over `duration` to loop, pass `time * 0.5` for half speed, a slider's value to scrub. Outside a track's keyframe range the nearest keyframe **holds**, so a one-shot (a door opening) plays once with `apply(anim, at: time)` and stays open.

Applying is **absolute, not additive**: the same time always produces the same pose, so calling it every frame in `draw()` just works, and applying twice changes nothing. Each animated node's transform rebuilds from its authored components with the sampled ones swapped in; a component no track animates keeps its authored value, and a `position` you set by hand survives a rotation-only track. (A hand `rotate(_:axis:)` on an *animated* node, though, is overwritten by the next `apply`; compose your own motion on nodes the animation doesn't drive.)

All three of the format's interpolation modes play as authored: stepped holds, linear blends (rotations along the shortest arc), and eased cubic splines. That covers *rigid* motion, whole nodes moving; the deforming tier, meshes that bend and blend, is next.

<a id="deforming"></a>
### Skins and morph targets

The deforming half of a file's animation plays too, and it needs no new API: `apply(_:at:)` samples it, `drawScene` poses it.

A **skin** bends a mesh through a joint hierarchy: the file binds each vertex to up to four joint nodes with blend weights, and as an animation (or your own node mutation) moves the joints, the mesh follows smoothly, an arm bending at the elbow rather than a rigid forearm swap. The joints are ordinary nodes in the tree, so `scene["shoulder"]?.rotate(...)` poses a skinned character by hand exactly like any other node drive. One rule from the format worth knowing: a skinned mesh's *own* node transform is ignored, its placement comes entirely from where its joints are, so move the joints' parent (usually the character root), not the mesh node.

**Morph targets** blend a mesh between authored shapes: the file stores per-vertex displacements for each target (a smile, a blink, a puffed body), and the node's **`weights`** mix them, one weight per target, `0` leaving a target out and `1` adding its whole displacement. A `weights` animation track drives them from `apply(_:at:)`, and they're also just a node property you can set directly, live blend-shape posing from a slider or any signal:

```swift
tank["anemone"]?.weights = [breath, 0.2]   // puff by `breath`, a light ripple held
```

A node's authored default weights load with the scene (the node's own if it has them, else the mesh's). Morphs apply before skinning, so a character can smile while it walks.

```swift
if let sway = tank.animations.first {
    tank.apply(sway, at: time.truncatingRemainder(dividingBy: sway.duration))
}
drawScene(tank)   // skins and morphs pose here, automatically
```

<a id="cameras"></a>
### The authored camera

`scene.camera` is the file's first camera as a ready `Camera3D` (`scene.cameras` has them all, in traversal order): its world position becomes `eye`, its view direction becomes the `target` (aimed at the scene's center along the view axis, so orbit controls pivot somewhere sensible), and the authored field of view, near, and far carry over; orthographic cameras carry their frame height. A file with no cameras gives `nil`, so the usual spelling is a fallback:

```swift
camera(stage.camera ?? .orbiting(radius: 6))
```

The camera is plain data. Start from it and move on: seed a [`cameraControl()`](./Camera.md) session by hand, or read `scene.camera` once in `setup()` and animate your own copy.

<a id="lights"></a>
### The authored lights

`scene.lights` holds the file's punctual lights, all three kinds, each resolved through its node's world transform: **directional** (aims down the node's forward axis), **point** (sits at the node's position), and **spot** (position + aim + cone, the inner-to-outer soft edge becoming `penumbra`). Apply them with `light(_:)`; they're ordinary `Light` values, so tweak one before applying it.

One deliberate conversion: glTF stores physical intensities (lux, candela), which only mean something with distance falloff, and Ollin's punctual lights don't attenuate with distance. So within each kind, intensities are **normalized to the brightest** (it becomes 1, the rest keep their ratio). The authored balance survives; absolute photometric units don't. If a light lands too dim or too hot, scale its `intensity` after loading.

<a id="in-code"></a>
### Building a scene in code

`Scene` and `SceneNode` are plain values with public initializers, so a scene doesn't have to come from a file, and a hand-built one draws the same way:

```swift
let stage = Scene(nodes: [
    SceneNode(name: "pedestal", mesh: .box(width: 0.8, height: 1, depth: 0.8),
              position: Vector3(0, 0.5, 0), children: [
        SceneNode(name: "gem", mesh: .icosahedron(radius: 0.3), position: Vector3(0, 0.9, 0)),
    ]),
])
drawScene(stage)
```

<a id="notes"></a>
### Notes

- **First material per node.** A glTF node's mesh may hold several primitives with different materials; until per-material submeshes land, each node's mesh wears its first material (preferring a textured one), the same rule `loadMesh` applies per file. Splitting the scene across nodes in the design tool sidesteps it entirely.
- **Deformation is CPU posing, per frame.** A skinned or morphing node re-derives its vertices each frame it draws (only such nodes pay; everything else is untouched). Typical character and creature meshes are cheap at this scale; a film-density mesh will tell you.
- **Morph targets displace positions and normals.** Tangent displacements aren't read (nothing consumes tangents yet), and a target's normals fall back to the base mesh's when the file authored none.
- **Cameras and lights are resolved at load** into `scene.cameras` / `scene.lights` (world space). Moving a node afterward, by hand or by an animation, moves its geometry, not a light that rode it in the file.
- **Duplicated names** resolve to the first match, depth-first. Unnamed nodes have an empty name.
- The bundled demos are full worked examples: `3D/Geometry/LoadedScene` (a static stage, `scene.gltf` generated by `Scripts/make-sample-scene.swift`), `3D/Geometry/AnimatedScene` (an orrery playing its authored "spin", generated by `Scripts/make-animated-scene.swift`), and `3D/Geometry/SkinnedScene` (a tidepool whose kelp sways on skins while an anemone pulses on morph targets, generated by `Scripts/make-skinned-scene.swift`); point `OLLIN_SCENE` at any glTF of your own to try any of them.
