# Ollin Capture — iPhone sensor app

Ollin's own iPhone capture app: the phone runs **ARKit body tracking**, **face
tracking**, and **rear-LiDAR scene depth** on its Neural Engine, plus **CoreMotion**
device motion, and streams them to a tethered Mac over USB. An Ollin sketch on the Mac
reads the live skeleton, face, depth cloud, or motion in `draw()` through the
[`OllinPhone`](../../Sources/OllinPhone) satellite (`PhoneDevice`).

This is the own-app successor to borrowing the Record3D app's RGBD feed
([`OllinRecord3D`](../../Sources/OllinRecord3D)): it streams what ARKit *perceives* —
a 3D body skeleton, a face mesh with its 52 expression blendshapes, a world-facing
RGBD depth frame (a point cloud, with the camera's 6DoF pose), and device motion
today, more sensors (segmentation, scene mesh) to come. The chain is Ollin's end to
end.

Body and World use the rear camera and face tracking the front TrueDepth camera, and
only one ARKit session runs at a time — the app has a **Body / Face / World** toggle
and runs one mode at a time. Device motion streams in all three.

## How it fits together

- **The wire format is shared, not duplicated.** [`PhoneWire.swift`](../../Sources/OllinPhone/PhoneWire.swift)
  lives in the `OllinPhone` Mac target and is compiled *verbatim* into this app too
  (see `project.yml`'s `sources`). It imports only Foundation/simd — never Ollin or
  Metal — so the same source builds on both ends and the framing can't drift.
- **Transport is the standard usbmuxd USB tunnel.** The app opens an `NWListener` on
  TCP `PhoneWire.streamPort` (1338, distinct from Record3D's 1337); the Mac's
  `PhoneDevice` tunnels to it through usbmuxd. No Wi-Fi, no pairing — just the cable.
- **One-way push.** Each ARKit body/face/depth update and motion sample is encoded
  with `PhoneWire` and broadcast to the connected Mac. The device-motion payload is
  the cheap transport smoke-test: it moves the instant the wire is alive, before ARKit
  has found a body, face, or depth. The depth payload is by far the heaviest (a
  256×192 LiDAR frame + a JPEG color image), so it streams only in World mode.

## Build & deploy

Like [`Apps/OllinCameraApp`](../OllinCameraApp), this builds through xcodegen +
Xcode, not SwiftPM (an iOS app is installed onto a device, not `swift run`).

```sh
cd Apps/OllinPhoneApp
xcodegen generate          # writes OllinPhoneApp.xcodeproj (gitignored)
open OllinPhoneApp.xcodeproj
# select "Edgardo's iPhone 15 Pro Max" as the run destination, then Run (⌘R)
```

Or headless:

```sh
xcodebuild -project OllinPhoneApp.xcodeproj -scheme OllinPhoneApp \
  -destination 'platform=iOS,id=<DEVICE_UDID>' -allowProvisioningUpdates build
```

Requirements:

- **A12+ iPhone** (ARKit body tracking) running iOS 17+. Verified target: iPhone 15
  Pro Max.
- **Automatic signing on team `3ET6D79498`.** The device must be registered in the
  developer account — the first build from the Xcode GUI registers it (the CLI can't
  register a new device without an App Store Connect API key). After that, on first
  launch trust the developer profile under Settings ▸ General ▸ VPN & Device
  Management.

## Run it

1. Build + run on the iPhone. The screen shows **READY** until the Mac connects,
   then **ON AIR**, with the **Body / Face / World** toggle and live status.
2. Connect the cable to the Mac.
3. On the Mac, run a sketch. With the toggle on **Body**: `swift run
   Example-3D-PhoneBodyPose` — the orbiting stick figure is driven by the phone's
   skeleton. On **Face**: `swift run Example-3D-PhoneFace` — the face mesh orbits and the
   expression bars move as you smile, blink, and open your mouth. On **World** (a
   LiDAR iPhone): `swift run Example-3D-PhoneDepthCloud` — point the phone at the room and
   the rear LiDAR's depth becomes a live point cloud. Before tracking begins, the
   gravity readout proves the USB wire is alive (tilt the phone — it moves).

## Notes

- ARKit's body skeleton is ~91 joints addressed by string name; `ARStreamer`
  maps a practical subset onto `PhoneJoint`. On the first tracked body it logs the
  device's real joint-name list (visible by running the binary directly, not under
  `open`, since NSLogs are privacy-redacted), so the mapping can be tuned against the
  device if a name doesn't resolve.
- The face stream (`FaceStreamer`) carries the deforming mesh in face-local space,
  the 52 blendshapes positionally in `PhoneBlendShape` order, and the head pose. Face
  tracking needs a TrueDepth front camera (Face ID devices).
- The depth stream (`DepthStreamer`) runs `ARWorldTrackingConfiguration` with scene
  depth (smoothed where supported) and sends the LiDAR depth map, a JPEG color image,
  the intrinsics scaled to the depth grid, per-pixel confidence, and the camera's
  6DoF transform. Scene depth needs a **LiDAR** sensor (Pro-tier iPhones); the World
  segment reports it unsupported otherwise. The Mac decodes it into a core `RGBDFrame`.
- The skeleton/face cloud is in **model space** (root or face at the origin) and the
  depth cloud is camera-relative. World mode carries the per-frame camera pose, but
  world placement / multi-frame fusion using it is a later slice.
