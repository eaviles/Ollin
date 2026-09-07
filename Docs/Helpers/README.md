#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Helpers</sup>

---

## Helpers

- [`Math`](./Math.md) - `map`, `dist`, `lerp`, and `Double.tau`
- [`Animation`](./Animation.md) - the `Easing` curves, `@Eased` (ease toward a target), `@Smoothed` (smooth a noisy signal), and `@Sprung` (spring toward a target with momentum)
- [`Parameters`](./Parameters.md) - `@Param` tunable parameters: live sliders in the inspector, optional smoothing, and binding from OSC or MIDI
- [`Tuning`](./Tuning.md) - a look described in words moves the `@Param`s it concerns, on the Mac's own model (`import OllinAssist`)
- [`Input`](./Input.md) - mouse and keyboard
- [`Accessibility`](./Accessibility.md) - color vision simulation, a palette check, the published safe set, and the reduce-motion setting
- [`Data`](./Data.md) - `loadTable` for CSV and TSV files, and `loadJSON` for documents whose values you look up by name and index
- [`LiveData`](./LiveData.md) - `DataFeed` reads one address again and again, so a sketch draws the current value instead of the value it read at launch
- [`Weather`](./Weather.md) - `Weather`, the sky over a place or a name as plain readings (temperature, clouds, wind, rain, the condition in a word), and `Place.sun(at:)` for where the sun is, with no network
- [`Audio`](./Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources. Ollin analyzes each source into `amplitude`, `spectrum`, and band values that you read in `draw()`
- [`Listening`](./Listening.md) - speech as a caption you can draw and phrases you can act on, and about 300 everyday sounds named as they happen. Both work from any audio source
- [`Synthesis`](./Synthesis.md) - `Synth`, the instrument a sketch plays. It gives you notes by name or number, `Voice` presets over a shaped and filtered oscillator, and delay and reverb effects
- [`Composition`](./Composition.md) - ways to work out what to play: Euclidean rhythms, scales and chords, arpeggios, and Markov sequences. Each one computes its result as a pure value from a step number
