#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Phone`</sup>

---

## Phone (iPhone sensor stream)

Borrow a tethered iPhone's on-device perception in a sketch that still renders on the Mac. **Ollin Capture** — Ollin's own iOS app ([`Apps/OllinPhoneApp`](../Apps/OllinPhoneApp/README.md)) — runs ARKit on the phone's Neural Engine and streams the results over the USB cable; `PhoneDevice` reads them on the Mac as typed values you use in `draw()`. It streams a **3D body skeleton**, a **face** (deforming mesh + the 52 expression blendshapes), a world-facing **RGBD depth frame** from the rear LiDAR (a point cloud, with the camera's 6DoF pose), and **device motion**.

Where [`Record3D`](./Record3D.md) borrows another app's color-plus-depth feed, this is Ollin's own app, so the stream carries what ARKit *perceives* — a body, a face, world-facing depth, and motion today, with more sensors (segmentation, richer depth) to come. The chain is Ollin's end to end.

`PhoneDevice` lives in a separate library so the drawing core stays lean; add `import OllinPhone` alongside `import Ollin`. The transport is the standard `usbmuxd` device tunnel (the same plumbing Xcode uses), so there's no third-party dependency and no Wi-Fi pairing — just the cable.

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

- [Setup](#setup) — install the capture app, connect the cable
- [Reading the stream](#reading-the-stream) — `latestBody`, `latestFace`, `latestDepthFrame`, `latestMotion`, the connection state
- [The body](#the-body) — `PhoneBody`, the joints, drawing the skeleton
- [The face](#the-face) — `PhoneFace`, the blendshapes, the mesh
- [World depth](#world-depth) — `latestDepthFrame`, `pointCloud(...)`, the camera pose
- [Device motion](#device-motion) — `PhoneMotion`, the transport smoke-test
- [Notes](#notes) — the wire, coordinate space, what's ahead

---

## Setup

The sketch side is just `import OllinPhone` and a `PhoneDevice`, but the phone needs the capture app:

1. **Build Ollin Capture onto the iPhone.** It's an xcodegen + Xcode project (an iOS app can't be `swift run`). From [`Apps/OllinPhoneApp`](../Apps/OllinPhoneApp/README.md): `xcodegen generate`, open the project, select the phone, and Run. Needs an A12+ iPhone on iOS 17+ and automatic signing (see that README for the device-registration step).
2. **Connect the cable** and launch the app — its screen reads **READY** until the Mac connects, then **ON AIR**.
3. **Run the sketch** on the Mac. `PhoneDevice` retries on its own, so launching the app (or plugging in) after the sketch is already running just begins the feed.

The bundled example is `swift run Example-PhoneBodyPose`.

## Reading the stream

`PhoneDevice` mirrors `Record3DDevice`'s shape — `start()` / `stop()`, a `waitingMessage` for the pre-connection notice, and `isStreaming`:

```swift
let device = PhoneDevice()
device.start()                       // begins connecting; safe to call once

device.isStreaming                   // Bool — frames currently arriving
device.waitingMessage                // a notice reflecting the live connection state
device.latestBody                    // PhoneBody?  — the latest skeleton (Body mode)
device.latestFace                    // PhoneFace?  — the latest face (Face mode)
device.latestDepthFrame              // RGBDFrame?  — the latest depth frame (World mode)
device.latestMotion                  // PhoneMotion? — the latest device-motion sample
```

These are fresh each time the phone sends one; read them within the current `draw()`. Each is `nil` until the first of its kind arrives — so motion typically lights up first (it needs no camera or model), proving the wire before ARKit has found a body, face, or depth.

**The three camera modes are mutually exclusive.** Body and World use the rear camera, Face the front TrueDepth camera, and only one ARKit session runs at a time. The capture app has a **Body / Face / World** toggle; whichever is selected is the one that updates (`latestBody`, `latestFace`, or `latestDepthFrame`). The others hold their last value, so read the one for the mode you mean to drive. (Motion streams across all three.)

## The body

`PhoneBody` carries every reported joint as a 3D position in **meters**, model space — the pelvis root at the origin, x to the picture's right, y up. Its accessor shape matches `Body3D` and `LiftedPose` from [`OllinVision`](./Vision.md):

```swift
if let body = device.latestBody {
    body.isTracked                   // Bool — ARKit tracking vs. extrapolating
    body.position(.head)             // Vector3? — one joint, model space
    body.positions                   // [PhoneJoint: Vector3]
    body.bones()                     // [(Vector3, Vector3)] — segments to draw
    body.center                      // Vector3 — centroid, to aim an orbiting camera
}
```

The joints are the `PhoneJoint` set — a practical subset of ARKit's ~91-joint skeleton (root, hips, spine, chest, neck, head, the arms and legs out to hands and feet). A joint ARKit didn't report this frame is simply absent.

3D mode has no line primitive yet, so the shipped way to draw the skeleton is as a `PointCloud` — each joint a splat, each bone a dotted line of splats — exactly like `LiftedPose.cloud`:

```swift
camera(.orbiting(target: body.center, radius: 2.6, azimuth: time * 0.4, elevation: 0.12))
drawPointCloud(body.cloud(jointSize: 0.055, boneSize: 0.018, color: .white))
```

## The face

In **Face** mode the phone tracks the operator's face on the front TrueDepth camera and streams `PhoneFace` — the 52 expression **blendshapes**, the deforming **mesh**, and the **head pose**:

```swift
if let face = device.latestFace {
    face.isTracked                   // Bool — ARKit tracking vs. extrapolating
    face.blendShape(.jawOpen)        // Double 0…1 — one expression coefficient
    face.blendShapes                 // [PhoneBlendShape: Double] — all 52
    face.strongestBlendShapes()      // the few firing now, strongest first
    face.meshPoints                  // [Vector3] — the mesh, face-local space (meters)
    face.headPosition                // Vector3 — head position in world space
    face.headOrientation             // SIMD4<Float> — head rotation quaternion (x,y,z,w)
}
```

The blendshapes are the `PhoneBlendShape` set — ARKit's 52 named coefficients (`jawOpen`, `eyeBlinkLeft`, `mouthSmileLeft`, `browInnerUp`, `cheekPuff`, `tongueOut`, …), each `0` (neutral) to `1` (fully expressed). They're the cheap, expressive payload: read one to drive a knob, or `strongestBlendShapes()` to name the current expression.

3D mode has no mesh primitive yet, so the mesh draws as a `PointCloud` — one splat per vertex, exactly like the skeleton. The vertices are face-local (centered on the face), so orbit `.zero`:

```swift
camera(.orbiting(target: .zero, radius: 0.42, azimuth: time * 0.4, elevation: 0.04))
drawPointCloud(face.cloud(pointSize: 0.0045, color: .white))
```

The bundled example is `swift run Example-PhoneFace`.

## World depth

In **World** mode the phone's rear **LiDAR** streams a world-facing RGBD frame — a metric depth map, the matching color image, the camera intrinsics, per-pixel confidence, and the camera's 6DoF pose. `PhoneDevice` exposes it as the source-agnostic core [`RGBDFrame`](./RGBD.md), so it unprojects into a point cloud the same way every depth source does. Needs a LiDAR iPhone (a Pro model).

```swift
if let cloud = device.pointCloud(depthRange: 0.3...5.0) {
    camera(.orbiting(target: .zero, radius: 2.5, azimuth: time * 0.3, elevation: 0.18))
    drawPointCloud(cloud)
}

device.latestDepthFrame              // RGBDFrame? — depth + color + intrinsics
device.latestPose                    // simd_float4x4? — the camera's 6DoF pose
```

`pointCloud(...)` is sugar over `latestDepthFrame?.pointCloud(...)` with rear-LiDAR defaults (`minimumConfidence: .medium`, an open depth range); see [`RGBD.md`](./RGBD.md) for the full unprojection parameters and the coordinate space (camera-relative, +x right, +y up, looking −z). For finer control — sampling a single depth point, lifting a 2D pose to metric 3D — reach for `latestDepthFrame` and the `RGBDFrame` API directly.

`PhoneDevice` is also a `FrameSource` and a `VideoFeed` in this mode, so a vision tracker can analyze the color feed and `drawFrame` can letterbox it (the color frame is only present while World mode is streaming).

The bundled example is `swift run Example-PhoneDepthCloud`.

## Device motion

`PhoneMotion` is the CoreMotion sample — attitude (a quaternion), gravity, rotation rate, and user acceleration — the cheap payload that proves the USB transport before any model runs:

```swift
if let m = device.latestMotion {
    m.gravity                        // Vector3 — gravity direction, in g
    m.attitude                       // SIMD4<Float> — orientation quaternion (x,y,z,w)
    m.rotationRate                   // Vector3 — rad/s
    m.userAcceleration               // Vector3 — g, gravity removed
}
```

Tilt the phone and `gravity` swings — a one-line check that the wire is alive.

## Notes

- **The wire is Ollin's own, shared verbatim.** Both ends are Swift, so the protocol skips the packed-image trick cross-language tools use: a length-prefixed stream of tagged binary messages (`PhoneWire`). That one source file is compiled into *both* the Mac satellite and the iOS app, so the framing can't drift between them.
- **USB only.** The transport is the `usbmuxd` tunnel over the cable (port 1338, distinct from Record3D's 1337). Wi-Fi is deliberately out.
- **Camera space, for now.** The skeleton is in model space (root at the origin) and the depth cloud is camera-relative. World mode *does* carry the per-frame camera pose (`latestPose`) — the input for placing a frame in a scene and fusing several frames into one world cloud — but applying it (world placement, fusion) is a later slice.
- **Depth is raw over the wire.** The LiDAR depth map ships uncompressed (a 256×192 frame is ~196 KB, comfortable over USB); LZFSE compression is a later optimization. The color image is sent as a downscaled JPEG.
- **A growing catalog.** Body pose, face, world depth, and motion are the shipped payloads; segmentation mattes and richer sensors are the same app sending new tagged payloads, not new pipelines.
