#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Haptics`</sup>

---

## Haptics

Haptics adds touch as an output, beside the pixels and the sound. A sketch writes a short pattern of taps and hums, then plays it at the moment something happens. So the hand feels the pattern at the same moment the eye sees the picture. The feature lives in a separate library, so the drawing core stays free of the haptic frameworks. Add `import OllinHaptics` beside `import Ollin` to reach it.

You design what the hand feels yourself. Nothing here reads the canvas and guesses what it should feel like. You say what the hand should feel, in the same way you say what the eye should see.

```swift
import Ollin
import OllinHaptics

final class Bouncer: Sketch {
    let landing = HapticPattern.tap(intensity: 1, sharpness: 0.8)
        .then(.hum(0.18, intensity: 0.3, fadeOut: 0.18))

    override func draw() {
        background(.white)
        ball.step()
        if ball.justLanded { playHaptic(landing) }
        fill(.black)
        drawCircle(ball.position, radius: 24)
    }
}
```

### Contents

- [Writing a pattern](#writing-a-pattern) - taps, hums, runs, and silence
- [Composing](#composing) - end to end, layered, moved, repeated, scaled, reversed
- [Playing it](#playing-it) - `playHaptic`, the volume parameter, and stopping
- [What is on the other end](#what-is-on-the-other-end) - an engine, a trackpad, or nothing
- [How a pattern reaches a trackpad](#how-a-pattern-reaches-a-trackpad) - the plan, and the four rules in it
- [What is not here yet](#what-is-not-here-yet) - rumble, and the phone

<a name="writing-a-pattern"></a>

### Writing a pattern

A `HapticPattern` is a value, like a `Color` or a `Shape`. It holds events on a short timeline, measured in seconds from the pattern's own start.

```swift
HapticPattern.tap(intensity: 1, sharpness: 0.5)              // one knock
HapticPattern.hum(0.4, intensity: 0.6, sharpness: 0.3)       // a buzz that lasts
HapticPattern.pulses(4, every: 0.12)                         // a run of knocks
HapticPattern.silence(0.2)                                   // a gap, to place between pieces
```

Two numbers describe every event, and both run 0 to 1:

- **`intensity`** is how strong it feels, from nothing up to as much as the hardware gives.
- **`sharpness`** is how crisp it feels, from a dull thud to a tight click.

A hum takes two more numbers, in seconds. They set how it arrives and how it leaves:

```swift
HapticPattern.hum(1.0, intensity: 0.8, fadeIn: 0.3, fadeOut: 0.5)
```

Every number is clamped as it goes in, so a value straight out of a sketch is safe. A negative time becomes zero, and an intensity above 1 becomes 1. A value that is not a number at all becomes zero, so it does not turn into a knock that never arrives.

Build an event yourself when the ready-made pieces do not fit:

```swift
HapticEvent(.tap, at: 0.25, intensity: 0.7, sharpness: 0.9)
HapticEvent(.hum, at: 0, intensity: 0.4, duration: 0.6, fadeIn: 0.2)
HapticPattern([first, second, third])                        // any order; they are sorted
```

<a name="composing"></a>

### Composing

Pieces join into larger patterns.

```swift
a.then(b)               // b starts where a ends
a.over(b)               // both start together
a.delayed(by: 0.2)      // the whole thing, later
a.repeated(3)           // three copies, end to end
a.repeated(3, every: 0.1)   // three copies, 0.1 s apart, overlapping if that is shorter
a.scaled(intensity: 0.5)    // the same shape, softer
a.scaled(speed: 2)      // the same shape, twice as fast
a.reversed()            // what landed last lands first
```

A heartbeat is two taps and a gap:

```swift
let heartbeat = HapticPattern.tap(intensity: 1, sharpness: 0.7)
    .then(.silence(0.12))
    .then(.tap(intensity: 0.55, sharpness: 0.5))

let ten = heartbeat.repeated(10, every: 0.85)
```

A knock that lands under a rising hum takes one `over`:

```swift
let arrival = HapticPattern.hum(0.8, intensity: 0.5, fadeIn: 0.6)
    .over(.tap(intensity: 1, sharpness: 0.9).delayed(by: 0.6))
```

`duration` reports how long a pattern lasts, and it counts the tail of the last hum. `isEmpty` says whether there is anything to play at all.

<a name="playing-it"></a>

### Playing it

```swift
playHaptic(pattern)         // start it now
stopHaptics()               // stop everything in flight
hapticStrength(0.4)         // the volume, 0 to 1, over everything
```

Play a pattern at the moment something happens, not every frame, because touch marks a single event rather than running continuously. A pattern played over one that is already running joins it, because there is only one actuator to share.

A parameter makes the strength something the room can set:

```swift
@Param(0 ... 1, icon: "speaker.wave.2") var feel = 1.0

override func draw() {
    hapticStrength(feel)
    …
}
```

On a machine with no haptic hardware, and in an export, every call above does nothing and the sketch runs on. The library says so once on the error stream. The reason is also readable from the sketch, so a piece can put it on the canvas.

<a name="what-is-on-the-other-end"></a>

### What is on the other end

```swift
hapticsAreAvailable            // Bool
hapticHardware              // .engine, .trackpad, or .none
hapticsUnavailableReason    // a sentence, or nil
```

There are two kinds of hardware. The difference matters because it changes what a pattern can express.

| | `.engine` | `.trackpad` |
|---|---|---|
| Strength | as written | one strength only |
| Crispness | as written | three fixed feelings |
| A hum | felt as one sustained buzz | felt as a fast run of knocks |
| A fade | follows the system envelope, so it arrives about right, but not to the millisecond | thins the run of knocks |

A Mac today is the `.trackpad` case. Its Force Touch trackpad is reached through the window system, which offers three fixed feelings and one strength. The haptic engine reports that a Mac supports no haptic hardware. The trackpad also actuates only while the button is held. A knock asked for during a plain pointer move is accepted, but nobody feels it. So ask for touch inside a drag, as the ridges example does. `.engine` is the phone and pad case. The code for it is here and checked, and it waits on those platforms.

Read `hapticHardware` when a piece should play a different pattern on each kind. A piece built on strength alone feels flat on a trackpad, so give it fewer, crisper marks there instead.

<a name="how-a-pattern-reaches-a-trackpad"></a>

### How a pattern reaches a trackpad

A trackpad is not a small speaker, so a pattern is planned into knocks before it is played. The plan is where the translation happens, and you can read it:

```swift
TrackpadPlan.knocks(for: pattern, strength: 1)   // [TrackpadKnock]
TrackpadKnock.time                               // seconds from the start
TrackpadKnock.feel                               // .soft, .level, or .crisp
```

Four rules make the plan, and each one is a choice you should know about:

- **Sharpness picks the feeling.** Under a third is `.soft`, over two thirds is `.crisp`, and the rest is `.level`.
- **Strength becomes density.** The hardware has one strength. So a strong hum arrives as a fast run of knocks, and a weak hum as a slow run. The rate runs from 6 knocks a second up to 30. The hand reads a faster run as a stronger buzz. For the same reason, a fade thins the run rather than lowering it.
- **Anything under the strength floor is dropped**, so a pattern that fades to nothing ends in silence instead of one stray knock.
- **Knocks closer than 20 ms are dropped.** Inside one pattern the plan drops them, and across patterns the player does. This is what stops a sketch that calls every frame from building a backlog it cannot feel.

The plan is a pure function of the pattern, so a sketch can draw it. [`HapticRidges`](../../Examples/Integration/HapticRidges/Sketch.swift) draws its plan along its bottom edge. That is the quickest way to see what a pattern will really ask of the hardware.

<a name="what-is-not-here-yet"></a>

### What is not here yet

- **Rumble on a game controller.** A pad's motors are an output of the same kind. They belong here rather than with [reading the pad](Controller.md). They need hardware to write against.
- **The phone and the pad.** Their engines play the `.engine` path above. That path is written and checked as far as it can be checked without one. It waits on those platforms rather than on this library.
