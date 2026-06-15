# Ollin Capture — iPhone sensor app

Ollin's own iPhone capture app: the phone runs **ARKit body tracking** on its
Neural Engine and **CoreMotion** device motion, and streams both to a tethered Mac
over USB. An Ollin sketch on the Mac reads the live skeleton in `draw()` through the
[`OllinPhone`](../../Sources/OllinPhone) satellite (`PhoneDevice`).

This is the own-app successor to borrowing the Record3D app's RGBD feed
([`OllinRecord3D`](../../Sources/OllinRecord3D)): where Record3D gives depth only,
this streams what ARKit *perceives* — a 3D body skeleton today, more sensors (face
mesh + blendshapes, segmentation, LiDAR depth) to come. The chain is Ollin's end to
end.

## How it fits together

- **The wire format is shared, not duplicated.** [`PhoneWire.swift`](../../Sources/OllinPhone/PhoneWire.swift)
  lives in the `OllinPhone` Mac target and is compiled *verbatim* into this app too
  (see `project.yml`'s `sources`). It imports only Foundation/simd — never Ollin or
  Metal — so the same source builds on both ends and the framing can't drift.
- **Transport is the standard usbmuxd USB tunnel.** The app opens an `NWListener` on
  TCP `PhoneWire.streamPort` (1338, distinct from Record3D's 1337); the Mac's
  `PhoneDevice` tunnels to it through usbmuxd. No Wi-Fi, no pairing — just the cable.
- **One-way push.** Each ARKit body update and motion sample is encoded with
  `PhoneWire` and broadcast to the connected Mac. The device-motion payload is the
  cheap transport smoke-test: it moves the instant the wire is alive, before ARKit
  has found a body.

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
   then **ON AIR**, with live body/motion/port status.
2. Connect the cable to the Mac.
3. On the Mac, run the sketch: `swift run Example-PhoneBodyPose`. The orbiting stick
   figure is driven by the phone's skeleton; before a body is found, the gravity
   readout proves the USB wire is alive (tilt the phone — it moves).

## Notes

- ARKit's body skeleton is ~91 joints addressed by string name; `ARStreamer`
  maps a practical subset onto `PhoneJoint`. On the first tracked body it logs the
  device's real joint-name list (visible by running the binary directly, not under
  `open`, since NSLogs are privacy-redacted), so the mapping can be tuned against the
  device if a name doesn't resolve.
- The cloud is the skeleton in **model space** (root at the origin). The per-frame
  ARKit world transform and world placement / multi-frame fusion are a later slice,
  as on the Record3D path.
