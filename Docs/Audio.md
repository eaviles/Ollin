#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Audio`</sup>

---

## Audio

Make a sketch react to sound, and make a little sound of its own. Audio lives in a separate library so the drawing core stays free of `AVFoundation` — add `import OllinAudio` alongside `import Ollin` to reach it.

There are two sides. **Analysis** turns a stream of audio — the microphone, a file, or a generated tone — into a few values you read in `draw()`: an overall `amplitude`, a frequency `spectrum`, and band queries (`bass`/`mid`/`treble`). **Generation** is a modest oscillator (`Tone`) for audible feedback and self-contained demos. Both are sugar over one typed core, the [`AudioAnalyzer`](#audioanalyzer).

The usual shape: make a source in `setup()`, keep it in a property, read its values in `draw()`.

```swift
import Ollin
import OllinAudio

final class Pulse: Sketch {
    let mic = AudioInput()

    override func setup() { try? mic.start() }

    override func draw() {
        background(.black)
        let r = (60 + Double(mic.amplitude) * 700) * scale
        fill(.white)
        drawCircle(width / 2, height / 2, r)
    }
}
```

### Contents

- [AudioInput](#audioinput) — analyze the live microphone
- [AudioPlayer](#audioplayer) — play and analyze an audio file
- [Tone](#tone) — generate (and analyze) an oscillator
- [Reading audio](#reading-audio) — `amplitude`, `spectrum`, `waveform`, and band queries
- [bands & beats](#bands-and-beats) — the ready-to-draw spectrum, and onset detection
- [AudioAnalyzer](#audioanalyzer) — the typed DSP core every source feeds

<a name="audioinput"></a>

### AudioInput

```swift
AudioInput(fftSize: Int = 1024, smoothing: Float = 0.8)
func start() throws
func stop()
```

Live audio from the system's default input. Call `start()` once (usually in `setup()`), then read the [audio values](#reading-audio) in `draw()`.

```swift
let mic = AudioInput()
override func setup() { try? mic.start() }
```

Capturing the microphone needs the user's permission; `start()` requests it the first time it runs. Until the user grants it, the level reads as silence. (On a packaged app, include a microphone-usage description; from `swift run` the system prompts on first use.)

<a name="audioplayer"></a>

### AudioPlayer

```swift
AudioPlayer(path: String, fftSize: Int = 1024, smoothing: Float = 0.8) throws
AudioPlayer(url: URL, …) throws
AudioPlayer(resource: String, withExtension: String, in: Bundle, …) throws
func play()
func pause()
func stop()
var loops: Bool
var isPlaying: Bool
```

Plays an audio file and analyzes it as it sounds — react to recorded music or a field recording the same way you react to the microphone. Decodes the formats AVFoundation reads (`.m4a`/AAC, `.mp3`, `.wav`, `.aiff`, `.caf`, …).

```swift
let song = try AudioPlayer(path: "/path/to/track.m4a")
override func setup() { song.loops = true; song.play() }
override func draw() {
    for (i, m) in song.spectrum.prefix(64).enumerated() {
        let h = Double(m) * 4000 * scale
        drawRect(Double(i) * 16 * scale, height - h, 14 * scale, h)
    }
}
```

A bundled audio file follows the same provenance rules as any asset: use one whose license permits redistribution, and credit it. Loading from a resource can't default the bundle to `.module` (that would resolve to Ollin's bundle, not yours), so pass your bundle explicitly.

<a name="tone"></a>

### Tone

```swift
Tone(frequency: Double = 440, amplitude: Double = 0.3,
     waveform: Waveform = .sine, fftSize: Int = 1024, smoothing: Float = 0.5)
func play()
func stop()
var frequency: Double      // Hz, settable live
var amplitude: Double      // 0...1, settable live
var waveform: Waveform     // .sine, .triangle, .sawtooth, .square
```

A single oscillator that synthesizes a tone you can hear — and, because it feeds the same analyzer, also read back. Enough for audible feedback and self-contained audio-reactive demos, short of a full synthesizer. `frequency`, `amplitude`, and `waveform` are all settable from `draw()`.

```swift
let tone = Tone(frequency: 220, waveform: .sine)
override func setup() { tone.play() }
override func draw() {
    tone.frequency = 110 + 440 * (mouseX / width)   // pitch follows the cursor
}
```

<a name="reading-audio"></a>

### Reading audio

Every source exposes the same read surface (it forwards to its [`AudioAnalyzer`](#audioanalyzer)):

```swift
var amplitude: Float                       // smoothed overall loudness, ~0...1
var spectrum: [Float]                       // per-bin magnitudes, low frequency first
var waveform: [Float]                       // recent raw samples, -1...1 (oscilloscope)
var bass: Float                             // energy in 20–250 Hz
var mid: Float                              // energy in 250–2000 Hz
var treble: Float                           // energy in 2000–8000 Hz
func magnitude(in range: ClosedRange<Double>) -> Float   // average over a Hz range
var smoothing: Float                        // response damping, 0...1
```

`spectrum` has `fftSize / 2` bins, each spanning `sampleRate / fftSize` Hz, from 0 up toward the Nyquist frequency. The magnitudes are smoothed but unnormalized, so scale them to taste for drawing — or reach for [`bands`](#bands-and-beats) below, which does that shaping for you. `smoothing` (0 = raw and twitchy, near 1 = heavily damped) trades responsiveness for steadiness and can be changed live.

<a name="bands-and-beats"></a>

### bands & beats

Two higher-level reads sit on top of the raw spectrum — the ones you usually want for audio-reactive visuals.

```swift
func bands(_ count: Int) -> [Float]   // normalized, log-spaced frequency bars (each ~0...1)
var beatCount: Int                     // beats detected so far
var timeSinceBeat: Double              // seconds since the last beat
var beat: Float                        // a 0...1 pulse that hits 1 on a beat and decays
var beatSensitivity: Float             // onset threshold; higher = fewer beats (default 1.5)
```

**`bands(count)`** is the spectrum shaped for drawing: `count` bars spread *logarithmically* (the way pitch is heard, so low notes aren't crammed into a few bins), each normalized to roughly `0...1` by an adaptive gain and smoothed with a fast-attack / slow-release envelope. So a bar height is just a map to pixels — no hand-tuned gain. Call it once per frame with a fixed `count`.

```swift
for (i, level) in source.bands(48).enumerated() {
    let h = Double(level) * 300 * scale          // level is already 0...1
    drawRect(Double(i) * w, height - h, w * 0.8, h)
}
```

**Beats** come from spectral-flux onset detection (a sudden broadband rise — a drum hit, a plucked string). The easiest use is `beat`, a ready-made pulse:

```swift
drawCircle(width / 2, height / 2, (40 + Double(source.beat) * 200) * scale)   // throbs on the beat
```

…or fire something exactly once per beat by watching `beatCount`:

```swift
if source.beatCount > lastBeat { lastBeat = source.beatCount; spawnRipple() }
```

Raise `beatSensitivity` if it triggers too eagerly, lower it if it misses beats. Beats are gated by a short refractory period, so a single hit won't double-fire.

```swift
let lows = tone.bass
let kick = tone.magnitude(in: 40...120)     // a tighter band
```

<a name="audioanalyzer"></a>

### AudioAnalyzer

The DSP behind every source: it windows incoming samples, runs a real FFT (Accelerate / vDSP), and publishes the values above. You rarely construct one directly — the sources own theirs and expose it as `.analyzer` — but it's public so the read surface and `smoothing` are reachable, and so you can feed it samples from a source of your own:

```swift
let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: 48000)
analyzer.process(samples: ptr, count: n)    // or process(_ buffer: AVAudioPCMBuffer)
```

Samples arrive on the audio thread while a sketch reads on the main thread; the analyzer is internally locked, so the reads are safe from anywhere.

---

See the **Spectrum** example (`Examples/Audio/Spectrum`) for a self-contained, generate-then-analyze sketch — a `Tone` glides in pitch and its harmonics drive a ring of spectrum bars.
