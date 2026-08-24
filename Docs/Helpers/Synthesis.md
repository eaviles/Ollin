#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Synthesis`</sup>

---

## Synthesis

Make a sketch play. [`Audio`](./Audio.md) is the listening side, and it turns sound into values you read in `draw()`. This is the other direction, where the sketch is what makes the sound. Add `import OllinAudio` alongside `import Ollin` to reach it.

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

Two things are worth noticing there. Nothing was started, because the first note starts the engine. The circle is sized from `synth.amplitude`. A `Synth` is an [`AudioSource`](./Audio.md#reading-audio) the way the microphone is, so a sketch can read back whatever it is playing.

### Contents

- [Synth](#synth) - the instrument, and how notes are asked for
- [Pitch](#pitch) - names, numbers, and what lies between them
- [Voice](#voice) - what a note is made of
- [Physical models](#physical-models) - a plucked string, a struck shape, a bowed string, and a blown tube
- [Patch](#patch) - an instrument built rather than picked
- [Sampled instruments](#sampled-instruments) - an instrument made of recordings, and where to find more
- [Placing a sound](#placing-a-sound) - where it comes from in the 3D scene
- [Sound in an export](#sound-in-an-export) - carrying the music out of the window
- [Envelope](#envelope) - how a note arrives and how it goes
- [`Voice.Filter`](#voicefilter) - what is taken out of it, and how that moves
- [Effects](#effects) - the chain the sound leaves through
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

**When voices run out**, the next note takes one. A note already fading is taken before a held one. A melody played over a held chord therefore takes its voices from its own earlier notes rather than eating the chord. A voice being taken is given a few milliseconds to get out of the way, so it does not click.

**Notes start on the next block of audio**, a few milliseconds after you ask. That is a property of the hardware, not a queue. The wait is below the length of a frame, so a note asked for in `draw()` lands with the frame that asked for it.

---

### Pitch

A pitch is written however you already think of one:

```swift
synth.play(60)                     // MIDI number
synth.play("C4")                   // note name, sharps or flats, any case
synth.play(60.5)                   // a quarter tone above middle C
synth.play(Pitch(frequency: 440))
```

`Pitch.midi` is a `Double`, so a pitch can sit between the keys. Bends, glides, and tunings outside the twelve equal steps all need that. `frequency` is derived from it, so `transposed(by: 12)` always doubles the frequency whatever it started from.

`"C4"` is middle C, and a name without an octave lands in that octave. A *literal* that is not a note name lands on middle C. It says so once rather than stopping the sketch. Use `Pitch(name:)`, which returns nil, where you want to be told in code.

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
| `source` | what the note is built from: `.wave(Waveform)`, `.string(PluckedString)`, `.body(ModalBody)`, `.bowed(BowedString)`, `.blown(BlownTube)`, `.patch(Patch)`, or `.sampled(Sampled)`. See [Physical models](#physical-models), [Patch](#patch) and [Sampled instruments](#sampled-instruments) |
| `waveform` | `.sine`, `.triangle`, `.sawtooth`, `.square`, `.noise`, brightest last |
| `envelope` | how the note's loudness moves. See [Envelope](#envelope) |
| `filter` | what is taken out of it, or nil. See [`Voice.Filter`](#voicefilter) |
| `detune` | a second oscillator this far away, in semitones |
| `gain` | the voice's own level before the note's velocity |

**`detune` is smaller than it looks.** A few hundredths of a semitone is the useful range. Two oscillators slightly apart drift in and out of phase, and that beating makes a held note shimmer rather than sit still. A whole semitone is an interval, not a shimmer, which is what `.bell` uses it for.

`waveform` and `source` are the same setting written two ways. Reading `waveform` on a string voice gives `.sine`, and setting it makes the voice an oscillator again.

The geometric waves are corrected as they are drawn. A sawtooth therefore still sounds like a sawtooth at the top of the keyboard, instead of ringing against itself.

---

### Physical models

A wave is a shape drawn over and over. A physical model is the thing itself, worked out as it goes, and what you hear falls out of that rather than being dialed in.

There are four, and they split into two kinds. A plucked string and a struck body are **set going once** and then left to fade, so the whole note is decided at its start. A bowed string and a blown tube are **kept going**. The note lasts as long as you keep driving it, and it can change while it sounds. `Synth.drive` is that driving, and it is the difference this section is really about.

#### A plucked string

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

A string is a disturbance running up and down a length of something under tension. It loses a little at each end, and it loses its top faster than its bottom. That is a delay line one period long with a filter in the loop. Everything a player recognizes comes out of that loop. It gives the attack, the way a held note darkens, and the difference between plucking near the bridge and over the hole.

<img src="../../Guide/Images/29-MakingSound/PluckedString.jpg" alt="A block diagram of a delay line whose output loses its top, is tuned, and is fed back round at slightly lower level, and below it four plucks of the same string at different points, each with the shape it leaves and a bar chart of the modes that pluck excites, showing the missing ones as gaps" width="680">

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

**`pick` is the one that sounds least like a setting.** A string held at a point cannot move there. Every harmonic with a node at that point is therefore missing. Plucking at `0.5` loses every even harmonic and comes out hollow. Plucking near the end keeps them all and comes out thin and nasal. A quarter of the way along is roughly where a guitar is played. `Examples/Audio/Strings` lets you click a string wherever you want to pluck it.

**A string decides for itself how a note fades.** The envelope only has to stay out of the way. `Envelope.plucked` is that envelope, and the string presets use it. Ask for a note long enough to let the string finish (`for: string.decay`), or the envelope's release will cut it off mid-ring.

**Tuning is exact.** The loop has to come out exactly one period long, and a whole number of samples cannot do that. An allpass filter supplies the fraction left over. The loop filter's own delay is counted into the budget, so changing `damping` cannot move the pitch. Without that, notes go progressively sharper or flatter towards the top of the keyboard. At the top of the range, rounding the loop to whole samples is out by most of a semitone.

Everything else about the voice is unchanged. `detune` gives a second string slightly apart, and the `filter` still applies after. A string is an ordinary `Voice`, so it can be assigned between notes like any other.

#### A struck body

The other model here is something hit rather than plucked. A struck object does not make a wave. It makes a handful of pure tones at once, each fading at its own rate. Its shape decides which tones those are.

```swift
let synth = Synth(.chime)
synth.play("C4", for: 4)
```

| Preset | What it sounds like |
|---|---|
| `.drum` | a round drumhead, with a pitch you can argue about |
| `.bar` | a xylophone key: a note with a knock on the front |
| `.chime` | a bell, with the minor third that makes one sound like a bell |
| `.glass` | rung rather than struck: nothing at the front, a long pure tone behind |

`ModalBody` is the value underneath, and `.drum`, `.plate`, `.bar`, `.bell`, `.wood`, and `.glass` are the ones with names. Its settings:

| Property | What it does |
|---|---|
| `modes` | the tones it rings at, as ratios to its lowest, and how much of each |
| `decay` | how long the lowest tone takes to fade, in seconds |
| `damping` | how much sooner the higher ones go, `0...3` |
| `hardness` | how hard the strike is, `0...1`: a small hard mallet against a soft one |

`damping` is most of what separates one struck thing from another. At 0 every tone fades together, which is a bell. At 1 a tone twice as high goes twice as fast, which is most things. Past 2 it is a knock rather than a note.

#### A shape you drew, struck

The frequencies can come from geometry instead of a list. A flat shape held at its edge rings at frequencies decided entirely by its outline, and `StruckShape` works them out:

```swift
let outline = textToShapes("O").first!
let bell = StruckShape(outline)                  // once, in setup()

override func mousePressed() {
    synth.voice = Voice(body: bell!.body(struckAt: Vector2(mouseX, mouseY)))
    synth.play("C4", for: 3)
}
```

Nothing chooses that sound. The ratios come from the outline itself:

- A round one rings like a real drumhead: 1, 1.59, 2.14, 2.30, and so on. Those are the zeros of the Bessel functions.
- A square one gives a square membrane's list: 1, 1.58, 2, 2.24.
- An outline nobody has a name for gives whatever its own geometry allows.

Only the *ratios* come from the shape. The note is decided when you play it, so one outline is an instrument rather than a single sound.

<img src="../../Guide/Images/29-MakingSound/StruckShapes.jpg" alt="Five outlines, each with the frequencies it rings at drawn on a scale from one to four: a circle, a square, a triangle, an oblong, and an irregular blob, where the symmetric ones show pairs of lines sitting together and the asymmetric ones show single lines" width="680">

| Member | What it does |
|---|---|
| `StruckShape(_:modes:resolution:)` | measures an outline. Nil if it is too small or thin to hold a standing wave |
| `ratios` | what it rings at, as multiples of its lowest tone |
| `body(struckAt:decay:damping:hardness:)` | the body it is, struck at a point |
| `gains(struckAt:)` | how much a strike there puts into each tone |

Three things are worth knowing:

- **Measuring is the expensive part, and striking is free.** Measuring a circle takes a few hundredths of a second in a release build. A sketch run straight from source is unoptimized, and there it takes a second or two. So do it once, in `setup()`, and keep the `StruckShape`. `ModalBody(shape:)` is the one-liner that measures every time, for when the shape never changes.
- **Where you strike it decides which tones answer.** A tone that holds still under your finger gets nothing. That is the same reason a string plucked in the middle sounds hollow. Strike a circle exactly in the middle, and every tone with a line of stillness through the center goes quiet. That is most of them.
- **A symmetric shape rings at some tones twice.** A pattern that fits at one rotation fits at another, and both are really there. That is why the circle's list above has each entry twice, apart from the ones with no rotation at all. A real drum does the same. Which of a pair takes a given strike is arbitrary, because they ring at the same frequency. Read their gains together rather than one at a time.

A body carries up to sixteen tones, which is what lets it reach the audio thread without allocating. A tone that would land above half the sample rate is dropped. Folding it back down the spectrum would add something that was never struck.

#### A bowed string

```swift
let synth = Synth(.cello)
synth.noteOn("G2")
synth.drive = 0.7          // and keep moving it while the note sounds
```

| Preset | What it sounds like |
|---|---|
| `.violin` | bright and a little edgy |
| `.cello` | broader and darker, bowed further from the bridge |
| `.bowed` | a light bow a long way up the string, soft and almost breathy |
| `.ponticello` | right next to the bridge: glassy, with the fundamental thinned out |

The string is the same string. What is different is that a pluck happens once and a bow keeps happening.

What makes it sound bowed is one nonlinearity. Rosin grips harder when the bow and the string are traveling together than when they are sliding past each other. The string is therefore caught by the bow, dragged sideways, torn loose, snapped back, and caught again, hundreds of times a second. That cycle is the tone, and it is why a bowed note comes out close to a sawtooth. The string spends most of each cycle stuck to the bow.

| Setting | What it does |
|---|---|
| `position` | where the bow sits, `0...1` from the bridge. Small is thin and bright, which is what *sul ponticello* means |
| `force` | how hard it presses. More force keeps the string stuck for longer in each cycle, which is louder and harder-edged |
| `decay` | how long the string would ring if the bow were lifted |
| `damping` | how much sooner the bright part goes than the low part |

Two things fall out of the model rather than being settings, and both are worth knowing:

- **Bow too fast for the force and it breaks.** The string tears loose twice a cycle instead of once. The note jumps to the octave, which is exactly what over-bowing sounds like on a real instrument. Raise `force` or lower `drive` and it settles back.
- **Loudness comes from force as much as from speed.** Across the whole range of `drive` the level moves by about 8 dB. `force` moves it further. That is also true of a bow, but it means `force` is the loudness knob and `drive` is the expression one.

#### A blown tube

```swift
let synth = Synth(.clarinet)
synth.noteOn("D4")
synth.drive = 0.8
```

| Preset | What it sounds like |
|---|---|
| `.clarinet` | hollow and woody |
| `.reed` | bitten tight: thin and pure, with almost nothing above the third harmonic |
| `.hollow` | a loose lip on a long tube, dark and full of air |

A column of air in a tube resonates, and a reed at one end keeps feeding it. The reed is pushed shut by the very pressure that is driving it, and that feedback is what makes the whole thing sing.

The tube is stopped at the reed and open at the far end, and that one fact is most of the sound. A tube closed at one end fits only a quarter of a wave, so it supports the odd harmonics and not the even ones. That is why it is hollow and woody rather than bright. It also sounds an octave and a fifth below an open tube of the same length, instead of an octave below. Nothing in the code decides that the even harmonics should be missing. They are missing because the tube is half as long as an open one.

| Setting | What it does |
|---|---|
| `embouchure` | the bite. Higher shuts the reed at a lower pressure so it never gets far open, which is thinner and purer; a looser lip is the fuller, reedier one |
| `breathiness` | how much of the breath arrives as noise. A wind instrument with none of it sounds synthetic in a way that is hard to place until it is put back |
| `decay` | how long the tube would ring if the breath stopped |
| `damping` | how much sooner the bright part goes |

#### Driving them

```swift
synth.drive = 0.3 + 0.5 * abs(sin(time * 2))
```

`drive` is `0...1`, read every sample, and shared by every note the instrument is playing. That is right for one bow and one breath. At zero there is nothing to hear, because nothing is being done. The sources that are set going once (a wave, a plucked string, a struck body) ignore it entirely. Adding it changed nothing that already worked.

This is the control an envelope cannot give you. An envelope is decided when the note starts. `drive` is whatever you are doing right now.

---

### Patch

An instrument built rather than picked.

A [`Voice`](#voice) is a fixed chain. Something makes a wave, an envelope shapes it, and a filter takes part of it away. That covers a great deal and it cannot be rearranged. A `Patch` is the tier underneath, where the routing itself is the value.

```swift
let bell = Patch.tone(.sine)
    .modulated(by: .tone(.sine, ratio: 3.5), index: 4)

synth.voice = Voice(patch: bell, envelope: .percussive)
```

The relationship is the one the drawing side already has. Bare calls sit on a `Drawer` that can do more, and the presets sit on this. Nothing about `Synth(.pluck)` changes because this exists, and a one operator patch renders the same samples the plain oscillator does.

#### What an operator is

One oscillator with a frequency, a level, and possibly something modulating it. Its frequency is a **ratio of the note** rather than a pitch, so a patch is an instrument rather than a chord. Ratio 1 is the note, and 2 is the octave above. Ratio 3.5 is not a note at all, and that is where metallic sounds come from.

An operator's `level` means one of two things depending on where it sits. On an operator that reaches the output it is a mix level. On one that modulates another it is how far it pushes, which is the difference between a slight waver and a bell. That is one number doing the two jobs a level does, and it is the convention rather than a shortcut.

| Building | What it does |
|---|---|
| `.tone(_:ratio:level:)` | one oscillator, sounding on its own |
| `.modulated(by:index:)` | the other patch stops being heard and starts being felt |
| `.mixed(with:)` | both sounding at once, additively |
| `.fedBack(_:)` | its output operators pushing themselves |
| `.at(level:)` / `.at(ratio:)` | balancing one against another |
| `operators` / `count` | reading a patch back |

| Named | What it sounds like |
|---|---|
| `.simple` | one sine |
| `.bell` | pushed at three and a half, which is not a harmonic, so it rings like struck metal |
| `.brass` | pushed hard by one an octave up |
| `.glass` | pushed at a ratio just off a whole number, so it drifts against itself |
| `.buzz` | one operator pushing itself |
| `.struck` | a body and a strike heard together |

#### Why modulation rather than a filter

A filter can only take harmonics away, and a sine has none to take. Modulation puts them in, which is why `index` turns a plain tone into brass and no amount of filtering will. Small values waver. Past about 2 it is a new instrument rather than the old one wobbling.

Whole ratios stay musical, since their tones land on the note's own harmonics. Anything else gives the inharmonic tones bells and metal are made of, which is the whole of why `.bell` uses 3.5.

<img src="../../Guide/Images/29-MakingSound/Modulation.jpg" alt="Four columns, each a wave above the tones it contains: a plain sine with a single bar, the same sine at index 2 and index 6 growing a run of harmonics, and one at ratio 3.5 whose bars land between the harmonics instead of on them" width="680">

#### Why it is a fixed size

A patch travels to the audio thread inside a note, through a queue of preallocated slots. It therefore has to be something that can be copied a word at a time, with no arrays, no references, and nothing to allocate. So the operators live in fixed lanes and there are **eight** of them, the same bargain [`ModalBody`](#physical-models) makes with its sixteen tones.

Eight is more than most instruments worth having need. A patch that would exceed it **comes back unchanged and says so**, rather than quietly dropping an operator. A patch with a piece missing is a different instrument, and finding that out by ear is worse than a note in the log.

Modulators always end up in an earlier lane than what they push, so one forward pass evaluates the whole patch. That is a property of how patches are built rather than something checked afterwards.

---

### Sampled instruments

Everything else a `Synth` plays is worked out as it goes. This is the other way. Someone recorded the thing, and a note means finding the nearest recording and moving it to the pitch asked for.

```swift
synth.instrument = SampledInstrument.builtin
synth.voice = Voice(sampled: Sampled(), envelope: .plucked)
synth.play("C4", for: 1.5)
```

Ollin bundles one small instrument, so this can be heard working without downloading anything. It is a struck bar recorded at five pitches. `Scripts/make-sample-instrument.swift` generates it rather than sourcing it, so it is Ollin's own and carries nobody's license. It is a demonstration, not a library.

#### Why the instrument is set separately from the voice

A `Voice` travels to the audio thread inside a note and has to be copyable a word at a time. That is why a [`ModalBody`](#physical-models) caps at sixteen tones and a [`Patch`](#patch) at eight operators. Recordings are megabytes on the heap and cannot ride along. So the recordings live on the `Synth` and the `Voice` says only how to play them.

| Member | What it does |
|---|---|
| `Synth.instrument` | which recordings. Set it before the notes that need it |
| `Voice(sampled:)` | how they are played |
| `Sampled.loops` | whether a note holds by repeating the looped part, where the recording says where that is |
| `Sampled.velocitySensitivity` | `0` plays every note as loud as it was recorded, which suits an instrument whose recordings are already its dynamics. `1` makes velocity the whole of it |
| `Sampled.transpose` | moves every note, for an instrument recorded at the wrong pitch |

The read head moves through a recording at whatever rate the pitch asks for. That moves its pitch and its length together, exactly as a tape does. That is also the limitation. Move a recording far enough and the instrument audibly changes size. A real library therefore ships many recordings rather than one, and the nearest is always chosen.

#### Loading one

```swift
let piano = SampledInstrument(sfz: "Piano.sfz", in: .module)   // bundled with the sketch
let other = SampledInstrument(contentsOf: url)                 // anywhere on disk
```

The format is **SFZ**, a plain text file listing regions. Each region names an audio file and the notes it answers to, with the audio beside it. It is what most freely licensed libraries ship in.

The opcodes read are the ones that decide which file plays and at what pitch. They are `sample`, `lokey` / `hikey` / `key`, `pitch_keycenter`, `lovel` / `hivel`, `tune`, `transpose`, `volume`, and the loop points. SFZ has hundreds of others covering filters, envelopes, round robins and modulation.

**An unknown opcode is skipped rather than refused**, so a library that uses them loads and plays, without the parts this does not model. A region whose audio file is missing costs that part of the range rather than the whole instrument.

#### Where to find instruments

The licenses matter here, so they are worth stating alongside the links.

**Free to use and to redistribute (CC0, public domain).** These can be bundled into anything, including something you sell.

| Where | What |
|---|---|
| [VCSL](https://github.com/sgossner/VCSL) | Versilian Community Sample Library. CC0, broad, ships in SFZ, and made explicitly for use inside software |
| [VSCO 2 Community Edition](https://versilian-studios.com/vsco-community/) | CC0 chamber orchestra, about 3 GB |
| [University of Iowa MIS](https://theremin.music.uiowa.edu/mis.html) | Anechoic instrument recordings, free of restrictions. Raw audio with no SFZ map, so you write the regions |
| [FreePats](https://freepats.zenvoid.org/) | A collection of free instruments; check each one, since the licenses differ across it |

**Free per item.** [Freesound](https://freesound.org/) is enormous, but every upload carries its own license: CC0, CC-BY, or CC-BY-NC. Filter by license and check each clip, because the three are mixed together.

**Free to make music with, but not to redistribute.** The [Philharmonia Orchestra samples](https://philharmonia.co.uk/resources/sound-samples/) are excellent. Their terms say they must not be made available "as is", meaning as samples or as a sampler instrument. That is fine for a piece you release. It is not something to ship inside a sketch you hand to someone else.

The [SFZ format site](https://sfzformat.com/) documents the format itself and lists more libraries.

---

---

### Placing a sound

A sound can come from somewhere in the 3D scene, with the camera as the listener.

```swift
override func draw() {
    cameraShowcase(.autoOrbit())
    guard let eye = activeCamera else { return }

    synth.place(at: Vector3(2, 0, -3), heardFrom: eye)
    synth.hearingRange = 1...20
}
```

Both facts arrive together because neither means anything alone. A position says nothing until something is listening, and where the sketch is looking from is where it hears from. Call it every frame, so a moving object and a moving camera both work.

On headphones the placing is done the way the ear works it out, which is more than loudness. It uses how much later the sound reaches one ear than the other, and what a head does to a sound arriving round it. So something behind you is behind you rather than merely quiet. On speakers it falls back to a plain left and right.

Placing survives an [export](#sound-in-an-export). The moves are written down as the frames are drawn, and applied when the soundtrack is rendered.

| Member | What it does |
|---|---|
| `place(at:heardFrom:)` | where the sound is, and where it is heard from |
| `position` | where it is, or nil if it has not been placed |
| `hearingRange` | the distance over which it fades, in scene units |
| `unplace()` | back to being heard from everywhere at once |

**The first call rebuilds the instrument's audio chain**, so make it before the first note if you can. Placing a sound is a different shape of graph rather than a setting on it. One stream has to arrive at something that knows where the ears are, and leave it as two. Once placed, an instrument stays placed.

`Examples/Audio/Spatial` is three chimes standing still and one walking past them.

---

### Sound in an export

A sketch that plays carries its sound out of the window:

```sh
swift run --package-path Examples Example-Audio-SoundInAnExport --export-video piece.mp4 --frames 480
```

The file has the music in it. There is no recording step and nothing to switch on. The exporters drive a sketch on a fixed clock with nothing playing. The notes are written down instead of going to the speakers. The soundtrack is rendered at the end, through the same code that would have fed them.

That works because the renderer takes events and gives back samples and has no clock of its own. An export is that same code with the waiting taken out. Which is also why **the sound reproduces**. Export twice and the audio comes back sample for sample identical, so a piece is something you can come back to.

What to know:

- **`--export-video` and `--export-loop` carry sound.** GIF has no way to hold any, and the still and vector exports are one frame.
- **An instrument has to be a property of the sketch**, in the usual place, so it can be found. One made and thrown away inside `draw()` is not.
- **A note's length travels in beats of real time, not samples**, so the file is written at its own rate. The hardware rate does not decide it.
- **Delay and reverb are in the file**, because the export runs the same effects the output had.
- **A placed sound is placed in the export too.** Where it was and where it was heard from are written down each frame. The notes travel the same way, and the soundtrack is rendered through a listener afterwards. So a sound that walks past you live walks past you in the file. Place from the first frame. The chain is fixed when the soundtrack machine is built. An instrument that starts playing before it is placed says so, rather than quietly coming out centered.
- **An exported placing is a plain left and right**, not the head model headphones get live. A file cannot know what it will be played back on.
- **A sketch that holds no instrument writes exactly the file it wrote before**, with no audio track at all.

---

### Envelope

The shape of a note over time.

```swift
Envelope(attack: 0.001, decay: 0.4, sustain: 0, release: 0.1)   // a pluck
Envelope(attack: 0.8, decay: 1.0, sustain: 0.7, release: 1.5)   // a pad
```

- `attack` is the time from silence to full level.
- `decay` is the time to fall from there to `sustain`.
- `sustain` is the level a held note rests at (`0...1`, not a time).
- `release` is the time to fall back to silence once the note is let go.

The falling segments approach rather than arrive. `decay` and `release` name the time to come **within a thousandth** of where they are headed. That is what the ear reads as the note being over.

A `sustain` of 0 means the note tells its whole story on its own, and a held key adds nothing. That is what struck things do, like bells, plucks, and drums.

Presets: `.percussive`, `.organ`, `.swell`, `.standard`.

<img src="../../Guide/Images/29-MakingSound/Voices.jpg" alt="Four envelope curves drawn over three seconds with the key let go at 1.4 seconds: a labeled one showing attack rising, decay falling to a held sustain level, and release falling away, then percussive spiking and vanishing at once, organ holding flat until it is let go, and swell rising and falling slowly" width="680">

A note let go early falls from wherever it had reached, and a voice retriggered while it is still sounding bends into the new note. Both exist so that neither clicks.

---

### `Voice.Filter`

What is taken out of the wave, and how that moves while the note sounds. This is most of what a synthesizer sounds like. A note that is bright when struck and darkens as it decays is a filter closing, not a wave changing.

```swift
Voice.Filter.lowpass(cutoff: 2000, resonance: 0.3)          // does not move
Voice.Filter.sweep(from: 400, by: 3.5, resonance: 0.35)     // opens, then closes
```

| Property | What it does |
|---|---|
| `mode` | `.lowpass` (the usual one), `.highpass`, `.bandpass`, `.notch` |
| `cutoff` | where the filter sits when the note starts, in Hz |
| `resonance` | how much it emphasizes its own cutoff, `0...1`. Past about 0.7 the cutoff whistles |
| `envelopeAmount` | how far `envelope` moves the cutoff, **in octaves**. Negative closes it as the note goes on |
| `envelope` | the shape of that movement |
| `keyTracking` | how far the cutoff follows the note being played, `0...1` |

`keyTracking` defaults to 0, so high notes come out duller than low ones, which is what real instruments do. At 1 the cutoff moves with the note step for step. That is what makes an unpitched wave playable. A noise voice has no pitch of its own, so the filter is the only thing a note can move. That is how `.breath` works.

The filter is solved by integrating the circuit rather than folding a fixed answer. The cutoff therefore lands where it was asked for across the whole range, and stays stable while it is swept. A filter that only behaves standing still is no use to a note that opens as it is struck.

---

### Effects

Everything done to the sound after it is made, in order.

```swift
synth.effects = [
    .distortion(Distortion(.softClip, mix: 0.3)),
    .delay(Delay(time: 0.28, feedback: 0.5)),
    .reverb(Reverb(.hall, mix: 0.4)),
]
```

The voice side of this library is routing as a value. A [`Patch`](#patch) says what an instrument is made of and how the pieces are wired. This is the same idea on the way out, so an instrument is finished rather than merely decorated.

**Order is the point.** An echo of a distorted sound and a distorted echo are different. So are a reverb of an echo and an echo of a reverb. The first repeats a room, and the second puts repeats in one. Writing the chain as a list is how that becomes something you can say.

| Effect | What it is |
|---|---|
| `.delay(Delay)` | the sound again, later and quieter each time |
| `.reverb(Reverb)` | a room around it |
| `.equalizer(Equalizer)` | lifting or cutting part of the spectrum |
| `.distortion(Distortion)` | driving it past where it fits |

#### The two that were here first

```swift
synth.reverb = Reverb(.hall, mix: 0.3)      // still works
synth.delay = Delay(time: 0.25)
```

`delay` and `reverb` are views over the chain. Reading gives the first of that kind, and setting replaces it **where it already is** or appends it. So a sketch that only wants one echo and one room never has to think about a chain. One that does can reach past them.

#### Delay

```swift
Delay(time: 0.25, feedback: 0.4, mix: 0.3, damping: 6000)
```

| Setting | What it does |
|---|---|
| `time` | seconds before the first repeat |
| `feedback` | how much of each repeat feeds the next, `0...0.95`. Higher runs longer |
| `mix` | how much of the result is the echo rather than the sound, `0...1` |
| `damping` | where the repeats start losing their top, in Hz. Lower makes each repeat duller than the last, the way a real one is |

#### Reverb

```swift
Reverb(.hall, mix: 0.3)
```

`.room`, `.hall`, `.plate`, `.cathedral`, biggest last, and `mix` is how much of the result is the room.

#### Equalizer

```swift
Equalizer(low: -6, high: 3)                 // thinner and brighter
Equalizer.lowCut(below: 300)                // when a sound is muddy
```

There are three controls. Two are the bottom and the top. The third goes wherever the problem is. Gains are in decibels, so zero is untouched. A few decibels is a great deal more than it sounds like written down. Presets: `.warm`, `.bright`, `.scooped`.

#### Distortion

```swift
Distortion(.softClip, drive: -6, mix: 0.3)
```

`.softClip` is warmth rather than damage. `.overdrive`, `.bitCrush`, `.ring` and `.squeeze` get progressively less polite. `drive` is how hard it is pushed in, in decibels, and `mix` dials the whole thing back to nothing.

#### What it costs to change one

Changing a **setting** costs nothing. The chain is the same wiring, and only the numbers move. Changing **which effects are in the chain** rewires it. That is done on the running engine rather than around a stop. Measured on this wiring, reconnecting while it runs costs nothing audible, and stopping costs the same.

The chain reaches an [export](#sound-in-an-export) as well, built the same way from the same list. An export that ran a different set of effects from the one the sketch was heard through would be a different piece.

---

### What is not here yet

Said plainly, so you can plan around it rather than go looking:

- **One instrument, one sound at a time.** A `Synth` plays one `voice`. Several sounds at once means several `Synth`s, which is fine and cheap.
- **A patch is oscillators, not a whole modular rack.** Operators push each other and mix. There is no filter, envelope, or effect inside a patch. Those are the `Voice` around it, one per voice rather than one per operator.
- **The chain is on the instrument, not on a note.** Every note a `Synth` plays goes through the same effects. Two different treatments means two `Synth`s.
- **No effect of your own.** The chain holds the four kinds above. There is no seam for a filter you wrote yourself, the way [`Shader`](../Shaders/Shaders.md) is that seam for drawing.
- **No sequencer.** Notes are asked for from `draw()`, on whatever clock the sketch keeps. [`Composition`](./Composition.md) is what decides which notes and when. [`TempoClock`](../Integration/MIDI.md) is the way to run on someone else's clock.
- **A sampler, but not a sample editor.** [Recordings](#sampled-instruments) are read and played. Nothing here trims, loops by ear, or lays out a map for you. The map is the `.sfz`.
- **One recording at a time per note.** There is no crossfading between velocity layers, or between neighboring recordings. A change of layer is a step rather than a fade.
- **No jet-driven tube.** The blown tube is reed-driven. A flute is a jet of air splitting across an edge, which is a different excitation and is not here.
- **One drive per instrument.** Every note a `Synth` is playing is bowed or blown by the same hand, which is usually what you want. Two independently driven lines means two `Synth`s.
- **One position per instrument.** A `Synth` is placed as a whole. Several sounds in several places means several `Synth`s, which is fine and cheap.
- **No sound in a GIF.** The format has no way to hold any.

---

<sup>[Audio](./Audio.md) covers the listening side. [MIDI](../Integration/MIDI.md) covers playing from a keyboard and running on an external clock.</sup>
