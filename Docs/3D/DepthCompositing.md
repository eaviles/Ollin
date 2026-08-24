#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Depth compositing`</sup>

---

## Depth compositing

In a [3D](../3D/3D.md) frame, 2D drawing lays *over* everything by default. That is right for a HUD or a caption. It is wrong for a label or a sprite that lives *in* the scene and should be hidden when something passes in front of it. Depth compositing lets 2D drawing join the depth buffer. A 2D mark placed at a world depth occludes the 3D geometry around it, and is occluded by it in turn.

It's opt-in twice over. A frame is only 3D once you set a [`camera`](../3D/3D.md#the-camera), and 2D drawing only joins the depth buffer once you give it a depth. Everything else composites over in draw order exactly as before.

There are two scenes to composite against. One is a **3D-camera** scene, such as a point cloud you drew. The other is a **depth-map** scene, a depth feed like a webcam depth model or an `RGBDFrame`. They share the same depth buffer and the same occlusion rule. They differ only in how you set a 2D mark's depth, by a world point or by a normalized value.

<img src="../../Guide/Images/27-DepthAndThePhone/DepthCompositing.jpg" alt="Three colored pillars at increasing distances against a near-black background, each encircled by a white ring of the same size. Every ring passes behind its own pillar and is cut where the pillar covers it, and each pillar top carries a small numbered white tag" width="680">

### Contents

