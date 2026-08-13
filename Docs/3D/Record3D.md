#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Record3D`</sup>

---

## Record3D (RGBD recordings)

Bring an iPhone's depth camera into a sketch through the **[Record3D](https://record3d.app)** iOS app, an ARKit color-plus-depth recorder. Its frames become 3D point clouds you orbit through a [`Camera3D`](../3D/3D.md). There are two ways in. Open a recorded `.r3d` **file** with `Record3DRecording`, or read the phone's **live USB stream** as it captures with `Record3DDevice`. Either way a Mac, which has no depth sensor of its own, gets a world-facing RGBD feed.

Record3D lives in a separate library so the drawing core stays free of the decode work. Add `import OllinRecord3D` alongside `import Ollin` to reach it. Everything decodes with Apple-native frameworks, so there's no third-party dependency. The `.r3d` container is a ZIP, its depth is LZFSE-compressed, its color is JPEG, and the USB path rides the standard `usbmuxd` device tunnel.

```swift
import Ollin
import OllinRecord3D

final class Scan: Sketch {
    var scan: Record3DRecording?

    override func setup() {
        scan = try? Record3DRecording(path: "/path/to/scan.r3d")
    }

    override func draw() {
        background(Color(white: 0.04))
        guard let scan, scan.frameCount > 0 else { return }
        let i = Int(time * 30) % scan.frameCount
        guard let cloud = try? scan.pointCloud(at: i) else { return }
        camera(.orbiting(radius: 2.5, azimuth: time * 0.3, elevation: 0.2))
        drawPointCloud(cloud)
    }
}
```

### Contents

