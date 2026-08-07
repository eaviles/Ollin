#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Composition`</sup>

---

## Composition

Work out what to play. [`Synthesis`](./Synthesis.md) shapes the sound a note makes; this is the other half, deciding which notes there are and when. Add `import OllinAudio` alongside `import Ollin` to reach it.

Everything here is a plain value with no clock, no engine, and no randomness of its own beyond a seed you hand it. Each type answers a step number, and one small counter turns musical time into step numbers, so the same pattern runs off the sketch clock now and off a drum machine later without changing a line.

```swift
import Ollin
import OllinAudio

final class Loop: Sketch {
    let synth = Synth(.pluck)
    let rhythm = Rhythm(5, in: 16)          // five strikes, evenly spread
    let scale = Scale(.minorPentatonic, root: "A3")
    var counter = StepCounter(perBeat: 4)

    override func draw() {
        background(.black)
        for step in counter.steps(upTo: time * 2) {      // 120 beats a minute
            if rhythm[step] { synth.play(scale[step % 5], for: 0.2) }
        }
    }
}
```

### Contents

- [StepCounter](#stepcounter) - musical time in, step numbers out
- [Rhythm](#rhythm) - a cycle of strikes, spread as evenly as the numbers allow
- [Scale](#scale) - whole numbers in, notes in key out
- [Chord](#chord) - notes meant to sound together
- [Arpeggio](#arpeggio) - a chord played one note at a time
- [MarkovChain](#markovchain) - carrying on the way something else carried on
- [Note](#note) - a pitch with its loudness and length attached
- [Putting it together](#putting-it-together)
- [What is not here yet](#what-is-not-here-yet)

---

### StepCounter

Hand it where the music has got to, in beats; it hands back the steps that have just gone by.

```swift
var counter = StepCounter(perBeat: 4)      // four steps to a beat

for step in counter.steps(upTo: beats) { … }
```

It returns a range rather than one step because at any real tempo a frame is longer than a step, and a step that fell inside a frame still has to be played. The first call always includes step 0, so a pattern starts on the downbeat.

Where `beats` comes from is the sketch's business, which is the point: `time * tempo / 60` for the sketch clock, `clock.beats` from a [`TempoClock`](../Integration/MIDI.md#tempo-sync-tempoclock) to run on a drum machine's, or a number you advance yourself. Nothing in this file knows what a second is.

Two behaviours are worth knowing:

- **Time going backwards** (a loop coming round, a seek) reports the step it landed on, so a repeating figure still begins, and carries on from there.
- **Time jumping a long way** (a stall, a window dragged onto another display) skips ahead rather than emptying the whole pattern into one frame. `maxCatchUp` is where that line is, sixteen steps by default.

`reset(to:)` moves the counter without reporting the steps in between.

---

### Rhythm

A cycle of steps, each one struck or silent. The quick way to one is a count of strikes over a count of steps:

```swift
let rhythm = Rhythm(3, in: 8)       // x..x..x.
rhythm[step]                        // true on a strike; wraps, so any step works
```

The strikes come out as evenly as whole steps allow, which is [Bjorklund's algorithm](#credits). When the counts divide it is the obvious answer; when they do not, the result is a rhythm somebody already plays. `Rhythm(3, in: 8)` is the Cuban tresillo, `Rhythm(5, in: 8)` the cinquillo, `Rhythm(4, in: 9)` the Turkish aksak. The named ones are on the type:

`.tresillo` `.cinquillo` `.bellPattern` `.bossaNova` `.samba` `.aksak` `.ruchenitza` `.yorkSamai` `.nawakhat` `.agsagSamai` `.fandango`

A rhythm can also be written out, which is what you want when the pattern is already in mind:

```swift
let clave: Rhythm = "x..x..x...x.x..."
```

`x`, `1`, and `*` are strikes; `.`, `-`, `_`, `0`, and spaces are rests. `Rhythm(pattern:)` is the form that returns nil rather than complaining, for text that came from somewhere else.

Reading one:

| | |
|---|---|
| `rhythm[step]` | whether that step is struck. Wraps in both directions |
| `length` | how many steps before it comes round |
| `pulseCount` | how many are struck |
| `onsets` | the struck step numbers |
| `intervals` | the gaps between strikes, counting the wrap |
| `rotated(by:)` | the same cycle starting later |
| `inverted()` | strikes and rests exchanged |
| `description` | written out, `x` and `.` |

`intervals` is the compact way to compare two rhythms: the tresillo is `[3, 3, 2]` whichever step it starts on. Rhythms that share their gaps but start in different places are close relatives, which is why several of the named ones are rotations: `.bellPattern` is `Rhythm(7, in: 12)` begun at its third strike.

---

### Scale

A set of pitches and a root they are measured from. It turns whole numbers into notes, which is what makes generated music sound like music: pick a number any way you like and the scale keeps it in key.

```swift
let scale = Scale(.minorPentatonic, root: "A3")
scale[0]       // the root
scale[5]       // an octave up, five notes along
scale[-1]      // the note below the root
```

Degrees run both ways and past the ends, so a wandering number never leaves the key however far it wanders.

The named modes: `.major` `.dorian` `.phrygian` `.lydian` `.mixolydian` `.minor` `.locrian` `.harmonicMinor` `.melodicMinor` `.majorPentatonic` `.minorPentatonic` `.blues` `.wholeTone` `.octatonic` `.chromatic` `.hirajoshi` `.inSen` `.iwato`. `Scale(intervals:root:)` takes one of your own, as semitones above the root.

Where a pitch was decided by something that is not music, a mouse position or a measurement, `snap(_:)` moves it to the nearest note of the scale instead:

```swift
synth.play(scale.snap(Pitch(40 + mouseY / 12)))
```

`degree(nearest:)` is the same fact the other way round, and `pitches(_:from:)` gives a run of them.

`chord(on:notes:spacing:)` builds a chord out of the scale itself by taking every other note:

```swift
scale.chord(on: 0)          // a triad on the root
scale.chord(on: 1)          // a triad on the second degree
scale.chord(on: 0, notes: 4)   // four notes, so a seventh
```

On a major scale the first of those is major and the second is minor, from the same call. That is the point of building a chord out of a key: the quality is a consequence of where you started rather than something you chose, so it follows the key when the key changes.

`Scale.Mode` is a `ParamOption`, so a mode can be a knob:

```swift
@Param var mode: Scale.Mode = .minorPentatonic
```

---

### Chord

Notes meant to sound together, as a root and a shape stacked on it.

```swift
let chord = Chord("C4", .minorSeventh)
synth.play(chord: chord.pitches, for: 2)
```

The qualities: `.major` `.minor` `.diminished` `.augmented` `.sus2` `.sus4` `.fifth` `.sixth` `.minorSixth` `.dominantSeventh` `.majorSeventh` `.minorSeventh` `.minorMajorSeventh` `.halfDiminishedSeventh` `.diminishedSeventh` `.addNine` `.ninth` `.majorNinth` `.minorNinth` `.eleventh` `.thirteenth`. `Chord.Quality` is a `ParamOption` too.

`inverted(_:)` lifts notes from the bottom to the top, which is how one chord moves to the next without every part leaping. Turning it all the way round arrives an octave up; a negative inversion drops notes from the top instead, which is how a close voicing is opened out. `spread(over:)` lays the chord across several octaves, because a chord packed inside one reads as crowded rather than rich.

---

### Arpeggio

A chord played one note at a time, in an order.

```swift
let arp = Arpeggio(Chord("A3", .minorSeventh), .upDown, octaves: 2)
synth.play(arp[step], for: 0.1)
```

Like a rhythm it answers a step number and wraps. Reading it at the step rather than counting strikes is what keeps the figure in its place in the bar instead of restarting every time.

The patterns: `.up` `.down` `.upDown` `.downUp` `.asPlayed` `.converge` `.diverge` `.random`.

`.upDown` and `.downUp` do not play either end twice in a row, so the turn sounds like a turn and not a stutter. `.asPlayed` is the only one that keeps the notes in the order they were given, which is the only way to hear a voicing you arranged by hand; every other pattern reads them as a ladder. `.random` is seeded and is a pure function of the step, so the same seed always gives the same sequence and adding one cannot shift anything else the sketch does at random.

`order` hands back one full pass, so a sketch can draw the figure it is about to play, and `notes` is the pool spread over the octaves it covers.

---

### MarkovChain

Show it a sequence and it learns what tends to follow what; ask it for elements and it gives you new ones with the same habits.

```swift
var melody = MarkovChain<Int>(seed: 4)
melody.learn([0, 2, 4, 2, 0, -3, 0, 4], loops: true)
melody.start(at: 0)

let degree = melody.next() ?? 0
synth.play(scale[degree])
```

It works over anything hashable, so degrees, `Pitch`es, chord qualities, or step counts all fit.

`order` is how far back it looks. At order 1 each element is chosen from what followed the one before it; at order 2 it looks at the last two, which tracks the source more closely and invents less. Where a context has never been seen it falls back to a shorter one and finally to how often each element appeared at all, so it always has an answer.

`loops: true` says the sequence comes round again, so what follows the last element is the first. Use it for a repeating figure; without it the chain can walk off the end of what it was shown and have to fall back.

Learning the same phrase twice counts twice, which is how one is made more likely than another. `continuations` reads the learned counts back as probabilities, most likely first, so the chain is a picture as much as a sound:

```swift
for (degree, probability) in melody.continuations {
    drawRect(x, y, probability * 200, 12)
}
```

The walk is seeded and keeps its own generator. `reset()` forgets where it is, keeps what it learned, and rewinds the randomness so the same walk comes out again.

---

### Note

A pitch with its loudness and length attached, for when all three were decided together.

```swift
let note = Note(scale[3], velocity: 0.9, length: 0.5)   // half a beat
synth.play(note, tempo: 120)
```

Its length is in beats, not seconds, because nothing in this tier knows how fast the music is going. The tempo joins when it is played.

Most sketches never need it: the composition types deal in pitches and step numbers, and `synth.play(pitch, velocity:for:)` takes the other two directly.

---

### Putting it together

The pieces are meant to stack. A rhythm decides *when*, a scale decides *which*, a chain or an arpeggio decides *what next*, and the counter joins them to time:

```swift
let bass = Synth(.bass)
let chords = Synth(.pluck)

let pulse = Rhythm(3, in: 16)
let figure = Rhythm(5, in: 16)
let key = Scale(.minorPentatonic, root: "A2")
var melody = MarkovChain(learning: [0, 2, 4, 2, 0, -3], seed: 4, loops: true)
var counter = StepCounter(perBeat: 4)

override func draw() {
    for step in counter.steps(upTo: time * 104 / 60) {
        if pulse[step] {
            bass.play(key[melody.next() ?? 0], for: 0.34)
        }
        if figure[step] {
            let arp = Arpeggio(Chord(key[0].transposed(by: 12), .minorSeventh), .upDown, octaves: 2)
            chords.play(key.snap(arp[step]), velocity: 0.55, for: 0.22)
        }
    }
}
```

`Examples/Audio/Generative` is that, drawn: three Euclidean rings on one step count, with the knobs changing what is played while it runs.

---

### What is not here yet

Said plainly, so you can plan around it rather than go looking:

- **No sequencer.** There is no type that holds a piece and plays it back. A step number goes in and notes come out, and the arrangement is the sketch's own code. That is deliberate: a sequencer would need a clock, and a clock is what keeps this tier from running on somebody else's.
- **No chord progressions.** Chords are named or built from a scale one at a time. Where the next chord comes from is a `MarkovChain` over qualities or degrees, which is a few lines rather than a type.
- **No note names for chords.** `Chord("C4", .minorSeventh)` rather than `"Cm7"`. Parsing chord symbols is a bigger job than it looks and it is not done.
- **No microtonal scales.** A `Pitch` holds a fractional MIDI number, so a scale of your own can sit between the keys with `Scale(intervals:)` taking whole semitones only. Non-twelve tunings need their own type and do not have one.
- **Nothing generates rhythm from audio.** [Beat detection](./Audio.md#bands-and-beats) reads a beat off incoming sound; nothing turns that into a `Rhythm`.

---

### Credits

The Euclidean rhythms come from Bjorklund's algorithm for spacing pulses in a spallation neutron source, which Godfried Toussaint connected to musical timelines. The named rhythms and the pattern-and-gap notation are from his paper; the implementation here is written from the description of the construction, not translated from anyone's code. Full credit in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

---

<sup>[Synthesis](./Synthesis.md) covers the sound a note makes. [MIDI](../Integration/MIDI.md) covers running on an external clock.</sup>
