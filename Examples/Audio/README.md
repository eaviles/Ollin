#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Audio</sup>

---

## Audio

These sketches listen to sound or play it. Audio lives in a separate library, so add `import OllinAudio`.

On the way in, there are three sources: `AudioInput` for the microphone, `AudioPlayer` for files, and `Tone` for an oscillator. Ollin analyzes each one into `amplitude`, a frequency `spectrum`, and band values that a sketch reads in `draw()`. It also recognizes speech and named sounds. On the way out, a `Synth` plays shaped voices through effects, and a composition tier works out what to play. Four physical models cover struck, plucked, bowed, and blown sounds. A sampler plays recordings, and sonification reads data out as notes. You can place sound in the 3D scene, and an export can render its sound into the video.

The references are [Audio](../../Docs/Helpers/Audio.md), [Synthesis](../../Docs/Helpers/Synthesis.md), [Composition](../../Docs/Helpers/Composition.md), [Sonification](../../Docs/Helpers/Sonification.md), and [Listening](../../Docs/Helpers/Listening.md).

| Example | What it shows |
|---|---|
| [Spectrum](Spectrum/Sketch.swift) | a radial ring of normalized `bands` driven by the live microphone, with the central disc flashing on each detected `beat` (clap at it). Until permission is granted, a generated sawtooth `Tone` stands in. It glides in pitch, and the disc pulses on the level. This shows how permission works, because `AudioInput.start()` asks for it and the picture plays either way (`AudioInput`, `Tone`, `bands`, `beat`) |
| [Listening](Listening/Sketch.swift) | the microphone read for *what* it is hearing: a live caption that corrects itself as more is heard, and named sounds (a clap, a knock, music) that appear as marks and fade. Both listeners share one microphone, and recognition runs on the Mac, so it asks for no permission of its own (`SpeechListener`, `SoundClassifier`, `events()`) |
| [FilePlayer](FilePlayer/Sketch.swift) | reacts to a playing audio file: a `bands` bar chart plus a `waveform` oscilloscope, and the whole canvas flashes on each `beat`. By default it loops a bundled clip (*El Fandanguito*, a traditional Mexican son huasteco for violin, CC BY-SA). Pass a path on launch to play your own track instead (`AudioPlayer`, `bands`, `beat`, `waveform`) |
| [ChladniResonance](ChladniResonance/Sketch.swift) | a signal generator sweeping a Chladni plate: a `Tone` glides in pitch, the plate responds, and each mode rings when the sweep passes its own frequency (`magnitude(in:)`) |
| [Synth](Synth/Sketch.swift) | a playable instrument: the home row is two octaves of a scale, a held key sounds until you let go, the number keys change what a note is made of, and space adds a room around it (`Synth`, `noteOn`, `noteOff`) |
| [Shaping](Shaping/Sketch.swift) | an effect written in the sketch itself: each bend is a few lines of arithmetic in a `.custom` link of the chain, and that link sits beside the built-in kinds |
| [Rooms](Rooms/Sketch.swift) | a room of your own around an instrument: five rooms drawn from rules (fading noise at two sizes, the same noise run backward, a resonator, a dropped ball) as an `ImpulseResponse`, played through as a convolution `Reverb`, with the room's answer to a click drawn as a waveform and the instrument's trace under it |
| [Changes](Changes/Sketch.swift) | chords that come out of a key: the progression is written as scale degrees rather than chord names, because the degrees are what survive a change of key (`Chord`, `Scale`) |
| [Generative](Generative/Sketch.swift) | music the sketch works out for itself from four small pieces: each ring is a `Rhythm`, and its strikes spread over the steps as evenly as whole steps allow |
| [Strings](Strings/Sketch.swift) | six strings you pluck wherever you click: each is a delay line one period long with a filtered loop around it, so where you pluck decides the tone (`PluckedString`) |
| [StruckShapes](StruckShapes/Sketch.swift) | shapes you can hit, and they sound like the shape they are: an outline's own standing waves decide the frequencies, and where you strike decides which ones you hear (`StruckShape`) |
| [Bowing](Bowing/Sketch.swift) | a note you keep playing: a bowed string or a blown tube. Both are worked out continuously, so the sound follows the hand for as long as it lasts instead of being decided at its start (`BowedString`, `BlownTube`) |
| [Patching](Patching/Sketch.swift) | an instrument you build rather than pick: a `Patch` is the tier under a fixed voice, where operators are wired into each other (`Patch`) |
| [Sampler](Sampler/Sketch.swift) | an instrument made of recordings: a note finds the nearest recorded one and shifts it, which is the opposite of working the sound out (`SampledInstrument`) |
| [Wavetable](Wavetable/Sketch.swift) | a wave you can draw: a row of cycles that a note reads by position and moves through as it sounds. The frames are drawn stacked, with the cycle the next note reads drawn over them (`Wavetable`, `WavetableScan`) |
| [OwnSampler](OwnSampler/Sketch.swift) | the rest of that path: your own `.sfz` map over your own recordings, read from the sketch's bundle, with the loop band that lets half a second of recording sustain for as long as the note is held. The three files beside it are generated by the folder's own script, so they carry nobody else's license (`SampledInstrument(sfz:in:)`) |
| [PlayAlong](PlayAlong/Sketch.swift) | playing along with the room: onsets heard at the microphone become a tempo and a beat position, the ring carries the musical beat between them, and once the follower is steady the sketch joins in (`BeatFollower`, `steadiness`, `isFollowing`) |
| [Tunings](Tunings/Sketch.swift) | twelve notes to the octave is a choice: one melody played in just, Pythagorean, quarter-tone, 19-tone, 31-tone, and Bohlen-Pierce tunings. Each degree is placed on a ladder by its `cents` and labeled with how far it is from the nearest equal-tempered note (`Tuning`, `snap(_:)`) |
| [ChordSymbols](ChordSymbols/Sketch.swift) | chords written the way they are written on paper: a chart of symbols you can retype plays as changes, each card spells out the pitches it returns, and slash chords show their changed bass note. The sibling `Changes` writes the same idea as scale degrees (`Chord`, `Progression(symbols:)`) |
| [Sonification](Sonification/Sketch.swift) | numbers you can hear: a line across a landscape is drawn as a profile and read out as a tune from the same numbers, and the playhead is the note sounding (`Sonification`) |
| [Spatial](Spatial/Sketch.swift) | sound that comes from somewhere: three chimes stand around you and one walks a circle past them. The camera is the listener (`place(at:heardFrom:)`) |
| [SoundInAnExport](SoundInAnExport/Sketch.swift) | a piece whose sound goes into the export: the same score is rendered offline into the exported video rather than played to the room |

Run one with `swift run Example-Audio-<Name>`, for example `swift run Example-Audio-Spectrum`.
