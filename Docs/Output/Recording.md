#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Recording`</sup>

---

## Recording

Record a live run while you play it: the frames as they render, the sound as it plays, written straight into a movie file in real time.

[Export](./Export.md) is the other way to a video, and the two answer different questions. An export re-renders the sketch on a fixed clock, which is how a file reproduces exactly. Nothing you do while it renders can reach it. A recording keeps the run that is happening right now, with the mouse, the knobs, and the sound in it. Tune a piece live and record the take. Play a live-coding set and keep the set.

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

`startRecording()` begins a take and `stopRecording()` finishes the file. With no destination the movie lands in `~/Movies/Ollin/`, named after the sketch and the moment, like `Orbit 2026-08-17 at 21.14.05.mov`. Pass a destination to choose: `startRecording(to: "take.mov")`. The path's extension picks the container, `.mov` unless you ask for `.mp4`.

Frames are stamped with the wall clock, so a frame that took longer simply lasts longer in the file instead of stretching time. The working example is [`Examples/Export/Record`](../../Examples/Export/Record/Sketch.swift).

### Sound

The recording listens to the sketch by default: it finds the instruments and players the sketch is holding (`Synth`, `AudioPlayer`, `Tone`), the same way the offline exporters find a soundtrack, and mixes what they play into the file's audio track. There is nothing to wire and no permission to grant. An instrument made mid-run joins the mix when it appears.

`audio:` chooses what is heard:

```swift
startRecording(audio: .sketch)               // the sketch's own sound (the default)
startRecording(audio: .microphone)           // the room, through the default input
startRecording(audio: .sketchAndMicrophone)  // both, mixed
startRecording(audio: .none)                 // picture only
```

The microphone modes ask for permission the first time. Sound and picture share one clock, and a device that drops buffers (switching headphones mid-take) leaves silence in the gap rather than sliding everything after it, so the two stay together for the length of a set.

Two sounds do not reach a recording yet: a `VideoPlayer`'s soundtrack, and anything another app is playing. For a set over external music, record the room.

### In the live hosts

Both hosts put recording on **⌘⇧R** (the Sketch menu). In `OllinLiveCoding` a red chip on the stage shows the take's elapsed time, and a toast names the file when it is saved.

A recording survives an evaluation. The take rides the runner across the swap, picks up the new sketch's instruments, and the movie plays straight through the reload, which is the point: a live-coding set is one performance, however many times the code changed.

`OllinLive` also takes a flag, so a run is recorded from its first frame:

```sh
swift run OllinLive MySketches/Loop.swift --record
ollin Loop.swift --record
```

### Endings

A take ends cleanly wherever the run ends. Stopping writes the file and prints its path. Quitting the host finishes the take first. Control-C in the terminal, or a `kill`, finishes it too, because a movie cut off mid-write is not a movie.

One thing a take cannot survive is the canvas changing size, since a movie's frames are all one size. The recording finishes the file it was writing and says so. Start a new take on the new canvas.

### The typed layer

The bare calls forward to `SessionRecorder`, a `SketchExtension` you can hold yourself:

```swift
let recorder = SessionRecorder(audio: .sketch, codec: .hevc)

override func setup() {
    extend(recorder)
}
```

`recorder.start(to:)`, `stop(completion:)`, `stopAndWait()`, `isRecording`, `elapsed`, and `url` are the full surface. `codec` takes the same [`VideoCodec`](./Export.md#video) choices as an export, `h264` by default. A running sketch's recorder is reachable as `sessionRecorder`.

### What it costs, and what it cannot do yet

While recording, each frame is re-rendered off screen and read back, the same grab the frame hook pays. A heavy sketch keeps less headroom while a take runs. A frame the encoder cannot take in time is dropped rather than awaited, and the stop line counts any drops. A sketch with `colorOutput` of `.extended` cannot record live yet. HDR stays with the offline exporters. Wide gamut records and is tagged as P3, standard as Rec. 709.
