#### <sup>[Ollin](../../README.md) → [Docs](../README.md) → Listening</sup>

# Listening

Speech becomes words you can draw, and everyday sounds become triggers. This is the audio counterpart of the [vision trackers](../Vision/Vision.md), and it works the same way. You bind a listener to something that makes sound, then read typed values in `draw()`.

```swift
import OllinAudio

let mic = AudioInput()
var speech: SpeechListener!
var ears: SoundClassifier!

override func setup() {
    speech = SpeechListener(of: mic)
    ears = SoundClassifier(of: mic)
    try? mic.start()
}

override func draw() {
    background(.black)
    drawText(speech.caption, at: center)
    for event in ears.events() where event.label == "clapping" { flash() }
}
```

Both listeners bind to **anything that makes sound**: `AudioInput` (the microphone), `AudioPlayer`, `Tone`, or the soundtrack of a playing `VideoPlayer`. Several listeners can share one source, and a [`Soundtrack`](Audio.md) analyzer can read the same audio at the same time.

Everything here runs on the Mac itself, so nothing is uploaded. Speech recognition asks for no permission of its own. The microphone asks for its permission the first time you `start()` it.

## Contents

- [Speech](#speech): [caption and transcript](#a-caption-and-a-transcript-are-different-things), [phrases as triggers](#acting-on-what-was-said), [languages](#languages)
- [Sound events](#sound-events): [levels and triggers](#a-level-and-a-trigger), [the vocabulary](#the-vocabulary), [your own model](#your-own-model)
- [Ahead of time](#ahead-of-time): the one-shot forms, and getting words into an export
- [What is not here](#what-is-not-here)

## Speech

`SpeechListener(of:)` starts listening. Recognition is on-device and continuous.

### A caption and a transcript are different things

The split comes from how recognition works. The recognizer guesses early and corrects itself as it hears more. So the words on screen a moment ago may not be the words it settles on.

<img src="../../Guide/Images/28-SoundAndControl/Listening.jpg" alt="A spoken sentence transcribed from growing prefixes of its audio, and three synthesized sounds with the labels the classifier gave them" width="680">

So there are three reads:

| Read | What it is | What it is for |
| --- | --- | --- |
| `caption` | the running best guess, tail included | drawing |
| `transcript` | only what the recognizer committed to | keeping, and acting on |
| `phrases()` | committed phrases, drained | triggering |

`caption` keeps only its last `captionWords` words (14 by default, about one line), so it does not run off the side of the canvas. `reset()` forgets everything heard so far.

### Acting on what was said

`phrases()` returns every `SpokenPhrase` the recognizer committed to since the last call, oldest first, and returns each one only once. This is the read to trigger from, because a word in `caption` can still be taken back and a word in a phrase cannot.

```swift
for phrase in speech.phrases() {
    let said = phrase.text.lowercased()
    if said.contains("red") { palette = .warm }
    if said.contains("blue") { palette = .cool }
}
```

Drain it in one place per frame, because a second call in the same frame gets nothing. `latest` is the most recent phrase, and it stays readable after a drain. Each phrase carries `start` and `duration`, measured in seconds of audio.

A phrase arrives when the recognizer is confident, which usually means after a short pause. If you need a faster reaction than that, read `caption` instead and accept that its words can change.

### Languages

`SpeechListener(of:locale:)` defaults to the Mac's own language and resolves it to one the recognizer knows. `SpeechListener.supportedLocales` lists the languages this Mac knows, which is a few dozen.

The first use of a language may install its model. That takes a moment and needs the network. During the install `isAvailable` is false and `unavailableReason` says what is happening. The listener starts on its own once the model is in place, and `isListening` reports whether it is taking audio yet. Audio that arrives before it starts is **held rather than dropped**, so the first words into a microphone still count.

If the recognizer does not know a language, the listener stays unavailable and `unavailableReason` says why. The listener does not keep running and returning nothing.

```swift
if let reason = speech.unavailableReason { return drawStatus(reason, style: .warning) }
```

## Sound events

`SoundClassifier(of:)` names sounds as they happen.

### A level and a trigger

You can ask two kinds of question about a sound, so the classifier gives you two kinds of read.

*Is this music?* is a level that rises and falls:

```swift
let musical = ears.confidence(of: "music")     // 0...1
let now = ears.topClassification               // the strongest label right now
let all = ears.classifications                 // everything over `threshold`
```

*Did somebody just clap?* is an event that happens once:

```swift
for event in ears.events() { print(event.label, event.confidence, event.time) }
let flash = max(0, 1 - ears.timeSinceHearing("clapping") / 0.3)
```

An event fires when a label crosses `threshold` (0.6 by default) **from below**. A sound that keeps going is therefore one event, not one per analysis window. `events()` drains what it returns. `timeSinceHearing(_:)` does not drain, which makes it the right read for a mark that fades. Both run on the sample clock, so they measure the audio itself rather than how long the machine took to analyze it.

You can set `threshold` while the classifier runs.

### The vocabulary

The built-in classifier knows 303 everyday sounds, and `labels` lists all of them. Among them are speech, laughter, applause, `clapping`, and `finger_snapping`. It covers dogs, cats, birds, and insects, and instruments by family and by name. It also covers weather, water, and fire, vehicles and sirens, and doors, taps, and keyboards, plus `knock`, `beep`, `click`, `glass_breaking`, and `silence`.

Two things about it are worth knowing. First, it always guesses, so read `topClassification` and apply a threshold rather than trusting every small number. `"music"` in particular turns up faintly under almost any sound. Second, it judges a **window** of audio at a time (`windowDuration`, 1.5 seconds by default, and adjustable). A short sound is therefore named a fraction of a second after it happens. A shorter window reacts sooner but judges on less audio. Measured against synthesized tones and taps, 1 second is a poor setting and 1.5 is a good one.

### Your own model

You can use your own Core ML sound classifier in the same place, including one you trained with Create ML's sound classifier:

```swift
let ears = SoundClassifier(of: mic, model: myModel)
let ears = try SoundClassifier(of: mic, modelAt: compiledURL)   // an .mlmodelc
```

Compile an `.mlmodel` first with `MLModel.compileModel(at:)`. Compile it to a **stable** path. A fresh temporary directory on each launch makes Core ML re-specialize the model every time, and that costs seconds.

## Ahead of time

Both listeners are **live only**. Under a headless export nothing is playing, so nothing is heard. Both listeners say so in `unavailableReason` rather than staying silently empty.

To put words and sounds into an export, work them out ahead of time with the one-shot forms. Both forms are deterministic, so the same audio always gives the same answer.

```swift
// In setup(), with `waitFor` to run an async call from a synchronous place.
let said = try waitFor {
    try await SpeechListener.transcribe(resource: "interview", withExtension: "m4a", in: .module)
}
let heard = try SoundClassifier.classify(resource: "field", withExtension: "wav", in: .module)
```

`transcribe` also takes `[Float]` samples and a `contentsOf: URL` (any audio or video file). `classify` takes the same three inputs. It returns each label at the highest confidence it reached anywhere in the clip, strongest first. So a single clap in a long recording still registers. `classify` runs inline and needs no `waitFor`.

`waitFor` blocks the calling thread. Call it from `setup()` and never from an async context. Do not read the sketch's own properties inside the closure. A `Sketch` is main-actor isolated, so the read would wait on the thread that is already waiting. Read what you need into local variables first.

## What is not here

- **No confidence per word.** A `SpokenPhrase` is text and a time range.
- **No speaker separation**, and no voice identification.
- **No `@Param` binding.** A confidence is already a plain read in `draw()`. Wrap it in [`@Smoothed`](Animation.md) if it jitters.
- **No wake word.** Listen for a phrase yourself, in `phrases()`.
- **Nothing recorded is kept.** A listener holds no audio, only what it heard.

## See also

- [Audio](Audio.md) covers level, spectrum, bands, and beat detection over the same sources.
- [Vision](../Vision/Vision.md) is the counterpart for seeing, and this page follows the shape of its trackers.
- [Synthesis](Synthesis.md) covers making sound rather than listening to it.
- Guide [Chapter 28](../../Guide/28-SoundAndControl.md) teaches it, under *Words, and what that noise was*.
- `Examples/Audio/Listening` draws a caption and named sounds over the live microphone.
