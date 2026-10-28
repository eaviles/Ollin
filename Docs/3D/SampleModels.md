#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Sample models`</sup>

---

## Sample models

A rubber duck travels with Ollin. It is there so a material, a light, an environment, a shadow, or a camera move can be tried on a real object before you have one of your own. It lives in its own library, `OllinSampleModels`, rather than in the framework, so an app that never imports it ships none of it. The library mirrors the [sample photographs](../Drawing/SamplePhotos.md). There is one value per model, a `load()` that reads it, and a `credit` that names who made it and the terms it is used under.

```swift
import OllinSampleModels

final class Duck: Sketch {
    var duck = Mesh.sphere(radius: 1)

    override func setup() {
        duck = SampleModel.duck.load().normalized(scale: 3)
    }

    override func draw() {
        background(Color(hex: 0x10141B))
        cameraShowcase(radius: 6)
        environment(.studio.lightingOnly())
        fill(.white)
        withState { rotateY(time * 0.3); drawMesh(duck) }
    }
}
```

### Contents

- [The duck](#duck) - what it is, and what it is good for
- [SampleModel](#samplemodel) - `load`, `url`, `credit`, `all`
- [Terms](#terms) - the license the model is used under

<a name="duck"></a>

### The duck

**`.duck`** is a smooth yellow rubber duck with an orange beak and a painted eye, the bath toy. Its paint and its shading come in one texture. It shows a material, a light, or an environment the way a photograph shows a filter. Everyone already knows what a rubber duck looks like, which leaves the eye free to read what the sketch did to it. It is under two thousand triangles, so it draws and casts shadows at any count. Its file is a quarter of a megabyte with the texture packed inside.

A model comes back as its author saved it, in its author's own units and position. `normalized(scale:)` recenters it on the origin and scales its longest side to the world units you ask for. That is the one call to make before drawing it. Keep the `fill` white so its own colors show. A colored fill tints it.

The `3D/Geometry/LoadedMesh` example draws it. The space bar cycles it with two other bundled files, a textured cube and a crystal that carries no material. Chapter 28 of the Guide starts its mesh lesson with it.

<a name="samplemodel"></a>

### SampleModel

`SampleModel` is a value with a `name`, a `subject` in a few words, and a `credit`. **`load()`** reads the model from the library's bundle into a `Mesh`, material and texture included. It reads the file on every call, so keep the result in a property rather than calling it from `draw()`. **`url`** is where the file is, for a loader that takes a path or a URL. `loadScene(url)` keeps the file's node structure instead of merging it, and a tool outside the framework can read the same bytes. **`all`** lists every bundled model.

Each **`credit`** is a `SampleModel.Credit` naming the `artist`, the `source` page the model came from, the `license`, and the `licenseURL`. `credit.line` is the one-line form, "Model by Alexandr (CC BY 4.0)", ready to draw at the foot of a frame.

```swift
drawText(SampleModel.duck.credit.line, at: Vector2(24, canvasRectangle.height - 24))
```

<a name="terms"></a>

### Terms

The duck is used under Creative Commons Attribution 4.0, which asks that its author be credited. The credit is in [`THIRD-PARTY-NOTICES.md`](../../THIRD-PARTY-NOTICES.md) beside the photographs, in `ATTRIBUTION.md`, and in code as `SampleModel.credit`. So a sketch that draws the duck can draw the line its artist is owed. The model was re-packed for the bundle. Its loose files were folded into one `.glb` and its texture re-encoded at its own 1024 pixels, with nothing else changed.

---

Example sketches: [`Examples/3D/Geometry/LoadedMesh`](../../Examples/3D/Geometry/LoadedMesh/Sketch.swift). For loading a file of your own, see [Meshes from file](./3D.md#load).
