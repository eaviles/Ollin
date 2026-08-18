#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Core](./README.md) → `Replay`</sup>

---

## Record & replay

A sketch run is a performance: the seed it rolled, the clock it followed, every pointer move and key press, every knob you turned. Ollin can write that performance down as a *take* and play it back exactly, so frame N of the replay is frame N of the original, pixel for pixel. Record a session of live tweaking, then step back through it to find the moment worth keeping, or re-render the whole performance offline at export quality.

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

The run starts recording at its own frame 0 (in the live host, the moment the first compile is on screen). The take ends when the run does: quitting writes the file. The recorder also autosaves along the way, so a run that dies still leaves its take behind. In the live host, saving an edit ends the take too, because an edited sketch is a different run; the file is written out before the swap.

Restarting the seed from the inspector's Variation card starts the take over on the new seed. A take that changed seed mid-stream could never reproduce.

### What a take holds

One JSON file, readable and diffable, holding:

- the `variation` seed the run grew from,
- one clock sample per frame (`time`, `deltaTime`, `frameRate`), exactly as the live display drove them, jitter included,
- every input event (pointer, buttons, pressure, scroll, keys, modifiers), stamped with the frame it preceded,
- the `@Param` knob values at the start, and every change after, stamped the same way.

That is everything a deterministic sketch is driven by. Play the same file into a fresh instance and it walks through the same frames.

### Replaying in the window

```sh
swift run Example-Basic-HelloCircle --replay take.json
ollin Dots.swift --replay take.json
```

The sketch restarts under the take's seed and knob values, and the recording drives it instead of your mouse. Live input is gated off, which frees the keyboard to be a transport:

| Key | Does |
| --- | --- |
| Space | Pause and resume; at the end, start over |
| ← / → | Step one frame (paused) |
| ⇧← / ⇧→ | Jump thirty frames |
| Home, `0` | Back to the first frame |
| End | Jump to the last frame |

Stepping backward restarts from frame 0 and re-simulates forward, which determinism makes exact. The cost is the frames in between. Scrubbing near the start is instant; scrubbing deep into a long, heavy take can take a moment.

When the take runs out the replay holds its last frame. Space starts it over.

### Re-rendering a performance

`--replay` composes with every export flag, so a performance played live can be re-rendered offline, exactly as played:

```sh
swift run MySketch --replay take.json --export-video performance.mov
swift run MySketch --replay take.json --export still.png --frame 240
swift run MySketch --replay take.json --path-traced --export-video film.mov
```

A video-shaped export with no `--frames`/`--seconds` renders the whole take. The recorded clock rides along, so the export reproduces the live run's exact motion, not an idealized fixed-step version of it.

### Same gestures, different world

`--seed N` beside `--replay` re-seeds the replayed run on purpose: the recorded gestures and knob moves play back unchanged while `random()` and `noise()` walk a different variation. One good performance can audition many worlds:

```sh
swift run MySketch --replay take.json --seed 511 --export-video v511.mov
```

### The `Take` type

The flags are sugar over a public value type, so a host built on Ollin can do the same:

```swift
let take = try Take.load(from: url)     // read, verify the format version
try take.write(to: url)                 // write, atomically, sorted JSON

let sketch = MySketch()
take.install(on: sketch)                // seed + starting knobs + the player
// ...then drive the sketch however you like; every frame replays.
```

`Take.install(on:)` prepares a fresh instance before its first frame. It applies the seed, restores the starting knob values, and attaches the player. The player overrides the clock and feeds the recorded inputs through the same paths live input takes, so the hooks fire again. Programmatic recording and the window transport live on the runner: `beginTake(writingTo:)`, `finishTake()`, `replay(_:)`, and `scrub(to:)`.

### What replays, and what cannot

A take captures what *drives* a sketch: time, inputs, knobs, and the seed behind `random()` and `noise()`. A sketch driven only by those replays exactly, and the tests pin that down to the byte.

What a take does not capture keeps playing live during a replay: a camera or microphone feed, incoming OSC or MIDI, network data, and a wall clock read directly (`Date()`). A sketch leaning on those follows the recorded gestures but not the recorded room. The host's own chrome (the camera menu's orthographic toggle, window placement) is also outside the take.
