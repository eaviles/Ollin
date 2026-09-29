// The names Chapter 37's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import OllinAudio
import OllinVideo

// The microphone of the first step, and the video player from Chapter 34.
@MainActor let mic = AudioInput()
@MainActor let player = try! VideoPlayer(url: SampleClip.dance.url)

// The stand-in band from the bottom of Anatomy.swift, by its signatures.
final class StageMic {
    let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: 44100)
    func listen(seconds: Double = 1.0 / 60) {}
}

// The two listeners on the microphone, what the word "red" changes, the marks
// a clap leaves, and the caption a recording is transcribed into.
@MainActor let speech = SpeechListener(of: mic)
@MainActor let ears = SoundClassifier(of: mic)
var ink = Color.black
struct Mark { var at: Vector2 }
var marks: [Mark] = []
var caption: String?
