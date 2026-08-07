#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Helpers</sup>

---

## Helpers

- [`Math`](./Math.md) - `map`, `dist`, `lerp`, and `Double.tau`
- [`Animation`](./Animation.md) - the `Easing` curves, `@Eased` (ease toward a target), `@Smoothed` (smooth a noisy signal), and `@Sprung` (spring toward a target with momentum)
- [`Parameters`](./Parameters.md) - `@Param` tunable knobs: live sliders in the inspector, optional smoothing, and binding from OSC or MIDI
- [`Input`](./Input.md) - mouse and keyboard
- [`Data`](./Data.md) - `loadTable` for CSV and TSV files, and `loadJSON` for documents you reach through by name and index
- [`Audio`](./Audio.md) - `import OllinAudio` for microphone, file, and oscillator sources, analyzed into `amplitude`/`spectrum`/band values you read in `draw()`
- [`Synthesis`](./Synthesis.md) - `Synth`, the instrument a sketch plays: notes by name or number, `Voice` presets over a shaped and filtered oscillator, delay and reverb
- [`Composition`](./Composition.md) - working out what to play: Euclidean rhythms, scales and chords, arpeggios, and Markov sequences, as pure values on a step number
