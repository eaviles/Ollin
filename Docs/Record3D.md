#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Record3D`</sup>

---

## Record3D (RGBD recordings)

Open an RGBD clip captured by the **[Record3D](https://record3d.app)** iOS app — an ARKit color-plus-depth recorder — and turn its frames into 3D point clouds you orbit through a [`Camera3D`](./3D.md). This is the device-free first step of bringing an iPhone's depth sensors into a sketch: record a clip on the phone, AirDrop the `.r3d` to your Mac, and inspect your room as a cloud — no networking, no live tether, no extra hardware on the Mac.

Record3D lives in a separate library so the drawing core stays free of the decode work; add `import OllinRecord3D` alongside `import Ollin` to reach it. Everything decodes with Apple-native frameworks — the `.r3d` container (a ZIP), its LZFSE-compressed depth, and its JPEG color — so there's no third-party dependency.

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

- [Loading](#loading) — from a path, URL, or bundled resource
- [Frames and point clouds](#frames-and-point-clouds) — `pointCloud(at:)`, `frame(at:)`, the options
- [Intrinsics and coordinates](#intrinsics-and-coordinates) — `CameraIntrinsics`, the camera-space convention
- [Notes](#notes) — the `.r3d` format, depth grids, what's ahead

<a name="loading"></a>

### Loading

```swift
Record3DRecording(path: String) throws       // a file on disk
Record3DRecording(url: URL) throws            // any file URL
Record3DRecording(data: Data) throws          // raw .r3d bytes already in memory
Record3DRecording(resource: String, withExtension: String, in: Bundle) throws
```

`path` throws if no file exists there; `resource` throws if the bundle doesn't contain it (pass your own bundle as `in:` — usually `.module` — since a default would resolve to Ollin's bundle, not yours). Opening parses the archive's directory and metadata up front; the per-frame color and depth decode lazily, so loading is cheap and stays cheap until you ask for a frame.

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

The one call you usually need: decode frame `index` and unproject every depth pixel into a colored [`PointCloud`](./3D.md), ready for `drawPointCloud`. The most recent frame is cached, so orbiting a held frame (re-reading the same index) costs nothing.

- **`minimumConfidence`** — ARKit tags each depth sample `.low`/`.medium`/`.high`; samples below this floor are dropped. `.high` is cleanest; `.medium` keeps a denser cloud. Ignored if the recording has no confidence map.
- **`depthRange`** — keep only samples whose depth (meters) falls in the range, trimming sensor noise near zero and far-away outliers. `nil` keeps every positive depth.
- **`step`** — sample every *n*-th pixel per axis (`1` = full density). A 256×192 LiDAR map is ~49k points at full density, comfortable to rebuild each frame.
- **`pointSize`** — the splat diameter in world units (meters); perspective shrinks distant points.

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

`color` is a normal [`Image`](./Images.md) (usually higher-resolution than the depth map) you can also just `drawImage`. `depth` is metric depth in meters, row-major from the top-left.

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

`unproject` back-projects a depth pixel into the camera's space using **ARKit's right-handed frame**: +x right, +y up, and the camera looking down −z (so a point in front of the lens has negative z, and metric depth maps to −z). That matches [`Camera3D`](./3D.md)'s right-handed, y-up world, so a cloud built here drops straight into `drawPointCloud` and orbits correctly. The cloud sits in the camera's space, not the world (per-frame poses, for fusing multiple frames into one world, are a later addition) — so orbit the cloud's own centroid, as the example does.

<a name="notes"></a>

### Notes

- **The `.r3d` format.** A `.r3d` is a ZIP holding a `metadata` JSON (camera intrinsics, capture resolution, frame rate) and, per frame, a JPEG color image, an LZFSE-compressed float32 depth map in meters, and an LZFSE-compressed confidence map. Ollin reads this clean-room from the format's public structure with Apple-native frameworks only (Foundation's ZIP-less archive read, `Compression` for LZFSE, ImageIO for JPEG); the `record3d` library that documents the format is LGPL-2.1 and is credited, never copied.
- **Depth grids.** LiDAR depth is 256×192, TrueDepth 640×480. The grid isn't stored explicitly, so it's recovered from the sample count and the capture aspect — both orientations (landscape and portrait) are handled.
- **Capturing.** Use the Record3D app on a LiDAR or TrueDepth iPhone, then share the `.r3d` (AirDrop is simplest). The runnable example reads the newest `.r3d` in `~/Downloads`.
- **What's ahead.** This reads recorded files; a live tether (the phone streaming over USB into a sketch as it renders) and a broader sensor stream are the next steps of the iPhone-as-a-sensor-array work (see [`ROADMAP.md`](../ROADMAP.md)).

The runnable example is [`Examples/3D/Record3DCloud`](../Examples/3D/Record3DCloud/Sketch.swift): it finds the newest `.r3d` in `~/Downloads`, plays the clip, and orbits the cloud (drag to spin it yourself).
