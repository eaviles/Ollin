# Bringing a scene over

You have a 3D scene, such as a model somebody built, a room laid out in Blender, or a file exported from a design tool. Ollin can already [load one whole](../3D/Scenes.md) and draw it with `drawScene`. This command does something different: it writes you a sketch.

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

Both directions are useful, and they end in different places. `loadScene` keeps the file as the source of truth, so re-exporting from the design tool updates the sketch. The import instead hands you **source you own**. The camera, the lights and every placement become lines you can animate, put on a parameter, or delete.

## What becomes source, and what does not

The split follows one rule: **structure becomes code, geometry stays in the file.**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/22-Meshes/SceneAsSource-dark.jpg">
  <img src="../../Guide/Images/22-Meshes/SceneAsSource.jpg" alt="Left, the generated draw() with its camera call, its lights and its nested withState blocks. Right, the same scene drawn from those placements: a torus on a pedestal beside a lamp and a blue sphere" width="680">
</picture>

Structure is everything you would otherwise type by hand. The camera comes out as a `Camera3D` with its own numbers, and each light comes out as the factory call that makes it. Each node becomes a `withState` block that holds the moves that put it where the file put it. Those blocks nest the way the file nests them, so a group still turns as one thing.

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

Geometry does not become source, because a mesh is not something you edit as text. The sketch reads the file once for its meshes, then places them itself. That is what `drawPart` does, and the part names it takes are written into the sketch:

```swift
private static let partNames = ["floor", "pedestal", "sculpture", "orb", "lampPost", "lampShade"]
```

If the scene repeats a name, or leaves one blank, each part still gets a name of its own. A scene with no geometry at all, a lighting rig for example, needs no scene file and does not get one.

## Where the scene comes from

The scene can be in any format Ollin can open: glTF (`.gltf`, `.glb`), USD (`.usd`, `.usda`, `.usdc`, `.usdz`), and the rest of the [scene list](../3D/Scenes.md). A file that will not open is refused before anything is written.

The other flags work as usual. `--kind single-file` writes one loose `.swift` with the scene beside it, and `--canvas` sets the canvas.

## What is left behind

The command prints what could not come over before it writes anything, and the sketch carries the same list as comments. Three of the things left behind are worth knowing about.

**A material stays with its mesh.** Each part keeps the material the file gave it, which is why the sketch calls no `fill`. To override one, call `fill` or [`material`](../3D/3D.md) inside that part's block.

**A mesh with several materials is drawn whole, in the first one.** `drawScene` draws each slice in its own material. A part placed by hand has only one material. The block for that part is marked, so you can see the difference where it happens.

**Animation, skins and blend shapes do not come over.** They belong to the file, and a written-out placement has nothing that drives them. Load the scene whole when you need them:

```swift
scene.apply(scene.animations[0], at: time)
drawScene(scene)
```

There is one rarer case. A transform that is not a translate, a rotate and a scale, usually a shear, cannot be written as those three calls. The block carries the closest fit it can and says so.

## Once it runs

What you get is an ordinary sketch, so you can put a placement on a parameter:

```swift
@Param(-2...2) var lampX = -1.45
```

You can also turn something every frame, animate the camera, or swap a part for a shape you draw yourself. Once every part is geometry of your own, delete the scene file and the loader with it. Nothing in the sketch marks it as generated code.

## See also

- [Scenes](../3D/Scenes.md) - loading a scene whole, with its animation and skins
- [3D](../3D/3D.md) - the camera, lights, materials and transforms the generated calls use
- [Project generator](ProjectGenerator.md) - the other ways to start a project
- [Bringing a shader over](ShaderImport.md) - the same idea, for a fragment shader
