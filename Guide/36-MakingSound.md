#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 36</sup>

---

# 36. Making sound

<!-- Hook image: the finished sketch, drawn outlines and strings struck, plucked, and bowed with the mouse, through an effects chain and a drawn room. Waiting on the finished sketch and its render. -->

This chapter gives a sketch a voice of its own. It starts with one note and builds everything a note is made of: an instrument patched from oscillators, envelopes, and filters, the effects that move a sound, hold it, or take it apart, a room you can draw, an instrument somebody recorded, wavetables and grains, the physical models that work a note out from a plucked string, a struck shape, a bow, or a breath, and a note bent under the finger. Which notes a sketch plays, and when, is [Chapter 37](37-MusicByRule.md). Nothing here needs a microphone, a controller, or a file. Run it and you will hear it.

## A sketch that plays

[Chapter 34](34-Listening.md)'s `Tone` sounds one note forever, which is enough to feed an analyzer and not much else. When you want the sketch to actually play something, the instrument is `Synth`, and asking it for a note is one line:

```swift
let synth = Synth(.pluck)

override func mousePressed() {
    synth.play("C4", for: 0.4)
}
```

Nothing was started. The first note starts the engine, because forgetting to is otherwise the most common way to end up staring at a silent sketch. Pitches are written however you already think of them. `"C4"` is a name, `60` a MIDI number, and `60.5` the quarter tone between the keys. And `for:` is how long to hold it, so the note ends without being told to again.

Notes that outlive one call are the other half, which is what a held key wants:

```swift
synth.noteOn("C4")     // sounds until told otherwise
synth.noteOff("C4")
```

A `Synth` plays several notes at once, sixteen by default, so chords and overlapping tails work without any bookkeeping from you. When they run out, the next note takes one from whatever is already fading, rather than from anything you are still holding. A melody over a held chord takes its voices from its own earlier notes.

**What a note is made of** is a `Voice`, and the presets are the quick way in: `.pluck`, `.bass`, `.pad`, `.bell`, `.stab`, `.breath`, `.sine`. Assigning a new one leaves sounding notes alone, so you can change instrument between notes:

```swift
synth.voice = .bell
```

Inside a voice, the part worth understanding first is the envelope. It is what makes a bell a bell and an organ an organ, using the same wave underneath.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/Voices-dark.jpg">
  <img src="Images/36-MakingSound/Voices.jpg" alt="Four envelope curves drawn over three seconds with the key let go at 1.4 seconds: a labeled one showing attack rising, decay falling to a held sustain level, and release falling away, then percussive spiking and vanishing at once, organ holding flat until it is let go, and swell rising and falling slowly" width="680">
</picture>

Four numbers, and only three of them are times. `attack` is how long the note takes to arrive, and `decay` how long it takes to settle. `release` is how long it takes to go once let go. `sustain` is the odd one out. It is the *level* the note rests at while held, not a duration. Set it to zero and holding the key adds nothing at all, which is exactly what struck things do. That is why `.percussive` sounds like a drum however long you lean on it.

You can draw the shape you designed, which is what the figure above does:

```swift
Envelope.swell.level(at: 0.7, heldFor: 1.4)   // where a note has got to
```

The other half of a voice is the `filter`, and it is most of what people mean when they say something sounds like a synthesizer. A note that is bright when struck and darkens as it fades is not the wave changing. It is a filter closing over it. `Voice.Filter.sweep(from:by:)` is that gesture, and `.pluck` is built from it.

Finally, a `Synth` is an `AudioSource` like the microphone is, so every read in [Chapter 34](34-Listening.md) works on the sketch's own playing:

```swift
drawCircle(width / 2, height / 2, 100 + Double(synth.amplitude) * 900)
```

That closes the loop the last chapter opened. A sketch that listens to the room can listen to itself instead, and then the picture and the sound are the same decision made once. The `Audio/Synth` example is a playable keyboard doing exactly that.

## Building an instrument instead of choosing one

A `Voice` is a fixed chain. Something makes a wave, an envelope shapes it, and a filter takes part of it away. Every preset so far is that chain with different numbers in it. The tier underneath is where the wiring itself is the value.

```swift
let bell = Patch.tone(.sine)
    .modulated(by: .tone(.sine, ratio: 3.5), amount: 4)

synth.voice = Voice(patch: bell, envelope: .percussive)
```

This is the same relationship the drawing side has had since [Chapter 1](01-HelloOllin.md). `drawCircle` sits on a `Drawer` that can do more, and the voice presets sit on this. Nothing about `Synth(.pluck)` changes because it exists.

An **operator** is one oscillator with a frequency, a level, and possibly something pushing it. Its frequency is a *ratio of the note* rather than a pitch, so a patch is an instrument and not a chord. Ratio 1 is the note, 2 the octave above, and 3.5 something that is not a note at all.

The reason to bother is one sentence. **A filter can only take harmonics away, and a sine has none to take.** Modulation puts them in. Turn `index` up on a sine being pushed by another sine and it becomes brass, and no amount of filtering would have got you there. Move the ratio off a whole number and it becomes metal. Its tones no longer land on the note's own harmonics, so they belong to no pitch in particular. That is the whole of why `.bell` uses 3.5.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/Modulation-dark.jpg">
  <img src="Images/36-MakingSound/Modulation.jpg" alt="Four columns, each a wave above the tones it contains: a plain sine with a single bar, the same sine at index 2 and index 6 growing a run of harmonics, and one at ratio 3.5 whose bars land between the harmonics instead of on them" width="680">
