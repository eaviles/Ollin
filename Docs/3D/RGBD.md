#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `RGBD`</sup>

---

## RGBD frames and depth-lifted pose

A color image, a depth map, and the intrinsics that tie them together — an **RGBD frame** — is the shape every depth source produces: a [Record3D](../3D/Record3D.md) `.r3d` file, its live USB stream, a webcam paired with a depth model, an iPhone capture app. `RGBDFrame` is that shape, in the `Ollin` core, so anything that lifts the 2D picture into 3D reads one type regardless of where the depth came from.

Two things come out the other end: a **point cloud** (every depth pixel unprojected — see [3D](../3D/3D.md#clouds)) and a **single lifted point** — a tracked joint, a tapped pixel — back-projected to its true metric position. The latter is what makes **depth-lifted pose**: a flat 2D skeleton placed at its real distance in space.

```swift
import Ollin
import OllinVision     // BodyTracker (the 2D pose)
import OllinRecord3D   // a depth source

final class Pose: Sketch {
    let device = Record3DDevice()
    lazy var bodies = BodyTracker(device)

    override func setup() { device.start(); _ = bodies }

    override func draw() {
        background(Color(white: 0.04))
        guard let frame = device.latestFrame else { return }

        let pose = bodies.bodies.first?.lifted(through: frame)
        camera(.orbiting(target: pose?.center ?? .zero, radius: 2.5, azimuth: time * 0.3))
        drawPointCloud(frame.pointCloud())     // the person, as depth points
        if let pose { drawPointCloud(pose.cloud()) }   // the skeleton, same space
    }
}
```

### Contents

- [The RGBD frame](#frame) — `RGBDFrame`, `CameraIntrinsics`, `DepthConfidence`
- [Lifting one point](#unproject) — `unproject(normalized:)`, `depth(atNormalizedX:y:)`
- [Depth-lifted pose](#pose) — `Body.lifted(through:)`, `LiftedPose`
- [The coordinate convention](#space)
- [What's here, what's ahead](#ahead)

<a name="frame"></a>
## The RGBD frame

`RGBDFrame` carries a color [`Image`](../Drawing/Images.md), a metric depth map (meters, row-major from the top-left), an optional per-pixel confidence map, and the depth-grid [`CameraIntrinsics`](#space).

```swift
struct RGBDFrame {
    let color: Image              // usually higher-res than the depth map
    let depth: [Float]            // metric meters, row-major, depthWidth × depthHeight
    let confidence: [UInt8]?      // 0/1/2 per pixel, or nil
    let depthWidth, depthHeight: Int
    let intrinsics: CameraIntrinsics   // already scaled to the depth grid

    func pointCloud(minimumConfidence:depthRange:step:pointSize:) -> PointCloud
    func unproject(normalized: Vector2, radius: Int = 2) -> Vector3?
    func depth(atNormalizedX: Double, y: Double, radius: Int = 2) -> Double?
}
```

You rarely build one by hand — a depth source hands it to you ([`Record3DRecording.frame(at:)`](../3D/Record3D.md), [`Record3DDevice.latestFrame`](../3D/Record3D.md#live-usb)). `DepthConfidence` is the `.low`/`.medium`/`.high` grade `pointCloud(...)` uses as a floor to drop noisy samples (ignored when a frame has no confidence map).

<a name="unproject"></a>
## Lifting one point

`unproject(normalized:)` takes a **Vision-normalized** image point — `0…1` across the frame, origin at the **lower-left**, y up, the convention [`Body`](../Vision/Vision.md) and the other trackers report points in — and returns its metric 3D position, or `nil` if there's no valid depth there.

```swift
if let p = frame.unproject(normalized: Vector2(0.5, 0.5)) {
    // p is in meters, camera space (see below)
}
```

A single depth pixel is often a hole (zero/invalid), especially at a silhouette edge where limbs sit. So the lookup samples a small `radius`-pixel window and takes the **median** of the valid samples there — robust to the odd dropout. Widen `radius` for noisier depth, narrow it for sharper edges. `depth(atNormalizedX:y:)` is the metric depth alone, if you want the distance without the 3D point.

This is the source-agnostic seam: hand it *any* 2D image point and *any* depth source, and get a 3D position back.

<a name="pose"></a>
## Depth-lifted pose

`Body.lifted(through:)` is the per-joint sugar over `unproject`: it back-projects every joint of a 2D [`Body`](../Vision/Vision.md) through a frame's depth into a `LiftedPose` — the skeleton in metric 3D.

```swift
let pose = body.lifted(through: frame)        // body from a BodyTracker
pose.position(.leftWrist)                       // Vector3? in meters, camera space
pose.bones()                                    // [(Vector3, Vector3)] 3D segments
pose.center                                     // centroid, to aim an orbiting camera
pose.cloud(jointSize: 0.06, color: .yellow)     // the skeleton as a PointCloud
```

`BodyTracker` finds **everyone** in view, so lift the whole set at once — `bodies.bodies.lifted(through: frame)` returns one `LiftedPose` per person, all in the frame's own camera space, so several skeletons land at their true relative positions in the same cloud:

```swift
for pose in bodies.bodies.lifted(through: frame) {
    drawPointCloud(pose.cloud(color: .yellow))
}
```

Where [`BodyTracker3D`](../Vision/Vision.md) *estimates* a skeleton's depth from a single flat image, this **reads** it: with a real depth source — an iPhone's LiDAR or TrueDepth camera — the joints sit at their true distance, not a guessed one. (`BodyTracker3D` itself follows only the most prominent person — depth-lift is the multi-person route to 3D skeletons.)

Run the `BodyTracker` on the **same source** as the depth (so the 2D poses come from the depth frame's own color image), then lift through the latest frame. A joint whose depth was a hole is dropped, just as a low-confidence 2D joint is absent from the source `Body`.

Since 3D mode has no line primitive yet, `cloud()` is the shipped way to draw the figure: each joint a splat, each bone a line of small splats, in the cloud's own space — so the skeleton lands inside the person's depth cloud and the whole scene orbits as one.

<a name="space"></a>
## The coordinate convention

`CameraIntrinsics` is a pinhole calibration — focal length `fx`/`fy` and principal point `cx`/`cy`, in pixels, at a stated resolution. Intrinsics are tied to that resolution, so `scaled(toWidth:height:)` brings color-frame intrinsics onto the smaller depth grid (a depth source does this for you).

Everything lifted lands in the camera's **right-handed, y-up space**: +x right, +y up, the camera looking down −z (a point in front of the lens has negative z, so metric depth maps to −z). That's the **same space** [`PointCloud`](../3D/3D.md) and [`Camera3D`](../3D/3D.md#camera) use, which is why a depth-lifted skeleton drops straight into the person's own cloud and both draw through one camera.

The **input** to `unproject` is Vision-normalized (lower-left origin); the **output** is camera-space meters. The y-flip between them is handled for you.

<a name="ahead"></a>
## What's here, what's ahead

Here: the core `RGBDFrame`/`CameraIntrinsics`/`DepthConfidence`, `unproject`/`pointCloud`, and depth-lifted pose (`Body.lifted` → `LiftedPose`). Also here, for a depth source that reports a camera **pose**: `PointCloud.transformed(by:)` places a camera-space cloud into world space, and `WorldCloud` fuses a sweep of pose-placed frames into one accumulated cloud — see [Phone › World fusion](../3D/Phone.md#world-fusion). And [depth-aware compositing](../3D/DepthCompositing.md) puts 2D drawing *inside* a depth scene, so a mark occludes and is occluded by the depth. Ahead: a depth-driven blur for camera-feed depth of field, and richer depth sources as the [iPhone sensor array](../../ROADMAP.md) grows.

### See also

- [3D](../3D/3D.md) — the camera and point clouds the lifted geometry draws through
- [Depth compositing](../3D/DepthCompositing.md) — placing 2D drawing inside a depth scene, with occlusion
- [Record3D](../3D/Record3D.md) — the iPhone depth sources that produce RGBD frames
- [Vision](../Vision/Vision.md) — `BodyTracker`, the 2D pose that gets lifted

### Example

- `Examples/3D/DepthLiftedPose` — a body skeleton lifted to true 3D from a tethered iPhone, drawn inside its own depth cloud
