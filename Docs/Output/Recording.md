#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Recording`</sup>

---

## Recording

A recording captures a live run while you play it. The frames are written as they render and the sound as it plays, straight into a movie file in real time.

[Export](./Export.md) is the other way to make a video, and the two serve different purposes. An export re-renders the sketch on a fixed clock, so the file reproduces exactly, and nothing you do while it renders can reach it. A recording keeps the run that is happening right now, including the mouse, the parameters, and the sound. So you can tune a piece live and record the take, or play a live-coding set and keep the set.

### From a sketch

```swift
override func keyPressed() {
    guard key == "r" else { return }
    if isRecording {
        stopRecording()
    } else {
        startRecording()
    }
}
```

`startRecording()` begins a take and `stopRecording()` finishes the file. With no destination, the movie is written to `~/Movies/Ollin/` and named after the sketch and the time, for example `Orbit 2026-08-17 at 21.14.05.mov`. To choose the destination, pass a path: `startRecording(to: "take.mov")`. The path's extension picks the container, which is `.mov` unless you ask for `.mp4`.

Each frame is stamped with the wall clock. A frame that took longer to render therefore lasts longer in the file, and time is not stretched. The working example is [`Examples/Export/Record`](../../Examples/Export/Record/Sketch.swift).

### Sound

By default, the recording listens to the sketch. It finds the instruments and players the sketch holds (`Synth`, `AudioPlayer`, `Tone`), the same way the offline exporters find a soundtrack. Then it mixes what they play into the file's audio track. There is nothing to wire and no permission to grant. An instrument made during the run joins the mix when it appears.

The `audio:` parameter chooses what the recording hears:

```swift
startRecording(audio: .sketch)               // the sketch's own sound (the default)
startRecording(audio: .microphone)           // the room, through the default input
startRecording(audio: .sketchAndMicrophone)  // both, mixed
startRecording(audio: .none)                 // picture only
```

The microphone modes ask for permission the first time you use them. Sound and picture share one clock. A device can still drop buffers, for example when you switch headphones during a take. Then the recording leaves silence in the gap instead of shifting everything after it. So sound and picture stay together for the length of a set.

Two sounds do not reach a recording yet: a `VideoPlayer`'s soundtrack, and anything another app is playing. For a set played over external music, record the room through the microphone.

### In the live hosts

Both hosts start and stop a recording with **⌘⇧R** in the Sketch menu. In `OllinLiveCoding`, a red chip on the stage shows the elapsed time of the take, and a toast names the file when it is saved.

A recording survives an evaluation. The take stays with the runner across the swap and picks up the new sketch's instruments, so the movie plays straight through the reload. A live-coding set is one performance, however many times the code changed, so the recording is built to run through it.

`OllinLive` also takes a `--record` flag, which records a run from its first frame:

```sh
swift run OllinLive MySketches/Loop.swift --record
ollin Loop.swift --record
```

### Endings

A take ends cleanly wherever the run ends. Stopping writes the file and prints its path. Quitting the host finishes the take first. Control-C in the terminal, or a `kill`, finishes it too, because a file left half-written is not a complete movie.

A take cannot survive a change in canvas size, because every frame in a movie is the same size. When the canvas changes size, the recording finishes the file it was writing and reports that it did. Start a new take on the new canvas.

### The typed layer

The bare calls forward to `SessionRecorder`, a `SketchExtension` that you can also hold yourself:

```swift
let recorder = SessionRecorder(audio: .sketch, codec: .hevc)

override func setup() {
    extend(recorder)
}
```

The full surface is `recorder.start(to:)`, `stop(completion:)`, `stopAndWait()`, `isRecording`, `elapsed`, and `url`. `codec` takes the same [`VideoCodec`](./Export.md#video) choices as an export, and the default is `h264`. A running sketch's recorder is reachable as `sessionRecorder`.

### What it costs, and what it cannot do yet

A take reads the frame the window shows, once the GPU has finished it. Recording therefore costs the sketch almost nothing, just one tone-map pass and one copy per frame. The render loop never waits for them. The picture is the live one, at the canvas size. A window larger than the canvas is scaled down into the take. A window smaller than the canvas draws the frame at the canvas size while the take runs, and shows it scaled. That means the window never decides how sharp the movie is. The 3D ground grid is host chrome, so it leaves the window while a take runs.

A take is not an export, and the difference shows in the picture. Temporal anti-aliasing settles over several frames, and reflections accumulate, as they do on screen. In an export, `--export-video` resolves every frame on its own. A frame the encoder cannot take in time is dropped rather than waited for, and the stop line counts any drops. A sketch with `colorOutput` set to `.extended` cannot record live yet, so HDR stays with the offline exporters. A wide-gamut sketch does record live, and its file is tagged as P3. A standard one is tagged as Rec. 709.
