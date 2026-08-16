#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Phone`</sup>

---

## Phone (iPhone sensor stream)

Borrow a tethered iPhone's on-device perception in a sketch that still renders on the Mac. **Ollin Capture**, Ollin's own iOS app ([`Apps/OllinPhoneApp`](../../Apps/OllinPhoneApp/README.md)), runs ARKit on the phone's Neural Engine and streams the results over the USB cable. `PhoneDevice` reads them on the Mac as typed values you use in `draw()`.

Six payloads come over. A **3D body skeleton**. **Faces**, up to 3 at once, each a deforming mesh plus the 52 expression blendshapes. A world-facing **RGBD depth frame** from the rear LiDAR, which unprojects into a point cloud and carries the camera's 6DoF pose. The **room mesh**, the space itself reconstructed as a labelled triangle surface. A **person-segmentation matte** from the rear camera, as a silhouette and a cutout. And **device motion**.

Where [`Record3D`](../3D/Record3D.md) borrows another app's color-plus-depth feed, this is Ollin's own app, so the stream carries what ARKit *perceives*. The chain is Ollin's end to end.

`PhoneDevice` lives in a separate library so the drawing core stays lean, so add `import OllinPhone` alongside `import Ollin`. The transport is the standard `usbmuxd` device tunnel, the same plumbing Xcode uses. There's no third-party dependency and no Wi-Fi pairing, just the cable.

```swift
import Ollin
import OllinPhone

final class Pose: Sketch {
    let device = PhoneDevice()

    override func setup() { device.start() }

    override func draw() {
        background(Color(white: 0.05))
        guard let body = device.latestBody else {
            return drawStatus(device.waitingMessage, style: .info)
        }
        camera(.orbiting(target: body.center, radius: 2.6, azimuth: time * 0.4, elevation: 0.12))
        drawPointCloud(body.cloud())
    }
}
```

### Contents

