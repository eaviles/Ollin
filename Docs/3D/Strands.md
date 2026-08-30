#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Strand fields`</sup>

---

## Strand fields

Some geometry cannot be a mesh you place. A meadow needs half a million blades, each with its own height, lean, curve, and sway, and the curve is the problem: an instanced draw can move rigid copies of one shape, but it cannot bend each copy differently along its length. A **`StrandField`** grows every blade inside the draw call itself. There is no vertex buffer, no instance list, and nothing to build: a GPU stage decides per tile what the camera can see and how much detail it deserves, and a second stage synthesizes the visible ribbons from hashes of each blade's index.

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

Blades shade on the solid lit path: they take the current `material(_:)` finish, the scene's lights, image-based lighting, and fog, and they receive cast shadows, so a boulder's shadow falls across the grass. The patch rides the 3D transform stack. The wind is the sketch clock, so an export sways exactly as the live window did.

As a reference point, the example's 500,000-blade meadow, lit, shadowed, and fogged at 1080² on an M2, draws in ~22.5 ms of GPU per frame, with zero geometry memory and zero per-frame CPU cost. Distance grading saves a further ~15% over full detail everywhere (`Scripts/benchmark.sh strands` reproduces both numbers).

### Contents

- [StrandField](#strandfield) - the patch and its blades
- [What the camera controls](#camera)
- [Notes](#notes)

<a id="strandfield"></a>
### StrandField

A value: patch extents, a blade count, and the blades' character. Every field has a sensible default, so `StrandField(width:depth:count:)` is already a meadow.

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

`count` is approximate (the internal tile grid rounds it); `field.bladeCount` is the exact number drawn. Two fields with different `seed`s are different lawns.

<a id="camera"></a>
### What the camera controls

The camera runs the economy, per tile of the patch:

- **Tiles outside the view are skipped whole.** `field.isCullingEnabled = false` draws them anyway; the picture must not change (a skipped tile was invisible), and the test suite pins that.
- **Distant tiles grow simpler blades.** Between `detailNear` and `detailFar` (world units from the eye) the per-blade segment count falls from 4 to 1. `field.isLevelOfDetailEnabled = false` gives every blade full detail everywhere, the honest way to measure what the grading saves.

<a id="notes"></a>
### Notes

- The blades exist only inside the draw. They cast no shadows into the maps, though they do *receive* them. The spatial exporter cannot record them and says so once, and SVG export skips them like every shaded solid. Strands are surface dressing; for solids at scale, reach for [instanced meshes and fields](./Instancing.md).
- `makeBatch { }` refuses a strand field. Its blades are grown by the GPU each frame, so there is nothing to retain. Draw it where the batch is drawn.
- Draw two fields, draw one twice under different transforms, or mutate the knobs live. A field is a plain value with no GPU state to invalidate.
- The [`Grassland`](../../Examples/Rendering/Grassland/Sketch.swift) example is the 500,000-blade meadow with boulders shading the grass and a knob that flips the distance grading.
