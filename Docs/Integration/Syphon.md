#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Syphon`</sup>

---

## Syphon

Syphon shares live visuals with the other apps running on your Mac. It is the macOS standard for passing GPU frames between applications in real time, and many creative-coding tools already support it. Those include openFrameworks (through `ofxSyphon`), Resolume, MadMapper, VDMX, and Syphon's own Simple Client and Simple Server. So an Ollin sketch can send its frames into a VJ rig, or draw a feed coming from another app, and nothing touches disk. Ollin's Syphon support lives in a separate library, which keeps the drawing core free of the dependency. Add `import OllinSyphon` alongside `import Ollin` to reach it.

Syphon works in two directions, and a sketch can use one of them or both:

- a **[server](#sharing-your-frames)** publishes the sketch's rendered frames as a Syphon *source*, which other apps can read.
- a **[client](#receiving-a-feed)** subscribes to a source from another app. It gives you each frame as an [`Image`](../Drawing/Images.md), and you draw that image with `drawImage`.

```text
   Ollin (server)                 another app (client)
   ┌──────────────┐  GPU texture  ┌────────────────────┐
   │  draw() ───→  │ ────────────→ │ Resolume / oF / …  │
   └──────────────┘  (IOSurface)  └────────────────────┘
```

Syphon works well next to [OSC](../Integration/OSC.md) or [MIDI](../Integration/MIDI.md). You can send visuals over Syphon and control over OSC, in both directions at once.

```swift
import Ollin
import OllinSyphon

final class Visuals: Sketch {
    override func setup() {
        publishSyphon(name: "Ollin")     // every frame is now a Syphon source
    }
    override func draw() {
        background(.black)
        drawCircle(width / 2, height / 2, (120 + sin(time) * 60) * scale)
    }
}
```

### Contents

- [Sharing your frames](#sharing-your-frames) - publish a Syphon source
- [Receiving a feed](#receiving-a-feed) - draw an incoming source as an `Image`
- [Discovering sources](#discovering-sources) - list what's available
- [How frames are shared](#how-frames-are-shared) - the GPU path, and a note on devices
- [Testing without a second app](#testing-without-a-second-app) - loopback, viewer, and Simple Client

<a name="sharing-your-frames"></a>

### Sharing your frames

```swift
@discardableResult
func publishSyphon(name: String = "Ollin") -> SyphonServer   // on Sketch

SyphonServer(name: String = "Ollin")
var hasClients: Bool        // is anyone reading right now?
var isPublishing: Bool      // has at least one frame gone out?
func stop()
```

Call `publishSyphon(name:)` in `setup()`, and the sketch shares its frames from then on under that name. Consumers identify the source by that name, usually paired with the app's name in their menus. The name does not have to be unique. That is all the setup it needs:

```swift
override func setup() {
    publishSyphon(name: "Ollin")
}
```

`publishSyphon` builds a `SyphonServer` and registers it as a [`SketchExtension`](../Core/Sketch.md). It then returns the server, so you can check `hasClients` yourself. That helps when a frame is expensive to draw and nobody is watching:

```swift
let syphon = publishSyphon(name: "Ollin")
// …later, in draw():
if syphon.hasClients { drawTheExpensiveLayer() }
```

The frame you publish is exactly what the sketch renders, taken straight from the GPU (see [below](#how-frames-are-shared)). Sharing costs something only while it is on, so a sketch that does not publish pays nothing.

<a name="receiving-a-feed"></a>

### Receiving a feed

```swift
SyphonClient()                                  // first available source
SyphonClient(named: String?, appName: String?)  // match by name and/or app
SyphonClient(source: SyphonServerInfo)          // a specific discovered source

var frame: Image?             // the latest frame, or nil if none yet
var isActive: Bool            // connected to a live source?
var hasNewFrame: Bool         // a new frame since the last read of frame?
var serverName: String?
var appName: String?
func connect(named: String?, appName: String?)
func stop()
```

Make a client, then read its frames in `draw()`. `frame` gives you the latest frame as an [`Image`](../Drawing/Images.md), backed by the source's live GPU texture. You draw it like any other image, so it scales, fits into a `Rectangle`, takes a tint, and follows the transform stack:

```swift
final class Viewer: Sketch {
    let feed = SyphonClient()           // first source on the system

    override func draw() {
        background(.black)
        if let frame = feed.frame {
            drawImage(frame, 0, 0, width, height)
        }
    }
}
```

Read `frame` once per frame and draw the result. Do not keep it across frames, because the next read gives you the current frame. A source can come and go. If the publishing app quits, `isActive` goes `false` and `frame` reads `nil`, and `connect()` looks for a source again. The returned `Image` wraps a live texture for drawing, so its CPU side (the `[x, y]` pixel subscript and `cgImage`) is not meaningful.

<a name="discovering-sources"></a>

### Discovering sources

```swift
SyphonClient.availableServers() -> [SyphonServerInfo]

struct SyphonServerInfo {
    let name: String?       // the source's name
    let appName: String?    // the app publishing it
    var label: String       // a friendly one-line label, e.g. "Composition (Resolume)"
}
```

`availableServers()` lists every Syphon source on the system right now. Use it to show a picker, or to connect to one particular source:

```swift
for source in SyphonClient.availableServers() {
    print(source.label)
}
let feed = SyphonClient(named: "Composition", appName: "Resolume Arena")
```

<a name="how-frames-are-shared"></a>

### How frames are shared

A published frame is the rendered canvas, handed over on the GPU with no CPU round-trip. Ollin takes the frame the window shows, tone-maps it once more into a texture of the canvas size, and shares that texture. So a feed costs one pass per frame, and nothing is drawn twice. The shared frame is what is on screen, brought to the canvas size, with lit meshes and effects included. Syphon carries it as an `IOSurface`, so another app reads the same memory rather than a copy sent over a wire.

Sharing happens on the sketch's own Metal device, and a client connects on the system's default device. On a single-GPU Mac, which is the common case, those are the same device, and that is what every consumer expects. On a multi-GPU machine they can differ, and Ollin does not handle that case.

Ollin handles orientation and color, so the frame looks right both in another app and back in Ollin. Published frames carry the vertical flip that Syphon's convention asks for, so consumers such as Simple Client, `ofxSyphon`, and Resolume show them upright. A feed read by `SyphonClient` is flipped back into Ollin's top-left space. Color travels as display-ready (sRGB-encoded) bytes, which is the Syphon convention, so tones match across apps. A small difference between Ollin's own window and another app is normal. Each app presents the shared surface through its own display color handling.

<a name="testing-without-a-second-app"></a>

### Testing without a second app

You can test Syphon with nothing but the Mac in front of you. The **SyphonLoopback** example (`Examples/Integration/SyphonLoopback`) runs both ends in one sketch. It publishes its own frames, subscribes to them, and draws each received frame back as an inset. That inset is part of the next published frame, so you get a video-feedback tunnel, which makes the round-trip visible. The **OSCLoopback** example shows an OSC message making the same round-trip.

To check the cross-app path, run a sketch that publishes, then open **Syphon's Simple Client**. That is a small free app from [syphon.github.io](https://syphon.github.io), and it lists every source and shows the one you pick. The name "Ollin" should appear there, and it should appear the same way in an `ofxSyphon` sketch, Resolume, or MadMapper. For the other direction, the **SyphonViewer** example (`Examples/Integration/SyphonViewer`) subscribes to any external source and draws it letterboxed. While it waits, it lists the sources it can see. Point Syphon's **Simple Server**, or any other publisher, at it.

---

See the **SyphonLoopback** example for a sketch that publishes and subscribes, so it needs no second app to run. Use **SyphonViewer** to display a feed from another application.
