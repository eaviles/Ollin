#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Depth compositing`</sup>

---

## Depth compositing

In a [3D](./3D.md) frame, 2D drawing lays *over* everything by default — right for a HUD or a caption, wrong for a label or a sprite that lives *in* the scene and should be hidden when something passes in front of it. Depth compositing lets 2D drawing participate in the depth buffer: a 2D mark placed at a world depth occludes — and is occluded by — the 3D geometry around it.

It's opt-in twice over. A frame is only 3D once you set a [`camera`](./3D.md#camera), and 2D drawing only joins the depth buffer once you give it a depth; everything else composites over in draw order exactly as before.

### Contents

- [Placing 2D at a world depth](#depth) — `depth(at:)`, `noDepth`
- [Projecting a world point to the canvas](#project) — `project`
- [Billboards](#billboard) — `withBillboard(at:)`
- [How occlusion reads](#how)
- [Notes](#notes)

<a id="depth"></a>
### Placing 2D at a world depth

`depth(at: worldPoint)` sets the depth of subsequent 2D drawing to a world point's depth in the active 3D scene, so it z-tests against the 3D geometry — hidden where the scene is nearer, drawn over where it's in front. `noDepth()` returns to drawing over (the default). Both are drawing state, scoped by [`withState`](./Drawing.md):

```swift
camera(.orbiting(target: .zero, radius: 5, azimuth: time * 0.3, elevation: 0.3))
drawPointCloud(cloud)

withState {
    depth(at: Vector3(0, 0, 0))   // sit at the origin's depth
    fill(.white)
    drawCircle(width / 2, height / 2, 40)   // occluded by any cloud point in front
}
```

`depth(at:)` only sets the depth — the 2D mark still draws wherever its canvas coordinates put it. To place it *at* the world point on screen too, project the point first (next), or use a [billboard](#billboard), which does both.

The depth is computed against the current frame's camera, so it resets each frame with the camera — set it in `draw()` after the camera, like the camera itself. Without a camera it's a no-op (drawing returns to "over").

<a id="project"></a>
### Projecting a world point to the canvas

`project(worldPoint)` maps a world point through the active camera to its position on the canvas (top-left origin, points), or `nil` if there's no camera or the point is behind it:

```swift
if let p = project(Vector3(1, 0.5, 0)) {
    drawCircle(p, 6)            // a 2D dot at the 3D point's screen position
}
```

Pair it with `depth(at:)` to draw a 2D mark at a 3D point *with* correct occlusion — or reach for `withBillboard`, which combines the two.

<a id="billboard"></a>
### Billboards

`withBillboard(at: worldPoint) { … }` anchors 2D drawing to a world point: it moves the origin to the point's projected canvas position and sets the depth to the point's depth, so 2D drawn inside the closure — in **local** coordinates around the origin — lands at the point and composites with correct occlusion. It's skipped when the point is behind the camera.

```swift
// A numbered tag riding a 3D point, hidden when the point swings behind the scene.
withBillboard(at: orbCenter) {
    fill(.white); drawCircle(0, 0, 14)          // local coords: (0,0) is the anchor
    fill(.black); textAlign(.center, .middle)
    drawText("\(i)", 0, 0)
}
```

It's sugar over `project` + `translate` + `depth(at:)`, scoped by `withState` — reach for the pieces directly when you want the screen position or the depth on their own.

<a id="how"></a>
### How occlusion reads

Occlusion follows the depth buffer *and* draw order. A 2D mark at depth `d` is hidden wherever nearer geometry has already written a smaller depth, and it writes `d` itself, so it hides farther geometry drawn after it. The classic arrangement is to draw the 3D scene first, then the depth-placed 2D over it:

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

The near orb (drawn before the card) shows *over* the card because the card's depth test fails where the orb wrote a nearer value; the far orb is *hidden* by the card. See the [`3D/DepthCompositing`](../Examples/3D/DepthCompositing/) example.

<a id="notes"></a>
### Notes

- **The default is unchanged.** A 2D draw with no depth set still composites over the 3D scene in draw order, and a 2D-only frame (no camera) is untouched.
- **It rides every 2D pipeline.** Shapes, images, text, and particles all honor the depth, since they share the 2D vertex path.
- **Point clouds have gaps.** A 2D mark behind a sparse cloud peeks through the gaps between splats — the depth test is per-fragment, and a gap left the far clear value. Denser clouds (or bigger splats) occlude more solidly.
- **Same limits as 3D.** The accumulation surface (`noClear`) and the live texture hand-off (Syphon, the virtual camera) don't depth-sort yet; keep depth-composited sketches on the live window and the raster/PNG export paths.