</picture>

The picture is that sentence measured. Each column is the arithmetic one operator pushing another does, with the wave on top and, below it, how much of the wave sits at each multiple of half the note. The plain sine has one bar and nothing else to take. Turn the index up and a run of harmonics grows out of it. Move the ratio to 3.5 and the bars stop landing on the note's own harmonics and fall between them, which is the difference between a tone and a clang.

`Examples/Audio/Patching` puts both parameters under your hand with the graph drawn as it is wired.

There is a constraint worth knowing about, because it explains the one number in the API that looks arbitrary. A patch travels to the audio thread inside a note, through a queue of slots that already exist. It has to be something copyable a word at a time, with no arrays, no references, and nothing to allocate. So the operators live in fixed lanes and there are eight. A patch that would need more comes back unchanged and says so, rather than quietly dropping one. A patch with a piece missing is a different instrument, and finding that out by ear is worse than reading it in the log.

### And the rest of the instrument

A patch says what the sound is made of. What happens to it afterwards is a chain, written the same way:

```swift
synth.effects = [
    .distortion(Distortion(.softClip, mix: 0.3)),
    .delay(Delay(time: 0.28, feedback: 0.5)),
    .reverb(Reverb(.hall, mix: 0.4)),
]
```

Order is the point, and it is the reason this is a list and not a pair of switches. An echo of a distorted sound and a distorted echo are different things: one repeats something dirty, the other dirties the repeats. Swap those two lines and you can hear which you have.

`synth.reverb = Reverb(.hall)` still works, and now means "put one room in the chain, or replace the one that is already there". Most sketches never need more than that, and the ones that do are not stuck with two slots.

Changing a setting costs nothing. Changing which effects are in the chain rewires it, and that happens on the running engine rather than around a stop. Measured on this wiring, reconnecting while it plays costs nothing you can hear.

### An effect nobody wrote for you

The built-in kinds in the chain are the classics. The last is a closure, and you write it:

```swift
synth.effects = [
    .custom("fold") { sound in
        for i in 0..<sound.frameCount {
            sound.left[i] = sin(sound.left[i] * 4)
            sound.right[i] = sin(sound.right[i] * 4)
        }
    },
    .reverb(Reverb(.hall, mix: 0.3)),
]
```

The closure is handed each block of samples on its way to the speakers and rewrites them in place. That is all an audio effect is. This one is a wavefolder: push a sample past the top and it comes back down. That fills a plain tone with harmonics no filter could put there. `sound.left` and `sound.right` are the two channels, `sound.sampleRate` is what a frequency means, and `sound.time` is a clock for anything that moves. It sits anywhere in the chain, so the reverb above hears the folded sound. It reaches an export like every other link.

An effect that has to remember something between blocks takes its memory as `state:` and gets it back on every block. That is how a filter, an envelope follower, or an echo of your own carries itself from one block to the next. The closure runs on the audio thread with the speakers waiting. Keep it to arithmetic over the samples: no allocating, no locking, no reaching back into the sketch. `state:` exists because the thread rule also means the closure cannot write into a captured variable.

`Examples/Audio/Shaping` is three of these behind one parameter: a wavefolder, a crush that remembers each held sample in `state:`, and a wobble that breathes on `sound.time`. The sound going in is drawn dim, and the sound coming out bright.

### A room you can draw

The reverb in that chain is one of four rooms somebody else built. Here is what a room is, so you can bring your own.

Clap once in a stairwell. What comes back is the stairwell: every surface and every distance, all at once, in the order the sound reached them. Record that and you have the room written down, as its answer to a single click. Play an instrument through the recording and it is heard in the stairwell. Every sample of the sound starts its own copy of the click's answer, and the answers add up. That is a convolution, and a reverb built this way is a convolution reverb.

```swift
let stairwell = try ImpulseResponse.resource("stairwell", withExtension: "wav", in: .module)
synth.reverb = Reverb(stairwell, mix: 0.4)
```

The room does not have to be real. A room is a rule over time, so you can draw one the way you draw anything else:

