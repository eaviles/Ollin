#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Haptics`</sup>

---

## Haptics

Touch as an output, beside the pixels and the sound. A sketch writes a short pattern of taps and hums, and plays it at the moment something happens. The hand gets the beat, and the eye gets the picture. It lives in a separate library so the drawing core stays free of the haptic frameworks. Add `import OllinHaptics` alongside `import Ollin` to reach it.

Good touch is designed, not derived. Nothing here reads the canvas and guesses what it should feel like: you say what the hand should feel, the way you say what the eye should see.

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
- [Playing it](#playing-it) - `playHaptic`, the volume knob, and stopping
- [What is on the other end](#what-is-on-the-other-end) - an engine, a trackpad, or nothing
- [How a pattern reaches a trackpad](#how-a-pattern-reaches-a-trackpad) - the plan, and the three rules in it
- [What is not here yet](#what-is-not-here-yet) - rumble, and the phone

<a name="writing-a-pattern"></a>

### Writing a pattern

A `HapticPattern` is a value, like a `Color` or a `Shape`. It holds events on a small timeline, measured in seconds from its own start.

```swift
HapticPattern.tap(intensity: 1, sharpness: 0.5)              // one knock
HapticPattern.hum(0.4, intensity: 0.6, sharpness: 0.3)       // a buzz that lasts
HapticPattern.pulses(4, every: 0.12)                         // a run of knocks
HapticPattern.silence(0.2)                                   // a gap, to place between pieces
```

Two numbers describe every event, and both run 0 to 1:

- **`intensity`** is how strong it feels, from nothing to as much as the hardware gives.
- **`sharpness`** is how crisp it feels, from a dull thud to a tight click.

A hum takes two more, in seconds, for how it arrives and how it leaves:

```swift
HapticPattern.hum(1.0, intensity: 0.8, fadeIn: 0.3, fadeOut: 0.5)
```

Every number is clamped as it goes in, so a value straight out of a sketch is safe. A negative time becomes zero, and an intensity above 1 becomes 1. A value that is not a number at all becomes zero, rather than a knock that never arrives.

Build an event yourself when the ready-made pieces do not fit:

```swift
HapticEvent(.tap, at: 0.25, intensity: 0.7, sharpness: 0.9)
HapticEvent(.hum, at: 0, intensity: 0.4, duration: 0.6, fadeIn: 0.2)
HapticPattern([first, second, third])                        // any order; they are sorted
```

<a name="composing"></a>

### Composing

Pieces join the way words make a sentence.

```swift
a.then(b)               // b starts where a ends
a.over(b)               // both start together
a.delayed(by: 0.2)      // the whole thing, later
a.repeated(3)           // three copies, end to end
a.repeated(3, every: 0.1)   // three copies, 0.1 s apart, overlapping if that is shorter
a.scaled(intensity: 0.5)    // the same shape, softer
a.speed(2)              // the same shape, twice as fast
a.reversed()            // what landed last lands first
```

A heartbeat is two taps and a gap:

```swift
let heartbeat = HapticPattern.tap(intensity: 1, sharpness: 0.7)
    .then(.silence(0.12))
    .then(.tap(intensity: 0.55, sharpness: 0.5))

let ten = heartbeat.repeated(10, every: 0.85)
```

A knock that lands under a rising hum is one `over`:

```swift
let arrival = HapticPattern.hum(0.8, intensity: 0.5, fadeIn: 0.6)
    .over(.tap(intensity: 1, sharpness: 0.9).delayed(by: 0.6))
```

`duration` reports how long a pattern lasts, counting the tail of the last hum, and `isEmpty` says whether there is anything to play at all.

<a name="playing-it"></a>

### Playing it

```swift
playHaptic(pattern)         // start it now
stopHaptics()               // stop everything in flight
hapticStrength(0.4)         // the volume knob, 0 to 1, over everything
```

Play at the moment something happens, not every frame. Touch marks events, the way a drum marks a bar. A pattern played over one already running joins it, because there is one actuator to share.

A knob makes the strength something the room can decide:

```swift
@Param(0 ... 1, icon: "speaker.wave.2") var feel = 1.0

override func draw() {
    hapticStrength(feel)
    …
}
```

On a machine with nothing to feel, and in an export, every call above does nothing and the sketch runs on. It says so once on the error stream, and the reason is readable from the sketch so a piece can put it on the canvas.

<a name="what-is-on-the-other-end"></a>

### What is on the other end

```swift
hapticsAvailable            // Bool
hapticHardware              // .engine, .trackpad, or .none
hapticsUnavailableReason    // a sentence, or nil
```

There are two kinds of hardware, and the difference is worth knowing because it changes what a pattern can say.

| | `.engine` | `.trackpad` |
|---|---|---|
| Strength | as written | one strength only |
| Crispness | as written | three fixed feelings |
| A hum | felt as one sustained buzz | felt as a fast run of knocks |
| A fade | rides the system envelope, so it arrives about right, not to the millisecond | thins the run of knocks |

A Mac today is the `.trackpad` case. Its Force Touch trackpad is reached through the window system, which offers three fixed feelings and one strength. Asking the haptic engine about a Mac's hardware answers that it supports none. `.engine` is the phone and pad case, and the code for it is here and checked, waiting on those platforms.

Read `hapticHardware` when a piece wants to say something different to each. A piece built on strength alone reads flat on a trackpad, and may want fewer, crisper marks there instead.

<a name="how-a-pattern-reaches-a-trackpad"></a>

### How a pattern reaches a trackpad

A trackpad is not a small speaker. So a pattern is planned into knocks before it is played, and the plan is where the translation happens in the open:

```swift
TrackpadPlan.knocks(for: pattern, strength: 1)   // [TrackpadKnock]
TrackpadKnock.time                               // seconds from the start
TrackpadKnock.feel                               // .soft, .level, or .crisp
```

Four rules make the plan, and each one is a choice worth knowing about:

- **Sharpness picks the feeling.** Under a third is `.soft`, over two thirds is `.crisp`, and the rest is `.level`.
- **Strength becomes density.** The hardware has one strength, so a strong hum arrives as a fast run of knocks and a weak one as a slow run, from 6 a second up to 30. The hand reads a faster run as a stronger buzz. A fade thins the run rather than lowering it, for the same reason.
- **Anything under the floor is dropped**, so a pattern that fades to nothing ends in silence instead of one stray knock.
- **Knocks closer than 20 ms are dropped.** Inside one pattern the plan does it, and across patterns the player does it, which is what stops a sketch that calls every frame from asking for a backlog it cannot feel.

The plan is a pure function of the pattern, so a sketch can draw it. [`HapticRidges`](../../Examples/Integration/HapticRidges/Sketch.swift) does exactly that along its bottom edge, which is the quickest way to see what a pattern will really ask of the hardware.

<a name="what-is-not-here-yet"></a>

### What is not here yet

- **Rumble on a game controller.** A pad's motors are an output of the same kind, and belong with this rather than with [reading the pad](Controller.md). They need hardware to write against.
- **The phone and the pad.** Their engines play the `.engine` path above, which is written and checked as far as it can be checked without one. It waits on those platforms rather than on this library.
