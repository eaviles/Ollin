#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Spatial`</sup>

---

## Spatial export

A 3D sketch is a scene, and a frame of it is a photograph of that scene. Writing one out as USDZ sends the scene instead. The model opens in Quick Look from the Finder or a message. It stands on a real table through AR, and drops into a visionOS app or Reality Composer. It is the three-dimensional sibling of the [fabrication](./Fabrication.md) writers, which send a single mesh to a printer. It is also the sibling of the [vector exporters](./Export.md#vector-svg), which send a flat frame to a plotter.

```sh
swift run Example-3D-Geometry-Solids --export-usdz piece.usdz
```

That is the whole thing. No window, no GPU. The sketch runs headlessly to the frame you name, and its 3D draw calls are collected into a model.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/SpatialExport-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/SpatialExport.jpg" alt="Two identical arrangements of a yellow sphere, blue rounded box and green torus; the left is surrounded by scattered gray dust motes, the right has none" width="680">
</picture>

### The two ways in

A frame and a scene are both exportable, and both go through one writer.

```swift
// One frame of a sketch, recorded as it draws.
OllinApp.exportSpatial(sketch, to: "piece.usdz", frame: 120)

// Any Scene: one you loaded, one you built, one you recorded.
scene.write(to: "piece.usdz")
saveScene(scene, to: "piece.usdz")            // the same, from inside a sketch
```

`OllinApp.spatialScene(of:frame:)` is the middle step, and it is worth knowing about. It hands back an ordinary [`Scene`](../3D/Scenes.md), the same kind `loadScene` gives you. So a recorded frame can be read, edited, drawn again with `drawScene`, or written later.

```swift
var scene = OllinApp.spatialScene(of: sketch, frame: 120)
scene["piece3"]?.position.y += 0.5
scene.write(to: "piece.usdz")
```

The recorder is why the frame path and the file path cannot drift. There is one writer, and the recorder feeds it.

### Size is a declaration

A model file records how big one scene unit is, and Ollin does not guess. Nothing is scaled on the way out. `metersPerUnit` says how to read the numbers that are there.

```swift
scene.write(to: "piece.usdz", metersPerUnit: 1)      // one unit is a meter (the default)
scene.write(to: "piece.usdz", metersPerUnit: 0.05)   // desk-sized
```

At the default of 1, a sphere of radius 1 arrives as a two-meter ball. That is right for something meant to fill a room, and much too big for something meant to sit on a table. Most 3D sketches work at unit scale, so `0.01` to `0.1` is the usual range for a model someone will place in a room.

### Choosing a format

| | holds | reach for it when |
|---|---|---|
| `.usdz` | the layer and its textures, in one file | you are sending it, opening it in Quick Look, or placing it in AR. The only one AR Quick Look reads. |
| `.usda` | the scene as readable text, one file | you want to look at what was written, diff two exports, or hand it to a tool. Textures have nowhere to go, so they are left out with a note. |

Both are USD, and the extension picks between them.

### What travels

- **Meshes**, with the transform that placed them. Each `drawMesh` becomes one node, and the geometry stays in its own space rather than being baked flat. So the model has the same structure the frame drew with. A [loaded scene](../3D/Scenes.md) keeps its tree.
- **Surfaces.** The fill color, the mesh's own base color, per-vertex colors, texture coordinates, and textures inside a `.usdz`.
- **The finish**, as far as the format goes. A [physically based material](../3D/3D.md#physically-based-metal-and-roughness) maps straight across, since USD describes a surface the same way. That covers metallic, roughness, opacity, index of refraction, and clearcoat. Glass travels as transparency.
- **The camera** the frame was drawn through, and **the lights** that shaded it, including the auto-lit default rig if the sketch set none. Every light kind maps to its USD counterpart.

### What does not, and says so

Nothing is dropped quietly. Anything the format cannot hold prints one note naming it.

- **2D drawing.** Text, shapes, and overlays are not geometry in a scene. A labeled diagram exports as the solids without the labels.
- **Point clouds, GPU particles, and raymarched fields.** These are not surfaces. `isosurface(at:in:_:)` and `particleSurface(of:)` turn a field or a cloud into a mesh, which does travel.
- **Stylized finishes.** Toon, gooch, matcap, iridescence, sparkle, rim, sheen, and subsurface are ways of shading rather than descriptions of a material. The surface exports with its color and how shiny it is. A stylized finish's `specularSharpness` converts to roughness through the same curve the renderer's own area lights use. So a polished surface stays polished.
- **Animation and skinning.** One pose is written, the one the scene is holding. Export several frames if you want several poses.
- **The environment.** An [image-based lighting](../3D/3D.md#environment-lighting) environment is not written. That is usually what you want. A viewer lights a model with its own surroundings. In AR those surroundings are the actual room the model is standing in.

### Reading it back

Ollin reads USD as well as it writes it, so a written model opens again:

```swift
let scene = loadScene("piece.usdz")
drawScene(scene!)
```

This is the round trip the writer is tested against. Geometry, node transforms, materials, textures, cameras, and every light kind go out and come back as themselves. That is what keeps the two halves honest. A writer that drifts from its reader is wrong in a way nothing else notices.

### Checking a model

The system's own USD tools read what Ollin writes, and are the last word on whether a package is well formed:

```sh
usdchecker --arkit piece.usdz      # the profile Apple's platforms hold a model to
usdcat piece.usdz | head -40       # look at the layer
usdtree piece.usdz                 # the prim tree
usdrecord piece.usdz look.png      # render it with someone else's renderer
```

Ollin's own test suite runs `usdchecker --arkit` over a package carrying every light kind, a texture, per-vertex colors, and a physically based material.

### The package, briefly

A `.usdz` is a ZIP with rules. There is no compression, and the layer comes first. Every file starts on a 64-byte boundary, so a reader can map the bytes in place. Ollin writes it itself rather than going through a system framework, which makes the output **byte-reproducible**. Writing the same scene twice gives the same file, so a model can be diffed or committed like any other artifact.

### Reference

| | |
|---|---|
| `scene.write(to:as:metersPerUnit:)` | write a scene as a spatial model; the extension picks the format |
| `scene.data(as:metersPerUnit:)` | the same, as bytes |
| `saveScene(_:to:as:metersPerUnit:)` | the sketch-side sugar, beside `saveMesh` |
| `OllinApp.spatialScene(of:frame:fps:)` | one frame's 3D draw calls as a `Scene` |
| `OllinApp.exportSpatial(_:to:frame:fps:metersPerUnit:)` | record a frame and write it |
| `SceneFileFormat` | `.usdz` (package) or `.usda` (text layer) |
| `--export-usdz <path>` | the CLI flag, with `--frame N` and `--meters-per-unit U` |

## Spatial video

A model sends the geometry and lets a viewer walk around it. **Spatial video** sends the motion instead, recorded from two eyes at once. That is the only way an animation reads as three-dimensional in a headset. It is the same format Apple's platforms record and play, which is stereo MV-HEVC with the metadata that says what shot it.

```sh
swift run Example-3D-Geometry-SpatialVideo --export-spatial piece.mov --seconds 8
```

The frame is drawn **once** and rendered twice, from two cameras a little way apart. That matters more than it sounds. Drawing twice would roll the sketch's randomness twice, and step every simulation twice. The sims that are honest about not reproducing frame for frame would then hand the two eyes genuinely different worlds. One draw, two renders, and both eyes see the same instant.

### The two numbers

A stereo pair needs exactly two numbers, and both are decisions about the piece rather than settings to get right.

**Convergence** is the distance at which the two eyes agree. Whatever sits there lands on the screen. Nearer things come out of it, and farther things sit behind it. Choosing it is choosing what the viewer is looking *into* rather than *out at*. Unset, it is the camera's own target, on the reasoning that you are already pointing at the thing the piece is about.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/StereoPair-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/StereoPair.jpg" alt="A plan-view diagram: two eyes at the bottom looking parallel, a horizontal line labeled the screen, and three objects whose sight lines land on the screen as paired marks, crossed for the near object, coincident at the screen, spread apart for the far one" width="680">
</picture>

**Interocular** is how far apart the eyes stand, in world units, and it is the depth dial. Half reads flatter, and twice reads deeper and starts to strain. Unset, the eyes sit **1% of the frame width apart, measured at the convergence plane**. For a camera with a vanishing point, that one sentence is also the classic comfort rule. Eyes 1% of the frame width apart at the convergence plane end up 1% of the frame width apart at infinity. The far background then separates by less than a viewer's own eyes do, so nothing ever asks them to point outward.

A sketch declares them, the way it declares a loop or its inks:

```swift
override var stereoGeometry: StereoGeometry {
    StereoGeometry(interocular: 0.1, convergence: 6)
}
```

Either number can be left out and derived, and either can be overridden per export (`--interocular X`, `--convergence D`) without disturbing the other. `StereoGeometry.resolved(for:)` hands back what they come to for a given camera. So a sketch can show the spacing it is about to export with, or take the derived figure as the thing to scale:

```swift
let spacing = StereoGeometry.automatic.resolved(for: shot).interocular
```

### What the two cameras do

The eyes step sideways along the camera's own right axis, and keep looking **parallel**. The projection leans back in, so the two agree exactly at the convergence distance. That is the rig a stereo film is shot on. Toeing two cameras in at the subject instead sounds equivalent, and is not. It tilts their frames against each other, and leaves a vertical misalignment at the corners that no viewer can fuse away.

Everything else about the camera is untouched, so a pair renders through the ordinary path. Same lens, same clipping, same everything one frame would have used.

### How big is a world unit

```sh
--meters-per-unit 0.01     # the sketch draws in centimetres
```

The file records the distance between the eyes that shot it, in real units, and a player scales the depth it shows from that. `metersPerUnit` is the same declaration the model exporter takes, and the same rule applies. Nothing is scaled on the way out, and this just says how to read the numbers that are there. A scene drawn in meters wants the default of 1.

### What it does not do

- **An accumulating sketch reads flat**, and says so once. The pile lives in one persistent surface, and there is only one of it, so both eyes are handed the same picture. A screen-space pile has no depth to give anyway.
- **A 2D sketch reads flat** for the same reason, and also says so.
- **Anything the sketch flattened itself during `draw()`** stays where it was flattened, whether that is a `project()`, a `depth(at:)` placement, or a billboard. Those land on the screen plane in both eyes, which for the notices and overlays that use them is usually what you want.
- Sound rides along exactly as it does in an ordinary video export.

### Checking a file

The reading that matters is the system's own, the one Photos and Quick Look take:

```swift
let options = await AVAssetPlaybackAssistant(asset: AVURLAsset(url: url))
    .playbackConfigurationOptions
options.contains(.spatialVideo)      // true
```

Careful with the near neighbors: `.stereoMultiviewVideo` is true for any two-layer file, spatial metadata or not, so it is not the test. On the command line, `ffprobe -show_entries stream_side_data` prints the baseline, the field of view, and which eye is the hero.

### Reference

| | |
|---|---|
| `OllinApp.exportSpatialVideo(_:to:frames:fps:stereo:metersPerUnit:…)` | render a sketch as spatial video |
| `--export-spatial <path.mov>` | the CLI flag, with `--frames`/`--seconds`, `--fps`, `--skip`, `--interocular`, `--convergence`, `--meters-per-unit`, `--bitrate`, `--quality` |
| `Sketch.stereoGeometry` | the sketch's own declaration; `.automatic` by default |
| `StereoGeometry(interocular:convergence:)` | the two numbers, either one derivable |
| `StereoGeometry.resolved(for:aspect:)` | what they come to for a camera |
| `Camera3D.stereoPair(_:aspect:)` | the two cameras a pair renders through |
| `Camera3D.stereoEye(_:interocular:convergence:)` | one of them, by name |

### See also

- [Scenes](../3D/Scenes.md) reads models in, which is the same tree this writes out.
- [Fabrication](./Fabrication.md) writes a single `Mesh` for a 3D printer.
- [Export](./Export.md) covers frames, ordinary video, and the vector formats.
- [3D](../3D/3D.md) and [Camera](../3D/Camera.md) cover the scene and the shot a stereo pair is taken from.
- `Examples/3D/Geometry/SpatialExport` is a ring of solids you can write out and open.
- `Examples/3D/Geometry/SpatialVideo` is a colonnade built for depth, with the two stereo numbers on parameters.
