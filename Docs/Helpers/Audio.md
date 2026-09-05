#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Audio`</sup>

---

## Audio

This library lets a sketch react to sound, and it can also produce a small sound of its own. Audio lives in a separate library so the drawing core stays free of `AVFoundation`. Add `import OllinAudio` beside `import Ollin` to use it.

There are two sides, **analysis** and **generation**. Analysis turns a stream of audio into a few values you read in `draw()`. The stream can be the microphone, a file, or a generated tone. The values are an overall `amplitude`, a frequency `spectrum`, and the band queries `bass`/`mid`/`treble`. Generation is a small oscillator, `Tone`, for audible feedback and self-contained demos. Both sides are a convenience layer over one typed core, the [`AudioAnalyzer`](#audioanalyzer).

The usual pattern is to create a source in `setup()`, keep it in a property, and read its values in `draw()`.

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

- [AudioInput](#audioinput) - analyze the live microphone
- [AudioPlayer](#audioplayer) - play and analyze an audio file
- [Tone](#tone) - generate (and analyze) an oscillator
- [Soundtrack](#soundtrack) - analyze the sound of a tappable source (a playing video)
- [Reading audio](#reading-audio) - `amplitude`, `spectrum`, `waveform`, and band queries
- [bands & beats](#bands-and-beats) - the ready-to-draw spectrum, and onset detection
- [AudioAnalyzer](#audioanalyzer) - the typed DSP core every source feeds

<a name="audioinput"></a>

### AudioInput

```swift
AudioInput(fftSize: Int = 1024, smoothing: Float = 0.8)
func start() throws
func stop()
var isRunning: Bool        // true while the mic is capturing
```

`AudioInput` captures live audio from the system's default input. Call `start()` once, usually in `setup()`, then read the [audio values](#reading-audio) in `draw()`.

```swift
let mic = AudioInput()
override func setup() { try? mic.start() }
```

Capturing the microphone needs the user's permission, and `start()` requests it the first time it runs. Until the user grants it, the level reads as silence. A packaged app must include a microphone-usage description. Under `swift run`, the system prompts on first use instead.

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

`AudioPlayer` plays an audio file and analyzes it as it sounds. That lets you react to recorded music or a field recording the same way you react to the microphone. It decodes the formats AVFoundation reads (`.m4a`/AAC, `.mp3`, `.wav`, `.aiff`, `.caf`, …).

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

A bundled audio file follows the same provenance rules as any asset, so use one whose license permits redistribution, and credit it. Loading from a resource cannot default the bundle to `.module`, because that would resolve to Ollin's bundle rather than yours. Pass your bundle explicitly.

Under a headless export ([Export](../Output/Export.md)) nothing audibly plays, so the player follows the export clock instead of the live engine. Each exported frame advances a sample playhead through the decoded file and feeds that slice to the analyzer. Exported frame `k` reads the file's analysis at `k / fps` seconds after `play()`, wrapped by `loops`. The result is identical on every run, so two exports of an audio-reactive sketch produce the same video. Create the player by the end of `setup()`, usually as a stored property, or the per-frame advance never finds it.

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
var isPlaying: Bool        // true while the tone is sounding
```

`Tone` is a single oscillator that synthesizes a tone you can hear. It feeds the same analyzer, so you can also read the tone back. It is enough for audible feedback and self-contained audio-reactive demos, but it is not a full synthesizer. `frequency`, `amplitude`, and `waveform` are all settable from `draw()`.

```swift
let tone = Tone(frequency: 220, waveform: .sine)
override func setup() { tone.play() }
override func draw() {
    tone.frequency = 110 + 440 * (mouseX / width)   // pitch follows the cursor
}
```

<a name="soundtrack"></a>

### Soundtrack

```swift
Soundtrack(of: any AudioTapSource, fftSize: Int = 1024, smoothing: Float = 0.8)
func detach()
```

`Soundtrack` analyzes the sound of any *tappable* source. Today that means a playing video, because `VideoPlayer` (from [`OllinVideo`](../Video/Video.md)) conforms to the core `AudioTapSource` seam. A sketch can therefore react to the soundtrack of the footage it is drawing:

```swift
let player = try VideoPlayer(path: "/path/to/clip.mp4")
lazy var sound = Soundtrack(of: player)
override func setup() { player.play() }
override func draw() {
    drawFrame(player)
    for (i, level) in sound.bands(32).enumerated() { … }   // bars over the footage
}
```

The analysis hears the source's own sound, before volume shaping, so `volume = 0` keeps it reacting in silence. Two caveats apply. First, a hard `isMuted = true` stops the source's audio processing altogether, so prefer `volume = 0`. Second, a headless export reads as silence, because nothing audibly plays there. When you need an analysis that stays deterministic under export, use [`AudioPlayer`](#audioplayer), which decodes its own file. There is one consumer per source, so creating a second `Soundtrack` of the same player replaces the first. Call `detach()` to release the slot.

<a name="reading-audio"></a>

### Reading audio

Every source exposes the same read surface, which forwards to its [`AudioAnalyzer`](#audioanalyzer):

```swift
var amplitude: Float                       // smoothed overall loudness, ~0...1
var spectrum: [Float]                       // per-bin magnitudes, low frequency first
var waveform: [Float]                       // the last fftSize samples, oldest first, -1...1
var bass: Float                             // energy in 20–250 Hz
var mid: Float                              // energy in 250–2000 Hz
var treble: Float                           // energy in 2000–8000 Hz
func magnitude(in range: ClosedRange<Double>) -> Float   // average over a Hz range
var smoothing: Float                        // response damping, 0...1
```

`spectrum` has `fftSize / 2` bins. Each bin spans `sampleRate / fftSize` Hz, from 0 up toward the Nyquist frequency. The magnitudes are smoothed but not normalized, so scale them as you like for drawing. You can also use [`bands`](#bands-and-beats) below, which does that shaping for you. `waveform` is a rolling window of the most recent `fftSize` samples, oldest first. That means a scope trace drawn from it stays continuous, no matter how the audio arrives in chunks. `smoothing` trades responsiveness for steadiness: 0 is raw and jittery, and a value near 1 is heavily damped. You can change it live.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/28-SoundAndControl/Anatomy-dark.jpg">
  <img src="../../Guide/Images/28-SoundAndControl/Anatomy.jpg" alt="Three stacked panels from one analyzed instant: the raw waveform wiggle, the spectrum with spikes marked at the kick, bass, and melody frequencies, and 24 normalized band bars" width="680">
</picture>

<a name="bands-and-beats"></a>

### bands & beats

Two higher-level reads sit on top of the raw spectrum, and they are the ones you usually want for audio-reactive visuals.

```swift
func bands(_ count: Int) -> [Float]   // normalized, log-spaced frequency bars (each ~0...1)
var beatCount: Int                     // beats detected so far
var timeSinceBeat: Double              // seconds of audio since the last beat
var beat: Float                        // a 0...1 pulse that hits 1 on a beat and decays
var beatSensitivity: Float             // onset threshold; higher = fewer beats (default 1.5)
```

**`bands(count)`** is the spectrum shaped for drawing. It gives `count` bars spread *logarithmically*, which is the way pitch is heard, so low notes are not crammed into a few bins. Each bar is normalized to roughly `0...1` by an adaptive gain and smoothed with a fast-attack / slow-release envelope. Turning a level into a bar height is then only a scale to pixels, with no hand-tuned gain. Call it once per frame with a fixed `count`.

```swift
for (i, level) in source.bands(48).enumerated() {
    let h = Double(level) * 300 * scale          // level is already 0...1
    drawRect(Double(i) * w, height - h, w * 0.8, h)
}
```

**Beats** come from spectral-flux onset detection. An onset is a sudden broadband rise, like a drum hit or a plucked string. The easiest use is `beat`, a ready-made pulse:

```swift
drawCircle(width / 2, height / 2, (40 + Double(source.beat) * 200) * scale)   // throbs on the beat
```

You can also fire something exactly once per beat by watching `beatCount`:

```swift
if source.beatCount > lastBeat { lastBeat = source.beatCount; spawnRipple() }
```

Raise `beatSensitivity` if it triggers too often, and lower it if it misses beats. The threshold is an absolute margin over the flux's own recent average, on a loudness-invariant scale. Because of that, quiet and loud material behave alike, and steady material (a held chord, a drone) does not produce false triggers. Beats are gated by a short refractory period, so a single hit does not fire twice.

The whole beat surface runs on the *sample clock*, so positions are counted in samples of audio. That means the same recording always beats at the same places, `timeSinceBeat` does not advance while no audio arrives, and detection is testable without hardware.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/28-SoundAndControl/BeatTimeline-dark.jpg">
  <img src="../../Guide/Images/28-SoundAndControl/BeatTimeline.jpg" alt="A six-second timeline in three strips: the loudness curve with regular peaks, the beat pulse snapping to one and decaying at each detection, and tick marks where beatCount incremented" width="680">
</picture>

```swift
let lows = tone.bass
let kick = tone.magnitude(in: 40...120)     // a tighter band
```

<a name="audioanalyzer"></a>

### AudioAnalyzer

`AudioAnalyzer` is the DSP behind every source. It windows incoming samples, runs a real FFT (Accelerate / vDSP), and publishes the values above. You rarely construct one directly, because each source owns its own and exposes it as `.analyzer`. It is public for two reasons. The read surface and `smoothing` stay reachable, and you can feed it samples from a source of your own:

```swift
let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: 48000)
analyzer.process(samples: ptr, count: n)    // or process(_ buffer: AVAudioPCMBuffer)
```

Samples arrive on the audio thread while a sketch reads on the main thread. The analyzer is internally locked, so the reads are safe from anywhere.

---

See the **Spectrum** example (`Examples/Audio/Spectrum`) for a self-contained sketch that generates a sound and then analyzes it. There a `Tone` glides in pitch, and its harmonics drive a ring of spectrum bars.