- [Loading](#loading) - from a path, URL, or bundled resource
- [Frames and point clouds](#frames-and-point-clouds) - `pointCloud(at:)`, `frame(at:)`, the options
- [Live streaming over USB](#live-usb) - `Record3DDevice`, a tethered phone as a real-time feed
- [Intrinsics and coordinates](#intrinsics-and-coordinates) - `CameraIntrinsics`, the camera-space convention
- [Notes](#notes) - the `.r3d` format, depth grids, and capturing

<a name="loading"></a>

### Loading

```swift
Record3DRecording(path: String) throws       // a file on disk
Record3DRecording(url: URL) throws            // any file URL
Record3DRecording(data: Data) throws          // raw .r3d bytes already in memory
Record3DRecording(resource: String, withExtension: String, in: Bundle) throws
```

`path` throws if no file exists there, and `resource` throws if the bundle doesn't contain it. Pass your own bundle as `in:`, usually `.module`, since a default would resolve to Ollin's bundle rather than yours. Opening parses the archive's directory and metadata up front, and the per-frame color and depth decode lazily. So loading is cheap and stays cheap until you ask for a frame.

```swift
var frameCount: Int          // RGBD frames in the recording
var fps: Double              // the clip's frame rate (0 if unstated)
var intrinsics: CameraIntrinsics   // at the capture resolution
```

<a name="frames-and-point-clouds"></a>

### Frames and point clouds

```swift
func pointCloud(at index: Int,
                minimumConfidence: DepthConfidence = .high,
                depthRange: ClosedRange<Double>? = nil,
                step: Int = 1,
                pointSize: Double = 0.012) throws -> PointCloud
```

This is the one call you usually need. It decodes frame `index` and unprojects every depth pixel into a colored [`PointCloud`](../3D/3D.md), ready for `drawPointCloud`. The most recent frame is cached, so orbiting a held frame costs nothing: re-reading the same index is free.

- **`minimumConfidence`** drops the samples that fall below the floor you pick. ARKit tags each depth sample `.low`, `.medium`, or `.high`, so `.high` is cleanest while `.medium` keeps a denser cloud. It's ignored if the recording has no confidence map.
- **`depthRange`** keeps only samples whose depth in meters falls in the range, trimming sensor noise near zero and far-away outliers. `nil` keeps every positive depth.
- **`step`** samples every *n*-th pixel per axis, so `1` is full density. A 256×192 LiDAR map is ~49k points at full density, comfortable to rebuild each frame.
- **`pointSize`** is the splat diameter in world units (meters), and perspective shrinks distant points.

For more control, decode the frame and build the cloud yourself:

```swift
func frame(at index: Int) throws -> RGBDFrame
```

```swift
struct RGBDFrame {
    let color: Image              // the decoded color frame
    let depth: [Float]            // metric meters, row-major, depthWidth × depthHeight
    let confidence: [UInt8]?      // 0/1/2 per pixel, or nil
    let depthWidth, depthHeight: Int
    let intrinsics: CameraIntrinsics   // scaled to the depth grid

    func pointCloud(minimumConfidence:depthRange:step:pointSize:) -> PointCloud
}
```

`color` is a normal [`Image`](../Drawing/Images.md), usually higher-resolution than the depth map, that you can also just `drawImage`. `depth` is metric depth in meters, row-major from the top-left.

`RGBDFrame` and `CameraIntrinsics` are **core** types, in `Ollin`, the source-agnostic shape every depth source produces. So beyond point clouds they also lift a single image point or a 2D body pose into metric 3D. See [RGBD frames and depth-lifted pose](../3D/RGBD.md).

A recording also carries the sweep's camera path:

```swift
var poses: [simd_float4x4]                    // camera-to-world, one per frame
func pose(at index: Int) -> simd_float4x4?    // nil past the recorded range
```

Each pose places that frame's camera-space cloud into the capture session's gravity-aligned world. That world is y up, with the first frame near the identity. Apply it with `PointCloud.transformed(by:)` and fuse the placed frames with a [`WorldCloud`](../3D/RGBD.md). The pose translations are also the camera path [`reconstructSurface(orientedToward:)`](../Generators/SurfaceReconstruction.md) wants.

One honest caveat: only clips captured with world tracking carry real motion. A recording made without it, such as a TrueDepth capture, stores every pose as the identity. A sweep from such a clip cannot be re-registered after the fact, though single frames still reconstruct fine.

<a name="live-usb"></a>

### Live streaming over USB

`Record3DDevice` is the live sibling of `Record3DRecording`. Instead of a recorded file, it reads the phone's RGBD stream over the cable in real time. The metric depth and the true intrinsics are the same, and the view moves as the phone moves.

```swift
let device = Record3DDevice()

override func setup() { device.start() }

override func draw() {
    background(Color(white: 0.04))
    guard let cloud = device.pointCloud() else {
        return drawStatus(device.waitingMessage, style: .info)
    }
    camera(.orbiting(radius: 2.5, azimuth: time * 0.3, elevation: 0.2))
    drawPointCloud(cloud)
}
```

**On the phone:** open Record3D, turn on **USB streaming** in its Settings, and keep it on the live screen, then connect the cable. The device retries on its own, so enabling the stream or plugging in after the sketch is already running just starts the feed. `waitingMessage` tells you what it's waiting for: no device, refused, reconnecting. Only one streaming mode is supported, deliberately. USB carries full-quality LZFSE float32 depth plus intrinsics and pose, where Record3D's WiFi mode is lossy and behind a paid add-on.

```swift
device.start()                 // begin connecting (retries until the phone is serving)
device.stop()                  // close the connection
var isStreaming: Bool          // frames currently arriving
var latestFrame: RGBDFrame?    // the most recent decoded frame (same type as the file path)
var latestPose: Record3DPose?  // the frame's ARKit camera pose (see below)
var camera: Record3DCamera?    // .trueDepth (front), .lidar (rear), or .unknown (nil before the first frame)
func pointCloud(minimumConfidence:depthRange:step:pointSize:) -> PointCloud?
```

**Which camera is streaming** is detectable, which is worth acting on because the two behave very differently. `camera`, and also `RGBDFrame.camera`, reports `.trueDepth` or `.lidar`, inferred from the depth grid. The front TrueDepth camera streams a dense 640×480 map and the rear LiDAR a sparse 256×192 one. No iPhone pairs them the other way, so the resolution identifies the camera.

Tune for whichever you get. The **front** camera is short-range and noisy past a meter, so clamp `depthRange` tight, around `0.2...1.2`, and demand `.high` confidence, which suits a face up close. The **rear LiDAR** reaches across a room, so open the range to several meters at `.medium`. The live example switches its settings on `frame.camera` and shows the detected camera in its caption.

`Record3DDevice` is also a [`FrameSource`](../Vision/Vision.md) and a `VideoFeed`. Its color frames flow into `drawFrame(device)` and into a vision tracker exactly like a `Camera`, which is the phone's camera analyzed on the Mac.

Each frame carries a `Record3DPose`, the ARKit camera rotation quaternion and translation in meters. Clouds come back in **camera space** with the pose published beside them rather than applied. To place a frame in a shared world, build a transform from the pose and pass it to `PointCloud.transformed(by:)`. `WorldCloud` then fuses a sweep of placed frames into one accumulated cloud, the flow worked through in [Phone › World fusion](../3D/Phone.md#world-fusion).

<a name="intrinsics-and-coordinates"></a>

### Intrinsics and coordinates

```swift
struct CameraIntrinsics {
    var fx, fy, cx, cy: Double    // focal length and principal point, in pixels
    var width, height: Int        // the resolution they're expressed at
    func scaled(toWidth:height:) -> CameraIntrinsics
    func unproject(col: Double, row: Double, depth: Double) -> Vector3
}
```

`unproject` back-projects a depth pixel into the camera's space using **ARKit's right-handed frame**. That is +x right, +y up, and the camera looking down −z. A point in front of the lens has negative z, so metric depth maps to −z. That matches [`Camera3D`](../3D/3D.md)'s right-handed, y-up world. A cloud built here drops straight into `drawPointCloud` and orbits correctly. The cloud sits in the camera's space rather than the world, so orbit the cloud's own centroid, as the example does. To move it into world space, apply the frame's own pose (see [World fusion](../3D/Phone.md#world-fusion)).

<a name="notes"></a>

### Notes

- **The `.r3d` format.** A `.r3d` is a ZIP holding a `metadata` JSON with camera intrinsics, capture resolution, and frame rate. Per frame it holds a JPEG color image, an LZFSE-compressed float32 depth map in meters, and an LZFSE-compressed confidence map. Ollin reads this clean-room from the format's public structure with Apple-native frameworks only: a small hand-written ZIP reader over `Data`, `Compression` for LZFSE, ImageIO for JPEG. The `record3d` library that documents the format is LGPL-2.1 and is credited, never copied.
- **Depth grids.** LiDAR depth is 256×192, TrueDepth 640×480. The grid isn't stored explicitly, so it's recovered from the sample count and the capture aspect. Both orientations, landscape and portrait, are handled.
- **The USB stream.** The live path uses Record3D's USB streaming over the standard `usbmuxd` device tunnel, TCP port 1337. Each frame is a small header of sizes, intrinsics, and pose, followed by JPEG color, LZFSE float32 depth, optional confidence, and a JSON metadata trailer. The wire format is read clean-room from its public structure, the same stance as the file format.
- **Capturing.** Use the Record3D app on a LiDAR or TrueDepth iPhone. For files, share the `.r3d`, where AirDrop is simplest. For live, enable USB streaming and tether the cable.
- **The wider sensor stream.** Record3D covers world-facing color and depth. [Phone](../3D/Phone.md) reads Ollin's own iOS capture app over the same USB tunnel, for a live 3D body skeleton, a face mesh with expression blendshapes, person segmentation, device motion, and pose-fused world scanning off the same phone.

The runnable examples are [`Examples/3D/Depth/Record3DCloud`](../../Examples/3D/Depth/Record3DCloud/Sketch.swift) and [`Examples/3D/Depth/Record3DLiveCloud`](../../Examples/3D/Depth/Record3DLiveCloud/Sketch.swift). The first reads the newest `.r3d` in `~/Downloads`, plays the clip, and orbits the cloud. The second does the same, live from a tethered phone. Drag to spin either one.
