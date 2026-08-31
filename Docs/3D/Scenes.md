#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Scenes`</sup>

---

## Scenes (structure-preserving import)

Bring a whole composed scene into a sketch, not just its geometry. [`loadMesh`](./3D.md#meshes-from-file) merges a file into one `Mesh`, which is the right thing for a prop you place yourself. **`loadScene`** keeps the file's *structure* instead. You get a tree of **named nodes**, each with its authored transform and an optional mesh. The **cameras** and **lights** the scene was authored with come too. Compose a layout in a 3D design tool and export glTF or USD. The sketch opens on the exact framing you built there, and any node is still yours to reach by name and drive from `draw()`.

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

Everything decomposes into the core types you already use. `scene.camera` is a [`Camera3D`](./3D.md#the-camera) you pass to `camera(_:)`, `scene.lights` are [`Light`](./3D.md#lights)s you apply with `light(_:)`, and each node's `mesh` is an ordinary `Mesh`. `drawScene` is just a walk. It composes each node's transform onto the 3D transform stack and calls `drawMesh`, so materials, shadows, reflections, and every other mesh feature apply unchanged. A `translate`, `rotate`, or `scale` before `drawScene` moves the whole scene.

### Contents

- [Loading](#loading) - `loadScene`, the formats, the mesh-only fallback
- [Drawing](#drawing) - `drawScene`, fill and materials
- [Reaching nodes](#nodes) - `node(_:)`, the subscript, animating a node
- [Playing authored animations](#animation) - `apply(_:at:)`, looping, one-shots
- [Skins and morph targets](#deforming) - bending meshes, blend shapes, `weights`
- [The authored camera](#cameras) - what carries over, and how
- [The authored lights](#lights) - glTF punctual and USD UsdLux kinds, intensity normalization
- [Building a scene in code](#in-code) - `Scene` and `SceneNode` are plain values
- [Notes](#notes) - limitations and the fine print

<a id="loading"></a>
### Loading

```swift
let scene = loadScene("Stage.gltf")                            // path (Sketch sugar)
let scene = Scene(contentsOf: url)                             // URL
let scene = Scene(resource: "scene", withExtension: "gltf", in: .module)   // bundled
```

Structure comes from two families:

- **`.gltf` / `.glb`** is the full-featured path. It carries the node graph with names and per-node transforms, cameras, lights, animations, and skins. Cameras are part of the core glTF spec. Lights come from the standard punctual-lights extension, which most exporters write.
- **`.usdz` / `.usdc` / `.usda` / `.usd`** is read end to end by Ollin's own USD parser. It carries the node graph with names and per-node transforms, and **children in the file's authored order**. Node-local meshes wear their authored preview-surface colors, whose linear values are shown correctly on screen. Their textures are read out of the `.usdz` package itself. Cameras come over perspective and orthographic, as do the authored **UsdLux lights**, in the kinds listed under [The authored lights](#lights). The authored **transform animation** becomes keyframe tracks baked from its xformOp timeSamples. So does the **UsdSkel deforming tier**: skeletons, skinned meshes, and blend shapes, their SkelAnimation joint and weight channels riding the same animation. A USD file's whole timeline arrives as one unnamed animation, so `scene.animations.first` is the way in. Every track binds to the exact prim that authored it, so duplicated names across branches stay unambiguous. A prim hidden in the design tool keeps its place in the tree but draws nothing, whether by `visibility = "invisible"` or by a `guide` or `proxy` purpose. A scene arrives in its author's own units and orientation, since `upAxis` and `metersPerUnit` are not applied. A subdivision-surface mesh draws its control cage; refine it with [`subdivided(_:)`](../Generators/SubdivisionSurfaces.md) when the smooth limit matters. An exported `.usdz` from a Mac or iOS design tool drops straight in.

Any other format `loadMesh` reads (`.obj`, `.stl`, `.ply`, …) has no scene graph Ollin preserves. Such a file loads honestly as a **single-node scene**: the merged mesh on one node named after the file, with no cameras or lights. Every loader returns `nil` if the file can't be read or holds nothing.

A multi-scene glTF loads its default scene. If you export from Blender, the glTF exporter includes cameras and punctual lights only when their export options are ticked. Some versions leave those off by default.

<a id="drawing"></a>
### Drawing

`drawScene(_:)` draws every node's mesh at its authored place, composing transforms down the tree. Each node's mesh carries the file's **base-color material** (color + texture), which the current `fill` tints. Keep the default white fill to show the authored colors true, or set a fill to tint the whole scene. All the mesh machinery applies as if you'd called `drawMesh` yourself: lights and materials, `castShadows()`, ray-traced reflections, an `environment(_:)`, wireframe mode.

Nodes draw in document order, depth-first. A node with no mesh (a grouping node, a camera or light carrier) contributes only its transform.

<a id="nodes"></a>
### Reaching nodes

```swift
let lamp = stage.node("lamp")                       // a copy (nodes are values)
stage["lamp"]?.position += Vector3(0, 0.1, 0)       // mutate in place
stage["sculpture"]?.rotate(0.02, axis: .unitY)      // spin about its own pivot
stage["pedestal"]?.scale(by: 1.01)
```

`node(_:)` finds the first node with a name, searching depth-first, and returns a **copy**. `Scene` and `SceneNode` are value types. To change the scene you draw, mutate through the **subscript**, which writes back in place. `position` reads and writes the node's local translation. `rotate(_:axis:)` and `scale(by:)` compose *inside* the authored transform, so a node turns and grows about its own pivot, wherever its parents put it. Children ride along, that's what the tree is for.

`scene.bounds` is the world-space bounding box over every node's mesh, with all transforms composed. Use it to frame a camera around an arbitrary file.

<a id="animation"></a>
### Playing authored animations

A scene carries the keyframe animations its file was authored with, in `scene.animations`. Find one by name with `scene.animation(_:)`. Each is a `SceneAnimation`: a name, a `duration` in seconds, and tracks that pose nodes by translation, rotation, and scale. **`apply(_:at:)`** samples one at a time of your choosing:

```swift
if let spin = stage.animation("spin") {
    stage.apply(spin, at: time.truncatingRemainder(dividingBy: spin.duration))   // loop
}
drawScene(stage)
```

The sketch's clock drives playback, so speed, looping, scrubbing, and playing backward are all just arithmetic on the `at:` time. Wrap it over `duration` to loop, pass `time * 0.5` for half speed, a slider's value to scrub. Outside a track's keyframe range the nearest keyframe **holds**. So a one-shot like a door opening plays once with `apply(anim, at: time)` and stays open.

Applying is **absolute, not additive**. The same time always produces the same pose, so calling it every frame in `draw()` just works, and applying twice changes nothing. Each animated node's transform rebuilds from its authored components with the sampled ones swapped in. A component no track animates keeps its authored value, and a `position` you set by hand survives a rotation-only track. A hand `rotate(_:axis:)` on an *animated* node, though, is overwritten by the next `apply`. Compose your own motion on nodes the animation doesn't drive.

All three of glTF's interpolation modes play as authored: stepped holds, linear blends (rotations along the shortest arc), and eased cubic splines. A USD file's timeline arrives the same way, as one animation whose tracks were baked from its xformOp timeSamples. USD's runtime default is linear, so that's what the baked tracks are, with timeCodes converted to seconds through the layer's `timeCodesPerSecond`. Its SkelAnimation joint and blend-shape channels join the same animation. That covers *rigid* motion, whole nodes moving. The deforming tier, meshes that bend and blend, is next.

<a id="deforming"></a>
### Skins and morph targets

The deforming half of a file's animation plays too, and it needs no new API: `apply(_:at:)` samples it, `drawScene` poses it.

A **skin** bends a mesh through a joint hierarchy. The file binds each vertex to up to four joint nodes with blend weights. As an animation or your own node mutation moves the joints, the mesh follows smoothly. An arm bends at the elbow rather than swapping in a rigid forearm. The joints are ordinary nodes in the tree, so `scene["shoulder"]?.rotate(...)` poses a skinned character by hand exactly like any other node drive. In a glTF they're the file's own nodes. In a USD, each Skeleton prim's joints arrive as a node subtree named after the skeleton, one node per joint, same idea. One rule from the format is worth knowing: a skinned mesh's *own* node transform is ignored. Its placement comes entirely from where its joints are, so move the joints' parent, not the mesh node. That parent is the character root in a glTF, and the skeleton's nodes in a USD.

Anything that can pose those joints can drive the figure. Besides an animation track and your own node mutation, there is [`addRagdoll`](../Simulation/Physics3D.md#ragdolls). It builds a rigid body per joint, and `scene.apply(ragdoll)` writes the simulated pose back, which is `apply(_:at:)` run backwards.

**Morph targets** blend a mesh between authored shapes. The file stores per-vertex displacements for each target: a smile, a blink, a puffed body. The node's **`weights`** mix them, one weight per target, `0` leaving a target out and `1` adding its whole displacement. A `weights` animation track drives them from `apply(_:at:)`. They're also just a node property you can set directly, which is live blend-shape posing from a slider or any signal:

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

`scene.camera` is the file's first camera as a ready `Camera3D`, and `scene.cameras` has them all, in traversal order. Its world position becomes `eye` and its view direction becomes the `target`. The target is aimed at the scene's center along the view axis, so orbit controls pivot somewhere sensible. The authored field of view, near, and far carry over, and orthographic cameras carry their frame height. A file with no cameras gives `nil`, so the usual spelling is a fallback:

```swift
camera(stage.camera ?? .orbiting(radius: 6))
```

The camera rides its node. It resolves through the tree's *current* transforms every time you read it, so moving the camera's carrier moves the camera with it. An animation does that, and so does your own node mutation.

It's also plain data, and the natural next step is handing it to the viewer. The `from:` forms of the camera rig seed their opening shot from any `Camera3D`. One call opens on the authored framing and gives the viewer the orbit:

```swift
cameraControl(from: stage.camera ?? .orbiting(radius: 6))
```

`cameraMove(_:from:)` and `cameraShowcase(_:from:)` seed the same way; see [Camera](./Camera.md#from-authored).

<a id="lights"></a>
### The authored lights

`scene.lights` holds the file's authored lights, each resolved through its node's *current* world transform every time you read it. A light rides its node, so moving the carrier carries the light along, by hand or by an applied animation.

A glTF file carries the three punctual kinds. **Directional** aims down the node's forward axis, **point** sits at the node's position, and **spot** carries position, aim, and cone. A spot's inner-to-outer soft edge becomes its `penumbra`.

A USD file carries the UsdLux kinds, and every one maps onto an Ollin light. A **SphereLight** becomes a point light, and one carrying a shaping cone becomes a spot. There the cone half-angle doubles into the full `coneAngle` and the cone softness becomes the `penumbra`. A **DistantLight** becomes directional. The area kinds arrive as the [area lights](./3D.md#lights) they are: **RectLight** → rect, **DiskLight** → disk, **CylinderLight** → tube. Their sizes ride any scale on the prim's transform.

Apply them all with `light(_:)`. They're ordinary `Light` values, so tweak one before applying it.

One deliberate conversion. Both formats store physical intensities in lux, candela, or luminance, which only mean something under a physical falloff model. Ollin's punctual lights don't attenuate with distance. So within each kind, intensities are **normalized to the brightest**: it becomes 1 and the rest keep their ratio. USD's `exposure` folds in as ×2^exposure first. The authored balance survives; absolute photometric units don't.

If a light lands too dim or too hot, scale its `intensity` after loading, and remember a light's *color* carries brightness too. One thing to know about such tweaks. Assigning `scene.lights` replaces the authored lights with your fixed, world-space array, so they stop following their nodes. Tweaking one element in place counts as assigning.

<a id="in-code"></a>
### Building a scene in code

`Scene` and `SceneNode` are plain values with public initializers, so a scene doesn't have to come from a file. A hand-built one draws the same way:

```swift
let stage = Scene(nodes: [
    SceneNode(name: "pedestal", mesh: .box(width: 0.8, height: 1, depth: 0.8),
              position: Vector3(0, 0.5, 0), children: [
        SceneNode(name: "gem", mesh: .icosahedron(radius: 0.3), position: Vector3(0, 0.9, 0)),
    ]),
])
drawScene(stage)
```

### Writing one back out

A scene goes out the way it came in. [`Scene.write(to:)`](../Output/Spatial.md) writes it as USDZ, the format Quick Look, Messages, and visionOS read. `OllinApp.spatialScene(of:frame:)` records a frame of any 3D sketch as a `Scene` first, so a piece can leave as a model rather than a picture of one.

```swift
scene.write(to: "piece.usdz", metersPerUnit: 0.05)
```

<a id="notes"></a>
### Notes

- **Multi-material meshes render as authored.** A glTF node's mesh may hold several primitives with different materials, and a USD mesh may partition its faces into material-binding `GeomSubset`s. Faces no subset claims keep the mesh's own binding, and `drawScene` draws each material's slice of the mesh with its own material. The node's `mesh` property stays one whole `Mesh`, wearing its first material and preferring a textured one, the same rule `loadMesh` applies per file. So drawing it standalone with `drawMesh` shows a single look; the per-material split lives on the scene path. A node says when it carries one of these through **`wearsSeveralMaterials`**, so a tool placing parts by hand can warn where the look will differ.
- **A node says when its transform won't split.** **`placementIsExact`** is `false` when the authored matrix carries a shear that translate, rotate, and scale can't reproduce. `drawScene` still draws it exactly (the matrix is kept verbatim); the flag is for anything re-expressing the node as separate moves, which works from an approximation there.
- **Deformation is CPU posing, per frame.** A skinned or morphing node re-derives its vertices each frame it draws. Only such nodes pay, and everything else is untouched. Typical character and creature meshes are cheap at this scale; a film-density mesh will tell you.
- **Morph targets displace positions and normals.** Tangent displacements aren't read (nothing consumes tangents yet), and a target's normals fall back to the base mesh's when the file authored none.
- **Cameras and lights ride their nodes.** `scene.cameras` / `scene.lights` resolve through the tree's current transforms on every read, so a moved carrier node carries its camera or light. That holds whether you moved it by hand or an animation did. Assigning either array replaces it with your own fixed world-space array, which no longer follows the nodes, and tweaking one element in place counts as assigning.
- **Duplicated names** resolve to the first match, depth-first. Unnamed nodes have an empty name.
- The bundled demos are full worked examples, each listed with the script that generated its asset. Point `OLLIN_SCENE` at any scene file of your own to try one on it.
  - `3D/Geometry/LoadedScene`, a static stage, `scene.gltf` from `Scripts/make-sample-scene.swift`; and, behind F, `stage.usda`, a sculpture court lit by its authored UsdLux rig with one light of every mapped kind, from `Scripts/make-usd-scene.swift`.
  - `3D/Geometry/AnimatedScene`, an orrery playing its authored "spin", from `Scripts/make-animated-scene.swift`; and, behind F, `stage.usda`, a kinetic mobile whose authored timeSamples spin, bob, tumble, swing, and breathe its parts, from `Scripts/make-usd-animated-scene.swift`.
  - `3D/Geometry/SkinnedScene`, a tidepool whose kelp sways on skins while an anemone pulses on morph targets, from `Scripts/make-skinned-scene.swift`; and, behind F, `stage.usda`, a pond where a sea serpent sways on a five-joint UsdSkel chain and a lotus breathes on blend shapes, from `Scripts/make-usd-skinned-scene.swift`.
  - `3D/Geometry/SceneExplorer`, a read-only lens on a scene file: orbit it or adopt its camera, switch the stage around it, toggle its lights one by one, and step a highlight or an isolation through the parts, each caged in its bounds with the import's warnings said on the part that carries them. It never edits the file; `ollin new --from-scene` is how a scene becomes source.
