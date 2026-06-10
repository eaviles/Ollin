#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Video`</sup>

---

## Video

Play a video file into a sketch as a live image. Recorded footage becomes drawing material the same way the [camera](./Vision.md) is: each decoded frame arrives as a GPU texture wrapped in an [`Image`](./Images.md), so it draws with `drawImage`, rides the transform stack, and takes `tint` — with no CPU round-trip per frame. Video lives in a separate library so the drawing core stays free of AVFoundation playback; add `import OllinVideo` alongside `import Ollin` to reach it.

```swift
import Ollin
import OllinVideo

final class Player: Sketch {
    var player: VideoPlayer?

    override func setup() {
        player = try? VideoPlayer(path: "/path/to/clip.mp4")
        player?.loops = true
        player?.play()
    }

    override func draw() {
        background(.black)
        if let player, let frame = player.frame,
           let rect = player.fittedRect(in: bounds) {
            drawImage(frame, in: rect)
        }
    }
}
```

### Contents

- [Loading](#loading) — from a path, URL, or bundled resource
- [Playback](#playback) — play, pause, loop, seek, rate, volume
- [Drawing frames](#drawing-frames) — `frame`, `fittedRect`, `size`
- [Pixels and analysis](#pixels-and-analysis) — `snapshot()` for CPU access
- [Notes](#notes) — formats, audio, and the Metal device

<a name="loading"></a>

### Loading

```swift
VideoPlayer(path: String) throws            // a file on disk
VideoPlayer(url: URL)                       // any file URL
VideoPlayer(resource: String, withExtension: String, in: Bundle) throws
```

`path` throws if no file exists there; `resource` throws if the bundle doesn't contain it. Pass your own bundle as `in:` — usually `.module` for an asset declared in your target (a default here would resolve to Ollin's bundle, not yours).

The file's metadata loads in the background right after init, so `duration` and `size` are `nil` for the first moments and fill in shortly — like the first camera frame, read them optionally in `draw()`.

<a name="playback"></a>

### Playback

```swift
func play()                  // start, or resume after pause
func pause()                 // hold the current position
func stop()                  // pause and rewind to the start
func seek(to seconds: Double)

var loops: Bool              // restart at the end (default false)
var rate: Double             // playback speed, 1 = natural
var volume: Double           // 0…1
var isMuted: Bool
var isPlaying: Bool
var duration: Double?        // seconds, once metadata loads
var currentTime: Double      // seconds from the start
```

Set `loops = true` before `play()` for the usual creative-coding loop. `rate` changes take effect immediately while playing — `0.25` is slow motion, `2` is double speed.

<a name="drawing-frames"></a>

### Drawing frames

```swift
var frame: Image?                                    // the current frame
var size: Vector2?                                   // pixel dimensions
func fittedRect(in container: Rectangle) -> Rectangle?
```

`frame` is the current video frame, ready for `drawImage`. It's `nil` until the first frame decodes; after that it always returns a frame — between video frames (your sketch usually draws faster than the video's frame rate) you get the same one again, so there's never a gap. The image wraps the decoder's texture directly, which is what keeps per-frame cost near zero.

`fittedRect(in:)` letterboxes the video into a rectangle without stretching — typically `bounds` for a full-canvas draw:

```text
bounds (1080×1080)                 a 16:9 video, fitted
┌───────────────────┐              ┌───────────────────┐
│                   │              │                   │  ← empty band
│                   │              ├───────────────────┤  y = 236
│      canvas       │      →       │   1080×608 video  │
│                   │              ├───────────────────┤  y = 844
│                   │              │                   │  ← empty band
└───────────────────┘              └───────────────────┘
```

Draw any overlays into the same rectangle so they line up with the picture.

<a name="pixels-and-analysis"></a>

### Pixels and analysis

```swift
func snapshot() -> Image?
```

`frame` is a live GPU texture, so the CPU paths on it (`image[x, y]`, `cgImage`) are inert. When you need the pixels — sampling colors, feeding a [vision tracker](./Vision.md)'s `detect(in:)` — take a `snapshot()`: a CPU-backed copy of the current frame that supports all of them. It costs a GPU→CPU copy, so take one when needed (every few frames is plenty for analysis) rather than unconditionally.

```swift
// OCR over a paused frame:
let text = TextRecognizer()
if let still = player.snapshot() {
    let lines = try await text.detect(in: still)
}
```

<a name="notes"></a>

### Notes

- **Formats.** Whatever AVFoundation reads: H.264, HEVC, and ProRes in `.mp4`, `.mov`, and `.m4v` containers.
- **Audio.** The file's audio track plays automatically through the system output; `volume` and `isMuted` control it. Routing it into `OllinAudio`'s analyzer is a possible later tie-in.
- **Metal device.** Frame textures are created on the system's default Metal device, which is the device the sketch renders on for any single-GPU Mac.
- **Headless export.** Playback follows the player's own clock, which advances with the runloop of a live window. The offline exporters (`--export`, `--export-sequence`, `--export-video`) drive the sketch clock headlessly without one, so a sketch that draws a video currently exports it as blank; a deterministic frame-pull for export is a planned follow-up.

The runnable example is [`Examples/Video/VideoPlayback`](../Examples/Video/VideoPlayback/Sketch.swift), which loops a bundled clip of the *Danza de los Voladores* (the Totonac pole-flying ritual) and draws playback progress over it.
