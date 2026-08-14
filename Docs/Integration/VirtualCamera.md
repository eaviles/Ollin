#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Virtual camera`</sup>

---

## Virtual camera

Turn a sketch into a webcam. The Ollin Camera virtual camera is a system-wide camera device. Anything that takes a webcam can read a sketch as a live input: Photo Booth, QuickTime, Zoom, Meet, OBS, and, importantly, the browser. Web tools like [Hydra](https://hydra.ojack.xyz) reach cameras through `getUserMedia`. An app-to-app transport like [Syphon](../Integration/Syphon.md) can't cross that boundary, so a virtual camera is the one live input the browser sandbox trusts. The publish side lives in a separate library so the drawing core stays free of the dependency. Add `import OllinCamera` alongside `import Ollin` to reach it.

```text
   Ollin sketch                Ollin Camera               any webcam app
   ┌─────────────┐  IOSurface  ┌─────────────┐  capture   ┌───────────────────┐
   │  draw() ──→  │ ──────────→ │  extension  │ ─────────→ │ Zoom / browser / … │
   └─────────────┘             └─────────────┘            └───────────────────┘
```

```swift
import Ollin
import OllinCamera

final class Visuals: Sketch {
    override func setup() {
        publishVirtualCamera()      // every frame now feeds the camera
    }
    override func draw() {
        background(.black)
        drawCircle(width / 2, height / 2, (120 + sin(time) * 60) * scale)
    }
}
```

### Contents

- [Installing the camera](#installing-the-camera) - the one-time setup
- [Publishing your frames](#publishing-your-frames) - `publishVirtualCamera`
- [The test card](#the-test-card) - what the camera shows when nothing is publishing
- [How frames travel](#how-frames-travel) - frame size, color, and the GPU path
- [If the picture looks mirrored or cropped](#if-the-picture-looks-mirrored-or-cropped)

<a name="installing-the-camera"></a>

### Installing the camera

The camera device itself is a macOS system extension, installed once by the **Ollin Camera** app (built from [`Apps/OllinCameraApp`](../../Apps/OllinCameraApp/README.md) in this repo). Launch it from `/Applications`, then approve the extension in *System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions*. From then on, "Ollin Camera" appears in every app's camera menu. No sketch needs to be running for the device to exist.

After that one-time step, any Ollin process can feed it: a plain `swift run` sketch, the live host, anything. If a sketch publishes while the camera isn't installed, nothing breaks, since the sketch keeps drawing, `isAvailable` stays `false`, and `unavailableReason` says what to do.

<a name="publishing-your-frames"></a>

### Publishing your frames

```swift
@discardableResult
func publishVirtualCamera(deviceName: String = "Ollin Camera") -> VirtualCameraServer   // on Sketch

VirtualCameraServer(deviceName: String = "Ollin Camera")
var isAvailable: Bool           // is the camera installed and reachable?
var unavailableReason: String?  // what to do when it isn't
var isPublishing: Bool          // has at least one frame gone out?
func stop()
```

Call `publishVirtualCamera()` in `setup()` and the sketch's frames feed the camera from then on. It builds a `VirtualCameraServer` and registers it as a [`SketchExtension`](../Core/Sketch.md), then returns it so you can check the connection:

```swift
let camera = publishVirtualCamera()
// …later, in draw():
if let reason = camera.unavailableReason {
    drawText(reason, 40, height - 40)
}
```

The server keeps retrying quietly while the camera is unreachable, so installing the camera mid-run picks the sketch up without a restart. Publishing only costs anything while it's connected, so a sketch that doesn't publish pays nothing.

<a name="the-test-card"></a>

### The test card

While no sketch is feeding it, the camera shows a broadcast-style test card. It has color bars, grayscale steps, a live clock, and a **NO SIGNAL** band. A viewer can always tell that the camera itself works. Run a publishing sketch and the picture switches over within a frame or two. Quit the sketch and the test card comes back about a second later. The clock and a moving dot make it obvious the card is a live picture, not a stuck frame.

<a name="how-frames-travel"></a>

### How frames travel

The published frame is the rendered canvas, taken straight from the GPU. It travels the same rendered-texture path Syphon publishes through. Ollin scales it to fit the camera's fixed **1280×720** frame, and centers it over black bars when the aspect doesn't match. A 16:9 canvas fills the camera frame exactly, so set `canvasSize = .size(1280, 720)` for that. The default square canvas gets pillarbox bars. The frame crosses to the camera extension as shared memory, an IOSurface, with no CPU round-trip in the sketch's process.

Color is carried as display-ready (sRGB-encoded) bytes, so tones in the camera match the sketch window. The camera runs at 30 fps. A faster sketch publishes every other frame, and a slower one updates the camera at its own pace.

<a name="if-the-picture-looks-mirrored-or-cropped"></a>

### If the picture looks mirrored or cropped

Some apps change how they *display* a camera, and it can look like the feed is wrong when it isn't:

- **Photo Booth mirrors every camera preview**, like a selfie mirror, so text in a sketch reads backwards there, the same way it does on the built-in camera. Conferencing apps usually mirror your self-view too (while sending the unmirrored picture to everyone else).
- **Photo Booth also crops**, because its preview pane isn't 16:9, so it scales the frame to fill and trims the edges.

QuickTime (File ▸ New Movie Recording) shows the frame as published, unmirrored and complete. It is the quickest way to check what other apps actually receive.

---

See the **VirtualCamera** example (`Examples/Integration/VirtualCamera`) for a publishing sketch with an on-canvas ON AIR badge. See [`Apps/OllinCameraApp`](../../Apps/OllinCameraApp/README.md) for how the camera device itself is built and installed.
