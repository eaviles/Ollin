#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Synthesis`</sup>

---

## Synthesis

Make a sketch play. [`Audio`](./Audio.md) is the listening side, turning sound into values you read in `draw()`; this is the other direction, where the sketch is what makes the sound. Add `import OllinAudio` alongside `import Ollin` to reach it.

The whole surface is one instrument you hold as a property and ask for notes.

```swift
import Ollin
import OllinAudio

final class Chime: Sketch {
    let synth = Synth(.bell)

    override func mousePressed() {
        synth.play("C5", for: 1.5)
    }

    override func draw() {
        background(.black)
        fill(.white)
        drawCircle(width / 2, height / 2, 100 + Double(synth.amplitude) * 900)
    }
}
```

Two things are worth noticing there. Nothing was started: the first note starts the engine. And the circle is sized from `synth.amplitude`, because a `Synth` is an [`AudioSource`](./Audio.md#reading-audio) like the microphone is: a sketch can read back whatever it is playing.

### Contents

- [Synth](#synth) - the instrument, and how notes are asked for
- [Pitch](#pitch) - names, numbers, and what lies between them
- [Voice](#voice) - what a note is made of
- [Physical models](#physical-models) - a string worked out rather than a wave drawn
- [Envelope](#envelope) - how a note arrives and how it goes
- [`Voice.Filter`](#voicefilter) - what is taken out of it, and how that moves
- [Delay and Reverb](#delay-and-reverb) - putting the sound somewhere
- [What is not here yet](#what-is-not-here-yet)

---

### Synth

```swift
Synth(_ voice: Voice = .pluck, polyphony: Int = 16, fftSize: Int = 1024)
```

An instrument. `polyphony` is how many notes may sound at once, tails included.

A note is asked for in one of two ways. With a length, it lets go by itself:

```swift
synth.play("C4", for: 0.4)                  // a note that ends on its own
synth.play(60, velocity: 0.4, for: 0.4)     // quieter, by MIDI number
synth.play(chord: [60, 64, 67], for: 1.2)   // three at once
```

Without one, it sounds until you let it go, which is what a held key wants:

```swift
synth.noteOn("C4")
synth.noteOff("C4")
synth.allNotesOff()     // let go of everything; the tails still sound
```

Held notes are usually a poll rather than an event, the same shape as drag-to-paint:

```swift
override func draw() {
    let down = isKeyDown("a")
    if down && !wasDown { synth.noteOn("C4") }
    if !down && wasDown { synth.noteOff("C4") }
    wasDown = down
}
```

The rest of the surface:

| Member | What it does |
|---|---|
| `voice` | the recipe new notes are built from. Changing it leaves sounding notes alone |
| `gain` | overall level, `0...1` |
| `delay`, `reverb` | effects on everything it plays, or nil |
| `activeVoiceCount` | how many notes are sounding right now |
| `isRunning` | whether the audio engine is going |
| `start()`, `stop()` | the first note calls `start()` for you |
| `amplitude`, `spectrum`, `waveform`, `bass`/`mid`/`treble`, `bands(_:)`, `beat` | everything an [`AudioSource`](./Audio.md#reading-audio) reads, over its own output |

**When voices run out**, the next note takes one. A note already fading is taken before a held one, so a melody played over a held chord takes its voices from its own earlier notes rather than eating the chord. A voice being taken is given a few milliseconds to get out of the way, so it does not click.

**Notes start on the next block of audio**, a few milliseconds after you ask. That is a property of the hardware, not a queue: it is below the length of a frame, so a note asked for in `draw()` lands with the frame that asked for it.

---

### Pitch

A pitch is written however you already think of one:

```swift
synth.play(60)                     // MIDI number
synth.play("C4")                   // note name, sharps or flats, any case
synth.play(60.5)                   // a quarter tone above middle C
synth.play(Pitch(frequency: 440))
```

`Pitch.midi` is a `Double` so a pitch can sit between the keys, which is what bends, glides, and tunings that are not the twelve equal steps need. `frequency` is derived from it, so `transposed(by: 12)` always doubles the frequency whatever it started from.

`"C4"` is middle C, and a name without an octave lands in that octave. A *literal* that is not a note name lands on middle C and says so once rather than stopping the sketch; use `Pitch(name:)`, which returns nil, where you want to be told in code.

---

### Voice

What a note is made of. It is a value, so build one, copy it, adjust it, and hand it over whenever.

```swift
let synth = Synth(.pluck)

var glass = Voice.bell          // start from a preset
glass.envelope.release = 3
glass.detune = 0.5
synth.voice = glass             // notes already sounding are undisturbed
```

| Preset | What it sounds like |
|---|---|
| `.pluck` | struck and gone, bright at the front and dark by the end |
| `.bass` | low, round, and quick |
| `.pad` | slow in and slow out, never quite still |
| `.bell` | no attack, a long ring, two tones beating against each other |
| `.stab` | blunt and immediate, and it stops when you do |
| `.breath` | air rather than pitch: noise through a band the note moves |
| `.sine` | one partial and nothing else |

| Property | What it does |
|---|---|
| `source` | what the note is built from: `.wave(Waveform)` or `.string(PluckedString)`. See [Physical models](#physical-models) |
| `waveform` | `.sine`, `.triangle`, `.sawtooth`, `.square`, `.noise`, brightest last |
| `envelope` | how the note's loudness moves. See [Envelope](#envelope) |
| `filter` | what is taken out of it, or nil. See [`Voice.Filter`](#voicefilter) |
| `detune` | a second oscillator this far away, in semitones |
| `gain` | the voice's own level before the note's velocity |

**`detune` is smaller than it looks.** A few hundredths of a semitone is the useful range: two oscillators slightly apart drift in and out of phase with each other, and that beating is what makes a held note shimmer rather than sit still. A whole semitone is an interval, not a shimmer, which is what `.bell` uses it for.

`waveform` and `source` are the same setting written two ways. Reading `waveform` on a string voice gives `.sine`, and setting it makes the voice an oscillator again.

The geometric waves are corrected as they are drawn, so a sawtooth still sounds like a sawtooth at the top of the keyboard instead of ringing against itself.

---

### Physical models

A wave is a shape drawn over and over. A physical model is the thing itself, worked out as it goes, and what you hear falls out of that rather than being dialled in.

```swift
let synth = Synth(.steel)
synth.play("E3", for: 3)
```

| Preset | What it sounds like |
|---|---|
| `.nylon` | soft and round, and it does not ring for long |
| `.steel` | brighter and longer, with more of the pluck left in the front |
| `.harp` | plucked near the middle, so it comes out hollow and rings a long time |
| `.muted` | a string stopped by the hand that plucked it |

A string is a disturbance running up and down a length of something under tension, losing a little at each end and losing its top faster than its bottom. That is a delay line one period long with a filter in the loop, and everything a player recognises comes out of it: the attack, the way a held note darkens, and the difference between plucking near the bridge and over the hole.

```swift
var string = PluckedString.steel
string.pick = 0.5              // halfway along
synth.voice = Voice(string: string)
```

| Property | What it does |
|---|---|
| `pick` | where along the string it is plucked, `0...1` |
| `hardness` | how hard, `0...1`: a fingertip against a plectrum |
| `decay` | how long the note takes to fade, in seconds at the note being played |
| `damping` | how much sooner the top goes than the bottom, `0...1` |

**`pick` is the one that sounds least like a setting.** A string held at a point cannot move there, so every harmonic with a node at that point is missing from the sound. Plucking at `0.5` loses every even harmonic and comes out hollow; near the end keeps them all and comes out thin and nasal. A quarter of the way along is roughly where a guitar is played. `Examples/Audio/Strings` lets you click a string wherever you want to pluck it.

**A string decides for itself how a note fades**, so the envelope's job is to stay out of the way rather than to shape it. `Envelope.plucked` is that envelope, and the string presets use it. Ask for a note long enough to let the string finish (`for: string.decay`), or the envelope's release will cut it off mid-ring.

**Tuning is exact.** The loop has to come out exactly one period long, and a whole number of samples cannot do that. The fraction left over is supplied by an allpass filter, and the loop filter's own delay is counted into the budget, so changing `damping` cannot move the pitch. Without that, notes go progressively sharper or flatter towards the top of the keyboard: at the top of the range, rounding the loop to whole samples is out by most of a semitone.

Everything else about the voice is unchanged. `detune` gives a second string slightly apart, the `filter` still applies after, and a string is an ordinary `Voice` that can be assigned between notes like any other.

---

### Envelope

The shape of a note over time.

```swift
Envelope(attack: 0.001, decay: 0.4, sustain: 0, release: 0.1)   // a pluck
Envelope(attack: 0.8, decay: 1.0, sustain: 0.7, release: 1.5)   // a pad
```

`attack` is the time from silence to full level, `decay` the time to fall from there to `sustain`, `sustain` the level a held note rests at (`0...1`, not a time), and `release` the time to fall back to silence once the note is let go.

The falling segments approach rather than arrive, so `decay` and `release` name the time to come **within a thousandth** of where they are headed, which is what the ear reads as the note being over.

A `sustain` of 0 means the note tells its whole story on its own and a held key adds nothing, which is what struck things do: bells, plucks, drums.

Presets: `.percussive`, `.organ`, `.swell`, `.standard`.

A note let go early falls from wherever it had reached, and a voice retriggered while it is still sounding bends into the new note. Both exist so that neither clicks.

---

### `Voice.Filter`

What is taken out of the wave, and how that moves while the note sounds. This is most of what a synthesizer sounds like: a note that is bright when struck and darkens as it decays is a filter closing, not a wave changing.

```swift
Voice.Filter.lowpass(cutoff: 2000, resonance: 0.3)          // does not move
Voice.Filter.sweep(from: 400, by: 3.5, resonance: 0.35)     // opens, then closes
```

| Property | What it does |
|---|---|
| `mode` | `.lowpass` (the usual one), `.highpass`, `.bandpass`, `.notch` |
| `cutoff` | where the filter sits when the note starts, in Hz |
| `resonance` | how much it emphasises its own cutoff, `0...1`. Past about 0.7 the cutoff whistles |
| `envelopeAmount` | how far `envelope` moves the cutoff, **in octaves**. Negative closes it as the note goes on |
| `envelope` | the shape of that movement |
| `keyTracking` | how far the cutoff follows the note being played, `0...1` |

`keyTracking` defaults to 0, so high notes come out duller than low ones, which is what real instruments do. At 1 the cutoff moves with the note step for step. That is what makes an unpitched wave playable: a noise voice has no pitch of its own, so the filter is the only thing a note can move, which is how `.breath` works.

The filter is solved by integrating the circuit rather than folding a fixed answer, so the cutoff lands where it was asked for across the whole range and stays stable while it is swept. A filter that only behaves standing still is no use to a note that opens as it is struck.

---

### Delay and Reverb

Where the sound is heard.

```swift
synth.delay = Delay(time: 0.28, feedback: 0.35, mix: 0.25)
synth.reverb = Reverb(.hall, mix: 0.3)
synth.reverb = nil                                   // dry again
```

`Delay` is an echo: `time` before the first repeat, `feedback` how much of each repeat feeds the next (`0...0.95`), `mix` how much of the result is the echo, and `damping` where the repeats start losing their top end, so each is duller than the last the way a real one is.

`Reverb` is a room: `.room`, `.hall`, `.plate`, or `.cathedral`, and a `mix`.

Both apply to everything the synth plays, delay first and reverb after, which is the order these are usually chained in. Effects per voice are not a thing here.

---

### What is not here yet

Said plainly, so you can plan around it rather than go looking:

- **One instrument, one sound at a time.** A `Synth` plays one `voice`. Several sounds at once means several `Synth`s, which is fine and cheap.
- **No sequencer.** Notes are asked for from `draw()`, on whatever clock the sketch keeps. [`Composition`](./Composition.md) is what decides which notes and when; [`TempoClock`](../Integration/MIDI.md) is the way to run on someone else's clock.
- **No sampler.** Playing a recorded sound is [`AudioPlayer`](./Audio.md#audioplayer)'s job, not a voice's.
- **One physical model.** A plucked string is here; a struck body, a bowed string, and a blown tube are not.
- **Not placed in the 3D scene.** A voice has no position, so nothing is heard from where it is drawn.
- **Not in an export.** The offline exporters render frames; a video written from a sketch has no sound. The renderer underneath is deterministic and offline-capable, which is what a future audio export would be built on, but nothing writes sound to a file today.

---

<sup>[Audio](./Audio.md) covers the listening side. [MIDI](../Integration/MIDI.md) covers playing from a keyboard and running on an external clock.</sup>
