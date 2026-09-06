#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Virtual camera`</sup>

---

## Virtual camera

A virtual camera turns a sketch into a webcam. The Ollin Camera device is a system-wide virtual camera. Any app that takes a webcam can then read a sketch as a live input. That includes Photo Booth, QuickTime, Zoom, Meet, OBS, and the browser. The browser matters because web tools like [Hydra](https://hydra.ojack.xyz) reach cameras through `getUserMedia`. An app-to-app transport like [Syphon](../Integration/Syphon.md) cannot cross the browser sandbox, which means a virtual camera is the one live input the browser accepts. The publish side lives in a separate library, so the drawing core does not depend on it. Add `import OllinCamera` beside `import Ollin` to use it.

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

The camera device is a macOS system extension, and the **Ollin Camera** app installs it once. That app is built from [`Apps/OllinCameraApp`](../../Apps/OllinCameraApp/README.md) in this repo. Launch the app from `/Applications`, then approve the extension in *System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions*. After that, "Ollin Camera" appears in every app's camera menu. The device exists whether or not a sketch is running.

Once the camera is installed, any Ollin process can feed it, including a plain `swift run` sketch, the live host, or anything else you run. If a sketch publishes while the camera is not installed, nothing breaks. The sketch keeps drawing, `isAvailable` stays `false`, and `unavailableReason` says what to do.

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

Call `publishVirtualCamera()` in `setup()`. From then on, the sketch's frames feed the camera. The call builds a `VirtualCameraServer` and registers it as a [`SketchExtension`](../Core/Sketch.md). It then returns the server, so you can check the connection:

```swift
let camera = publishVirtualCamera()
// …later, in draw():
if let reason = camera.unavailableReason {
    drawText(reason, 40, height - 40)
}
```

While the camera is unreachable, the server keeps retrying quietly in the background. Because of that, you can install the camera while the sketch runs, and it starts showing the sketch without a restart. Publishing costs something only while the camera is connected. A sketch that never publishes pays nothing.

<a name="the-test-card"></a>

### The test card

While no sketch is feeding it, the camera shows a broadcast-style test card. The card has color bars, grayscale steps, a live clock, and a **NO SIGNAL** band. The card tells a viewer that the camera itself works. When you run a publishing sketch, the picture switches over within a frame or two. When you quit the sketch, the test card comes back about a second later. The clock and a moving dot show that the card is a live picture, not a stuck frame.

<a name="how-frames-travel"></a>

### How frames travel

The published frame is the rendered canvas, taken straight from the GPU. It travels the same rendered-texture path that Syphon publishes through. Ollin scales the picture to fit the camera's fixed **1280×720** frame. When the aspect ratio does not match, Ollin centers the picture over black bars. A 16:9 canvas fills the camera frame exactly, so set `canvasSize = .size(1280, 720)` when you want that. The default square canvas gets pillarbox bars. The frame crosses to the camera extension as shared memory (an IOSurface), so there is no CPU round-trip in the sketch's process.

Color travels as display-ready bytes, which are sRGB-encoded, so tones in the camera match the sketch window. The camera runs at 30 fps. A faster sketch publishes every other frame, and a slower sketch updates the camera at its own pace.

<a name="if-the-picture-looks-mirrored-or-cropped"></a>

### If the picture looks mirrored or cropped

Some apps change how they *display* a camera, so the feed can look wrong when nothing is wrong with it:

- **Photo Booth mirrors every camera preview.** Text in a sketch reads backwards there, the same way it does on the built-in camera. Conferencing apps usually mirror your self-view too, while they send the unmirrored picture to everyone else.
- **Photo Booth also crops.** Its preview pane is not 16:9, so it scales the frame to fill the pane and trims the edges.

QuickTime (File ▸ New Movie Recording) shows the frame as published, unmirrored and complete. It is the quickest way to check what other apps receive.

---

The **VirtualCamera** example (`Examples/Integration/VirtualCamera`) is a publishing sketch with an on-canvas ON AIR badge. [`Apps/OllinCameraApp`](../../Apps/OllinCameraApp/README.md) explains how the camera device itself is built and installed.
