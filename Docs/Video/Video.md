#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Video](./README.md) → `Video`</sup>

---

## Video

Play a video file into a sketch as a live image. Recorded footage becomes drawing material in the same way the [camera](../Vision/Vision.md) does. Each decoded frame arrives as a GPU texture wrapped in an [`Image`](../Drawing/Images.md). That means you draw it with `drawImage`, it follows the transform stack, and it takes `tint`, with no CPU round-trip per frame. The player is also a [frame source](../Vision/Vision.md#frame-sources). A vision tracker attaches to it in the same way it attaches to a camera, and analyzes the footage as it plays. Video lives in a separate library, which keeps the drawing core free of AVFoundation playback. Add `import OllinVideo` beside `import Ollin` to reach it.

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

`path` throws if no file exists there, and `resource` throws if the bundle does not contain it. Pass your own bundle as `in:`, usually `.module` for an asset declared in your target. There is no default for `in:`, because a default would resolve to Ollin's bundle, not yours.

The file's metadata loads in the background right after init, so `duration` and `size` are `nil` for the first moments and fill in shortly. Read them as optionals in `draw()`, in the same way you would read the first camera frame.

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

Set `loops = true` before `play()` for the usual creative-coding loop. A change to `rate` takes effect at once while the video plays, so `0.25` is slow motion and `2` is double speed.

<a name="drawing-frames"></a>

### Drawing frames

```swift
var frame: Image?                                    // the current frame
var size: Vector2?                                   // pixel dimensions
func fittedRectangle(in container: Rectangle) -> Rectangle?

// on Sketch, for any VideoFeed (a VideoPlayer, a Camera, your own):
@discardableResult
func drawFrame(_ feed: some VideoFeed, in container: Rectangle? = nil,
               waiting: String? = nil) -> Rectangle?
```

`drawFrame(player)` draws the video in one call. It letterboxes the current frame into the canvas, or into `container` when you pass one, and returns the rectangle the frame landed in. Until the first frame decodes, it shows a standard "Waiting for video…" notice. Pass `waiting:` to replace that text. It works on any `VideoFeed`, the core protocol that `VideoPlayer` and the vision `Camera` share. So you can use a player anywhere a camera works.

When you work from the typed pieces instead, `frame` is the current video frame, ready for `drawImage`. It is `nil` until the first frame decodes, and after that it always returns a frame. Your sketch usually draws faster than the video's frame rate, so between video frames you get the same frame again. That means there is never a gap. The image wraps the decoder's texture directly, which is what keeps the cost per frame near zero.

`fittedRectangle(in:)` letterboxes the video into a rectangle without stretching it. For a full-canvas draw, that rectangle is usually `bounds`:

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

Draw any overlays into the same rectangle, so that they line up with the picture.

<a name="pixels-and-analysis"></a>

### Pixels and analysis

For **live analysis**, attach a [vision tracker](../Vision/Vision.md) directly. `VideoPlayer` is a [frame source](../Vision/Vision.md#frame-sources), so every tracker accepts it where it accepts a camera, and analyzes the footage as it plays. Decoded frames reach the analyzer off the GPU path, so drawing stays as fast as a texture draw:

```swift
let player = try VideoPlayer(path: "/path/to/clip.mp4")
lazy var contours = ContourDetector(player)   // traces the clip as it plays
```

For **depth over a recording**, use [`DepthClip`](../Vision/Vision.md#depthclip) instead. It reads the whole file ahead of time and answers by clip time. Because of that, it keeps working under an export, where a live tracker reads nothing.

```swift
func snapshot() -> Image?
```

For **one-shot pixel access**, `frame` is a live GPU texture, so the CPU paths on it (`image[x, y]`, `cgImage`) do nothing. When you need the pixels, take a `snapshot()`. That is a CPU-backed copy of the current frame, and it supports all of those paths. Use it to sample colors, or to feed a tracker's still-image `detect(in:)`. A snapshot costs a GPU→CPU copy, so take one only when you need it, not on every frame. Every few frames is plenty.

```swift
// OCR over a paused frame:
if let still = player.snapshot() {
    let lines = try await TextRecognizer.detect(in: still)
}
```

For **the soundtrack**, the player is an audio-tap source, in the same way that it is a frame source. Hand it to [`Soundtrack`](../Helpers/Audio.md#soundtrack) from `OllinAudio`, and the clip's own audio drives the full analyzer surface (`amplitude`, `spectrum`, `bands`, beats) as it plays:

```swift
let player = try VideoPlayer(path: "/path/to/clip.mp4")
lazy var sound = Soundtrack(of: player)   // needs `import OllinAudio`
override func draw() {
    drawFrame(player)
    drawCircle(center: center, radius: 200 + Double(sound.beat) * 80)   // kicks on the beat
}
```

The analysis reads the soundtrack itself, before volume shaping, so `volume = 0` keeps the visuals reacting in silence. `isMuted = true` is the exception, because a hard mute stops audio processing and stops the analysis with it.

<a name="notes"></a>

### Notes

- **Formats.** The player reads whatever AVFoundation reads: H.264 and HEVC in `.mp4`/`.m4v`, and ProRes in `.mov`.
- **Audio.** The file's audio track plays automatically through the system output, and `volume` and `isMuted` control it. To *react* to the audio, analyze it with [`Soundtrack`](#pixels-and-analysis).
- **Metal device.** Frame textures are created on the system's default Metal device. On any single-GPU Mac, that is the device the sketch renders on.
- **Headless export.** The offline exporters (`--export`, `--export-sequence`, `--export-video`, `--export-gif`) drive the sketch clock at a fixed timestep, with no live window. So the player switches to a deterministic decode that follows that clock. Frame `k` of an export always shows the clip at `k / fps` seconds after `play()`, scaled by `rate` and wrapped by `loops`. A second export reproduces it exactly. Create the player by the end of `setup()`, as a stored property in the usual place. Do not create it lazily mid-run, because then the export clock never reaches it. Two things stay live-only. A `Soundtrack` reads silence during an export, because nothing audibly plays. To react to sound in an export, use an [`AudioPlayer`](../Helpers/Audio.md#audioplayer) over an audio file, which is deterministic under the export clock. A vision tracker attached to the player also analyzes nothing, because its frames arrive on the live clock. For depth, [`DepthClip`](../Vision/Vision.md#depthclip) reads the whole file ahead of time, so it is exact under the export clock.

There are three runnable examples. The first, [`Examples/Video/VideoPlayback`](../../Examples/Video/VideoPlayback/Sketch.swift), loops a bundled clip of the *Voladores de Papantla* (the Totonac pole-flying ritual, *Danza de los Voladores*). It draws playback progress over the clip. The second, [`Examples/Vision/ContourTrace`](../../Examples/Vision/ContourTrace/Sketch.swift), runs a contour tracker over a clip handed to it on launch. The third, [`Examples/Video/SoundReactive`](../../Examples/Video/SoundReactive/Sketch.swift), draws spectrum bars and a beat ring driven by its clip's own soundtrack.