- [Setup](#setup) - install the capture app, connect the cable
- [Reading the stream](#reading-the-stream) - `latestBody`, `latestFace`, `latestDepthFrame`, `sceneMesh`, `latestMotion`, the connection state
- [The body](#the-body) - `PhoneBody`, the joints, drawing the skeleton
- [The face](#the-face) - `PhoneFace`, the blendshapes, the mesh
- [World depth](#world-depth) - `latestDepthFrame`, `pointCloud(...)`, the camera pose
- [World fusion](#world-fusion) - `WorldCloud`, sweeping a room into one cloud, and [keeping it registered](#drift)
- [The room mesh](#the-room-mesh) - `sceneMesh`, the room as a labelled surface, the Mesh mode
- [Segmentation](#segmentation) - `latestSegmentationMatte`, `latestSegmentationCutout`, the Segment mode
- [Device motion](#device-motion) - `PhoneMotion`, the transport smoke-test
- [Notes](#notes) - the wire, coordinate space, what's ahead

---

## Setup

The sketch side is just `import OllinPhone` and a `PhoneDevice`, but the phone needs the capture app:

1. **Build Ollin Capture onto the iPhone.** It's an xcodegen + Xcode project, since an iOS app can't be `swift run`. From [`Apps/OllinPhoneApp`](../../Apps/OllinPhoneApp/README.md): `xcodegen generate`, open the project, select the phone, and Run. It needs an A12+ iPhone on iOS 17+ and automatic signing; that README has the device-registration step.
2. **Connect the cable** and launch the app. Its screen reads **READY** until the Mac connects, then **ON AIR**.
3. **Run the sketch** on the Mac. `PhoneDevice` retries on its own, so launching the app or plugging in after the sketch is already running just begins the feed.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneBodyPose`.

## Reading the stream

`PhoneDevice` mirrors `Record3DDevice`'s shape, with `start()` / `stop()`, a `waitingMessage` for the pre-connection notice, and `isStreaming`:

```swift
let device = PhoneDevice()
device.start()                       // begins connecting; safe to call once

device.isStreaming                   // Bool, frames currently arriving
device.waitingMessage                // a notice reflecting the live connection state
device.latestBody                    // PhoneBody?, the latest skeleton (Body mode)
device.latestFaces                   // [PhoneFace], every tracked face, up to 3 (Face mode)
device.latestFace                    // PhoneFace?, the most prominent face (= latestFaces.first)
device.latestDepthFrame              // RGBDFrame?, the latest depth frame (World mode)
device.sceneMesh                     // PhoneSceneMesh, the room scanned so far (Mesh mode)
device.latestMotion                  // PhoneMotion?, the latest device-motion sample
```

These are fresh each time the phone sends one, so read them within the current `draw()`. Each is `nil` until the first of its kind arrives. Motion typically lights up first, since it needs no camera or model, proving the wire before ARKit has found a body, face, or depth.

**The camera modes are mutually exclusive.** Body, World, Segment, and Mesh use the rear camera, Face the front TrueDepth camera, and only one ARKit session runs at a time. The capture app has a **Body / Face / World / Segment / Mesh** toggle, and whichever is selected is the one that updates: `latestBody`, `latestFace`, `latestDepthFrame`, the segmentation images, or `sceneMesh`. The others hold their last value, so read the one for the mode you mean to drive. Motion streams across all of them.

## The body

`PhoneBody` carries every reported joint as a 3D position in **meters**, in model space. The pelvis root sits at the origin. ARKit's convention puts x to the picture's right, y up, and z toward the camera. Its accessor shape matches `Body3D` and `LiftedPose` from [`OllinVision`](../Vision/Vision.md):

```swift
if let body = device.latestBody {
    body.isTracked                   // Bool, ARKit tracking vs. extrapolating
    body.position(.head)             // Vector3?, one joint, model space
    body.positions                   // [PhoneJoint: Vector3]
    body.bones()                     // [(Vector3, Vector3)], segments to draw
    body.center                      // Vector3, centroid, to aim an orbiting camera
}
```

The joints are the `PhoneJoint` set, a practical subset of ARKit's ~91-joint skeleton. It holds root, hips, spine, chest, neck, head, and the arms and legs out to hands and feet. A joint ARKit didn't report this frame is simply absent.

3D drawing has no thin-line primitive, so the way to draw the skeleton is as a `PointCloud`. Each joint is a splat and each bone a dotted line of splats, exactly like `LiftedPose.cloud`:

```swift
camera(.orbiting(target: body.center, radius: 2.6, azimuth: time * 0.4, elevation: 0.12))
drawPointCloud(body.cloud(jointSize: 0.055, boneSize: 0.018, color: .white))
```

## The face

In **Face** mode the phone tracks faces on the front TrueDepth camera, **up to 3 at once**. Each streams as a `PhoneFace`: the 52 expression **blendshapes**, the deforming **mesh**, and the **head pose**. Read `latestFaces` for the whole set, or `latestFace` for just the most prominent one:

```swift
for face in device.latestFaces {     // up to 3 people
    face.isTracked                   // Bool, ARKit tracking vs. extrapolating
    face.blendShape(.jawOpen)        // Double 0…1, one expression coefficient
    face.blendShapes                 // [PhoneBlendShape: Double], all 52
    face.strongestBlendShapes()      // the few firing now, strongest first
    face.mesh()                      // Mesh, the triangle surface (draw solid/wireframe)
    face.meshPoints                  // [Vector3], the mesh vertices, face-local (meters)
    face.headPosition                // Vector3, head position in world space
    face.headOrientation             // SIMD4<Float>, head rotation quaternion (x,y,z,w)
}
```

`latestFaces` is the complete current set each frame, so a face leaving simply drops out and the list shrinks. ARKit's order isn't spatially meaningful, so sort by `headPosition.x` if you want each face to keep a steady color.

The blendshapes are the `PhoneBlendShape` set, ARKit's 52 named coefficients: `jawOpen`, `eyeBlinkLeft`, `mouthSmileLeft`, `browInnerUp`, `cheekPuff`, `tongueOut`, and the rest. Each runs `0` at neutral to `1` fully expressed. They're the cheap, expressive payload, so read one to drive a knob, or `strongestBlendShapes()` to name the current expression.

Draw each face as a `mesh()`, its triangle surface, carrying the ARKit topology and computed normals. Draw it solid, textured, or as a `wireframe()`, the recognizable AR face net. The vertices are face-local, centered on the face, so add `face.headPosition` to place several people apart in space, then orbit their centroid:

```swift
// One face: face-local space, so orbit .zero
camera(.orbiting(target: .zero, radius: 0.42, azimuth: time * 0.4, elevation: 0.04))
wireframe()
drawMesh(face.mesh())
```

`face.cloud()` draws the vertices as points instead, if you want the splat look. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneFace`.

## World depth

In **World** mode the phone's rear **LiDAR** streams a world-facing RGBD frame. It holds a metric depth map, the matching color image, the camera intrinsics, per-pixel confidence, and the camera's 6DoF pose. `PhoneDevice` exposes it as the source-agnostic core [`RGBDFrame`](../3D/RGBD.md), so it unprojects into a point cloud the same way every depth source does. It needs a LiDAR iPhone, meaning a Pro model.

```swift
if let cloud = device.pointCloud(depthRange: 0.3...5.0) {
    camera(.orbiting(target: .zero, radius: 2.5, azimuth: time * 0.3, elevation: 0.18))
    drawPointCloud(cloud)
}

device.latestDepthFrame              // RGBDFrame?, depth + color + intrinsics
device.latestPose                    // simd_float4x4?, the camera's 6DoF pose
```

`pointCloud(...)` is sugar over `latestDepthFrame?.pointCloud(...)` with rear-LiDAR defaults: `minimumConfidence: .medium` and an open depth range. See [`RGBD.md`](../3D/RGBD.md) for the full unprojection parameters and the coordinate space, which is camera-relative, +x right, +y up, looking −z. For finer control, like sampling a single depth point or lifting a 2D pose to metric 3D, reach for `latestDepthFrame` and the `RGBDFrame` API directly.

`PhoneDevice` is also a `FrameSource` and a `VideoFeed` in this mode. A vision tracker can analyze the color feed and `drawFrame` can letterbox it. The color frame is only present while World mode is streaming.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneDepthCloud`.

## World fusion

A single depth frame is only the slice of the world in front of the lens. The camera's 6DoF pose, `latestPose`, is what turns slices into a whole. ARKit's world is fixed and gravity-aligned. Transforming each frame's camera-space cloud by its pose places it where it really is in the room. Sweep the phone and the slices stack up.

`WorldCloud`, in the core, does the fusing. It keeps one point per small cube of space, so re-seeing a wall refreshes it in place rather than piling up duplicates. The cloud's size is bounded by the scene's surface area, not the number of frames. A sweep can run as long as you like:

```swift
var world = WorldCloud(voxelSize: 0.025)   // fuse at 2.5 cm

override func draw() {
    // Fuse each fresh frame once, draw() runs faster than frames stream in.
    if let id = device.latestDepthFrameID, id != lastFused,
       let pose = device.latestPose,
       let cameraCloud = device.pointCloud(minimumConfidence: .low, depthRange: 0.3...5.0) {
        world.add(cameraCloud, correcting: pose)
        lastFused = id
    }
    camera(.orbiting(target: center, radius: r, azimuth: time * 0.2, elevation: 0.22))
    drawPointCloud(world.cloud)            // the whole accumulated room
}
```

`add(_:transformedBy:)` applies the camera-to-world pose and merges in one pass, `add(_:correcting:)` corrects that pose first (see below), and `add(_:)` merges an already-world-space cloud. `latestDepthFrameID` changes only when a new depth frame arrives, so comparing it against the last fused id adds each frame exactly once. `world.cloud` is the fused `PointCloud`, `world.count` its point total, and `world.reset()` starts a fresh scan. The placement primitive underneath, `PointCloud.transformed(by:)`, is public too, so any 4×4 matrix can be applied to a cloud's positions, and `Vector3.transformed(by:)` does the same for one point.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneWorldScan`. Sweep the phone, press **C** to turn the correction off, and **R** to reset.

<a name="drift"></a>
### Keeping a long sweep registered

ARKit reports its pose with a small error, and the error never goes away, so it piles up. Over a minute of sweeping it grows into tens of centimeters: a wall seen at the start of the scan and again at the end lands in two places, and the fused cloud thickens into a smear. That is drift, and it is the reason a long scan looks worse than a short one.

`add(_:correcting:)` takes it out. Before each frame is merged, the frame is slid and turned until it sits on the surfaces already fused, and the fix that did it is kept and used as the starting guess for the next frame:

```swift
let fix = world.add(cameraCloud, correcting: pose)

fix.pose          // the pose the cloud actually went in at
fix.error         // what is left between the frame and the scan, in meters
fix.overlap       // how much of the frame found a surface to match, 0 to 1
fix.applied       // false when the fit was held back
world.correction  // the whole fix so far: placed = correction * reported
```

Two rules keep it honest. A frame that finds too little to match, or that asks for a jump rather than a nudge, is **held back**: the cloud still goes in, at the fix earlier frames established, and `applied` reads false. And a direction the geometry does not pin down is left alone rather than guessed, so sweeping one blank wall corrects across it and never slides along it.

The fit costs about half of what merging the frame costs, and it stops as soon as a round stops moving the cloud, so a well-tracked frame pays for one or two rounds. `CloudAlignment.Settings` has the knobs (how many points to fit through, how many rounds, how far to look, and the two guards); the defaults suit a hand-held sweep at a few centimeters per voxel.

Apply `world.correction` to anything else the phone reports in the same space, so it lands where the fused cloud does:

```swift
let whereTheCameraReallyIs = Vector3.zero.transformed(by: world.correction * pose)
```

This corrects the error as it accumulates. It does not close a **loop**: walk a full circle around a building and come back, and the scan will have wandered by more than one frame's fit can find. That needs loop detection and a pose graph, which is still ahead.

To see the difference without a phone, `swift run --package-path Examples Example-3D-Depth-DriftCorrectedScan` sweeps a made-up room twice, side by side, with the correction on and off.

## The room mesh

In **Mesh** mode the phone stops sending you raw depth and sends you the room itself. ARKit reconstructs the space around it as a real triangle surface on the device, and labels each triangle with what it is. What arrives on the Mac already has normals, and already knows the floor from the wall.

Where [world fusion](#world-fusion) builds a cloud of points on the Mac, this is a solid surface built on the phone. Both come from the same LiDAR, so pick by what you want to do with it. Points are for a cloud you scatter, deform, or reconstruct yourself. A mesh is for a surface you light, hide things behind, or bounce something off.

```swift
device.sceneMesh                     // PhoneSceneMesh, the room scanned so far
device.sceneMeshVersion              // Int?, changes when a block arrives or is retired
device.resetSceneMesh()              // forget it and collect the room again
```

The room arrives **in blocks**. ARKit divides the space into pieces, reports each as its own anchor, and keeps improving a piece as you look at it again. So a block turns up many times under the same identity, and the newest reading replaces the last. Blocks arrive at up to 15 a second while you walk.

**Rebuild the mesh when it changes, never once per frame.** A scanned room reaches hundreds of thousands of triangles, and `draw()` runs far faster than blocks arrive. `sceneMeshVersion` is the gate:

```swift
var room = Mesh(positions: [], indices: [])
var built: Int?

override func draw() {
    if device.sceneMeshVersion != built {
        built = device.sceneMeshVersion
        room = device.sceneMesh.mesh          // the whole room, one Mesh
    }
    drawMesh(room)
}
```

`PhoneSceneMesh` gives three shapes of the same room:

```swift
let scan = device.sceneMesh
scan.mesh                            // Mesh, the whole room, world space, meters
scan.mesh(of: .floor, .table)        // Mesh, only the labels you ask for
scan.mesh { surface in ... }         // Mesh, painted a color per triangle
```

Plus what you need to frame it and report it: `chunks`, `chunkCount`, `vertexCount`, `triangleCount`, `bounds`, `center`, `isEmpty`, and `foundSurfaces` (the labels the scan has actually produced).

A label is a `PhoneSurface`: `wall`, `floor`, `ceiling`, `table`, `seat`, `window`, `door`, or `unclassified`. **Early in a scan almost everything is `unclassified`**, because ARKit decides what a surface is only once it has seen enough of it. That is the honest picture rather than a fault, so a sketch that keys off labels should say so while the room fills in. `foundSurfaces` tells you what is available.

```swift
// A floor you could stand something on, and the rest of the room behind it.
fill(Color(white: 0.25)); drawMesh(scan.mesh)
fill(Color(hex: 0x4C9A6B)); drawMesh(scan.mesh(of: .floor))
```

Positions are in ARKit's fixed, gravity-aligned world space, in meters. That is the same space `latestPose` reports, so a mesh block and a fused cloud from one session line up.

Starting a scan resets that world origin, which would leave an older room floating in a space that no longer exists. So every block says which run of the scanner it came from, and `PhoneDevice` drops the room it was holding the moment a new run begins. Leaving Mesh mode and coming back is a new run.

Scene reconstruction needs a LiDAR sensor, so Mesh mode is Pro-tier iPhones only. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneRoomMesh`.

## Segmentation

In **Segment** mode the phone's rear camera runs ARKit's on-device **person segmentation**. The Neural Engine separates the people in the scene from the background, and the phone streams the matte plus the color frame. `PhoneDevice` turns them into two drawable `Image`s:

```swift
device.latestSegmentationMatte       // Image?, a tintable white-alpha silhouette
device.latestSegmentationCutout      // Image?, the person, lifted off the background
```

Both are `nil` until a Segment-mode frame arrives, and both line up with each other when drawn into the same rectangle. The **matte** is white with the person's alpha, so `tint(_:)` recolors it into a silhouette, a drop shadow, or a colored glow. The **cutout** keeps the camera's own pixels where the matte is on and is transparent elsewhere: the person ready to composite over anything. The cutout costs a little more to build, since the color is masked, so it's produced only when you read it.

```swift
guard let cutout = device.latestSegmentationCutout else {
    return drawStatus(device.waitingMessage, style: .info)
}
let rect = Rectangle(fitting: Vector2(Double(cutout.width), Double(cutout.height)),
                     in: canvasRectangle)
drawImage(cutout, in: rect)           // the person over whatever you drew first
```

The matte and cutout come back **upright** for how the phone is held, and they stay aligned with each other. The capture app sends the device orientation and `PhoneDevice` rotates both to match. Person segmentation needs an A12 or later iPhone, and uses the **rear** camera. ARKit's segmentation is rear-only, and a front or selfie matte is a later addition. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneSegmentation`.

## Device motion

`PhoneMotion` is the CoreMotion sample: attitude as a quaternion, gravity, rotation rate, and user acceleration. It's the cheap payload that proves the USB transport before any model runs:

```swift
if let m = device.latestMotion {
    m.gravity                        // Vector3, gravity direction, in g
    m.attitude                       // SIMD4<Float>, orientation quaternion (x,y,z,w)
    m.rotationRate                   // Vector3, rad/s
    m.userAcceleration               // Vector3 in g, gravity removed
}
```

Tilt the phone and `gravity` swings, a one-line check that the wire is alive.

## Notes

- **The wire is Ollin's own, shared verbatim.** Both ends are Swift, so the protocol skips the packed-image trick cross-language tools use. It is a length-prefixed stream of tagged binary messages, `PhoneWire`. That one source file is compiled into *both* the Mac satellite and the iOS app, so the framing can't drift between them.
- **USB only.** The transport is the `usbmuxd` tunnel over the cable, on port 1338, distinct from Record3D's 1337. Wi-Fi is deliberately out.
- **Per-frame clouds are camera-relative, and fusion is world-space.** A single `pointCloud(...)` is in the camera's own frame, root at the lens, and the skeleton is in model space, root at the origin. [World fusion](#world-fusion) is what lifts a sweep into one fixed world cloud, by applying each frame's `latestPose`. It fuses several poses' clouds into a single *registered* scene, but not the richer multi-frame tricks like loop closure and drift correction. So a long sweep drifts with ARKit's own tracking.
- **Depth is raw over the wire.** The LiDAR depth map ships uncompressed, and a 256×192 frame is ~196 KB, comfortable over USB. LZFSE compression is a later optimization. The color image is sent as a downscaled JPEG.
- **A growing catalog.** Body pose, face, world depth, the room mesh, person segmentation, and motion are the payloads today. Richer sensors are the same app sending new tagged payloads, not new pipelines.
- **A mesh block is carried raw, and sending is what is throttled.** The phone reads a block's geometry the moment ARKit hands it over, since those buffers belong to the session. It then queues the block and sends a few at a time. A block too big for one payload is skipped and counted on the app's own screen.