- [Placing 2D at a world depth](#depth) - `depth(at:)`, `noDepth()` (a 3D-camera scene)
- [Projecting a world point to the canvas](#project) - `project`
- [Billboards](#billboard) - `withBillboard(at:)`
- [A depth-map scene](#scene) - `drawDepthScene`, `depth(_:)` (a depth feed)
- [A metric depth scene](#metric) - `Camera3D.fromIntrinsics`, `drawDepthScene(_:)` (true meters)
- [How occlusion reads](#how)
- [Notes](#notes)

<a id="depth"></a>
### Placing 2D at a world depth

`depth(at: worldPoint)` sets the depth of subsequent 2D drawing to a world point's depth in the active 3D scene. The mark then z-tests against the 3D geometry: hidden where the scene is nearer, drawn over where it's in front. `noDepth()` returns to drawing over, the default. Both are drawing state, scoped by [`withState`](../Drawing/Drawing.md):

```swift
camera(.orbiting(target: .zero, radius: 5, azimuth: time * 0.3, elevation: 0.3))
drawPointCloud(cloud)

withState {
    depth(at: Vector3(0, 0, 0))   // sit at the origin's depth
    fill(.white)
    drawCircle(width / 2, height / 2, 40)   // occluded by any cloud point in front
}
```

`depth(at:)` only sets the depth, and the 2D mark still draws wherever its canvas coordinates put it. To place it *at* the world point on screen too, project the point first, as the next section shows. Or use a [billboard](#billboard), which does both.

The depth is computed against the current frame's camera, so it resets each frame with the camera. Set it in `draw()` after the camera, the way you set the camera itself. Without a camera it's a no-op, and drawing returns to "over".

<a id="project"></a>
### Projecting a world point to the canvas

`project(worldPoint)` maps a world point through the active camera to its position on the canvas, top-left origin, in points. It returns `nil` if there's no camera or the point is behind it:

```swift
if let p = project(Vector3(1, 0.5, 0)) {
    drawCircle(center: p, radius: 6)   // a 2D dot at the 3D point's screen position
}
```

Pair it with `depth(at:)` to draw a 2D mark at a 3D point *with* correct occlusion, or reach for `withBillboard`, which combines the two.

<a id="billboard"></a>
### Billboards

`withBillboard(at: worldPoint) { … }` anchors 2D drawing to a world point. It moves the origin to the point's projected canvas position and sets the depth to the point's depth. So 2D drawn inside the closure, in **local** coordinates around the origin, lands at the point and composites with correct occlusion. It's skipped when the point is behind the camera.

```swift
// A numbered tag riding a 3D point, hidden when the point swings behind the scene.
withBillboard(at: orbCenter) {
    fill(.white); drawCircle(0, 0, 14)          // local coords: (0,0) is the anchor
    fill(.black); textAlign(.center, .middle)
    drawText("\(i)", 0, 0)
}
```

It's sugar over `project` + `translate` + `depth(at:)`, scoped by `withState`, so reach for the pieces directly when you want the screen position or the depth on their own.

<a id="scene"></a>
### A depth-map scene

The other scene to composite against isn't 3D geometry you drew. It's a **depth feed**: a color image paired with a depth map, from a webcam depth model or an `RGBDFrame`. `drawDepthScene(color:depth:)` draws the color as the backdrop *and* writes the depth map into the depth buffer. So 2D drawn afterward is occluded by the scene, and a mark behind a nearer subject is hidden by it.

```swift
// `depth` is a gray map, white nearest by default.
drawDepthScene(color: cameraFrame, depth: depthMap)

// A mark at a normalized scene depth: 0 is nearest, 1 is farthest.
depth(0.5)
drawCircle(width / 2, height / 2, 40)   // hidden where the scene is nearer than mid
```

This needs no 3D camera, because the depth scene allocates the depth buffer on its own. Where a 3D-camera scene uses `depth(at: worldPoint)`, a depth-map scene uses **`depth(_ t:)`** with a normalized `t`, `0` nearest and `1` farthest. The map's depth is a relative range, not metric world units. `drawDepthScene` fills the whole canvas by default. Pass `in: rect` to letterbox a feed into a fitted rectangle, and `whiteIsNear: false` if the map encodes far as white.

The color image and the depth map usually come from the same source, so they line up. That source is either a depth model run over a camera frame, or an `RGBDFrame`'s `color` beside a gray image of its `depth`. The [`3D/DepthOcclusion`](../../Examples/3D/Depth/DepthOcclusion/) example hangs a field of discs at a draggable depth plane in front of a live webcam. Whoever stands nearer than the plane occludes them.

<a id="metric"></a>
### A metric depth scene

A normalized `depth(_ t:)` is enough to hide a sprite behind a nearer subject, but it can't say *how far*. `t` is a relative 0…1 rather than a distance. When the feed is a true depth camera, such as a LiDAR iPhone, its `RGBDFrame` carries **metric** depth in meters and the lens `intrinsics` that took it. Build a camera from those intrinsics and the whole scene shares **one metric space**. That covers a drawn point cloud, the depth feed, and any object you place. So you can put something *1.5 m in front of the camera* and have the feed occlude it at exactly that distance.

```swift
guard let frame = device.latestFrame else { return }       // an RGBDFrame (meters)

// A camera from the feed's own lens. A point cloud, the depth scene, and any
// placed object now live in one space measured in meters.
camera(.fromIntrinsics(frame.intrinsics))

// The color picture as the backdrop AND the frame's metric depth written into
// the depth buffer (this overload takes the RGBDFrame, not a gray Image).
drawDepthScene(frame)

// A marker at a true world point (1 m ahead, 0.2 m up), hidden the moment
// something nearer than 1 m passes in front of it.
withBillboard(at: Vector3(0, 0.2, -1)) {
    fill(.white); drawCircle(0, 0, 24)
}
```

The key difference from the gray-map scene is how depth is placed. Use **`depth(at: worldPoint)`** in real meters, or `withBillboard`, which projects *and* sets the depth, rather than the normalized `depth(_ t:)`. The same metric `Camera3D` drives both the feed's depth and the object's. `Camera3D.fromIntrinsics` sits the camera at the origin looking down −z, exactly where `RGBDFrame.pointCloud(...)` and `unproject` put their points. So a metric `drawDepthScene` and a `drawPointCloud` of the same frame land on top of each other. Move the camera's `eye`/`target` afterward to orbit a drawn cloud, or leave it at the default to keep it aligned with a depth-scene backdrop.

Two practical notes. The metric overload **needs a camera**, since it reads the near/far that map meters onto the depth buffer, and `fromIntrinsics` is the matching one. Without a camera it's a no-op. It also **letterboxes the feed into the canvas** by the feed's own aspect. The picture is never stretched, whatever the `canvasSize` or the phone's orientation. The metric camera letterboxes to match, so placed geometry stays glued to the picture, with bars where the aspects differ. The [`3D/MetricDepthScene`](../../Examples/3D/Depth/MetricDepthScene/) example floats a grid of markers at a draggable metric plane in a live LiDAR feed. Stepping within that many meters of the camera blocks them.

<a id="how"></a>
### How occlusion reads

Occlusion follows the depth buffer *and* draw order. A 2D mark at depth `d` is hidden wherever nearer geometry has already written a smaller depth. It writes `d` itself, so it hides farther geometry drawn after it. The classic arrangement is to draw the 3D scene first, then the depth-placed 2D over it:

```
        camera looks  ──►
        ┌─────────────────────────────┐
        │   ● near orb (small depth)   │   drawn first, writes depth
        │        ┌───────────┐         │
        │        │  2D card  │  depth d │   tests ≤ d: passes over the far orb,
        │        └───────────┘         │   fails behind the near orb
        │              ● far orb (big depth)   hidden by the card
        └─────────────────────────────┘
```

The near orb was drawn before the card, so it shows *over* it. The card's depth test fails where the orb wrote a nearer value. The far orb is *hidden* by the card. See the [`3D/DepthCompositing`](../../Examples/3D/Depth/DepthCompositing/) example.

<a id="notes"></a>
### Notes

- **The default is unchanged.** A 2D draw with no depth set still composites over the 3D scene in draw order, and a 2D-only frame with no camera is untouched.
- **It rides every 2D pipeline.** Shapes, images, text, and particles all honor the depth, since they share the 2D vertex path.
- **Point clouds have gaps.** A 2D mark behind a sparse cloud peeks through the gaps between splats, because the depth test is per-fragment and a gap left the far clear value. Denser clouds or bigger splats occlude more solidly.
- **Same limits as 3D.** The accumulation surface (`noClear`) and the live texture hand-off (Syphon and the virtual camera) don't depth-sort yet. Keep depth-composited sketches on the live window and the raster/PNG export paths.
