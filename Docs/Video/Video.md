#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Video](./README.md) → `Video`</sup>

---

## Video

Play a video file into a sketch as a live image. Recorded footage becomes drawing material the same way the [camera](../Vision/Vision.md) does. Each decoded frame arrives as a GPU texture wrapped in an [`Image`](../Drawing/Images.md), so it draws with `drawImage`, rides the transform stack, and takes `tint`, all with no CPU round-trip per frame. The player is also a [frame source](../Vision/Vision.md#frame-sources), so a vision tracker attaches to it the way one attaches to a camera and analyzes the footage as it plays. Video lives in a separate library so the drawing core stays free of AVFoundation playback, so add `import OllinVideo` alongside `import Ollin` to reach it.

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
        if let player { drawFrame(player) }
    }
}
```

### Contents

- [Loading](#loading) - from a path, URL, or bundled resource
- [Playback](#playback) - play, pause, loop, seek, rate, volume
- [Drawing frames](#drawing-frames) - `drawFrame`, `frame`, `fittedRect`, `size`
- [Pixels and analysis](#pixels-and-analysis) - live trackers, the soundtrack analyzed, and `snapshot()` for CPU access
- [Notes](#notes) - formats, audio, exporting, and the Metal device

<a name="loading"></a>

### Loading

```swift
VideoPlayer(path: String) throws            // a file on disk
VideoPlayer(url: URL)                       // any file URL
VideoPlayer(resource: String, withExtension: String, in: Bundle) throws
```

`path` throws if no file exists there, and `resource` throws if the bundle doesn't contain it. Pass your own bundle as `in:`, usually `.module` for an asset declared in your target (a default here would resolve to Ollin's bundle, not yours).

The file's metadata loads in the background right after init, so `duration` and `size` are `nil` for the first moments and fill in shortly. Read them optionally in `draw()`, the way you would the first camera frame.

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

Set `loops = true` before `play()` for the usual creative-coding loop. `rate` changes take effect immediately while playing, so `0.25` is slow motion and `2` is double speed.

<a name="drawing-frames"></a>

### Drawing frames

```swift
var frame: Image?                                    // the current frame
var size: Vector2?                                   // pixel dimensions
func fittedRect(in container: Rectangle) -> Rectangle?

// on Sketch, for any VideoFeed (a VideoPlayer, a Camera, your own):
@discardableResult
func drawFrame(_ feed: some VideoFeed, in container: Rectangle? = nil,
               waiting: String? = nil) -> Rectangle?
```

`drawFrame(player)` is the one-call draw. It letterboxes the current frame into the canvas (or `container`) and returns the rectangle it landed in, showing a standard "Waiting for video…" notice (override it with `waiting:`) until the first frame decodes. It works on any `VideoFeed`, the core protocol `VideoPlayer` and the vision `Camera` share, so a player drops in anywhere a camera does.

Working from the typed pieces instead, `frame` is the current video frame, ready for `drawImage`. It's `nil` until the first frame decodes, and after that it always returns a frame. Between video frames (your sketch usually draws faster than the video's frame rate) you get the same one again, so there's never a gap. The image wraps the decoder's texture directly, which is what keeps per-frame cost near zero.

`fittedRect(in:)` letterboxes the video into a rectangle without stretching, typically `bounds` for a full-canvas draw:

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

For **live analysis**, attach a [vision tracker](../Vision/Vision.md) directly. `VideoPlayer` is a [frame source](../Vision/Vision.md#frame-sources), so every tracker takes it where it takes a camera and analyzes the footage as it plays (decoded frames are handed to the analyzer off the GPU path, so drawing stays texture-fast):

```swift
let player = try VideoPlayer(path: "/path/to/clip.mp4")
lazy var contours = ContourDetector(player)   // traces the clip as it plays
```

```swift
func snapshot() -> Image?
```

For **one-shot pixel access**, `frame` is a live GPU texture, so the CPU paths on it (`image[x, y]`, `cgImage`) are inert. When you need the pixels, whether for sampling colors or for feeding a tracker's still-image `detect(in:)`, take a `snapshot()`, which is a CPU-backed copy of the current frame that supports all of them. It costs a GPU→CPU copy, so take one when needed (every few frames is plenty) rather than unconditionally.

```swift
// OCR over a paused frame:
if let still = player.snapshot() {
    let lines = try await TextRecognizer.detect(in: still)
}
```

For **the soundtrack**, the player is an audio-tap source the same way it's a frame source. Hand it to [`Soundtrack`](../Helpers/Audio.md#soundtrack) (from `OllinAudio`) and the clip's own audio drives the full analyzer surface (`amplitude`, `spectrum`, `bands`, beats) as it plays:

```swift
let player = try VideoPlayer(path: "/path/to/clip.mp4")
lazy var sound = Soundtrack(of: player)   // needs `import OllinAudio`
override func draw() {
    drawFrame(player)
    drawCircle(center: center, radius: 200 + Double(sound.beat) * 80)   // kicks on the beat
}
```

The analysis hears the soundtrack itself, before volume shaping, so `volume = 0` keeps the visuals reacting in silence. `isMuted = true` is the exception, because a hard mute stops audio processing, and the analysis with it.

<a name="notes"></a>

### Notes

- **Formats.** Whatever AVFoundation reads: H.264 and HEVC in `.mp4`/`.m4v`, and ProRes in `.mov`.
- **Audio.** The file's audio track plays automatically through the system output, and `volume` and `isMuted` control it. To *react* to it, analyze it with [`Soundtrack`](#pixels-and-analysis).
- **Metal device.** Frame textures are created on the system's default Metal device, which is the device the sketch renders on for any single-GPU Mac.
- **Headless export.** The offline exporters (`--export`, `--export-sequence`, `--export-video`, `--export-gif`) drive the sketch clock at a fixed timestep with no live window, so the player switches to a deterministic decode that follows that clock. Frame `k` of an export always shows the clip at `k / fps` seconds after `play()` (scaled by `rate`, wrapped by `loops`), and re-exporting reproduces it exactly. Create the player by the end of `setup()`, as a stored property in the usual place, rather than lazily mid-run, or the export clock never reaches it. Two things stay live-only by nature. A `Soundtrack` reads silence during an export, since nothing audibly plays, and an [`AudioPlayer`](../Helpers/Audio.md#audioplayer) over an audio file is the export-deterministic way to react to sound. A vision tracker attached to the player also analyzes nothing, because its frames pump on the live clock.

The runnable examples are [`Examples/Video/VideoPlayback`](../../Examples/Video/VideoPlayback/Sketch.swift), which loops a bundled clip of the *Voladores de Papantla* (the Totonac pole-flying ritual, *Danza de los Voladores*) and draws playback progress over it, [`Examples/Vision/VideoTrace`](../../Examples/Vision/VideoTrace/Sketch.swift), which runs a contour tracker over the same clip as it plays, and [`Examples/Video/SoundReactive`](../../Examples/Video/SoundReactive/Sketch.swift), which draws spectrum bars and a beat ring driven by its clip's own soundtrack.
