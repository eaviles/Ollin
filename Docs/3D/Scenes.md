#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Scenes`</sup>

---

## Scenes (structure-preserving import)

`loadScene` brings a whole composed scene into a sketch, not just its geometry. Compare it with [`loadMesh`](./3D.md#meshes-from-file), which merges a file into one `Mesh` and suits a prop you place yourself. **`loadScene`** keeps the file's *structure* instead. You get a tree of **named nodes**. Each node has its authored transform and an optional mesh. The **cameras** and **lights** the scene was authored with come too. So you can compose a layout in a 3D design tool and export it as glTF or USD. The sketch then opens on the exact framing you built there, and you can still reach any node by name and drive it from `draw()`.

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

Everything decomposes into the core types you already use. `scene.camera` is a [`Camera3D`](./3D.md#the-camera) that you pass to `camera(_:)`. `scene.lights` are [`Light`](./3D.md#lights) values that you apply with `light(_:)`. Each node's `mesh` is an ordinary `Mesh`. `drawScene` is a walk over the tree. It composes each node's transform onto the 3D transform stack and calls `drawMesh`, so materials, shadows, reflections, and every other mesh feature apply unchanged. A `translate`, `rotate`, or `scale` before `drawScene` moves the whole scene.

### Contents

- [Loading](#loading) - `loadScene`, the formats, the mesh-only fallback
- [Drawing](#drawing) - `drawScene`, fill and materials
- [Reaching nodes](#nodes) - `node(_:)`, the subscript, animating a node
- [Playing authored animations](#animation) - `apply(_:at:)`, looping, one-shots
- [Skins and morph targets](#deforming) - bending meshes, blend shapes, `weights`
- [The authored camera](#cameras) - what carries over, and how
- [The authored lights](#lights) - glTF punctual and USD UsdLux kinds, intensity normalization
- [Building a scene in code](#in-code) - `Scene` and `SceneNode` are plain values
- [Notes](#notes) - limitations and the details

<a id="loading"></a>
### Loading

```swift
let scene = loadScene("Stage.gltf")                            // path (Sketch sugar)
let scene = Scene(contentsOf: url)                             // URL
let scene = Scene(resource: "scene", withExtension: "gltf", in: .module)   // bundled
```

Structure comes from two families of format:

- **`.gltf` / `.glb`** is the more complete of the two. It carries the node graph with names and per-node transforms, cameras, lights, animations, and skins. Cameras are part of the core glTF spec. Lights come from the standard punctual-lights extension, which most exporters write.
- **`.usdz` / `.usdc` / `.usda` / `.usd`** is read end to end by Ollin's own USD parser. It carries the node graph with names and per-node transforms, and **children in the file's authored order**. Node-local meshes keep their authored preview-surface colors, and those linear values show correctly on screen. Their textures are read out of the `.usdz` package itself. Cameras come over, both perspective and orthographic. The authored **UsdLux lights** come over too, in the kinds listed under [The authored lights](#lights). The authored **transform animation** becomes keyframe tracks baked from its xformOp timeSamples. The **UsdSkel deforming tier** comes over the same way: skeletons, skinned meshes, and blend shapes. Their SkelAnimation joint and weight channels join the same animation. A USD file's whole timeline arrives as one unnamed animation, so `scene.animations.first` is the way to reach it. Every track binds to the exact prim that authored it, so a name repeated across branches stays unambiguous. A prim hidden in the design tool keeps its place in the tree but draws nothing. That holds whether it is hidden by `visibility = "invisible"` or by a `guide` or `proxy` purpose. A scene arrives in its author's own units and orientation, because `upAxis` and `metersPerUnit` are not applied. A subdivision-surface mesh draws its control cage. Refine it with [`subdivided(_:)`](../Generators/SubdivisionSurfaces.md) when you need the smooth limit surface. A `.usdz` exported from a Mac or iOS design tool loads with no extra work.

Any other format that `loadMesh` reads (`.obj`, `.stl`, `.ply`, …) has no scene graph for Ollin to preserve. Such a file loads as a **single-node scene**: the merged mesh on one node named after the file, with no cameras or lights. Every loader returns `nil` if the file can't be read or holds nothing.

A glTF with several scenes loads its default scene. If you export from Blender, the glTF exporter includes cameras and punctual lights only when their export options are ticked. Some versions leave those off by default.

<a id="drawing"></a>
### Drawing

`drawScene(_:)` draws every node's mesh at its authored place, composing the transforms down the tree. Each node's mesh carries the file's **base-color material** (color and texture), and the current `fill` tints it. Keep the default white fill to show the authored colors as they are, or set a fill to tint the whole scene. Everything that applies to `drawMesh` applies here too: lights and materials, `castShadows()`, ray-traced reflections, an `environment(_:)`, and wireframe mode.

Nodes draw in document order, depth-first. A node with no mesh contributes only its transform. A grouping node works that way, and so does a node that carries a camera or a light.

<a id="nodes"></a>
### Reaching nodes

```swift
let lamp = stage.node("lamp")                       // a copy (nodes are values)
stage["lamp"]?.position += Vector3(0, 0.1, 0)       // mutate in place
stage["sculpture"]?.rotate(0.02, axis: .unitY)      // spin about its own pivot
stage["pedestal"]?.scale(by: 1.01)
```

`node(_:)` finds the first node with the given name, searching depth-first, and returns a **copy**, because `Scene` and `SceneNode` are value types. To change the scene you draw, mutate through the **subscript**, which writes back in place. `position` reads and writes the node's local translation. `rotate(_:axis:)` and `scale(by:)` compose *inside* the authored transform, so a node turns and grows about its own pivot, wherever its parents put it. Children move with their parent.

`scene.bounds` is the world-space bounding box over every node's mesh, with all transforms composed. Use it to frame a camera around any file.

<a id="animation"></a>
### Playing authored animations

A scene carries the keyframe animations its file was authored with, in `scene.animations`. Find one by name with `scene.animation(_:)`. Each one is a `SceneAnimation`. It holds a name, a `duration` in seconds, and tracks that pose nodes by translation, rotation, and scale. You sample one with **`apply(_:at:)`** at a time of your choosing:

```swift
if let spin = stage.animation("spin") {
    stage.apply(spin, at: time.truncatingRemainder(dividingBy: spin.duration))   // loop
}
drawScene(stage)
```

The sketch's clock drives playback, so speed, looping, scrubbing, and playing backward are all arithmetic on the `at:` time. Wrap it over `duration` to loop, pass `time * 0.5` for half speed, or pass a slider's value to scrub. Outside a track's keyframe range the nearest keyframe **holds**. So a one-shot such as a door opening plays once with `apply(anim, at: time)` and then stays open.

Applying is **absolute, not additive**. The same time always produces the same pose, so you can call it every frame in `draw()`, and applying it twice changes nothing. Each animated node's transform rebuilds from its authored components with the sampled ones swapped in. A component that no track animates keeps its authored value, so a `position` you set by hand survives a rotation-only track. A hand `rotate(_:axis:)` on an *animated* node, though, is overwritten by the next `apply`. So compose your own motion on nodes that the animation doesn't drive.

All three of glTF's interpolation modes play as authored: stepped holds, linear blends (rotations along the shortest arc), and eased cubic splines. A USD file's timeline arrives the same way, as one animation whose tracks were baked from its xformOp timeSamples. USD's runtime default is linear, so the baked tracks are linear. Their timeCodes convert to seconds through the layer's `timeCodesPerSecond`. Its SkelAnimation joint and blend-shape channels join the same animation. All of this is *rigid* motion, where whole nodes move. The next section covers the deforming tier, where meshes bend and blend.

<a id="deforming"></a>
### Skins and morph targets

The deforming half of a file's animation plays too, and it needs no new API. `apply(_:at:)` samples it, and `drawScene` poses it.

A **skin** bends a mesh through a joint hierarchy. The file binds each vertex to up to four joint nodes with blend weights. When an animation or your own node mutation moves the joints, the mesh follows smoothly. So an arm bends at the elbow instead of swapping in a rigid forearm. The joints are ordinary nodes in the tree, so `scene["shoulder"]?.rotate(...)` poses a skinned character by hand in the same way as any other node. In a glTF the joints are the file's own nodes. In a USD, each Skeleton prim's joints arrive as a node subtree named after the skeleton, with one node per joint. Those joints work the same way.

A skinned mesh's *own* node transform is ignored, because its placement comes entirely from where its joints are. So move the joints' parent, not the mesh node. That parent is the character root in a glTF, and the skeleton's nodes in a USD.

Anything that can pose those joints can drive the figure. Besides an animation track and your own node mutation, there is [`addRagdoll`](../Simulation/Physics3D.md#ragdolls). It builds a rigid body per joint, and `scene.apply(ragdoll)` writes the simulated pose back into the nodes. The pose travels the opposite way from `apply(_:at:)`, which reads a pose out of an animation.

**Morph targets** blend a mesh between authored shapes. The file stores per-vertex displacements for each target, such as a smile, a blink, or a puffed body. The node's **`weights`** mix them, with one weight per target. `0` leaves a target out, and `1` adds its whole displacement. A `weights` animation track drives them from `apply(_:at:)`. They are also a plain node property you can set directly, which gives you live blend-shape posing from a slider or any other signal:

```swift
tank["anemone"]?.weights = [breath, 0.2]   // puff by `breath`, a light ripple held
```

A node's authored default weights load with the scene (the node's own if it has them, otherwise the mesh's). Morphs apply before skinning, so a character can smile while it walks.

```swift
if let sway = tank.animations.first {
    tank.apply(sway, at: time.truncatingRemainder(dividingBy: sway.duration))
}
drawScene(tank)   // skins and morphs pose here, automatically
```

<a id="cameras"></a>
### The authored camera

`scene.camera` is the file's first camera as a ready `Camera3D`, and `scene.cameras` has them all in traversal order. The camera's world position becomes `eye`, and its view direction becomes the `target`. The target is aimed at the scene's center along the view axis, so orbit controls pivot around a sensible point. The authored field of view, near, and far carry over, and an orthographic camera carries its frame height. A file with no cameras gives `nil`, so the usual spelling includes a fallback:

```swift
camera(stage.camera ?? .orbiting(radius: 6))
```

The camera follows its node. It resolves through the tree's *current* transforms every time you read it, so moving the camera's carrier node moves the camera with it. An animation can move that node, and so can your own node mutation.

The camera is also plain data, so you can pass it to a camera rig that the viewer controls. The `from:` forms of the camera rig seed their opening shot from any `Camera3D`. One call opens on the authored framing and gives the viewer the orbit:

```swift
cameraControl(from: stage.camera ?? .orbiting(radius: 6))
```

`cameraMove(_:from:)` and `cameraShowcase(_:from:)` seed the same way. See [Camera](./Camera.md#from-authored).

<a id="lights"></a>
### The authored lights

`scene.lights` holds the file's authored lights. Each one resolves through its node's *current* world transform every time you read it. A light follows its node, so moving the carrier node moves the light with it, whether by hand or by an applied animation.

A glTF file carries the three punctual kinds. A **directional** light aims down the node's forward axis. A **point** light sits at the node's position. A **spot** light carries position, aim, and cone, and its inner-to-outer soft edge becomes its `penumbra`.

A USD file carries the UsdLux kinds, and every one maps onto an Ollin light. A **SphereLight** becomes a point light, and a SphereLight with a shaping cone becomes a spot. In that case the cone half-angle doubles into the full `coneAngle`, and the cone softness becomes the `penumbra`. A **DistantLight** becomes directional. The area kinds arrive as [area lights](./3D.md#lights): **RectLight** → rect, **DiskLight** → disk, **CylinderLight** → tube. Their sizes include any scale on the prim's transform.

Apply them all with `light(_:)`. They are ordinary `Light` values, so you can adjust one before applying it.

Intensity goes through one deliberate conversion. Both formats store physical intensities in lux, candela, or luminance, and those units only mean something under a physical falloff model. Ollin's punctual lights don't attenuate with distance. So within each kind, intensities are **normalized to the brightest** light. That light becomes 1, and the rest keep their ratio to it. USD's `exposure` is applied first, as ×2^exposure. The authored balance survives, but the absolute photometric units don't.

If a light is too dim or too bright, scale its `intensity` after loading. Remember that a light's *color* carries brightness too. Making that change means assigning `scene.lights`, which replaces the authored lights with your own fixed, world-space array, so they stop following their nodes. Changing one element in place counts as assigning.

<a id="in-code"></a>
### Building a scene in code

`Scene` and `SceneNode` are plain values with public initializers, so a scene does not have to come from a file. You can build one by hand, and it draws the same way:

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

A `Scene` can go back out to a file as well as come in from one. Write it as USDZ with [`Scene.write(to:)`](../Output/Spatial.md), which is the format Quick Look, Messages, and visionOS read. `OllinApp.spatialScene(of:frame:)` records a frame of any 3D sketch as a `Scene` first. So a piece can leave as a model rather than as a picture of one.

```swift
scene.write(to: "piece.usdz", metersPerUnit: 0.05)
```

<a id="notes"></a>
### Notes

- **Multi-material meshes render as authored.** A glTF node's mesh may hold several primitives with different materials. A USD mesh may partition its faces into material-binding `GeomSubset`s. Faces that no subset claims keep the mesh's own binding, and `drawScene` draws each material's slice of the mesh with its own material. The node's `mesh` property stays one whole `Mesh`. It carries its first material, preferring a textured one, which is the same rule `loadMesh` applies per file. So drawing it on its own with `drawMesh` shows a single look, and the per-material split exists only on the scene path. A node reports that it carries several materials through **`wearsSeveralMaterials`**, so a tool that places parts by hand can warn where the look will differ.
- **A node says when its transform won't split.** **`placementIsExact`** is `false` when the authored matrix carries a shear. Translate, rotate, and scale can't reproduce a shear. `drawScene` still draws such a node exactly, because the matrix is kept verbatim. The flag is for anything that re-expresses the node as separate moves, because it has only an approximation to work from.
- **Deformation is CPU posing, per frame.** A skinned or morphing node re-derives its vertices each frame it draws. Only such nodes pay that cost, and everything else is untouched. Typical character and creature meshes are cheap at this scale. A film-density mesh will show the cost.
- **Morph targets displace positions and normals.** Tangent displacements aren't read, because nothing consumes tangents yet. When the file authored no normals for a target, the target falls back to the base mesh's normals.
- **Cameras and lights ride their nodes.** `scene.cameras` and `scene.lights` resolve through the tree's current transforms on every read. So a moved carrier node carries its camera or light with it, whether you moved it by hand or an animation did. Assigning either array replaces it with your own fixed world-space array, which no longer follows the nodes. Changing one element in place counts as assigning.
- **Duplicated names** resolve to the first match, depth-first. Unnamed nodes have an empty name.
- The bundled demos are full worked examples. Each one is listed with the script that generated its asset. Point `OLLIN_SCENE` at any scene file of your own to try a demo on it.
  - `3D/Geometry/LoadedScene`, a static stage. Its `scene.gltf` comes from `Scripts/make-sample-scene.swift`. Press F to load `stage.usda` from `Scripts/make-usd-scene.swift`, a sculpture court lit by its authored UsdLux rig, with one light of every mapped kind.
  - `3D/Geometry/AnimatedScene`, an orrery playing its authored "spin", from `Scripts/make-animated-scene.swift`. Press F to load `stage.usda` from `Scripts/make-usd-animated-scene.swift`, a kinetic mobile whose authored timeSamples spin, bob, tumble, swing, and breathe its parts.
  - `3D/Geometry/SkinnedScene`, a tidepool from `Scripts/make-skinned-scene.swift`. Its kelp sways on skins while an anemone pulses on morph targets. Press F to load `stage.usda` from `Scripts/make-usd-skinned-scene.swift`, a pond. There a sea serpent sways on a five-joint UsdSkel chain, and a lotus breathes on blend shapes.
  - `3D/Geometry/SceneExplorer`, a read-only viewer for a scene file. You can orbit it or adopt its camera, switch the stage around it, and toggle its lights one by one. You can also step through the parts one at a time, highlighting a part or isolating it. Each part is drawn inside a box at its bounds, and the import's warnings appear on the part that carries them. It never edits the file. To turn a scene into source, use `ollin new --from-scene`.
