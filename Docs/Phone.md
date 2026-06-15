#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Phone`</sup>

---

## Phone (iPhone sensor stream)

Borrow a tethered iPhone's on-device perception in a sketch that still renders on the Mac. **Ollin Capture** — Ollin's own iOS app ([`Apps/OllinPhoneApp`](../Apps/OllinPhoneApp/README.md)) — runs ARKit on the phone's Neural Engine and streams the results over the USB cable; `PhoneDevice` reads them on the Mac as typed values you use in `draw()`. The first slice streams a **3D body skeleton** and **device motion**.

Where [`Record3D`](./Record3D.md) borrows another app's color-plus-depth feed, this is Ollin's own app, so the stream carries what ARKit *perceives* — a body pose today, with more sensors (face mesh + blendshapes, segmentation, LiDAR depth) to come. The chain is Ollin's end to end.

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
- [Reading the stream](#reading-the-stream) — `latestBody`, `latestMotion`, the connection state
- [The body](#the-body) — `PhoneBody`, the joints, drawing the skeleton
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
device.latestBody                    // PhoneBody?  — the latest skeleton
device.latestMotion                  // PhoneMotion? — the latest device-motion sample
```

`latestBody` and `latestMotion` are fresh each time the phone sends one; read them within the current `draw()`. Both are `nil` until the first of their kind arrives — so motion typically lights up first (it needs no camera or model), proving the wire before ARKit has found a body.

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
- **Camera space, for now.** The skeleton is in model space (root at the origin). The per-frame ARKit world transform — for placing the figure in a scene and fusing frames into one world — is a later slice, as on the Record3D path.
- **A growing catalog.** Body pose and motion are the first payloads; face mesh + blendshapes, segmentation mattes, and LiDAR depth are the same app sending new tagged payloads, not new pipelines.
