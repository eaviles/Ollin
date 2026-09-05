#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Replay`</sup>

---

## Record & replay

A sketch run is a performance. Four things drive it: the seed the run started from, the clock it followed, every pointer move and key press, and every parameter you adjusted. Ollin can write that performance down as a *take* and play it back exactly. Frame N of the replay is then frame N of the original, pixel for pixel. You can record a session of live tuning and step back through it to find the moment you want to keep. You can also re-render the whole performance offline at export quality.

### Contents

- [Recording a take](#recording-a-take)
- [What a take holds](#what-a-take-holds)
- [Replaying in the window](#replaying-in-the-window)
- [Re-rendering a performance](#re-rendering-a-performance)
- [Same gestures, different world](#same-gestures-different-world)
- [The `Take` type](#the-take-type)
- [What replays, and what cannot](#what-replays-and-what-cannot)

---

### Recording a take

Add `--record-take <file>` to any windowed run:

```sh
swift run Example-Basic-HelloCircle --record-take take.json
ollin Dots.swift --record-take take.json        # a loose file, in the live host
```

The run starts recording at its own frame 0. In the live host, that is the moment the first compile is on screen. The take ends when the run ends, so quitting writes the file. The recorder also autosaves along the way, which means a run that crashes still leaves its take behind. In the live host, saving an edit ends the take too, because an edited sketch is a different run. Ollin writes the file before it swaps in the edited sketch.

Restarting the seed from the inspector's Variation card starts the take over on the new seed. Ollin does this because a take that changed seed partway through could never play back the same way.

### What a take holds

A take is one JSON file, so you can read it and diff it. It holds:

- the `variation` seed the run started from,
- one clock sample per frame (`time`, `deltaTime`, `frameRate`), exactly as the live display drove them, jitter included,
- every input event (pointer, buttons, pressure, scroll, keys, modifiers), stamped with the frame it preceded,
- the `@Param` parameter values at the start, and every change after, stamped the same way.

That is everything that drives a deterministic sketch. Play the same file into a fresh instance and it goes through the same frames.

### Replaying in the window

```sh
swift run Example-Basic-HelloCircle --replay take.json
ollin Dots.swift --replay take.json
```

The sketch restarts under the take's seed and parameter values, and the recording drives it instead of your mouse. Live input is turned off, so the keyboard is free to control playback:

| Key | Does |
| --- | --- |
| Space | Pause and resume; at the end, start over |
| ← / → | Step one frame (paused) |
| ⇧← / ⇧→ | Jump thirty frames |
| Home, `0` | Back to the first frame |
| End | Jump to the last frame |

Stepping backward restarts from frame 0 and simulates forward again. Because the replay is deterministic, the result is exact. The cost is the time to simulate the frames in between. Scrubbing near the start is instant, but scrubbing deep into a long, heavy take can take a moment.

When the take runs out, the replay holds its last frame. Space starts it over.

### Re-rendering a performance

`--replay` works with every export flag, so you can re-render a live performance offline, exactly as it was played:

```sh
swift run MySketch --replay take.json --export-video performance.mov
swift run MySketch --replay take.json --export still.png --frame 240
swift run MySketch --replay take.json --path-traced --export-video film.mov
```

A video-shaped export with no `--frames`/`--seconds` renders the whole take. The export uses the recorded clock, so it reproduces the exact motion of the live run rather than an idealized fixed-step version of it.

### Same gestures, different world

`--seed N` beside `--replay` re-seeds the replayed run on purpose. The recorded gestures and parameter changes play back unchanged, while `random()` and `noise()` follow a different variation. That lets you play one good performance under many variations:

```sh
swift run MySketch --replay take.json --seed 511 --export-video v511.mov
```

### The `Take` type

The flags are a shortcut for a public value type, so a host built on Ollin can do the same:

```swift
let take = try Take.load(from: url)     // read, verify the format version
try take.write(to: url)                 // write, atomically, sorted JSON

let sketch = MySketch()
take.install(on: sketch)                // seed + starting parameters + the player
// ...then drive the sketch however you like; every frame replays.
```

`Take.install(on:)` prepares a fresh instance before its first frame. It applies the seed, restores the starting parameter values, and attaches the player. The player overrides the clock and feeds the recorded inputs through the same paths that live input takes, so the input hooks fire again. The runner carries recording from code and the window's playback controls: `beginTake(writingTo:)`, `finishTake()`, `replay(_:)`, and `scrub(to:)`.

### What replays, and what cannot

A take captures what *drives* a sketch: time, inputs, parameters, and the seed behind `random()` and `noise()`. A sketch driven only by those replays exactly, and the tests check that down to the byte.

What a take does not capture keeps running live during a replay. That includes a camera or microphone feed, incoming OSC or MIDI, network data, and a wall clock read directly (`Date()`). A sketch that depends on those follows the recorded gestures, but its surroundings are whatever is live at the time. The host's own controls (the camera menu's orthographic toggle, window placement) are also outside the take.