```swift
let hall = ImpulseResponse.decay(seconds: 3, damping: 0.6)                     // fading noise
let backward = hall.reversed()                                                // swelling toward the click
let humming = ImpulseResponse(seconds: 2) { t, _ in exp(-3 * t) * sin(.tau * 220 * t) }
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/Rooms-dark.jpg">
  <img src="Images/36-MakingSound/Rooms.jpg" alt="Three rooms drawn as their answer to a click: fading noise three seconds long, the same noise run backward so it swells to the end, and a dropped ball whose bursts arrive closer and closer together" width="680">
</picture>

Fading noise is the plainest room there is. Real rooms lose their top end first, which is what `damping` does. Run the same noise backward and the room swells toward the click instead of fading from it, a sound records have used for sixty years. The third room in the picture is a dropped ball: a burst on every bounce, the gaps closing by a fixed ratio. A rule that ignores the noise it is handed gives a resonator instead. That is a room that hums at one pitch, and it tunes everything you play into it.

Every room is brought to the same level on the way in, so `mix` means one thing whether the recording was quiet or loud. Turn `mix` on a room that is sounding and the tail keeps going. Change the room itself, or its `preDelay`, and a fresh one starts. `Examples/Audio/Rooms` draws five rooms from rules and plays through each, with the room's answer to a click drawn above the instrument's trace.

### Something that moves: chorus, flanger, phaser, tremolo

The effects so far leave a sound where it is. Four more move it. Each is one slow wave and the thing it moves, and the wave's `rate` and `depth` are the two settings they all share.

```swift
synth.effects = [.chorus(Chorus(rate: 0.8, depth: 0.5))]
synth.effects = [.flanger(Flanger(rate: 0.25, depth: 0.7, feedback: 0.5))]
synth.effects = [.phaser(Phaser(rate: 0.4, stages: 4))]
synth.effects = [.tremolo(Tremolo(rate: 5, depth: 0.6))]
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/Movement-dark.jpg">
  <img src="Images/36-MakingSound/Movement.jpg" alt="Four panels: a tremolo's level breathing over a tone, a chorus's copy sliding later and earlier around twenty milliseconds, a flanger's comb of notches through the spectrum, and a phaser's two notches swept up the spectrum" width="680">
</picture>

A **tremolo** moves the level. It rises and falls with the wave, from full down to whatever `depth` leaves, and nothing else changes. It is the plainest of the four and the one a guitar amplifier had a knob for. Set `spread` to 1 and the two sides breathe in opposite turns, so the sound swings from side to side.

A **chorus** moves a copy of the sound. The copy sits about twenty milliseconds behind, and the wave slides it later and earlier. A copy that is always sliding is never quite in tune with the original, and two voices that can never agree read as several. That is the whole trick, and the name. The two sides slide a quarter turn apart, which is why a chorus is wide by itself.

A **flanger** is the same copy brought in close, a millisecond or so behind. That close, you no longer hear a second voice. The copy and the original cancel at every frequency where the gap is half a wavelength, which cuts a comb of notches through the spectrum. The wave sweeps the gap, so the comb sweeps, and that is the jet-plane whoosh every record has used. `feedback` sends the copy back to be copied again, which sharpens the teeth. Make it negative and the comb turns inside out.

A **phaser** makes fewer notches, and makes them differently. The sound goes through a row of stages that each turn its phase without touching its level. Added back to the original, the turned parts cancel at one frequency for every two stages. The wave sweeps those notches up and down the spectrum. Four stages give two notches, which is the usual count, and the result is the softer swirl of the four.

None of them invents a sound. Each is the sound and a copy of itself, or the sound and a wave, so a `mix` of 0 is the plain sound exactly. Turn a setting while the sound plays and the motion carries on from where it was. [`Examples/Audio/Movement`](../Examples/Audio/Movement/Sketch.swift) plays one phrase through each of the four, every setting on a parameter, with the wave drawn over the trace.

### Something that holds a level: compressor, limiter, gate

Those four move a sound. Three more watch how loud it is and act on that.

```swift
synth.effects = [.compressor(Compressor(threshold: -18, ratio: 4, makeupGain: 6))]
synth.effects = [.gate(Gate(threshold: -40, hold: 0.08)), .limiter(Limiter())]
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/Levels-dark.jpg">
  <img src="Images/36-MakingSound/Levels.jpg" alt="Three panels: the curve a compressor puts between the level coming in and the level leaving, with a threshold, two ratios, a knee and a ceiling; a level stepping up and the gain reduction answering it over an attack and a release; and a note decaying through a gate's threshold, held open by the hold and chopped without it" width="680">
</picture>

Every threshold here is in decibels below full scale, where 0 is as loud as a sample can be. It is a scale worth getting used to: a level you would mix at sits somewhere under -12, and a difference of 6 is a halving.

A **compressor** works on what is over its `threshold`. A `ratio` of 4 means four decibels over the line arrive as one. The first panel is the whole of it: below the threshold nothing happens, above it the curve tilts. What that buys is not a quieter sound but a narrower one, which is why `makeupGain` matters, since it brings the whole thing back up with the loud parts still held. A `knee` bends the corner, so the holding starts before the threshold rather than at it, and that is most of what makes a compressor hard to hear working.

`attack` and `release` are the other half, and the second panel is them: how long the holding takes to come on, and how long it takes to let go. A fast attack catches the very front of a note, which is where a plucked or struck sound has most of its level. A slow release keeps holding through the notes after the loud one, so the whole phrase breathes together. Neither is right; they are the difference between a phrase that keeps its shape and one that pumps.

A **limiter** is a promise rather than a shape. Nothing leaves above its `ceiling`, whatever arrives. It gets there by turning the level down the instant a peak asks for it, so a single loud note ducks the sound around it for a `release` rather than tearing. It belongs last in a chain, after a distortion or anything else that can hand it more than it bargained for.

A **gate** works on what is under its threshold, and turns it down by `depth`. That takes hiss, hum, and room out of the gaps between notes. The catch is a decaying note, which passes under the threshold long before it is finished, and `hold` is the answer: how long the gate stays open after the level drops. The third panel is a note with the hold and without it, and the one without is missing its tail.

The level is read from both sides at once, so a loud note on one side pulls the other down with it and the sound stays where you put it. Turn a setting while it plays and the gain carries on from where it is. One thing is not here: a key from somewhere else, the trick where one sound ducks another, needs a detector on one instrument listening to a different one, and each `Synth` runs its own engine. [`Examples/Audio/Levels`](../Examples/Audio/Levels/Sketch.swift) plays a phrase with accents in it through each of the three, with the threshold drawn across the meter so you can watch the accents meet it.

### Something that takes the sound apart: pitch shift, freeze, stretch

Every effect so far worked on the sound as a wave. These take it apart first.

```swift
synth.effects = [.pitchShift(PitchShift(semitones: 7, mix: 0.5))]
synth.effects = [.freeze(Freeze(amount: mouseIsPressed ? 1 : 0))]
let bar = SampledInstrument.builtIn!
let slow = bar.recording(at: 0, over: 0...127).stretched(by: 4)
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/Spectral-dark.jpg">
  <img src="Images/36-MakingSound/Spectral.jpg" alt="Three panels: the partials of a note as bars on a frequency axis, with the same bars a fifth higher drawn over them; four partials fading over time until a line, and holding flat from the line to the edge; and the outline of a struck recording with the same recording drawn three times as long under it, on one time axis" width="680">
