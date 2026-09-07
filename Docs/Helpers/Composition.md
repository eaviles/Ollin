#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Composition`</sup>

---

## Composition

This page covers deciding what to play. [`Synthesis`](./Synthesis.md) shapes the sound a note makes. The types here are the other half, and they decide which notes there are and when they sound. Add `import OllinAudio` beside `import Ollin` to reach them.

Every type here is a plain value. It has no clock, no engine, and no randomness of its own beyond a seed you give it. You read each type by step number, and one small counter turns musical time into step numbers. Because of that split, the same pattern runs from the sketch clock now and from a drum machine later, without changing a line.

```swift
import Ollin
import OllinAudio

final class Loop: Sketch {
    let synth = Synth(.pluck)
    let rhythm = Rhythm(5, in: 16)          // five strikes, evenly spread
    let scale = Scale(.minorPentatonic, root: "A3")
    let tempo: Tempo = 120
    var counter = StepCounter(perBeat: 4)

    override func draw() {
        background(.black)
        for step in counter.steps(upTo: tempo.beats(at: time)) {
            if rhythm[step] { synth.play(scale[step % 5], for: tempo.seconds(of: .eighth)) }
        }
    }
}
```

### Contents

- [StepCounter](#stepcounter) - musical time in, step numbers out
- [Tempo and note lengths](#tempo-and-note-lengths) - seconds into beats, and a note's length back into seconds
- [Rhythm](#rhythm) - a cycle of strikes, spread as evenly as the numbers allow
- [Scale](#scale) - whole numbers in, notes in key out
- [Chord](#chord) - notes meant to sound together
- [Progression](#progression) - a cycle of chords, built out of a key
- [Arpeggio](#arpeggio) - a chord played one note at a time
- [MarkovChain](#markovchain) - new elements that continue a sequence the way it was shown
- [Tuning](#tuning) - pitches described by ratios rather than by semitones
- [BeatFollower](#beatfollower) - the beat in what the sketch hears, so it can play along
- [Note](#note) - a pitch with its loudness and length attached
- [Putting it together](#putting-it-together)
- [What is not here yet](#what-is-not-here-yet)

---

### StepCounter

You give it the current position of the music, in beats. It returns the steps that have gone by since the last call.

```swift
var counter = StepCounter(perBeat: 4)      // four steps to a beat

for step in counter.steps(upTo: beats) { … }
```

It returns a range rather than one step, because at any real tempo a frame is longer than a step. A step whose moment fell inside the frame still has to be played. The first call always includes step 0, so a pattern starts on the downbeat.

The sketch decides where `beats` comes from. That is deliberate, and it is why the counter works with any clock. Use `tempo.beats(at: time)`, with a [`Tempo`](#tempo-and-note-lengths), to run from the sketch clock, or `clock.beats` from a [`TempoClock`](../Integration/MIDI.md#tempo-sync-tempoclock) to run from a drum machine's clock. A number you advance yourself works too. Nothing in this tier but the tempo knows what a second is.

There are two behaviors to know about:

- **Time going backwards**, when a loop comes round or after a seek, makes the counter report the step it landed on. A repeating figure therefore starts again and carries on from there.
- **Time jumping a long way**, after a stall or a window dragged onto another display, makes the counter skip ahead. The counter does not empty the whole pattern into one frame. `maxCatchUp` sets how far it catches up, sixteen steps by default.

`reset(to:)` moves the counter without reporting the steps in between.

---

### Tempo and note lengths

A `Tempo` is beats per minute, with how many beats make a bar. It is the one value on this page that knows what a second is, so it does the two conversions everything else leaves out:

```swift
let tempo: Tempo = 104                  // or Tempo(104, beatsPerBar: 3)

tempo.beats(at: time)                   // seconds in, beats out: what a StepCounter wants
tempo.seconds(of: .eighth)              // a note length in, seconds out: what `play(for:)` wants
tempo.seconds(beats: 1.5)               // any count of beats
tempo.seconds(bars: 8)                  // eight bars, for a `loopDuration`
tempo.secondsPerBeat                    // 0.577 at 104
tempo.bars(at: time)                    // where the music is, in bars
```

A `NoteLength` is a length in beats, where a beat is a quarter note. The names are the ones on a stave, and two properties derive the rest:

| Length | Beats |
|---|---|
| `.whole` | 4 |
| `.half` | 2 |
| `.quarter` | 1 |
| `.eighth` | 0.5 |
| `.sixteenth` | 0.25 |
| `.thirtySecond` | 0.125 |
| `.quarter.dotted` | 1.5, the dot after a note |
| `.eighth.triplet` | a third, three in the time of two |

A plain number stands in for either type, so `tempo: 120` and `length: 0.5` read as they always did, and `NoteLength(beats: 1.1)` holds a length no name covers. `length.seconds(at: tempo)` is the same conversion from the other side, and `.quarter * 3` or `.quarter + .eighth` build a longer one.

Both are parameters. `@Param(60...160) var tempo: Tempo = 104` is a slider in beats per minute. A [MIDI](../Integration/MIDI.md#binding-to-a-param) knob or an [OSC](../Integration/OSC.md#binding-to-a-param) address binds to it the way it binds to a number. The beats per bar stay what the declaration gave them. `@Param var length: NoteLength = .eighth` is a menu of the named lengths.

---

### Rhythm

A `Rhythm` is a cycle of steps, and each step is struck or silent. The quick way to make one is a count of strikes over a count of steps:

```swift
let rhythm = Rhythm(3, in: 8)       // x..x..x.
rhythm[step]                        // true on a strike; wraps, so any step works
```

The strikes are spread as evenly as whole steps allow, using [Bjorklund's algorithm](#credits). When the counts divide, the result is the obvious even spacing. When they do not, the result is a rhythm that is already played in some musical tradition. `Rhythm(3, in: 8)` is the Cuban tresillo, `Rhythm(5, in: 8)` is the cinquillo, and `Rhythm(4, in: 9)` is the Turkish aksak. The named ones are available on the type:

`.tresillo` `.cinquillo` `.bellPattern` `.bossaNova` `.samba` `.aksak` `.ruchenitza` `.yorkSamai` `.nawakhat` `.agsagSamai` `.fandango`

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/29-MakingSound/Euclidean-dark.jpg">
  <img src="../../Guide/Images/29-MakingSound/Euclidean.jpg" alt="Seven rows showing 2, 3, 4, 5, 7, 9, and 11 strikes spread over sixteen steps, with the gaps between strikes listed beside each row, and below them the tresillo, cinquillo, and bell pattern drawn as the shape between their strikes on a circle" width="680">
</picture>

You can also write a rhythm out as text, which is the better form when you already know the pattern:

```swift
let clave: Rhythm = "x..x..x...x.x..."
```

`x`, `1`, and `*` are strikes. `.`, `-`, `_`, `0`, and a space are rests. `Rhythm(pattern:)` is the form that returns nil rather than complaining, so use it for text that came from somewhere else.

To read one:

| | |
|---|---|
| `rhythm[step]` | whether that step is struck. Wraps in both directions |
| `length` | how many steps before it repeats |
| `onsetCount` | how many are struck |
| `onsets` | the struck step numbers |
| `intervals` | the gaps between strikes, counting the wrap |
| `rotated(by:)` | the same cycle starting later |
| `inverted()` | strikes and rests exchanged |
| `description` | written out, `x` and `.` |

`intervals` is the compact way to compare two rhythms. The tresillo is `[3, 3, 2]` whichever step it starts on, so two rhythms that share their gaps but start in different places are close relatives. Several of the named ones are rotations. For example, `.bellPattern` is `Rhythm(7, in: 12)` started at its third strike.

---

### Scale

A `Scale` is a set of pitches and a root they are measured from. It turns whole numbers into notes of that key, which is what keeps generated music sounding musical. You can pick a number any way you like, and the scale keeps it in key.

```swift
let scale = Scale(.minorPentatonic, root: "A3")
scale[0]       // the root
scale[5]       // an octave up, five notes along
scale[-1]      // the note below the root
```

Degrees run in both directions and past the ends of the scale, so a wandering number never leaves the key, however far it goes.

The named modes are: `.major` `.dorian` `.phrygian` `.lydian` `.mixolydian` `.minor` `.locrian` `.harmonicMinor` `.melodicMinor` `.majorPentatonic` `.minorPentatonic` `.blues` `.wholeTone` `.octatonic` `.chromatic` `.hirajoshi` `.inSen` `.iwato`. `Scale(intervals:root:)` takes a mode of your own, as semitones above the root.

Sometimes a pitch comes from something that is not music, like a mouse position or a measurement. Then `snap(_:)` moves it to the nearest note of the scale:

```swift
synth.play(scale.snap(Pitch(40 + mouseY / 12)))
```

`degree(nearest:)` answers the same question the other way round, returning the degree nearest a pitch. `pitches(_:from:)` returns a run of pitches.

`chord(on:noteCount:spacing:)` builds a chord out of the scale itself, by taking every other note:

```swift
scale.chord(on: 0)          // a triad on the root
scale.chord(on: 1)          // a triad on the second degree
scale.chord(on: 0, noteCount: 4) // four notes, so a seventh
```

On a major scale the first of those is a major chord and the second is a minor chord, from the same call. That is the point of building a chord out of a key. The quality follows from where you started rather than from a choice you made, so it changes when the key changes.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/29-MakingSound/ScaleLadder-dark.jpg">
  <img src="../../Guide/Images/29-MakingSound/ScaleLadder.jpg" alt="Left: a ladder of pentatonic scale rungs over a faint semitone grid, with a wandering numbered sequence of dots landing only on rungs. Right: seven triads built on the degrees of C major, each three stacked marks two rungs apart, colored by what fell out: major on I, IV, and V, minor on ii, iii, and vi, diminished on the seventh" width="680">
</picture>

`Scale.Mode` is a `ParamOption`, so a mode can be a parameter:

```swift
@Param var mode: Scale.Mode = .minorPentatonic
```

---

### Chord

A `Chord` is a set of notes meant to sound together. It is written as a root and a shape of intervals stacked on that root.

```swift
let chord = Chord("C4", .minorSeventh)
synth.play(chord: chord.pitches, for: 2)
```

The qualities are: `.major` `.minor` `.diminished` `.augmented` `.sus2` `.sus4` `.fifth` `.sixth` `.minorSixth` `.dominantSeventh` `.majorSeventh` `.minorSeventh` `.minorMajorSeventh` `.halfDiminishedSeventh` `.diminishedSeventh` `.addNine` `.ninth` `.majorNinth` `.minorNinth` `.eleventh` `.thirteenth`. `Chord.Quality` is a `ParamOption` too.

`inverted(_:)` moves notes from the bottom of the chord to the top. That is how one chord moves to the next without every part leaping. Inverting a chord all the way round brings it back an octave up. A negative inversion drops notes from the top to the bottom instead, which is how a close voicing is opened out. `spread(over:)` lays the chord across several octaves, because a chord packed inside one octave sounds crowded rather than rich.

### Progression

A `Progression` is a cycle of chords, written as scale degrees rather than as chord names.

```swift
let changes = Progression("I vi IV V", in: Scale(.major, root: "C3"))

for step in counter.steps(upTo: time * 2) {
    synth.play(chord: changes.pitches(at: step), for: 1.8)
}
```

It uses degrees rather than names because degrees survive a change of key. `I vi IV V` is the same progression in every key. Written that way, the quality of each chord comes from the scale instead of being spelled out. So the same four numerals come out major in a major key and minor in a minor key, with nothing changed.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/29-MakingSound/Changes-dark.jpg">
  <img src="../../Guide/Images/29-MakingSound/Changes.jpg" alt="Two rows of four chord stacks. The top row, in C major, reads C major, A minor, F major, G major; the bottom row, the same numerals in C minor, reads C minor, G sharp major, F minor, G minor. Each stack shows the three notes the progression hands back, at their own pitches" width="680">
</picture>

The text is Roman numerals `I` to `VII`, separated by any other characters. Upper and lower case are both accepted and treated the same, because the key decides major or minor. Anything unreadable is skipped.

| Member | What it gives |
|---|---|
| `pitches(at:)` / `[step]` | the notes of the chord at a step, lowest first |
| `degree(at:)` | which scale degree that chord is built on |
| `root(at:)` | its root, for a bass line underneath |
| `chord(at:)` | the `Chord` itself, for a progression written as symbols. Nil for one written as degrees |
| `count` | how many chords before it repeats |
| `noteCount` / `spacing` | `noteCount` is three or four, and a `spacing` of two degrees is the usual stack of thirds |
| `transposed(by:)` / `rotated(by:)` | the same progression elsewhere, or starting elsewhere |

The cycle wraps, so a step number can climb forever.

**The named progressions** each take a key to build in. They are `.pop` (I V vi IV), `.fifties` (I vi IV V), `.twoFiveOne`, `.blues` over twelve bars, `.andalusian`, and `.circleOfFifths`.

#### Wandering

```swift
let changes = Progression("I vi IV V ii V", in: key).wandering(32)
```

`wandering(_:)` builds a longer progression that only makes the moves the original already makes. The result sounds like the same music, but it is a different cycle. Underneath, it is a [`MarkovChain`](#markovchain) over the degrees. The chain is learned round the loop, so the last chord returning to the first counts as a move.

It is seeded per call rather than from the sketch's own randomness. So you can ask again for a progression you liked, and get the same one back. Adding one cannot shift anything else you were drawing at random.

#### Chord symbols

```swift
let chord: Chord = "F#m7"
let changes = Progression(symbols: "Dm7 G7 Cmaj7 Cmaj7")
```

Symbols are the other way to write changes down, and the one to use when the chords do not all come from one key. A symbol starts with a root like `C`, `Bb`, or `F#`, with an optional octave as in `C3`. An optional quality comes next, such as `m7`, `maj7`, `dim7`, `sus4`, `m7b5`, or `add9`. Each of those has several spellings, and any of them is accepted. An optional bass note comes last, after a slash, as in `C/G`, which inverts the chord until that note is lowest.

`Chord(symbol:)` returns nil for anything that is not a chord, so a typo is something you find out about. The literal form lands on C major instead and says so once, the same way a pitch name literal does.

The one ambiguous part of the notation is a trailing number. The 7 of `Cmaj7` is part of a quality, and the 3 of `Cm3` is an octave. The parser tries the whole suffix as a quality first. Only if that is not a quality does it read a trailing number as an octave.

The trade between the two forms is that degrees survive a change of key and symbols do not.

`Examples/Audio/ChordSymbols` draws the symbol form, and `Examples/Audio/Changes` draws the degree form. In the first, you type a chart into a text parameter. The example draws a card for each token, and it spells out the chord that is sounding.

---

---

### Arpeggio

An `Arpeggio` is a chord played one note at a time, in a set order.

```swift
let arp = Arpeggio(Chord("A3", .minorSeventh), .upDown, octaves: 2)
synth.play(arp[step], for: 0.1)
```

Like a rhythm, you read it by step number, and it wraps. Reading it at the step, rather than counting strikes, keeps the figure in its place in the bar instead of restarting it every time.

The patterns are: `.up` `.down` `.upDown` `.downUp` `.asPlayed` `.converge` `.diverge` `.random`.

`.upDown` and `.downUp` do not play either end note twice in a row, so the turn sounds like a turn and not a stutter. `.asPlayed` is the only pattern that keeps the notes in the order they were given. Every other pattern sorts the notes into a ladder, so `.asPlayed` is the only way to hear a voicing you arranged by hand. `.random` is seeded and is a pure function of the step. The same seed always gives the same sequence, and adding one cannot shift anything else the sketch does at random.

`order` returns one full pass of the pattern, so a sketch can draw the figure it is about to play. `notes` is the pool of notes, spread over the octaves the arpeggio covers.

---

### MarkovChain

A `MarkovChain` learns from a sequence what tends to follow what. Then, when you ask it for elements, it gives you new ones with the same habits.

```swift
var melody = MarkovChain<Int>(seed: 4)
melody.learn([0, 2, 4, 2, 0, -3, 0, 4], loops: true)
melody.start(at: 0)

let degree = melody.next() ?? 0
synth.play(scale[degree])
```

It works over any hashable type, so degrees, `Pitch`es, chord qualities, and step counts all fit. There is a one-line form too. `MarkovChain(learning:order:seed:loops:)` builds the chain and learns the sequence in one step, which is what the example at the end of this page uses.

`order` is how far back it looks. At order 1, each element is chosen from what followed the one before it. At order 2, it looks at the last two elements, which tracks the source more closely and invents less. When it has never seen the current context, it falls back to a shorter one. If that fails too, it falls back to how often each element appeared at all, so it always has an answer.

`loops: true` says the sequence repeats, so what follows the last element is the first. Use it for a repeating figure. Without it, the chain can walk off the end of what it was shown and then has to fall back.

Learning the same phrase twice counts it twice, which is how you make one phrase more likely than another. `continuations` reads the learned counts back as probabilities, most likely first, so a sketch can draw the chain as well as play it:

```swift
for (degree, probability) in melody.continuations {
    drawRect(x, y, probability * 200, 12)
}
```

The walk is seeded and keeps its own random generator. `reset()` forgets where it is, keeps what it learned, and rewinds the randomness, so the same walk comes out again.

### Tuning

A `Tuning` describes pitches by frequency ratios rather than by semitones.

```swift
let tuning = Tuning.just.rooted(at: "C3")
synth.play(tuning[degree])
```

[`Scale`](#scale) divides the octave into twelve semitones, because almost all the music a sketch is likely to make uses those twelve semitones. A `Tuning` does not assume that division. It has the same shape as a `Scale`, so a sketch that indexes degrees and snaps stray pitches works the same way with either type.

The reason to use one is that equal temperament is a compromise. It makes every key equally usable by making every interval except the octave slightly out of tune. A drone piece that never changes key gives up nothing by being tuned in whole number ratios. It gains intervals that lock together instead of beating.

| Member | What it gives |
|---|---|
| `tuning[degree]` / `pitch(_:)` | the pitch of a degree, running past both ends into the periods above and below |
| `frequency(_:)` | the same in Hz |
| `snap(_:)` | the nearest pitch in the tuning, for something decided by a mouse or a sensor |
| `cents` | how far each degree sits above the root, so you can see what a tuning is doing |
| `ratios` / `period` / `degreeCount` | what it is made of |
| `rooted(at:)` | the same tuning somewhere else |

| Named | What it is |
|---|---|
| `.equalTemperament` | twelve equal steps: the ordinary keyboard |
| `.just` | five limit just intonation, the major scale in whole number ratios |
| `.pythagorean` | stacked fifths: a pure fifth and a noticeably wide third |
| `.quarterTones` | twenty four equal steps |
| `.nineteen` / `.thirtyOne` | equal divisions with sweeter thirds than twelve |
| `.bohlenPierce` | thirteen equal steps of a *third* rather than an octave |

`Tuning.equal(_:period:root:)` builds any equal division, and `Tuning(ratios:)` takes ratios of your own, folded into one period and deduplicated.

**Bohlen-Pierce has no octave in it at all.** Every listener is used to a doubled frequency, so a tuning without one sounds wrong at first. After you listen for a while, it stops sounding wrong and simply sounds strange. It works because odd harmonics still line up, so it suits sounds that have only odd harmonics. The [blown tube](./Synthesis.md#physical-models) is one such sound.

`Examples/Audio/Tunings` plays one triad through all seven tunings. A ladder places every degree by its `cents` against the equal-tempered grid, so you can see what moved as well as hear it.

---

### BeatFollower

A `BeatFollower` follows the beat in whatever the sketch is listening to, so the sketch can play along.

```swift
let mic = AudioInput()
lazy var room = BeatFollower(mic)
var counter = StepCounter(perBeat: 2)

override func draw() {
    room.update(at: time)
    for step in counter.steps(upTo: room.beats) {
        synth.play(scale[step % 5], for: 0.2)      // in time with the room
    }
}
```

| Member | What it gives |
|---|---|
| `update(at:)` | reads what has been heard since the last call. Call it once a frame |
| `beats` | the current position of the music, in beats. Hand this to a `StepCounter` |
| `tempo` | beats per minute, or zero until it has an estimate |
| `isFollowing` | whether it has heard enough to be worth following |
| `steadiness` | `0...1`. One means machine-steady timing. A low number means a human player with uneven timing, or a detector that is unsure |
| `rhythm(steps:perBeat:)` | the room's own pattern, as a [`Rhythm`](#rhythm) a sketch can play |
| `reset()` | forget everything, for when the music changes |

There are three things to know about it:

- **A tempo outside the range is folded into it.** The common failure is hearing every eighth note as a beat. That reports twice the tempo for the same music. The follower halves or doubles the tempo until it lands in `60...160`, which stops that.
- **A missed beat costs nothing.** The tempo is the middle value of the recent gaps rather than their average. One missed beat doubles one gap, which moves an average but does not move a middle value.
- **It hears note onsets, not the beat a drummer would tap.** It follows a steady loop well, and it follows rubato playing badly. `steadiness` tells you how much to trust it.

`BeatEngine` is the same mechanism with no audio input. Onset times go in, and musical time comes out. That makes it testable, and it is there for a sketch that decides for itself when a beat happened.

`Examples/Audio/PlayAlong` runs a `BeatFollower` on the microphone. Once `isFollowing` comes on, it plays a note on every beat the follower reports. A generated pulse stands in until the microphone is allowed, so the whole mechanism is visible before any permission is granted.

---

---

### Note

A `Note` is a pitch with its loudness and length attached, for when all three were decided together.

```swift
let note = Note(scale[3], velocity: 0.9, length: .eighth)   // half a beat
synth.play(note, tempo: 120)
```

Its length is a [`NoteLength`](#tempo-and-note-lengths), in beats, because nothing in this tier knows how fast the music is going. The [`Tempo`](#tempo-and-note-lengths) is supplied when the note is played, and `note.seconds(at: tempo)` is the number the synth is handed.

Most sketches never need it, because the composition types deal in pitches and step numbers, and `synth.play(pitch, velocity:for:)` takes the loudness and length directly.

---

### Putting it together

The pieces are meant to be combined. A rhythm decides *when*, a scale decides *which* notes, a chain or an arpeggio decides *what comes next*, and the counter joins them to time:

```swift
let bass = Synth(.bass)
let chords = Synth(.pluck)

let pulse = Rhythm(3, in: 16)
let figure = Rhythm(5, in: 16)
let key = Scale(.minorPentatonic, root: "A2")
var melody = MarkovChain(learning: [0, 2, 4, 2, 0, -3], seed: 4, loops: true)
let tempo: Tempo = 104
var counter = StepCounter(perBeat: 4)

override func draw() {
    for step in counter.steps(upTo: tempo.beats(at: time)) {
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

`Examples/Audio/Generative` draws that sketch as three Euclidean rings on one step count, and its parameters change what is played while it runs.

---

### What is not here yet

This section lists what is missing, so you can plan around it rather than go looking:

- **No sequencer.** There is no type that holds a piece and plays it back. A step number goes in and notes come out, and the arrangement is the sketch's own code. That is deliberate. A sequencer would need a clock, and a clock of its own would stop this tier from running on somebody else's clock.
- **A `Scale` is still twelve-tone.** `Scale(intervals:)` takes whole semitones. Anything else is a [`Tuning`](#tuning), which is a separate type rather than a setting on a scale. Chords are not built out of a tuning.
- **Following a beat is not following a bar.** A [`BeatFollower`](#beatfollower) knows where the beat is but not where the downbeat is. So a pattern locks to the pulse rather than to the phrase.

---

### Credits

The Euclidean rhythms come from Bjorklund's algorithm for spacing pulses in a spallation neutron source. Godfried Toussaint connected that algorithm to musical timelines, and the named rhythms and the pattern-and-gap notation are from his paper. The implementation here is written from the description of the construction, not translated from anyone's code. The tunings are historical. Five limit just intonation and the Pythagorean stack of fifths are older than notation. Bohlen-Pierce is named for Heinz Bohlen, Kees van Prooijen, and John R. Pierce, who each arrived at it separately. Full credit is in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

---

<sup>[Synthesis](./Synthesis.md) covers the sound a note makes. [MIDI](../Integration/MIDI.md) covers running on an external clock.</sup>
