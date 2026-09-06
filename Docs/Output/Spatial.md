#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Spatial`</sup>

---

## Spatial export

A 3D sketch draws a scene, and an exported frame is a flat picture of that scene. A USDZ export sends the scene itself instead of a picture. The model opens in Quick Look from the Finder or from a message. In AR it stands on a real table, and you can add it to a visionOS app or open it in Reality Composer. The [fabrication](./Fabrication.md) writers send a single mesh to a printer, and the [vector exporters](./Export.md#vector-svg) send a flat frame to a plotter. This exporter is the three-dimensional counterpart of both.

```sh
swift run --package-path Examples Example-3D-Geometry-SpatialExport --export-usdz piece.usdz
```

That one command is the whole export. It opens no window and uses no GPU. The sketch runs headlessly up to the frame you name, and its 3D draw calls are collected into a model.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/SpatialExport-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/SpatialExport.jpg" alt="Two identical arrangements of a yellow sphere, blue rounded box and green torus; the left is surrounded by scattered gray dust motes, the right has none" width="680">
</picture>

### The two ways in

You can export one frame of a sketch or a whole scene, and both go through the same writer.

```swift
// One frame of a sketch, recorded as it draws.
OllinApp.exportSpatial(sketch, to: "piece.usdz", frame: 120)

// Any Scene: one you loaded, one you built, one you recorded.
scene.write(to: "piece.usdz")
saveScene(scene, to: "piece.usdz")            // the same, from inside a sketch
```

`OllinApp.spatialScene(of:frame:fps:)` is the step between the two. It returns an ordinary [`Scene`](../3D/Scenes.md), the same kind `loadScene` gives you. So you can read a recorded frame, edit it, draw it again with `drawScene`, or write it later.

```swift
var scene = OllinApp.spatialScene(of: sketch, frame: 120)
scene["piece3"]?.position.y += 0.5
scene.write(to: "piece.usdz")
```

There is one writer, and the recorder feeds it. Because a frame export goes through the recorder and then through that same writer, the frame path and the scene path cannot drift apart.

### Size is a declaration

A model file records how big one scene unit is, and Ollin does not guess that size. Nothing is scaled on the way out. Instead, `metersPerUnit` says how to read the numbers already in the scene.

```swift
scene.write(to: "piece.usdz", metersPerUnit: 1)      // one unit is a meter (the default)
scene.write(to: "piece.usdz", metersPerUnit: 0.05)   // desk-sized
```

At the default of 1, a sphere of radius 1 arrives as a ball two meters across. That is right for a piece meant to fill a room, and much too big for one meant to sit on a table. Most 3D sketches work at unit scale, so `0.01` to `0.1` is the usual range for a model that someone will place in a room.

### Choosing a format

| | holds | reach for it when |
|---|---|---|
| `.usdz` | the layer and its textures, in one file | you are sending it, opening it in Quick Look, or placing it in AR. It is the only format AR Quick Look reads. |
| `.usda` | the scene as readable text, one file | you want to read what was written, diff two exports, or hand it to a tool. A text layer has no place for textures, so they are left out and a note says so. |

Both formats are USD, and the file extension picks between them.

### What travels

- **Meshes**, with the transform that placed them. Each `drawMesh` becomes one node, and the geometry stays in its own space instead of being baked into world space. So the model keeps the same structure the frame drew with. A [loaded scene](../3D/Scenes.md) keeps its tree.
- **Surfaces.** The fill color, the mesh's own base color, per-vertex colors, texture coordinates, and, inside a `.usdz`, the textures.
- **The finish**, as far as the format can hold it. A [physically based material](../3D/3D.md#physically-based-metal-and-roughness) maps straight across, because USD describes a surface the same way. That covers metallic, roughness, opacity, index of refraction, and clearcoat. Glass travels as transparency.
- **The camera** the frame was drawn through, and **the lights** that shaded it. If the sketch set no lights, the auto-lit default rig is written. Every light kind maps to its USD counterpart.

### What does not, and says so

Nothing is dropped silently. When the format cannot hold something, the exporter prints one note that names it.

- **2D drawing.** Text, shapes, and overlays are not geometry in a scene, so a labeled diagram exports as the solids without the labels.
- **Point clouds, GPU particles, and raymarched fields.** These are not surfaces, so they are not written. `isosurface(at:in:_:)` and `particleSurface(of:)` turn a field or a cloud into a mesh, and a mesh does travel.
- **Stylized finishes.** Toon, gooch, matcap, iridescence, sparkle, rim, sheen, and subsurface are ways of shading, not descriptions of a material. So they are not written. The surface exports with its color and its shininess. A stylized finish's `specularSharpness` converts to roughness through the same curve the renderer's own area lights use, so a polished surface stays polished.
- **Animation and skinning.** One pose is written, the pose the scene holds at that moment. If you want several poses, export several frames.
- **The environment.** An [image-based lighting](../3D/3D.md#environment-lighting) environment is not written. That is usually what you want, because a viewer lights a model with its own surroundings. In AR those surroundings are the real room the model stands in.

### Reading it back

Ollin reads USD as well as writing it, so a model it wrote opens again:

```swift
let scene = loadScene("piece.usdz")
drawScene(scene!)
```

This round trip is what the writer is tested against. Geometry, node transforms, materials, textures, cameras, and every light kind go out and come back unchanged. The test matters because a writer that drifts from its reader is wrong in a way nothing else would notice.

### Checking a model

The system's own USD tools read what Ollin writes, and they are the final check on whether a package is well formed:

```sh
usdchecker --arkit piece.usdz      # the profile Apple's platforms hold a model to
usdcat piece.usdz | head -40       # look at the layer
usdtree piece.usdz                 # the prim tree
usdrecord piece.usdz look.png      # render it with someone else's renderer
```

Ollin's own test suite runs `usdchecker --arkit` over a package that carries every light kind, a texture, per-vertex colors, and a physically based material.

### The package, briefly

A `.usdz` is a ZIP archive with extra rules. Nothing in it is compressed, and the layer comes first. Every file inside starts on a 64-byte boundary, so a reader can map the bytes in place. Ollin writes the archive itself instead of going through a system framework, which makes the output **byte-reproducible**. Writing the same scene twice gives the same file, so you can diff or commit a model like any other artifact.

### Reference

| | |
|---|---|
| `scene.write(to:as:metersPerUnit:)` | write a scene as a spatial model, with the extension picking the format |
| `scene.data(as:metersPerUnit:)` | the same, returned as bytes |
| `saveScene(_:to:as:metersPerUnit:)` | the same call from inside a sketch, beside `saveMesh` |
| `OllinApp.spatialScene(of:frame:fps:)` | one frame's 3D draw calls as a `Scene` |
| `OllinApp.exportSpatial(_:to:frame:fps:metersPerUnit:)` | record a frame and write it |
| `SceneFileFormat` | `.usdz` (package) or `.usda` (text layer) |
| `--export-usdz <path>` | the CLI flag, with `--frame N` and `--meters-per-unit U` |

## Spatial video

A model sends the geometry and lets a viewer walk around it. **Spatial video** sends the motion instead, recorded from two eyes at once. That is the only way an animation reads as three-dimensional in a headset. The file uses the same format Apple's platforms record and play: stereo MV-HEVC, with metadata that describes the rig that shot it.

```sh
swift run --package-path Examples Example-3D-Geometry-SpatialVideo --export-spatial piece.mov --seconds 8
```

Each frame is drawn **once** and rendered twice, from two cameras a short distance apart. That distinction matters, because drawing twice would roll the sketch's randomness twice and step every simulation twice. The simulations that are documented as not reproducing frame for frame would then give the two eyes different worlds. With one draw and two renders, both eyes see the same instant.

### The two numbers

A stereo pair needs exactly two numbers. Both are choices about the piece, not settings with one correct value.

**Convergence** is the distance at which the two eyes agree. Whatever sits at that distance appears on the screen plane. Nearer things come out of the screen, and farther things sit behind it. So the convergence decides what the viewer looks *into* rather than *out at*. When you leave convergence unset, Ollin uses the camera's own target, because you are already pointing the camera at the thing the piece is about.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/StereoPair-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/StereoPair.jpg" alt="A plan-view diagram: two eyes at the bottom looking parallel, a horizontal line labeled the screen, and three objects whose sight lines land on the screen as paired marks, crossed for the near object, coincident at the screen, spread apart for the far one" width="680">
</picture>

**Interocular** is how far apart the eyes stand, in world units, and it controls how much depth the viewer sees. Half the distance reads flatter. Twice the distance reads deeper and starts to strain the viewer's eyes. When it is unset, the eyes sit **1% of the frame width apart, measured at the convergence plane**. For a camera with a vanishing point, that default is also the classic comfort rule. Eyes 1% of the frame width apart at the convergence plane end up 1% of the frame width apart at infinity. The far background then separates by less than the distance between a viewer's own eyes, so nothing ever asks the eyes to point outward.

A sketch declares both numbers as an overridden property, the same way it declares its loop or its colors:

```swift
override var stereoGeometry: StereoGeometry {
    StereoGeometry(interocular: 0.1, convergence: 6)
}
```

You can leave either number out and let Ollin derive it. You can also override either one per export (`--interocular X`, `--convergence D`) without changing the other. `StereoGeometry.resolved(for:aspect:)` returns the final values for a given camera. So a sketch can show the spacing it will export with. It can also scale from the derived value:

```swift
let spacing = StereoGeometry.automatic.resolved(for: shot).interocular
```

### What the two cameras do

The two eyes step sideways along the camera's own right axis and keep looking **parallel**. The projection is then shifted back inward, so the two views agree exactly at the convergence distance. That is the rig a stereo film is shot on. Toeing two cameras in (toe-in) at the subject instead sounds equivalent, but it is not. It tilts the two frames against each other and leaves a vertical misalignment at the corners that no viewer can fuse away.

Everything else about the camera is untouched, so a pair renders through the ordinary path. It uses the same lens, the same clipping, and everything else one frame would have used.

### How big is a world unit

```sh
--meters-per-unit 0.01     # the sketch draws in centimetres
```

The file records the distance between the eyes that shot it, in real units. A player scales the depth it shows from that distance. `metersPerUnit` is the same declaration the model exporter takes, and the same rule applies. Nothing is scaled on the way out, and the value only says how to read the numbers already there. A scene drawn in meters uses the default of 1.

### What it does not do

- **An accumulating sketch reads flat**, and the export says so once. The accumulated picture is held in a persistent surface, and there is only one of those, so both eyes receive the same picture. A screen-space accumulation has no depth to give anyway.
- **A 2D sketch reads flat** for the same reason, and the export says so too.
- **Anything the sketch flattened itself during `draw()`** stays where it was flattened, whether that flattening was a `project()`, a `depth(at:)` placement, or a billboard. Those land on the screen plane in both eyes. For the notices and overlays that use them, that is usually what you want.
- Sound is included exactly as it is in an ordinary video export.

### Checking a file

The check that matters is the system's own reading, the one Photos and Quick Look use:

```swift
let options = await AVAssetPlaybackAssistant(asset: AVURLAsset(url: url))
    .playbackConfigurationOptions
options.contains(.spatialVideo)      // true
```

Do not test one of the near neighbors instead. `.stereoMultiviewVideo`, for example, is true for any two-layer file, with or without spatial metadata, so it does not prove the file is spatial. On the command line, `ffprobe -show_entries stream_side_data` prints the baseline, the field of view, and which eye is the hero.

### Reference

| | |
|---|---|
| `OllinApp.exportSpatialVideo(_:to:frames:fps:stereo:metersPerUnit:…)` | render a sketch as spatial video |
| `--export-spatial <path.mov>` | the CLI flag, with `--frames`/`--seconds`, `--fps`, `--skip`, `--interocular`, `--convergence`, `--meters-per-unit`, `--bitrate`, `--quality` |
| `Sketch.stereoGeometry` | the sketch's own declaration, `.automatic` by default |
| `StereoGeometry(interocular:convergence:)` | the two numbers, either one derivable |
| `StereoGeometry.resolved(for:aspect:)` | the final values for a camera |
| `Camera3D.stereoPair(_:aspect:)` | the two cameras a pair renders through |
| `Camera3D.stereoEye(_:interocular:convergence:)` | one of them, by name |

### See also

- [Scenes](../3D/Scenes.md) reads models in, and its tree is the same one this page writes out.
- [Fabrication](./Fabrication.md) writes a single `Mesh` for a 3D printer.
- [Export](./Export.md) covers frames, ordinary video, and the vector formats.
- [3D](../3D/3D.md) and [Camera](../3D/Camera.md) cover the scene and the shot that a stereo pair is taken from.
- `Examples/3D/Geometry/SpatialExport` is a ring of solids that you can write out and open.
- `Examples/3D/Geometry/SpatialVideo` is a colonnade built to show depth, with the two stereo numbers exposed as parameters.
