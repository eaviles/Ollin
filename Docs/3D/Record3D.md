#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Record3D`</sup>

---

## Record3D (RGBD recordings)

The **[Record3D](https://record3d.app)** iOS app records color and depth from ARKit. With it, you bring an iPhone's depth camera into a sketch, and its frames become 3D point clouds that you orbit with a [`Camera3D`](../3D/3D.md). There are two ways to read that camera. `Record3DRecording` opens a recorded `.r3d` **file**, and `Record3DDevice` reads the phone's **live USB stream** while the phone captures. Either way, a Mac gets a world-facing RGBD feed. A Mac cannot produce one on its own, because it has no depth sensor.

Record3D support lives in a separate library, so the drawing core stays free of the decode work. Add `import OllinRecord3D` beside `import Ollin` to use it. Everything decodes with Apple-native frameworks, so there is no third-party dependency. That covers the `.r3d` container, which is a ZIP with LZFSE-compressed depth and JPEG color. It also covers the USB path, which uses the standard `usbmuxd` device tunnel.

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

`path` throws if no file exists there, and `resource` throws if the bundle does not contain it. Pass your own bundle as `in:`, usually `.module`, because a default value would resolve to Ollin's bundle rather than yours. Opening a recording parses the archive's directory and metadata up front. The color and depth of each frame decode only when you ask for that frame, so loading is cheap. It stays cheap until you ask for one.

```swift
var frameCount: Int          // RGBD frames in the recording
var fps: Double              // the clip's frame rate (0 if unstated)
var intrinsics: CameraIntrinsics   // at the capture resolution
```

<a name="frames-and-point-clouds"></a>

### Frames and point clouds

```swift
func pointCloud(at index: Int,
                minConfidence: DepthConfidence = .high,
                depthRange: ClosedRange<Double>? = nil,
                step: Int = 1,
                pointSize: Double = 0.012) throws -> PointCloud
```

This is the one call you usually need. It decodes frame `index` and unprojects every depth pixel into a colored [`PointCloud`](../3D/3D.md), ready for `drawPointCloud`. The most recent frame is cached, so reading the same index again is free, and orbiting a held frame costs nothing.

- **`minConfidence`** drops the samples below the minimum you pick. ARKit tags each depth sample `.low`, `.medium`, or `.high`. `.high` gives the cleanest cloud, and `.medium` keeps a denser one. The option is ignored if the recording has no confidence map.
- **`depthRange`** keeps only the samples whose depth in meters falls in the range. That trims sensor noise near zero and far-away outliers. `nil` keeps every positive depth.
- **`step`** samples every *n*-th pixel per axis, so `1` is full density. A 256×192 LiDAR map is about 49k points at full density, which is comfortable to rebuild each frame.
- **`pointSize`** is the splat diameter in world units (meters). Perspective shrinks distant points.

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

    func pointCloud(minConfidence:depthRange:step:pointSize:) -> PointCloud
}
```

`color` is a normal [`Image`](../Drawing/Images.md), usually at a higher resolution than the depth map, and you can also draw it directly with `drawImage`. `depth` is metric depth in meters, row-major from the top-left.

`RGBDFrame` and `CameraIntrinsics` are **core** types in `Ollin`. Every depth source produces frames in this shape. Because they are core types, they do more than point clouds. They also lift a single image point or a 2D body pose into metric 3D. See [RGBD frames and depth-lifted pose](../3D/RGBD.md).

A recording also carries the sweep's camera path:

```swift
var poses: [simd_float4x4]                    // camera-to-world, one per frame
func pose(at index: Int) -> simd_float4x4?    // nil past the recorded range
```

Each pose places that frame's camera-space cloud into the gravity-aligned world of the capture session. That world is y up, and the first frame sits near the identity. Apply a pose with `PointCloud.transformed(by:)`, then fuse the placed frames with a [`WorldCloud`](../3D/RGBD.md). The pose translations are also the camera path that [`reconstructSurface(orientedToward:)`](../Generators/SurfaceReconstruction.md) needs.

Only clips captured with world tracking carry real motion. A recording made without it, such as a TrueDepth capture, stores every pose as the identity. A sweep from such a clip cannot be re-registered later, but single frames still reconstruct fine.

<a name="live-usb"></a>

### Live streaming over USB

`Record3DDevice` is the live counterpart of `Record3DRecording`. Instead of a recorded file, it reads the phone's RGBD stream over the cable in real time. You get the same metric depth and the same true intrinsics, and the view moves as the phone moves.

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

**On the phone:** open Record3D, turn on **USB streaming** in its Settings, keep the app on the live screen, then connect the cable. The device retries on its own. So if you enable the stream or plug in the cable after the sketch is already running, the feed starts anyway. `waitingMessage` tells you what it is waiting for: no device, refused, or reconnecting.

Only one streaming mode is supported, and that is deliberate. USB carries full-quality LZFSE float32 depth plus intrinsics and pose, while Record3D's WiFi mode is lossy and needs a paid add-on.

```swift
device.start()                 // begin connecting (retries until the phone is serving)
device.stop()                  // close the connection
var isRunning: Bool          // frames currently arriving
var latestFrame: RGBDFrame?    // the most recent decoded frame (same type as the file path)
var latestPose: Record3DPose?  // the frame's ARKit camera pose (see below)
var camera: Record3DCamera?    // .trueDepth (front), .lidar (rear), or .unknown (nil before the first frame)
func pointCloud(minConfidence:depthRange:step:pointSize:) -> PointCloud?
```

You can detect **which camera is streaming**, and it is worth acting on, because the two cameras behave differently. `camera`, and also `RGBDFrame.camera`, reports `.trueDepth` or `.lidar`, or `.unknown` when the grid matches neither. It is `nil` before the first frame. The value is inferred from the depth grid. The front TrueDepth camera streams a dense 640×480 map, and the rear LiDAR streams a sparse 256×192 one. No iPhone pairs them the other way, so the resolution identifies the camera.

Tune for whichever camera you get. The **front** camera is short-range and noisy past a meter. So set `depthRange` to a narrow band, around `0.2...1.2`, and require `.high` confidence, which suits a face up close. The **rear LiDAR** reaches across a room, so open the range to several meters at `.medium`. The live example switches its settings on `frame.camera` and shows the detected camera in its caption.

`Record3DDevice` is also a [`FrameSource`](../Vision/Vision.md) and a `VideoFeed`. Its color frames flow into `drawFrame(device)` and into a vision tracker exactly like a `Camera` does. That means the phone's camera is analyzed on the Mac.

Each frame carries a `Record3DPose`, which holds the ARKit camera rotation as a quaternion and the translation in meters. Clouds come back in **camera space**, so the pose is published beside them, not applied to them. To place a frame in a shared world, build a transform from the pose and pass it to `PointCloud.transformed(by:)`. `WorldCloud` then fuses a sweep of placed frames into one accumulated cloud. [Phone › World fusion](../3D/Phone.md#world-fusion) walks through that flow.

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

`unproject` back-projects a depth pixel into the camera's space using **ARKit's right-handed frame**. In that frame +x points right, +y points up, and the camera looks down −z. A point in front of the lens has negative z, so metric depth maps to −z. That matches the right-handed, y-up world of [`Camera3D`](../3D/3D.md). So you can pass a cloud built here straight to `drawPointCloud`, and it orbits correctly. The cloud sits in the camera's space rather than the world, so orbit the cloud's own centroid, as the example does. To move it into world space, apply the frame's own pose (see [World fusion](../3D/Phone.md#world-fusion)).

<a name="notes"></a>

### Notes

- **The `.r3d` format.** A `.r3d` is a ZIP. It holds a `metadata` JSON with the camera intrinsics, the capture resolution, and the frame rate. For each frame it holds a JPEG color image, an LZFSE-compressed float32 depth map in meters, and an LZFSE-compressed confidence map. Ollin reads this clean-room from the format's public structure, using Apple-native frameworks only. It uses a small hand-written ZIP reader over `Data`, `Compression` for LZFSE, and ImageIO for JPEG. The `record3d` library that documents the format is LGPL-2.1. It is credited, never copied.
- **Depth grids.** LiDAR depth is 256×192, and TrueDepth depth is 640×480. The grid is not stored explicitly, so it is recovered from the sample count and the capture aspect. Both orientations, landscape and portrait, are handled.
- **The USB stream.** The live path uses Record3D's USB streaming over the standard `usbmuxd` device tunnel, on TCP port 1337. Each frame starts with a small header of sizes, intrinsics, and pose. JPEG color, LZFSE float32 depth, optional confidence, and a JSON metadata trailer follow the header. The wire format is read clean-room from its public structure, the same stance as for the file format.
- **Capturing.** Use the Record3D app on a LiDAR or TrueDepth iPhone. For files, share the `.r3d` from the phone. AirDrop is the simplest way. For live use, enable USB streaming and connect the cable.
- **The wider sensor stream.** Record3D covers world-facing color and depth. [Phone](../3D/Phone.md) reads Ollin's own iOS capture app over the same USB tunnel. The same phone gives you a live 3D body skeleton, a face mesh with expression blendshapes, person segmentation, device motion, and pose-fused world scanning.

The runnable example is [`Examples/3D/Depth/Record3DCloud`](../../Examples/3D/Depth/Record3DCloud/Sketch.swift). It reads the newest `.r3d` in `~/Downloads`, plays the clip, and orbits the cloud. The moment a phone connects, it switches to the live tethered stream. Drag to spin the cloud.
