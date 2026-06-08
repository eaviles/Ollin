#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Audio</sup>

---

## Audio

Sound-reactive sketches. Audio lives in a separate library — add `import OllinAudio` — with three sources (`AudioInput` for the microphone, `AudioPlayer` for files, `Tone` for an oscillator) analyzed into `amplitude`, a frequency `spectrum`, and band values a sketch reads in `draw()`. See the [Audio reference](../../Docs/Audio.md).

| Example | What it shows |
|---|---|
| [Spectrum](Spectrum/Sketch.swift) | a generated sawtooth `Tone` that glides in pitch, its harmonics analyzed back into a radial frequency `spectrum` while the central disc pulses with `amplitude` — self-contained, so it runs with no microphone permission or bundled file (`Tone`, `spectrum`, `amplitude`) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-Spectrum`.
