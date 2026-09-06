#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Strand fields`</sup>

---

## Strand fields

Some geometry cannot be a mesh you place. A meadow needs half a million blades, and each blade wants its own height, lean, curve, and sway. The curve is the hard part. An instanced draw can move rigid copies of one shape, but it cannot bend each copy differently along its length. A **`StrandField`** grows every blade inside the draw call itself. There is no vertex buffer, no instance list, and nothing to build. One GPU stage decides, for each tile, what the camera can see and how much detail that tile needs. A second stage then builds the visible ribbons from hashes of each blade's index.

<img src="../../Guide/Images/23-Landscapes/GrassMeadow.jpg" alt="A dense meadow of individually curved grass blades in deep greens, each catching the warm key light differently, with pale boulders half-buried among them and the field dimming into darkness at the horizon" width="640">

```swift
var meadow = StrandField(width: 90, depth: 90, count: 500_000)

override func setup() {
    meadow.bladeHeight = 0.7
    meadow.tipColor = Color(hue: 0.24, saturation: 0.5, brightness: 0.65)
}

override func draw() {
    camera(...)
    directionalLight(...)
    castShadows()
    drawStrands(meadow)        // the whole meadow, grown in-draw
}
```

Blades shade on the solid lit path. They take the current `material(_:)` finish, the scene's lights, image-based lighting, and fog. They also receive cast shadows, so a boulder's shadow falls across the grass. The patch follows the 3D transform stack. The wind runs on the sketch clock, so an export sways exactly as the live window did.

For a reference point, take the example's 500,000-blade meadow, lit, shadowed, and fogged at 1080² on an M2. It draws in ~22.5 ms of GPU per frame, with zero geometry memory and zero per-frame CPU cost. Distance grading saves a further ~15% over full detail everywhere. `Scripts/benchmark.sh strands` reproduces both numbers.

### Contents

- [StrandField](#strandfield) - the patch and its blades
- [What the camera controls](#camera)
- [Notes](#notes)

<a id="strandfield"></a>
### StrandField

A `StrandField` is a value that holds the patch extents, a blade count, and the character of the blades. Every property has a sensible default, so `StrandField(width:depth:count:)` is already a meadow.

```swift
var field = StrandField(width: 30, depth: 30, count: 200_000)
field.bladeHeight = 0.8        // world units, before variance
field.heightVariance = 0.4     // 0 uniform ... 1 wild
field.bladeWidth = 0.05        // at the root; blades taper toward the tip
field.lean = 0.3               // how far a tip leans from vertical
field.swayAmplitude = 0.12        // how far the wind carries a tip
field.swayFrequency = 1.6      // radians per second on the sketch clock
field.lowColor = ...           // root color; tipColor at the tip
field.seed = 3                 // a different lawn
```

`count` is approximate, because the internal tile grid rounds it. Read `field.bladeCount` for the exact number drawn. Two fields with different `seed`s are different lawns.

<a id="camera"></a>
### What the camera controls

The camera decides how much work each tile of the patch takes:

- **Tiles outside the view are skipped whole.** Set `field.isCullingEnabled = false` to draw them anyway. The picture must not change, because a skipped tile was invisible, and the test suite pins that.
- **Distant tiles grow simpler blades.** Between `detailNear` and `detailFar` (world units from the eye) the per-blade segment count falls from 4 to 1. Set `field.isLevelOfDetailEnabled = false` to give every blade full detail everywhere, which is how you measure what the grading saves.

<a id="notes"></a>
### Notes

- The blades exist only inside the draw. They cast no shadows into the maps, but they do *receive* them. The spatial exporter cannot record them, and it says so once. SVG export skips them, as it skips every shaded solid. Strands are surface dressing, so for solids at scale use [instanced meshes and fields](./Instancing.md).
- `makeBatch { }` refuses a strand field. The GPU grows its blades each frame, so there is nothing to retain. Draw it where the batch is drawn.
- You can draw two fields, draw one field twice under different transforms, or change the parameters while the sketch runs. A field is a plain value, and it holds no GPU state to invalidate.
- The [`Grassland`](../../Examples/Rendering/Grassland/Sketch.swift) example draws the 500,000-blade meadow, with boulders shading the grass and a parameter that turns the distance grading on and off.
