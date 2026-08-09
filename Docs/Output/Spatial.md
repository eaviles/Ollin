#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Spatial`</sup>

---

## Spatial export

A 3D sketch is a scene, and a frame of it is a photograph of that scene. Writing one out as USDZ sends the scene instead: a model that opens in Quick Look from the Finder or a message, stands on a real table through AR, and drops into a visionOS app or Reality Composer. It is the three-dimensional sibling of the [fabrication](./Fabrication.md) writers, which send a single mesh to a printer, and of the [vector exporters](./Export.md#vector-svg), which send a flat frame to a plotter.

```sh
swift run Example-3D-Geometry-Solids --export-usdz piece.usdz
```

That is the whole thing. No window, no GPU: the sketch runs headlessly to the frame you name, and its 3D draw calls are collected into a model.

### The two ways in

A frame and a scene are both exportable, and both go through one writer.

```swift
// One frame of a sketch, recorded as it draws.
OllinApp.exportSpatial(sketch, to: "piece.usdz", frame: 120)

// Any Scene: one you loaded, one you built, one you recorded.
scene.write(to: "piece.usdz")
saveScene(scene, to: "piece.usdz")            // the same, from inside a sketch
```

`OllinApp.spatialScene(of:frame:)` is the middle step, and it is worth knowing about: it hands back an ordinary [`Scene`](../3D/Scenes.md), the same kind `loadScene` gives you. So a recorded frame can be read, edited, drawn again with `drawScene`, or written later.

```swift
var scene = OllinApp.spatialScene(of: sketch, frame: 120)
scene["piece3"]?.position.y += 0.5
scene.write(to: "piece.usdz")
```

The recorder is why the frame path and the file path cannot drift: there is one writer, and the recorder feeds it.

### Size is a declaration

A model file records how big one scene unit is, and Ollin does not guess. Nothing is scaled on the way out; `metersPerUnit` says how to read the numbers that are there.

```swift
scene.write(to: "piece.usdz", metersPerUnit: 1)      // one unit is a meter (the default)
scene.write(to: "piece.usdz", metersPerUnit: 0.05)   // desk-sized
```

At the default of 1, a sphere of radius 1 arrives as a two-meter ball, which is right for something meant to fill a room and much too big for something meant to sit on a table. Most 3D sketches work at unit scale, so `0.01` to `0.1` is the usual range for a model someone will place in a room.

### Choosing a format

| | holds | reach for it when |
|---|---|---|
| `.usdz` | the layer and its textures, in one file | you are sending it, opening it in Quick Look, or placing it in AR. The only one AR Quick Look reads. |
| `.usda` | the scene as readable text, one file | you want to look at what was written, diff two exports, or hand it to a tool. Textures have nowhere to go, so they are left out with a note. |

Both are USD, and the extension picks between them.

### What travels

- **Meshes**, with the transform that placed them. Each `drawMesh` becomes one node, and the geometry stays in its own space rather than being baked flat, so the model has the same structure the frame drew with. A [loaded scene](../3D/Scenes.md) keeps its tree.
- **Surfaces**: the fill color, the mesh's own base color, per-vertex colors, texture coordinates, and textures (inside a `.usdz`).
- **The finish**, as far as the format goes. A [physically based material](../3D/3D.md#physically-based-metal-and-roughness) maps straight across, since USD describes a surface the same way: metallic, roughness, opacity, index of refraction, clearcoat. Glass travels as transparency.
- **The camera** the frame was drawn through, and **the lights** that shaded it, including the auto-lit default rig if the sketch set none. Every light kind maps to its USD counterpart.

### What does not, and says so

Nothing is dropped quietly. Anything the format cannot hold prints one note naming it.

- **2D drawing.** Text, shapes, and overlays are not geometry in a scene. A labelled diagram exports as the solids without the labels.
- **Point clouds, GPU particles, and raymarched fields.** These are not surfaces. `isosurface(at:in:_:)` and `particleSurface(of:)` turn a field or a cloud into a mesh, which does travel.
- **Stylized finishes.** Toon, gooch, matcap, iridescence, sparkle, rim, sheen, and subsurface are ways of shading rather than descriptions of a material. The surface exports with its color and how shiny it is: a stylized finish's `shininess` converts to roughness through the same curve the renderer's own area lights use, so a polished surface stays polished.
- **Animation and skinning.** One pose is written, the one the scene is holding. Export several frames if you want several poses.
- **The environment.** An [image-based lighting](../3D/3D.md#environment-lighting) environment is not written, and this is usually what you want: a viewer lights a model with its own surroundings, which in AR is the actual room the model is standing in.

### Reading it back

Ollin reads USD as well as it writes it, so a written model opens again:

```swift
let scene = loadScene("piece.usdz")
drawScene(scene!)
```

This is the round trip the writer is tested against. Geometry, node transforms, materials, textures, cameras, and every light kind go out and come back as themselves, which is what keeps the two halves honest: a writer that drifts from its reader is wrong in a way nothing else notices.

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

A `.usdz` is a ZIP with rules: no compression, every file starting on a 64-byte boundary so a reader can map the bytes in place, and the layer first. Ollin writes it itself rather than going through a system framework, which means the output is **byte-reproducible**: writing the same scene twice gives the same file, so a model can be diffed or committed like any other artifact.

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

### See also

- [Scenes](../3D/Scenes.md) reads models in, which is the same tree this writes out.
- [Fabrication](./Fabrication.md) writes a single `Mesh` for a 3D printer.
- [Export](./Export.md) covers frames, video, and the vector formats.
- `Examples/3D/Geometry/SpatialExport` is a ring of solids you can write out and open.