</picture>

The sound is read in frames of about forty milliseconds. Each frame is taken apart into the partials in it, every one with a level and an exact frequency, and put back together with those partials moved or held. That is a phase vocoder, and the taking apart is what buys three things a wave cannot do.

A **pitch shift** moves the pitch and leaves the length. That sounds small until you remember the sampler: a recording played an octave down lasts twice as long, because pitch and length are one control on a tape. Here they are two. A chord a fifth up still ends when it ended. With `mix` under 1 the original plays under the moved copy, which is a harmonizer, and the first panel is that: the partials of a note, and the same partials a fifth higher over them.

A **freeze** holds an instant. The moment `amount` rises above 0, the spectrum of whatever is sounding is caught, and from then on that instant plays for as long as the amount stays up. A struck chord becomes a pad. The second panel is a note fading until the freeze, and then not fading at all. The amount is also the blend, so a freeze can be eased in rather than switched, and back at 0 the instant is let go.

A **stretch** is the same idea done once to a recording rather than live. `stretched(by: 4)` gives a recording four times as long at the same pitch, which the sampler then plays like any other. It changes the length, so it is a thing done in `setup()` rather than a link in the chain. The third panel is a struck recording and the same recording stretched, on one time axis.

Two honest limits. Each of these arrives a frame late, about forty milliseconds, which you will not notice on a phrase and might on a drum. And a pitch shift moves the whole spectrum, so a voice an octave up is a small voice rather than a high one. [`Examples/Audio/Spectral`](../Examples/Audio/Spectral/Sketch.swift) is all three behind a parameter, with the freeze on the mouse.

## An instrument somebody recorded

Everything in this chapter so far is worked out as it goes. The other way round is to start from a recording.

```swift
synth.instrument = SampledInstrument.builtIn
synth.voice = Voice(sampled: Sampler(), envelope: .plucked)
synth.play("C4", for: 1.5)
```

Ollin bundles one small instrument so you can hear this without downloading anything: a struck bar recorded at five pitches. Playing a note means finding the nearest recording and moving it.

Moving it is the whole model, and it is also the whole limitation. A recording plays at another pitch by being read faster or slower, which moves its pitch and its length *together*, exactly as a tape does. Move it far enough and the instrument audibly changes size. High notes go thin and hurried, and low ones slow and heavy. `Examples/Audio/Sampler` has a key that swaps five recordings for one stretched over everything, and the difference is not subtle. That is why real libraries ship hundreds of recordings rather than one, and why the nearest is always chosen.

There is a design detail here worth noticing, because it is the same constraint from a page ago wearing a different hat. The recordings are set on the **synth**, not inside the `Voice`:

```swift
synth.instrument = piano          // which recordings
synth.voice = Voice(sampled: ...) // how to play them
```

A `Voice` travels to the audio thread inside a note and has to be copyable a word at a time. That is why a struck body caps at sixteen tones and a patch at eight operators. Recordings are megabytes on the heap and cannot ride along at all. So they stay put and the note carries only a handful of numbers. The constraint did not go away. It decided the shape of the API.

To load a real instrument, the format is **SFZ**. It is a text file listing which audio file answers which notes, with the audio beside it.

```swift
let piano = try SampledInstrument(sfz: "Piano.sfz", in: .module)
```

