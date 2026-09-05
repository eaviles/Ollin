#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Retained batches`</sup>

---

## Retained batches

Every frame, each draw call records its geometry, and the renderer uploads that geometry to the GPU. This per-frame work is what makes motion the default, and for most sketches it is far from the bottleneck. Some sketches, though, draw something heavy that never changes: a texture of a hundred thousand dots, a long traced orbit, a fixed point cloud. Recording that again every frame is wasted work. A **`Batch`** records the drawing once and replays it from geometry that is already on the GPU. A replay does no per-shape recording, no tessellation, and no upload.

```swift
var stars: Batch!

override func setup() {
    stars = makeBatch {
        for _ in 0 ..< 200_000 {
            fill(Color(white: 1, alpha: random(0.2, 0.9)))
            drawCircle(random(width), random(height), random(0.5, 1.5))
        }
    }
}

override func draw() {
    background(.black)
    drawBatch(stars)        // replays for (almost) free
}
```

As a reference point, take 150,000 circles. On the ordinary path they cost about 13.5 ms of CPU per frame in a release build on an M2. That caps the frame rate at about 74 fps before anything else happens. The same field replayed as a `Batch` costs about 0.003 ms. The [`RetainedBatch`](../../Examples/Rendering/RetainedBatch/Sketch.swift) example has a parameter that switches between the two paths, so you can watch the difference live in the inspector.

A `Batch` is different from the collection calls such as [`drawCircles(_:)`](./Drawing.md#batches). Those draw many shapes in one call but still record them every frame, so use them when the drawing changes every frame. Use a `Batch` when the drawing stays the same.

### Contents

- [makeBatch](#makebatch) - record a drawing once
- [drawBatch](#drawbatch) - replay it, place it, stamp it
- [What records](#what-records)
- [Notes](#notes)

<a id="makebatch"></a>
### makeBatch(_:) → Batch

Record everything drawn inside the block into a reusable `Batch`. Call it once, usually in `setup()`, and keep the result. A `Batch` is **persistent**, like a `Feedback` layer, so recording it again every frame rebuilds the geometry and gains nothing. The contents cannot change once recorded, so when the drawing you want changes, record a new batch.

The block records in its own canvas-space frame, and the transform inside it starts at the identity. So you can build the drawing around whatever origin suits it. For content you mean to stamp, the origin itself is a good anchor. The block also handles drawing state the way [`withState { }`](./Drawing.md#isolated) does. The state in force when the block starts carries in, and any change made inside is restored when the block ends. The replay keeps per-shape state set inside the block, such as fill, stroke, or blend mode.

```swift
let motif = makeBatch {
    noStroke()
    fill(.white)
    drawStar(0, 0, 30, 12, points: 5)      // built around the origin,
    stroke(.white)                          // ready to stamp anywhere
    noFill()
    drawCircle(0, 0, 40)
}
```

<a id="drawbatch"></a>
### drawBatch(_:)

Replay a recorded batch. The transform in force when you call `drawBatch` moves the **whole recording as a unit**. So one recording can be placed, rotated, resized, and stamped any number of times per frame:

```swift
override func draw() {
    background(.black)
    for i in 0 ..< 12 {
        withState {
            translate(width / 2, height / 2)
            rotate(Double(i) / 12 * .tau)
            translate(0, -300)
            scale(0.5 + Double(i) * 0.05)
            drawBatch(motif)
        }
    }
}
```

A replay composites in draw order with everything else, exactly like the calls it recorded. Drawing made before a `drawBatch` sits under it, and drawing made after sits over it. The active layer ([`withTarget`](./Effects.md)), the clip region ([`withClip`](./Drawing.md#clip)), and [`depth(at:)`](../3D/DepthCompositing.md) all apply to the replay as they would to any draw call. Analytic SDF shapes keep their sharp edge of about 1px under any replay rotation or scale. Tessellated fills and strokes transform like any baked geometry, so a large scale-up eventually shows the tessellation.

A batch also replays into vector exports. `--export-svg` and `--export-pdf` insert the recorded drawing under the draw-time transform, so a plotter file gets every stamp.

<a id="what-records"></a>
### What records

The whole 2D drawing surface records: analytic SDF shapes and their gradients, fills, strokes, curves, polygons, polylines, text, images, and [SDF combinator](./Combinators.md) fields. Text records in both the outline mode and the atlas mode. Point clouds record too. The draw-time transform is 2D and leaves them untouched, so they replay through whichever camera is active that frame.

A few things are per-frame by nature, so the recording leaves them out and reports that once. Those things are meshes and raymarched 3D fields, GPU particles, layer blocks such as `withTarget`, clipping, and `background(_:)`. Meshes and fields are left out because they are tied to the frame's shadow and reflection passes. Particles are left out because they already live on the GPU. Draw those where the batch is *drawn*, not inside the recording.

A [`symmetry(_:)`](./Drawing.md#symmetry) set inside the block folds the content recorded there. But symmetry active when you call `drawBatch` does not fold the replay.

<a id="notes"></a>
### Notes

- **Record in `setup()`.** The point of a batch is to make it once and keep it. Recording inside `draw()` works, but it repeats the recording every frame, which is the work the batch exists to avoid.
- **The inspector's per-frame counts drop to zero** for retained content. Those counters show what the frame *records*, and a replayed batch records nothing, so the counters report the saving directly.
- **A live layer freezes when recorded.** A `drawImage` of a live source records that texture as it stands when the batch is *drawn*. A render target's `.image` and a video frame both count as live sources. The recording does not repeat the per-frame layer work, so keep live layers outside it.
- **Variations and reload re-record on their own.** `setup()` runs again on a seed change or a live reload. The batches then rebuild with the new content, and the old GPU buffers are released with the old handles.
