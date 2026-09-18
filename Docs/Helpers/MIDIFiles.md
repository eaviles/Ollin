#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `MIDI files`</sup>

---

## MIDI files

A Standard MIDI File is how a piece of music travels between programs. Every sequencer, notation program, and drum machine reads and writes one, and there are decades of them on disk. `MIDIFile` reads one into notes a sketch can play or draw, and writes one back out, so a phrase a sketch worked out for itself opens in a program made for editing music.

This lives in `OllinAudio` rather than `OllinMIDI`, because a file arrives as music rather than as messages: its notes are [`ScheduledNote`](./Composition.md#schedulednote) values, the same thing a [`StepSequencer`](./Composition.md#stepsequencer) hands back, so a [`Synth`](./Synthesis.md) plays them with nothing in between. [`MIDI`](../Integration/MIDI.md) is the other half, and it covers gear playing live on a cable.

```swift
import Ollin
import OllinAudio

final class Player: Sketch {
    let synth = Synth(.pluck, polyphony: 12)
    var song = MIDIFile([])

    override func setup() {
        song = (try? MIDIFile(resource: "prelude", in: .module)) ?? MIDIFile([])
    }

    override func draw() {
        background(.black)
        // Where the music is now, and where it will be at the end of the frame.
        let now = song.beats(at: time)
        let ahead = song.beats(at: time + deltaTime)
        synth.play(song.notes(from: now, to: ahead), tempo: song.tempo(at: now), from: now)

        for note in song.notes {
            let x = width * note.beat / song.lastBeat
            drawRect(corner: Vector2(x, height - note.pitch.midi * 8), width: 6, height: 6)
        }
    }
}
```

### Contents

- [Reading a file](#reading-a-file) - from disk, from a bundle, or from bytes
- [What comes back](#what-comes-back) - tracks, notes, and everything else the file carries
- [Beats and seconds](#beats-and-seconds) - the tempo map, read from either side
- [Writing a file](#writing-a-file) - from notes a sketch worked out
- [Recording what you play](#recording-what-you-play) - a take off a live instrument
- [What is read, and what is passed over](#what-is-read-and-what-is-passed-over)
- [Things worth knowing](#things-worth-knowing)

---

### Reading a file

Three ways in, all of them throwing a `MIDIFile.ReadError` that names the byte it stopped at.

```swift
let fromDisk = try MIDIFile(contentsOf: "~/Music/prelude.mid")
let bundled = try MIDIFile(resource: "prelude", withExtension: "mid", in: .module)
let received = try MIDIFile(data: bytes)
```

`in:` has no default. A default would resolve to Ollin's own bundle rather than your sketch's, so pass `.module` yourself.

An error reads as a sentence, and carries the two things worth acting on:

```swift
do {
    song = try MIDIFile(contentsOf: path)
} catch let error as MIDIFile.ReadError {
    print(error)              // "byte 14: the track says it holds 400 bytes and the file ends first"
    print(error.offset ?? 0)  // 14
    print(error.problem)      // the sentence without the byte
} catch {
    print("the file could not be opened: \(error)")
}
```

### What comes back

A `MIDIFile` is a value with everything the file said in it.

| Member | What it holds |
|---|---|
| `format` | `.oneTrack`, `.parallelTracks`, or `.separatePatterns`: the 0, 1, or 2 in the header |
| `division` | `.perQuarter(960)`, or `.perSecond(framesPerSecond:ticksPerFrame:)` for a file cut to picture |
| `name` | what the file calls the piece |
| `tracks` | the parts, one per channel |
| `tempoChanges` | where the music changes speed, each a `MIDIFile.TempoChange` |
| `timeSignatures` | where the bars change shape, each a `MIDIFile.TimeSignature` |
| `markers` | the places somebody named, each a `MIDIFile.Marker` |

A `MIDIFile.Track` is one part:

| Member | What it holds |
|---|---|
| `name` | what the file calls the part |
| `channel` | 1 to 16, the way a sequencer labels them. 10 is drums by convention |
| `program` | the sound the file asks for, 0 to 127, if it asks for one |
| `notes` | `ScheduledNote` values: pitch, loudness, length in beats, and the beat it lands on |
| `controls` | `MIDIFile.ControlChange`: a mod wheel, a pedal, a fader, each `0...1` |
| `bends` | `MIDIFile.PitchBend`: where the wheel sat, `-1...1` with 0 at rest |
| `isEmpty`, `lastBeat` | whether anything happens on it, and where its last note lets go |

Reading across every part at once:

```swift
song.notes                       // every track's notes, in playing order
song.notes(from: now, to: ahead) // the ones that start in a stretch of beats
song.lastBeat                    // where the last note lets go, in beats
song.duration                    // how long the piece lasts, in seconds
song.tempo                       // how fast it starts
song.tempo(at: beat)             // how fast it is there, with the bars from the time signature
song.timeSignature(at: beat)     // "3/4", and `barLength` in beats
```

A `MIDIFile.TimeSignature` carries `count` and `unit` (the 3 and the 4 in `3/4`) plus `barLength`, which is three beats in `6/8` rather than six, since a beat is a quarter note everywhere in Ollin.

### Beats and seconds

Nothing in the composition tier knows what a second is, and a file agrees: every position in it is a beat. The tempo map is what joins the two, and it reads from either side.

```swift
song.seconds(at: 16)   // where bar five falls on the clock
song.beats(at: time)   // where the music is after this many seconds
```

They are exact inverses, and they walk the tempo map rather than dividing by one number, so a file that slows down partway through still lines up with the sketch clock. A playhead is one line:

```swift
let beat = song.beats(at: time).truncatingRemainder(dividingBy: song.lastBeat)
```

### Writing a file

The short form takes notes and a tempo. Anything that answers in `ScheduledNote` values goes straight in, which is every pattern type in [`Composition`](./Composition.md).

```swift
var phrase: [ScheduledNote] = []
var bar = 0.0
while bar < 32 {
    phrase += sequencer.events(upTo: bar)
    bar += 4
}
try MIDIFile(phrase, tempo: 112, name: "Pattern").write(to: "pattern.mid")
```

The long form builds the parts yourself, with everything else the file can carry:

```swift
var file = MIDIFile(
    format: .parallelTracks, name: "Eight Bars",
    tracks: [
        MIDIFile.Track(chords, name: "Chords", channel: 1, program: 89),
        MIDIFile.Track(melody, name: "Melody", channel: 2, program: 46),
    ],
    tempoChanges: [MIDIFile.TempoChange(beat: 0, tempo: 96),
                   MIDIFile.TempoChange(beat: 24, tempo: 80)],
    timeSignatures: [MIDIFile.TimeSignature(count: 4, unit: .quarter)])
file.markers = [MIDIFile.Marker(beat: 0, text: "head")]

// A part can carry what else happened on its channel, written out with it.
file.tracks[1].controls = [
    MIDIFile.ControlChange(beat: 0, controller: 1, value: 0),     // the mod wheel at rest
    MIDIFile.ControlChange(beat: 8, controller: 1, value: 1),     // and all the way up
]
file.tracks[1].bends = [MIDIFile.PitchBend(beat: 12, position: -0.5)]

try file.write(to: "eight-bars.mid")
let written = file.data()        // the same thing, if you would rather send it
```

`write(to:)` takes a path, and `data()` hands back the bytes. In a file laid out as parallel tracks the first chunk carries the timing, which is where a sequencer looks for it; reading such a file back folds that chunk into the tempo map rather than handing you an empty part.

### Recording what you play

A `Synth` will write down what it is asked to play, so a take improvised at the keyboard can be opened somewhere else.

```swift
override func keyPressed() {
    switch key {
    case "r": synth.startRecording(tempo: 96, name: "Take")
    case "s": try? synth.stopRecording().write(to: "take.mid")
    default: break
    }
}
```

| Call | What it does |
|---|---|
| `startRecording(tempo:name:)` | starts writing notes down against a clock that starts here |
| `stopRecording()` | stops, and hands back a `MIDIFile`. A note still sounding is let go |
| `recordedSoFar()` | what has been played so far, without stopping |
| `isRecording` | whether one is running |

The tempo decides where the bar lines fall around what was played, and nothing else: the notes keep the timing they were played with, down to the wait each one was asked with, so a sequencer's swing survives. Only notes are written. A bend, a press, or a slide belongs to the instrument that made the sound rather than to the music.

### What is read, and what is passed over

Read and written: notes, control changes, pitch bends, program changes, track names, tempo changes, time signatures, and markers.

Read and stepped over: aftertouch, system-exclusive blocks, key signatures, and the meta events that describe the file rather than the music. Their bytes are counted and skipped, so a file that carries them loads and plays without the parts this does not model. A chunk whose kind is unknown is skipped by its own length, which is what the format says to do with one.

### Things worth knowing

- **A track plays on one channel.** A track that uses several reads as one track per channel, since the channel is what says which instrument a note belongs to. That is what makes a format 0 file useful: everything in it is on one chunk, and it arrives split into the parts that were playing.
- **A tempo is held as whole microseconds in a quarter note.** So 120 and 96 come back exactly and 112 comes back a ten-thousandth off. Compare tempos with a tolerance rather than for equality.
- **Loudness comes in 127 steps.** A velocity written at 0.8 comes back within a step of it. A note asked for at 0 is written at the quietest a file can carry, because a note struck at nothing is how the format spells a note let go.
- **The resolution decides which beats survive.** The default, 960 ticks in a quarter note, divides by three, four, five, six, and eight, so triplets and swung offbeats land exactly where they were put.
- **Format 2 is patterns, not parts.** Its tracks are separate pieces rather than parts of one, so reading `notes` across them joins music the file never claimed was together. Read each track on its own.
- **Reading is not playing.** A file names a program number, not a sound. Which voice plays a part is the sketch's choice.

---

### Credits

The format is the Standard MIDI File specification published by the MIDI Association, and this reader and writer are written from it. Full credit is in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

---

<sup>[Composition](./Composition.md) covers working out what to play. [Synthesis](./Synthesis.md) covers the sound a note makes. [MIDI](../Integration/MIDI.md) covers gear playing live on a cable.</sup>
