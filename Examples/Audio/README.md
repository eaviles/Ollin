#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Audio</sup>

---

## Audio

Sound-reactive sketches. Audio lives in a separate library — add `import OllinAudio` — with three sources (`AudioInput` for the microphone, `AudioPlayer` for files, `Tone` for an oscillator) analyzed into `amplitude`, a frequency `spectrum`, and band values a sketch reads in `draw()`. See the [Audio reference](../../Docs/Audio.md).

| Example | What it shows |
|---|---|
| [Spectrum](Spectrum/Sketch.swift) | a generated sawtooth `Tone` that glides in pitch, its harmonics analyzed back into a radial frequency `spectrum` while the central disc pulses with `amplitude` — self-contained, so it runs with no microphone permission or bundled file (`Tone`, `spectrum`, `amplitude`) |
| [Microphone](Microphone/Sketch.swift) | the same radial visual driven by the live microphone — bars trace the `spectrum`, the disc swells with `amplitude`; `AudioInput.start()` requests mic permission and the sketch stays quiet until it's granted (`AudioInput`) |
| [FilePlayer](FilePlayer/Sketch.swift) | reacts to a playing audio file — a spectrum bar chart plus a waveform oscilloscope; loops a bundled CC0 Bach clip by default, or pass a path on launch to play your own track (`AudioPlayer`, `spectrum`, `waveform`) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-Spectrum`.
