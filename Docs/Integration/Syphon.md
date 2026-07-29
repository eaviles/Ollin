#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Syphon`</sup>

---

## Syphon

Share live visuals with the other apps running on your Mac. Syphon is the macOS standard for passing GPU frames between applications in real time, and the creative-coding ecosystem already speaks it: openFrameworks (through `ofxSyphon`), Resolume, MadMapper, VDMX, and Syphon's own Simple Client and Simple Server. So an Ollin sketch can send its frames into a VJ rig, or draw a feed coming from another app, without anything touching disk. It lives in a separate library so the drawing core stays free of the dependency. Add `import OllinSyphon` alongside `import Ollin` to reach it.

It works two ways, and a sketch can do either or both:

- a **[server](#sharing-your-frames)** publishes the sketch's rendered frames as a Syphon *source* other apps can read.
- a **[client](#receiving-a-feed)** subscribes to a source from another app and hands you each frame as an [`Image`](../Drawing/Images.md) you draw with `drawImage`.

```text
   Ollin (server)                 another app (client)
   ┌──────────────┐  GPU texture  ┌────────────────────┐
   │  draw() ───→  │ ────────────→ │ Resolume / oF / …  │
   └──────────────┘  (IOSurface)  └────────────────────┘
```

Pairs naturally with [OSC](../Integration/OSC.md) or [MIDI](../Integration/MIDI.md): visuals over Syphon, control over OSC, both directions at once.

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

Call `publishSyphon(name:)` in `setup()` and the sketch's frames are shared from then on, under that name. The name is how consumers identify the source (usually paired with the app's name in their menus), and it needn't be unique. That's all it takes:

```swift
override func setup() {
    publishSyphon(name: "Ollin")
}
```

`publishSyphon` builds a `SyphonServer` and registers it as a [`SketchExtension`](../Core/Sketch.md), then returns it so you can check `hasClients`, which helps if a frame is expensive to draw and you'd rather skip the work when nobody's watching:

```swift
let syphon = publishSyphon(name: "Ollin")
// …later, in draw():
if syphon.hasClients { drawTheExpensiveLayer() }
```

The frame you publish is exactly what the sketch renders, taken straight from the GPU (see [below](#how-frames-are-shared)). Sharing only costs anything while it's on, so a sketch that doesn't publish pays nothing.

<a name="receiving-a-feed"></a>

### Receiving a feed

```swift
SyphonClient()                                  // first available source
SyphonClient(named: String?, appName: String?)  // match by name and/or app
SyphonClient(source: SyphonServerInfo)          // a specific discovered source

func newFrame() -> Image?     // the latest frame, or nil if none yet
var isActive: Bool            // connected to a live source?
var hasNewFrame: Bool         // a new frame since the last newFrame()?
var serverName: String?
var appName: String?
func reconnect(named: String?, appName: String?)
func stop()
```

Make a client, then read its frames in `draw()`. `newFrame()` hands you the latest frame as an [`Image`](../Drawing/Images.md) backed by the source's live GPU texture, so you draw it like any other image: scaled, into a `Rectangle`, tinted, under the transform stack:

```swift
final class Viewer: Sketch {
    let feed = SyphonClient()           // first source on the system

    override func draw() {
        background(.black)
        if let frame = feed.newFrame() {
            drawImage(frame, 0, 0, width, height)
        }
    }
}
```

Call `newFrame()` each frame and draw the result, and don't hold onto it across frames (the next call gives you the current frame). A source can come and go, so if the publishing app quits, `isActive` goes `false` and `newFrame()` returns `nil`, and `reconnect()` looks again. Because the returned `Image` wraps a live texture, its CPU side (the `[x, y]` pixel subscript, `cgImage`) isn't meaningful, since it's for drawing.

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

`availableServers()` lists every Syphon source on the system right now, so you can show a picker or connect to a specific one:

```swift
for source in SyphonClient.availableServers() {
    print(source.label)
}
let feed = SyphonClient(named: "Composition", appName: "Resolume Arena")
```

<a name="how-frames-are-shared"></a>

### How frames are shared

A published frame is the rendered canvas, handed over on the GPU with no CPU round-trip, so Ollin re-renders the frame off-screen into a texture and shares that, which is pixel-identical to what's on screen and to `--export`. Syphon carries it as an `IOSurface`, so another app reads the same memory rather than a copy over a wire.

Sharing happens on the sketch's own Metal device, and a client connects on the system's default device. On a single-GPU Mac (the common case) those are the same, which is what every consumer expects. On a multi-GPU machine they can differ, and that case isn't handled.

Orientation and color are handled so the frame looks right both in another app and back in Ollin. Frames are published with the vertical flip Syphon's convention wants (so consumers like Simple Client, `ofxSyphon`, and Resolume show them upright), and a feed read by `SyphonClient` is flipped back to Ollin's top-left space. Color is carried as display-ready (sRGB-encoded) bytes, the Syphon convention, so tones match across apps. (A small residual difference between Ollin's own window and another app is normal, since each app presents the shared surface through its own display color handling.)

<a name="testing-without-a-second-app"></a>

### Testing without a second app

You can exercise Syphon with nothing but the Mac in front of you. The **SyphonLoopback** example (`Examples/Integration/SyphonLoopback`) runs both ends in one sketch, publishing its own frames *and* subscribing to them, drawing the received frame back as an inset. Because that inset is part of the next published frame, you get a video-feedback tunnel, the round-trip made visible, the way the **OSCLoopback** example shows an OSC message making its trip.

To prove the cross-app path, run a sketch that publishes and open **Syphon's Simple Client** (a small free app from [syphon.github.io](https://syphon.github.io) that lists every source and shows the one you pick). "Ollin" should appear there, and in an `ofxSyphon` sketch, Resolume, or MadMapper just the same. Going the other way, the **SyphonViewer** example (`Examples/Integration/SyphonViewer`) subscribes to any external source and draws it letterboxed, listing what it can see while it waits, so point Syphon's **Simple Server** (or any publisher) at it.

---

See the **SyphonLoopback** example for a self-contained publish-and-subscribe sketch that needs no second app to run, and **SyphonViewer** for displaying a feed from another application.
