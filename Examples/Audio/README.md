#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Audio</sup>

---

## Audio

Sound-reactive sketches. Audio lives in a separate library — add `import OllinAudio` — with three sources (`AudioInput` for the microphone, `AudioPlayer` for files, `Tone` for an oscillator) analyzed into `amplitude`, a frequency `spectrum`, and band values a sketch reads in `draw()`. See the [Audio reference](../../Docs/Audio.md).

| Example | What it shows |
|---|---|
| [Spectrum](Spectrum/Sketch.swift) | a generated sawtooth `Tone` that glides in pitch, its harmonics analyzed into a radial ring of normalized `bands` while the central disc pulses with the level — self-contained, so it runs with no microphone permission or bundled file (`Tone`, `bands`) |
| [Microphone](Microphone/Sketch.swift) | the same radial visual driven by the live microphone — bars trace the normalized `bands`, the central disc flashes on each detected `beat` (clap at it); `AudioInput.start()` requests mic permission and the sketch stays quiet until it's granted (`AudioInput`, `bands`, `beat`) |
| [FilePlayer](FilePlayer/Sketch.swift) | reacts to a playing audio file — a `bands` bar chart plus a `waveform` oscilloscope, the whole canvas flashing on each `beat`; loops a bundled clip (*El Fandanguito*, a traditional Mexican son huasteco for violin, CC BY-SA) by default, or pass a path on launch to play your own track (`AudioPlayer`, `bands`, `beat`, `waveform`) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-Spectrum`.
