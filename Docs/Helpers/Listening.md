#### <sup>[Ollin](../../README.md) → [Docs](../README.md) → Listening</sup>

# Listening

Speech as words you can draw, and everyday sounds as triggers. The audio sibling of the [vision trackers](../Vision/Vision.md): bind a listener to something that makes sound, then read typed values in `draw()`.

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

Both listeners bind to **anything that makes sound**: `AudioInput` (the microphone), `AudioPlayer`, `Tone`, or a playing `VideoPlayer`'s soundtrack. Several can listen to one source at once, and a [`Soundtrack`](Audio.md) analyzer can be reading the same audio alongside them.

Everything here runs on this Mac. Nothing is uploaded, and speech recognition asks for no consent of its own; the microphone asks for its own the first time you `start()` it.

## Contents

- [Speech](#speech): [caption and transcript](#a-caption-and-a-transcript-are-different-things), [phrases as triggers](#acting-on-what-was-said), [languages](#languages)
- [Sound events](#sound-events): [levels and triggers](#a-level-and-a-trigger), [the vocabulary](#the-vocabulary), [your own model](#your-own-model)
- [Ahead of time](#ahead-of-time): the one-shot forms, and getting words into an export
- [What is not here](#what-is-not-here)

## Speech

`SpeechListener(of:)` starts listening. Recognition is on-device and continuous.

### A caption and a transcript are different things

This is the whole design, and it comes from how recognition works: it guesses early and corrects itself as it hears more. The words on screen a moment ago may not be the words it settles on.

<img src="../../Guide/Images/26-SoundAndControl/Listening.jpg" alt="A spoken sentence transcribed from growing prefixes of its audio, and three synthesized sounds with the labels the classifier gave them" width="680">

So there are two reads:

| Read | What it is | What it is for |
| --- | --- | --- |
| `caption` | the running best guess, tail included | drawing |
| `transcript` | only what the recognizer committed to | keeping, and acting on |
| `phrases()` | committed phrases, drained | triggering |

`caption` keeps its last `captionWords` words (14 by default, about a line), so it does not grow off the side of the canvas. `reset()` forgets everything heard so far.

### Acting on what was said

`phrases()` hands back every `SpokenPhrase` committed to since the last call, oldest first, and hands each one out once. That is the trigger surface: a word in `caption` can still be taken back, a word in a phrase cannot.

```swift
for phrase in speech.phrases() {
    let said = phrase.text.lowercased()
    if said.contains("red") { palette = .warm }
    if said.contains("blue") { palette = .cool }
}
```

Drain it in one place per frame: a second call in the same frame gets nothing. `latest` is the most recent phrase and stays readable after a drain. Each phrase carries `start` and `duration` in seconds of audio.

A phrase lands when the recognizer is confident, which usually means after a small pause. For a faster reaction than that, read `caption` and accept that it can change its mind.

### Languages

`SpeechListener(of:locale:)` defaults to the Mac's own language and resolves it to one the recognizer knows. `SpeechListener.supportedLocales` lists the ones this Mac knows, a few dozen.

The first use of a language may install its model, which takes a moment and needs the network. During that time `isAvailable` is false and `unavailableReason` says what is happening; the listener starts on its own when it lands. `isListening` reports whether audio is actually being taken yet, and audio arriving before that is **held rather than dropped**, so the first words into a microphone still count.

A language the recognizer does not know leaves the listener unavailable, named in `unavailableReason`, rather than hearing nothing forever.

```swift
if let reason = speech.unavailableReason { return drawStatus(reason, style: .warning) }
```

## Sound events

`SoundClassifier(of:)` names sounds as they happen.

### A level and a trigger

There are two kinds of question, so there are two kinds of read.

*Is this music?* is a level that rises and falls:

```swift
let musical = ears.confidence(of: "music")     // 0...1
let now = ears.top                             // the strongest label right now
let all = ears.classifications                 // everything over `threshold`
```

*Did somebody just clap?* happens once:

```swift
for event in ears.events() { print(event.label, event.confidence, event.time) }
let flash = max(0, 1 - ears.timeSinceHearing("clapping") / 0.3)
```

An event fires when a label crosses `threshold` (0.6 by default) **from below**, so a sound that goes on is one event and not one per analysis window. `events()` drains; `timeSinceHearing(_:)` does not, which is what makes it the right read for a mark that fades. Both run on the sample clock, so they measure the audio rather than how long the machine took to think about it.

`threshold` is settable live.

### The vocabulary

The built-in classifier knows 303 everyday sounds: speech, laughter, applause, `clapping`, `finger_snapping`, dogs and cats and birds and insects, instruments by family and by name, weather and water and fire, vehicles and sirens, doors and taps and keyboards, `knock`, `beep`, `click`, `glass_breaking`, `silence`. `labels` lists them.

Two things to know about it. It is always willing to guess, so read `top` and a `threshold` rather than believing every small number; `"music"` in particular turns up faintly under almost anything. And it judges a **window** of audio at a time (`windowDuration`, 1.5 seconds by default, adjustable), so a short sound is named a fraction of a second after it happens. A shorter window reacts sooner and judges on less; measured against synthesized tones and taps, 1 second is a notably poor setting and 1.5 a good one.

### Your own model

A Core ML sound classifier of your own (what Create ML's sound classifier trains) goes in the same place:

```swift
let ears = SoundClassifier(of: mic, model: myModel)
let ears = try SoundClassifier(of: mic, modelAt: compiledURL)   // an .mlmodelc
```

An `.mlmodel` has to be compiled first with `MLModel.compileModel(at:)`. Compile to a **stable** path: a fresh temporary directory each launch makes Core ML re-specialize the model every time, which costs seconds.

## Ahead of time

Both listeners are **live only**. Under a headless export nothing is playing, so nothing is heard, and both say so in `unavailableReason` rather than sitting silently empty.

The way to put words and sounds into an export is to work them out ahead of time. Both one-shot forms are deterministic: the same audio always gives the same answer.

```swift
// In setup(), with `waitFor` to run an async call from a synchronous place.
let said = try waitFor {
    try await SpeechListener.transcribe(resource: "interview", withExtension: "m4a", in: .module)
}
let heard = try SoundClassifier.classify(resource: "field", withExtension: "wav", in: .module)
```

`transcribe` also takes `[Float]` samples and a `contentsOf: URL` (any audio or video file). `classify` takes the same three, and returns each label at the highest confidence it reached anywhere in the clip, strongest first, so a single clap in a long recording still registers. `classify` runs inline and needs no `waitFor`.

`waitFor` parks the calling thread, so call it from `setup()` and never from an async context, and do not read the sketch's own properties inside the closure (a `Sketch` is main-actor isolated, so the read would wait on the thread that is already waiting). Read what you need into locals first.

## What is not here

- **No confidence per word.** A `SpokenPhrase` is text and a time range.
- **No speaker separation**, and no voice identification.
- **No `@Param` binding.** A confidence is already a plain read in `draw()`; wrap it in [`@Smoothed`](Animation.md) if it jitters.
- **No wake word.** Listen for a phrase yourself, in `phrases()`.
- **Nothing recorded is kept.** A listener holds no audio, only what it heard.

## See also

- [Audio](Audio.md) covers level, spectrum, bands, and beat detection over the same sources.
- [Vision](../Vision/Vision.md) is the seeing half, whose tracker shape this follows.
- [Synthesis](Synthesis.md) is making sound rather than listening to it.
- Guide [Chapter 26](../../Guide/26-SoundAndControl.md) teaches it, under *Words, and what that noise was*.
- `Examples/Audio/Listening` is a caption and named sounds over the live microphone.