Where to find them, and the licenses, are on the [Synthesis](../Docs/Helpers/Synthesis.md#where-to-find-instruments) page. Here is the short version. [VCSL](https://github.com/sgossner/VCSL) and [VSCO 2 Community Edition](https://versilian-studios.com/vsco-community/) are CC0, so you can do anything with them, including ship them. [Freesound](https://freesound.org/) is per-clip and mixes CC0 with non-commercial, so check each one. The [Philharmonia](https://philharmonia.co.uk/resources/sound-samples/) samples are free to make music with, but explicitly not free to pass on as a sampler instrument. That distinction is worth reading before you build something on them.

## A wave you can draw: wavetables

An oscillator traces one shape. A patch pushes a few shapes into each other. A wavetable is the plain third way: several cycles side by side, any shapes at all, and a note reads the blend of the two its position lands between.

```swift
synth.wavetable = .basic                                     // sine, triangle, sawtooth, square
synth.voice = Voice(wavetable: WavetableScan(position: 0.3))
synth.play("C3", for: 2)
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/WavetableFrames-dark.jpg">
  <img src="Images/36-MakingSound/WavetableFrames.jpg" alt="Four cycles stacked up the page, sine to square, with a colored cycle drawn between the triangle and the sawtooth where a position of 0.4 reads, and below it the sawtooth frame three times, with every harmonic, with sixteen, and with four, the corner softening each time" width="680">
</picture>

The top of that picture is the whole idea. The position runs up the stack, and the colored cycle is what a note at 0.4 reads: mostly triangle, a little sawtooth. Move the position and the wave changes shape. That is the part an envelope and a filter cannot do, and it is what makes a held note travel:

```swift
synth.voice = .morph     // struck to the square end, settling back toward the sine
```

A `WavetableScan` carries the position, and a `sweep` with its own envelope moves it over the note. `morph` starts at the first frame, jumps to the last as the note strikes, and slides most of the way back while it sounds. Give the sweep a slow attack instead and a note opens up as it is held. `Examples/Audio/Wavetable` puts the position under the pointer and the sweep on a parameter, with the frames stacked on screen and the cycle the next note reads drawn over them.

The table is set on the synth, not inside the voice, for the reason you met a page ago. A voice has to be copyable a word at a time, and a table is hundreds of kilobytes. Three are built in. `.basic` is the four plain shapes, `.pulse` a square narrowing to a spike, and `.vowels` five mouth shapes a note sings through. Making your own is one line:

```swift
synth.wavetable = Wavetable(name: "bend", frameCount: 8) { phase, frame in
    sin(.tau * pow(phase, 1 + 2 * frame))         // a sine bent harder in every frame
}
```

The bottom of the picture is the quiet part of the design. A sawtooth has a corner, and a corner holds harmonics past any sampling limit. Read it fast enough and those fold back down as a gritty ring that gets *worse* as the note goes up. So every frame is kept at eleven strengths, each with half the harmonics of the one before, and a note reads the strongest one whose top harmonic still fits under half the sample rate. The three panels are the same sawtooth as a low, a middle, and a high note read it. The corner softens and the note stays clean. Every strength is built from the same harmonics, so nothing shifts when a note moves from one to the next.

## A sound in pieces: grains

Every instrument so far reads a sound from one end to the other. A sampler does it most plainly: play a recording a note higher and it comes out shorter, because moving faster through it moves both. Pitch and time are one number.

A grain is how they come apart. Cut a few thousandths of a second out of a sound and put an envelope on it so it does not click at either end. What you have is too short to carry a pitch of its own. Pile hundreds of those up a second and what you hear is the statistics of the pile. Now there are two clocks instead of one. The grains are read at whatever speed the note asks for. The place they are cut from travels at its own `speed`.

```swift
synth.grainSource = GrainSource(recording: SampledInstrument.builtIn!.recording(at: 2, over: 0...127))
synth.voice = Voice(granular: GrainCloud(size: 0.08, density: 40, speed: 0))
synth.play("C4", for: 8)
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/GrainClouds-dark.jpg">
  <img src="Images/36-MakingSound/GrainClouds.jpg" alt="Three panels of dots, time across and place in the sound up: at speed 1 the dots run diagonally, at 0.25 they climb slowly, at 0 they lie flat; below them the six envelope shapes a grain is cut with" width="680">
</picture>

Time runs across each panel and where in the sound a grain was cut from runs up it. At `speed: 1` the dots run diagonally, which is just a recording playing. At 0.25 the same sound is crawled through at a quarter of the speed, and nothing has moved in pitch. At 0 they lie flat: the reading has stopped and the note has not. That last one is the sound nothing else in this chapter can make, one moment of a recording held for as long as you like.

And you can pull it about while it sounds:

```swift
override func draw() {
    synth.grainScrub = mouseX / width         // drag the reading through the sound
}
```

That reaches notes that are already playing, the way `pressure` does, because it is read every sample rather than once at the start. Everything else about a cloud is read when the note begins.

The rest of a `GrainCloud` is how the pile is made. `size` is how long one grain lasts. Under about 10 ms a grain carries no pitch and the cloud is pure texture. Over about 100 ms each one is heard as a recognizable fragment. `density` is how many start each second. `positionJitter` is how far each one strays from the reading. A little of it stops a dense cloud sounding like one sound played very loudly. `pitchSpread` scatters the grains either side of the note, so an octave of it makes the cloud a chord of itself. `panSpread` throws them across the stereo picture, which is most of why a cloud sounds like a space rather than a point.

Two of the numbers have a catch in them.

**Loudness goes up with the square root of the density, not with the density.** Grains land on each other at random times, so what adds up is power rather than amplitude. Four times as many grains is twice as loud. That is not a quirk of this implementation; it is what independent things do.

**`scatter` at 0 gives you a pitch you did not ask for.** With no scatter the grains arrive on a strict clock. If the reading is frozen they all repeat the same piece of sound, so the output is exactly periodic at `density` hertz, whatever the sound was. Set `density` to 220 and you hear an A, made out of a recording of something else. It is a real instrument rather than a fault, and turning `scatter` back up is how you stop hearing it.

The bottom row of the picture is the shape each grain is cut with, and at these lengths it is most of the character. `.bell` adds nothing and is the one to reach for. `.plateau` is flat in the middle, so the middle of the grain is the sound exactly as it was recorded. Reach for it when the cloud should sound like the source rather than like grains. `.tick` is sharp at the front and gone, so a cloud of them is a rattle. `shape.level(at:)` hands the curve back, so you can draw the cut you chose.

Three presets come ready to play with before you build your own. `Voice.cloud` is a held moment spread wide, `Voice.smear` is the sound crawling past in pieces, and `Voice.rain` is short sharp grains one at a time. `Examples/Audio/Grains` draws the sound with the band the grains come from lit over it and lets you drag that band through by hand.

The sound goes on the synth and the cut goes in the voice, for the reason you have now met three times. A voice travels to the audio thread inside a note; a few seconds of sound does not fit in one.

## A string, worked out rather than drawn: the plucked string

Every voice so far starts with a wave, a shape an oscillator traces over and over. You then carve it with an envelope and a filter until it sounds like something. That works, and it is what most synthesizers are. But it is a description of a result, and there is another way in.

```swift
let synth = Synth(.steel)
synth.play("E3", for: 3)
```

That is a string. Not a recording of one, and not a wave shaped to resemble one. It is a length of something under tension, with a disturbance running up and down it, worked out sample by sample as it goes.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/PluckedString-dark.jpg">
  <img src="Images/36-MakingSound/PluckedString.jpg" alt="A block diagram of a delay line whose output loses its top, is tuned, and is fed back round at slightly lower level, and below it four plucks of the same string at different points, each with the shape it leaves and a bar chart of the modes that pluck excites, showing the missing ones as gaps" width="680">
</picture>

The top of that picture is the whole model. A delay line one period long is the disturbance traveling. A filter in the loop is what the string loses at each end, taking more off the top than the bottom. And a little less comes back each time round than went out. Feed a burst of noise into it and it turns into a note by itself.

What makes this worth the trouble is what you get without asking. The note attacks like a string because that is what a disturbance settling into a loop does. It darkens as it rings, because the top is lost faster than the bottom, so a long note changes color with nothing moving. And it responds to *where you pluck it*:

```swift
var string = PluckedString.steel
string.position = 0.5          // halfway along
synth.voice = Voice(plucked: string)
```

The lower half of the picture is why. A string held at a point cannot move there, so every mode with a node under your finger gets nothing. Pluck halfway along and every even mode is missing, which is the hollow tone in the top row's gaps. Pluck near the end and they are all there, thinly, which is the nasal sound of a guitar played by the bridge. The shape on the left and the bars on the right are the same fact drawn twice.

`Examples/Audio/Strings` is six strings you click on, wherever you want to pluck them, and the shape it draws on each one is those same modes.

Three more things are worth knowing. `hardness` is how quickly you let go, which decides how much of the string you set moving. `decay` is how long the note rings, and `damping` is how much sooner the bright part goes than the low part. And a string decides its own fade, so the envelope's job is to stay out of the way. Ask for a note long enough to let it finish, or the release will cut it off mid-ring.

The tuning is the part you would never think to check and would certainly hear. A loop has to come out exactly one period long, and a whole number of samples cannot do that. At the bottom of the keyboard the rounding error hides in a loop hundreds of samples long. At the top, where a period is ten samples, rounding is out by most of a semitone. So the fraction left over is handled by a filter that supplies a fraction of a sample. The loop filter's own delay is counted into the same budget, which is why turning `damping` up cannot pull the note flat.

## A shape you can hit: modal synthesis

A string is one length of one thing, and its model is one loop. Something struck is different. Hit a plate or a bell or a sheet of glass and it does not make a wave at all. It makes a handful of pure tones at once, each fading at its own rate.

Which tones is the interesting part, because it is decided by the object's shape and by nothing else.

```swift
let synth = Synth(.chime)
synth.play("C4", for: 4)
```

That is a bell, from a list of ratios a bell founder would recognize, and `.drum`, `.bar`, `.wood`, and `.glass` are beside it. But a list is not the point. The point is that the list can come from an outline you drew:

```swift
let outline = textToShapes("O").first!
let bell = StruckShape(outline)                 // once, in setup()

override func mousePressed() {
    synth.voice = Voice(struck: bell!.body(struckAt: Vector2(mouseX, mouseY)))
    synth.play("C4", for: 3)
}
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/StruckShapes-dark.jpg">
  <img src="Images/36-MakingSound/StruckShapes.jpg" alt="Five outlines, each with the frequencies it rings at drawn on a scale from one to four: a circle, a square, a triangle, an oblong, and an irregular blob, where the symmetric ones show pairs of lines sitting together and the asymmetric ones show single lines" width="680">
</picture>

Nothing in that picture was chosen. Each row is the outline beside it, measured. The circle's ratios are the zeros of the Bessel functions, which is what a real drumhead rings at. They run 1, 1.59, 2.13, and 2.30 in turn. The square comes back at 1, 1.58, 2, 2.24, which is what a real square membrane rings at. The blob comes back at whatever a blob rings at, and nobody has a name for that.

The reason it works is simple. A flat thing held at its edge can only vibrate in the shapes that fit inside its outline, with nothing moving at the rim. Ask which those are and you have asked an eigenvalue problem, and the frequencies are the square roots of its answers. Ollin measures the outline onto a grid and solves it.

Look again at the pairs. The circle, the square, and the triangle each show most of their lines doubled up, and the blob shows none. That is symmetry. A pattern that fits a circle at one rotation fits it at another. So there are two of them, and they ring at the same frequency. An outline with no symmetry has nothing to double. A real drum does this too, and a real drum is never quite round. Its pairs sit fractionally apart and beat against each other, which is part of why a drum sounds alive.

Two practical things. **Measuring is the expensive part and striking is free**, so measure in `setup()` and keep the `StruckShape`. And **where you hit it decides which tones answer**. A tone that holds still under your finger gets nothing, which is the pick position again in a different costume. Hit a circle exactly in the middle and most of its tones stay silent. Most of them have a line of stillness straight through the center.

`Examples/Audio/StruckShapes` is six of these you can click, and the bars under each one move as you move where you hit it.

## A note you keep playing: bowed and blown

The string and the shape have something in common that is easy to miss. Both are set going once. You pluck, or you strike, and the whole note is decided at that instant. Everything after is the thing fading.

A bow is not like that, and neither is a breath. They keep happening, so the note has a middle, and the middle is yours.

```swift
let synth = Synth(.cello)
synth.noteOn("G2")

override func draw() {
    synth.pressure = 0.3 + 0.5 * abs(sin(time * 2))   // still playing it
}
```

`pressure` is how fast the bow is being drawn, or how hard the tube is being blown. It is read every sample, so moving it moves the note that is already sounding. At zero there is nothing to hear, because nothing is being done. This is the one thing an envelope cannot give you. An envelope is decided when the note starts, and this is whatever you are doing right now.

Two things fall out of the models rather than being settings. Both are the kind of detail that tells you a model is doing its job.

**Bow too fast for the force and the note breaks.** The string tears loose from the rosin twice per cycle instead of once, and it jumps to the octave. That is exactly what over-bowing sounds like on a real instrument, and nothing in the code puts it there. It is what the friction curve does when you push past it. Press harder or draw slower and it settles back.

**The clarinet has no even harmonics.** Nothing filters them out. The tube is stopped at the reed and open at the far end, so it fits a quarter of a wave rather than a half. A tube like that supports the odd harmonics and not the even ones, which is why it sounds hollow and woody. It also plays an octave and a fifth below an open tube of the same length, instead of an octave below. The whole of that is one line deciding the loop is half a period long rather than a whole one.

`Examples/Audio/Bowing` is both of them under the mouse. Hold to play, move up and down to lean on it, and press `B` to swap the bow for a reed.

## A note under the finger: expression

A keyboard's wheel bends every note at once. A finger on a polyphonic-expression surface, a Seaboard or a LinnStrument, bends one note, presses it, and slides along its key. The notes beside it are left alone. That is the whole of MIDI Polyphonic Expression, and it is a good way to think about a note whoever is playing it.

`noteOn` hands the note back. Hold on to it, and the note can be told three things while it sounds.

```swift
let synth = Synth(.pad)
var note: PlayingNote?

override func mousePressed() { note = synth.noteOn("C4") }
override func mouseReleased() { if let note { synth.noteOff(note) } }

override func draw() {
    guard let note else { return }
    synth.bend(note, semitones: (mouseX / width - 0.5) * 4)   // across the window, two semitones each way
    synth.slide(note, 1 - mouseY / height)                    // up opens the filter
    synth.press(note, 0.8)
}
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/36-MakingSound/Expression-dark.jpg">
  <img src="Images/36-MakingSound/Expression.jpg" alt="Three panels: two notes on a time axis, one rising by a fifth and falling back while the other holds a straight line; a level rising from a struck level toward full as pressure runs from zero to one, at two slopes; and three lowpass curves on a frequency axis, one an octave below the note's own cutoff, one at it, one an octave above" width="680">
</picture>

`bend` moves the pitch, and every source follows it. The string is cut to a new length while it rings, and the tube too. A recording is read faster, and a wavetable and a patch run faster. The one that holds is the struck body, because its tones were decided by the strike, the way a bell rung cannot be retuned. `press` is the note's own bow or breath on the cello and the clarinet. On everything else it raises the note from the level it was struck at toward full, by the voice's `pressureAmount`. `slide` opens the filter above the middle of the key and closes it below, by the filter's `slideAmount`. Each glides over a few milliseconds, so a value handed over every frame moves the note rather than stepping it.

A controller that speaks this way puts each note on a channel of its own. `MIDIInput` reads it back as `heldNotes`: every held note with its bend, its pressure, and its slide already sorted out. The wiring from there is a dozen lines. Start each note as it appears, let it go as it leaves, and hand each held note its three values every frame.

```swift
let synth = Synth(.pad)
let midi = MIDIInput()
var playing: [Int: PlayingNote] = [:]

override func setup() { try? midi.start() }

override func draw() {
    let held = midi.heldNotes
    for note in held where playing[note.id] == nil {
        playing[note.id] = synth.noteOn(Pitch(Double(note.note)), velocity: note.velocity)
    }
    for (id, note) in playing where !held.contains(where: { $0.id == id }) {
        synth.noteOff(note)
        playing[id] = nil
    }
    for note in held {
        guard let playing = playing[note.id] else { continue }
        synth.bend(playing, semitones: note.pitchBend)
        synth.press(playing, note.pressure)
        synth.slide(playing, note.slide)
    }
}
```

The same read works on a plain keyboard, where the wheel and the aftertouch belong to every note on the channel. The wiring does not care what is plugged in. [`Examples/Audio/Expression`](../Examples/Audio/Expression/Sketch.swift) is a surface the mouse plays through a virtual MIDI source, so a bend from the mouse crosses Core MIDI the way a controller's does. A real controller plugged in joins the same picture. Switch its `bowed` parameter on, and pressure becomes the bow.

<!-- Putting it together: the finished sketch goes here: drawn outlines and strings struck, plucked, and bowed with the mouse, through an effects chain and a drawn room, built from this chapter's steps, with its full listing. -->

## Where this comes from

Frequency modulation as a way of making sound is John Chowning's, worked out at Stanford in the late 1960s and published in 1973. It reached most people as the Yamaha DX7, whose bells and electric pianos are the sound of a decade. The plucked string is Kevin Karplus and Alex Strong's algorithm (1983), a discovery in the literal sense. They were building a wavetable synthesizer, and a bug which averaged the table as it played turned a burst of noise into a plucked string. They worked out afterwards why. David Jaffe and Julius Smith published the extensions the same year, and it is their version, tuned by an allpass and plucked at a position, that Ollin implements.

Playing a sound through a recorded room is convolution, and it was too slow to be useful until Thomas Stockham showed in 1966 that the fast Fourier transform made it cheap. William Gardner worked out in 1995 how to do it with no delay at all, by running the first stretch of the room directly and the rest through the transform, which is the arrangement Ollin uses. Taking a sound apart into its partials and putting it back moved or held is the phase vocoder, James Flanagan and Roger Golden's at Bell Labs in 1966, which Mark Dolson's 1986 tutorial turned from a laboratory tool into something a musician could run. The way Ollin keeps each partial whole while it moves it is Jean Laroche and Mark Dolson's, from 1999.

Hearing a shape has a mathematical name, from Mark Kac's 1966 question "Can one hear the shape of a drum?". It also has an answer. Not always, since two different outlines can ring identically, but you can certainly hear a great deal of it. Working the frequencies out from the outline is modal synthesis. Jean-Marie Adrien set it out for sound, and Kees van den Doel and Dinesh Pai developed it for struck objects.

Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Synthesis](../Docs/Helpers/Synthesis.md): `Synth`, pitches, the `Voice` presets and what is inside one, envelopes, filters, delay and reverb, [a room of your own](../Docs/Helpers/Synthesis.md#a-room-of-your-own), [the four that move](../Docs/Helpers/Synthesis.md#the-four-that-move), and the whole effects chain.
- [Expression](../Docs/Helpers/Synthesis.md#expression): one note bent, pressed, or slid on its own, where each value goes on each source, and [reading a polyphonic-expression controller](../Docs/Integration/MIDI.md#per-note-expression-mpe).
- [The two that work in the spectrum](../Docs/Helpers/Synthesis.md#the-two-that-work-in-the-spectrum): the pitch shift and the freeze, what a frame late means, and [stretching a recording](../Docs/Helpers/Synthesis.md#stretching-a-recording).
- [Patches](../Docs/Helpers/Synthesis.md#patch): what an operator is, the named patches, and why eight.
- [Sampled instruments](../Docs/Helpers/Synthesis.md#sampled-instruments): loading an SFZ instrument, what a recording being moved costs, and where to find instruments you are allowed to ship.
- [Wavetables](../Docs/Helpers/Synthesis.md#wavetables): the built-in tables, making one from harmonics, drawn cycles, or a rule, and why a high note reads a softer copy.
- [Grains](../Docs/Helpers/Synthesis.md#grains): the whole cloud setting by setting, the six shapes, where a sound can come from, and what a strict clock and a full pile do.
- [Physical models](../Docs/Helpers/Synthesis.md#physical-models): all four models, their settings, why the tuning is exact, and how a shape is measured for its modes.
- Appendix B draws the idea this chapter rests on: [Sound as numbers](B-JustEnoughMath.md#sound-as-numbers).
- Worked examples, in [`Examples/Audio/`](../Examples/Audio/): `Synth` (a playable keyboard), `Patching` (the graph drawn as it is wired), `Spectral` (the pitch moved, an instant held, a recording stretched), `Expression` (a surface where each note is bent, pressed, and slid on its own), `Sampler`, `OwnSampler` (an instrument made from your own `.sfz`), `Wavetable` (a row of cycles read by position, the frames stacked on screen), `Strings`, `StruckShapes`, and `Bowing`.

---

[Contents](README.md#contents) · Previous: [Chapter 35, Controls and signals](35-ControlsAndSignals.md) · Next: [Chapter 37, Music by rule](37-MusicByRule.md)
