# Bringing a scene over

You have a 3D scene: a model somebody built, a room laid out in Blender, a file exported from a design tool. Ollin can already [load one whole](../3D/Scenes.md) and draw it with `drawScene`. This does the other thing. It writes you a sketch.

```sh
ollin new Yard --from-scene yard.usdz
```

You get a folder that builds and runs, with the scene file copied in beside the sketch:

```
Yard/
  Package.swift
  Sources/Yard/Sketch.swift
  Sources/Yard/yard.usdz
```

Both directions are worth having, and they end in different places. `loadScene` keeps the file as the source of truth, so re-exporting from the design tool updates the sketch. This hands over **source you own**, so the camera, the lights and every placement become lines you can animate, put on a knob, or delete.

## What becomes source, and what does not

The split runs along one line: **structure becomes code, geometry stays in the file.**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/22-Meshes/SceneAsSource-dark.jpg">
  <img src="../../Guide/Images/22-Meshes/SceneAsSource.jpg" alt="Left, the generated draw() with its camera call, its lights and its nested withState blocks. Right, the same scene drawn from those placements: a torus on a pedestal beside a lamp and a blue sphere" width="680">
</picture>

Structure is everything a person would otherwise be typing. The camera comes out as a `Camera3D` with its own numbers. Each light comes out as the factory that makes it. Each node becomes a `withState` block holding the moves that put it where the file put it. Blocks nest the way the file nests them, so a group still turns as one thing.

```swift
// lamp
withState {
    translate(-1.45, 0, -0.55)
    // lampPost
    withState {
        translate(0, 0.75, 0)
        drawPart("lampPost")
    }
    // lampShade
    withState {
        translate(0, 1.55, 0)
        drawPart("lampShade")
    }
}
```

Geometry does not become source, because a mesh is not something anybody edits as text. The sketch reads the file once for its meshes and places them itself. That is what `drawPart` does, and the names it uses are written into the sketch:

```swift
private static let partNames = ["floor", "pedestal", "sculpture", "orb", "lampPost", "lampShade"]
```

A file the scene repeats a name in, or leaves one blank, still gets one name per part. A scene carrying no geometry at all, a lighting rig for instance, needs no file and gets none.

## Where the scene comes from

Any format Ollin can open: glTF (`.gltf`, `.glb`), USD (`.usd`, `.usda`, `.usdc`, `.usdz`), and the rest of the [scene list](../3D/Scenes.md). A file that will not open is refused before anything is written.

The other flags work as usual, so `--kind single-file` writes one loose `.swift` with the scene beside it, and `--canvas` sets the canvas.

## What is left behind

The command prints what could not come over before it writes anything, and the sketch carries the same list as comments. Three things are worth knowing.

**A material rides its mesh.** Each part keeps the material the file gave it, which is why the sketch calls no `fill`. Call `fill` or [`material`](../3D/3D.md) inside a block to override one.

**A mesh wearing several materials is drawn whole, in the first.** `drawScene` draws each slice in its own material; a part placed by hand has one. The block for such a part is marked, so the difference is visible where it happens.

**Animation, skins and blend shapes do not come over.** They are the file's own, and nothing in a written-out placement drives them. Load the scene whole for those:

```swift
scene.apply(scene.animations[0], at: time)
drawScene(scene)
```

One more, rarer: a transform that is not a translate, a rotate and a scale (a shear, usually) cannot be written as those three. The block carries the closest fit and says so.

## Once it runs

It is an ordinary sketch. Put a placement on a knob:

```swift
@Param(-2...2) var lampX = -1.45
```

Turn something every frame, animate the camera, or swap a part for a shape you draw yourself. Once every part is geometry of your own, delete the file and the loader with it. Nothing in the sketch knows it was generated.

## See also

- [Scenes](../3D/Scenes.md) - loading a scene whole, with its animation and skins
- [3D](../3D/3D.md) - the camera, lights, materials and transforms the generated calls use
- [Project generator](ProjectGenerator.md) - the other ways to start a project
- [Bringing a shader over](ShaderImport.md) - the same idea, for a fragment shader
