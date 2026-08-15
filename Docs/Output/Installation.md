#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Installation`</sup>

---

## Running unattended

A sketch at a desk runs for a session, with you watching it. A piece on a wall runs for days, with nobody there. Different things end it. The screen saver comes on. The display sleeps. Somebody unplugs a monitor. The clock the shaders read runs out of precision overnight.

Declaring an installation holds all of that off.

```swift
override var installation: Installation { .on }
```

That is the whole declaration. The window fills the screen, the pointer disappears, and the display stays awake with the screen saver held off.

Command-Q quits, whatever the piece covers. The menu bar is hidden, not gone.

### What `.on` turns on

| Part | What it does |
|---|---|
| `fillsScreen` | The window takes the whole display, with no title bar, and the menu bar and Dock get out of the way. The canvas keeps its own proportions inside that, centred on black. |
| `hidesPointer` | The pointer goes away. Nobody is holding the mouse, so an arrow parked over the work is only ever a blemish. |
| `keepsDisplayAwake` | The display stays lit and the screen saver never arms, for as long as the piece runs. |
| `clock` | When the clock a shader reads starts over, so a run of weeks stays exact. See [the clock](#the-clock-is-the-part-that-breaks) below. |
| `checkpoint` | How often the run writes its state down, so a relaunch resumes rather than restarts. Off until asked for. See [picking up where it left off](#picking-up-where-it-left-off). |

Build one by hand to change any part of it. Anything you build is running: `.off` is the only value that is not.

```swift
override var installation: Installation {
    Installation(fillsScreen: false)     // a window, but still left running
}
```

### The two flags

You do not have to edit a sketch to try it on a wall, or to get a wall piece back onto your desk.

```sh
swift run --package-path Examples Example-Motion-Orbits --installation        # any sketch, full screen, left running
swift run --package-path Examples Example-Installation-Unattended --no-installation   # back to an ordinary window
```

`--no-installation` is the one to work in. Everything else about the sketch is unchanged, so what you tune at your desk is what goes up.

### The clock is the part that breaks

Two things go wrong with time in a long run, and both are held off for you.

**A gap in the frames is a pause, not a jump.** The sketch clock is the sum of its own frame steps, and each step is capped at a quarter of a second. So a display asleep overnight, a window held during a drag, or a stall of any kind resumes where the piece left off. Without the cap, the first frame back reports the whole gap as `deltaTime`. One eight-hour step throws every integrator a sketch has into the far distance.

A quarter of a second is past any frame rate worth animating at, so a running sketch never meets the cap. A sketch slower than four frames a second runs in slow motion, which beats the alternative.

**The clock a shader reads starts over.** Your sketch reads `time` as a 64-bit number, which stays exact for centuries. A shader reads it as a 32-bit one, which does not. A day into a run, one frame's worth of time is at the limit of what that number resolves, and the motion goes uneven. A week in, adding a frame to it changes nothing at all, and anything animated inside a shader stops dead.

So a piece that repeats hands its shaders a clock that starts over on a whole lap:

```swift
override var installation: Installation { .on }
override var loopDuration: Double? { 120 }     // two minutes a lap
```

Nothing on screen moves at the restart, because the piece is back where it began anyway. That is why the restart is tied to the loop rather than to a round number of seconds.

A sketch that does not declare a loop keeps its clock running, because there is no moment where a jump would be free. Say when to restart it if you know one, or say to leave it alone:

```swift
Installation(clock: .restarting(every: 600))   // every ten minutes
Installation(clock: .continuous)               // never
```

Pick a whole number of the periods your shaders animate on, or expect a visible jump each time. `time` itself always keeps counting, so nothing in your own `draw()` changes.

### Picking up where it left off

A piece that has been growing for three days cannot be rebuilt from its seed in any useful sense. Getting back there means running the three days again. So the state itself is written down, and the next launch reads it.

Two things to say. How often to write, and what is worth writing.

```swift
override var installation: Installation { Installation(checkpoint: .every(seconds: 60)) }

@Saved var polyps: [Vector2] = []
@Saved var generation = 0
```

That is the whole surface. Every `@Saved` property is written on the cadence, along with the seed, the clock, and every `@Param` value. A relaunch puts them all back, and the piece carries on.

Checkpointing is off until you ask for it, even under `.on`. Restoring changes what a piece does on launch, which is right for a wall and confusing at a desk.

Anything `Codable` can be saved: numbers, strings, arrays, dictionaries, and your own structs and enums once you mark them `Codable`. Ollin's small value types (`Vector2`, `Vector3`, `Color`, `Rectangle`, `Insets`) already are.

**What cannot be saved is anything living on the GPU.** An accumulated canvas, a feedback layer, a simulation field, a compute buffer: those are textures the framework owns, and a checkpoint does not reach them. A piece built on those comes back on a clean canvas.

### When the file and the sketch disagree

You will edit the sketch while a checkpoint from the old one is still sitting there. Every mismatch costs exactly the thing it touches:

| What changed | What happens |
|---|---|
| A property renamed | The old value finds nothing and the fresh one stands. Values are matched by property name. |
| A property retyped | The old value will not decode, so it is named in the log and the fresh one stands. Everything else still restores. |
| A property added | It gets its starting value, since the file has nothing for it. |
| The sketch renamed | The file belongs to a name, so a renamed sketch starts over with an empty one of its own. |
| The canvas resized | Everything restores and the log says the size changed, since only you know whether that matters. |
| The file damaged | It is ignored and the piece starts fresh. A half-written file cannot happen anyway: writes are atomic. |

Nothing here ever stops a piece from starting, because a gallery piece that will not start is worse than one that started over.

### Starting over, and saving by hand

```sh
swift run --package-path Examples Example-Installation-Resuming --fresh
```

`--fresh` ignores the saved state without deleting it, so one clean run does not cost you the file. To throw it away for good, call `forgetCheckpoint()`. To write one at a moment of your choosing, on a key press or at the end of a phase, call `saveCheckpoint()`.

The file is JSON, sorted and indented, in `~/Library/Application Support/Ollin/Checkpoints/`, one per sketch. It is meant to be read: when a piece comes back wrong, the state it came back with is the first thing to look at.

```json
{
  "frameCount" : 4098,
  "sketch" : "Resuming",
  "state" : {
    "nextLanding" : 68,
    "tiles" : [ { "cell" : 106, "shade" : 0.354, "turn" : 0.303 } ]
  },
  "time" : 67.98
}
```

The save happens on the frame it falls on, so keep the saved state to what the piece actually needs. A hundred thousand particles will hitch that frame.

### Displays that change under you

A monitor unplugged, replugged, or re-resolved reaches the piece as a burst of notifications, sometimes dozens in a second. The burst is waited out first. Then the piece is put back on a screen that still exists, and the draw loop is retimed to the refresh rate it now faces. A piece moved from a 60 Hz panel to a 120 Hz one asks for the right rate from then on.

Waking up is handled the same way. The assertion that keeps the display awake is taken out again, since it does not always survive a sleep.

### The log

An unattended run leaves a trace on stdout, stamped and flushed on the spot. The log is the only witness a piece running for a week has.

```
Ollin installation [2026-08-15 08:41:45]: running unattended; Command-Q quits
Ollin installation [2026-08-15 08:41:46]: the displays changed: now 1 (1680x1050)
Ollin installation [2026-08-16 03:12:08]: the screens woke
```

Send it somewhere you can read later:

```sh
swift run --package-path Examples Example-Installation-Unattended >> ~/piece.log 2>&1
```

### Where it applies

The declaration is read when a sketch opens its own window, which is the `swift run Example-X` path and any sketch with `@main`. The live host and the examples gallery own their windows and their own chrome, so a sketch under them stays in their window. Tune it there, then run it on its own to put it up.

Exports open no window, so none of the window parts apply to them. The clock restart does travel with the piece, because it belongs to the sketch rather than to the window. It lands on a whole lap there too.

### See also

- [`Export`](./Export.md) for writing frames, video, and vectors out of a piece.
- [`Sketch`](../Core/Sketch.md) for `loopDuration` and the rest of the declared configuration.
- [`Canvas`](../Core/Canvas.md) for how the canvas and the window relate, which is what lets a 1080 square fill a wide screen without distorting.
- The [Unattended example](../../Examples/Installation/Unattended/Sketch.swift), and the [Resuming example](../../Examples/Installation/Resuming/Sketch.swift), a wall that fills in and remembers how far it got.
