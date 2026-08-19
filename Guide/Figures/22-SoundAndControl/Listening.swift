// figure: frame=0 unstable
//
// Guide diagram (Chapter 22): the two ways a sketch can listen, and the one
// thing about speech that shapes the whole API.
//
// Everything on this page is real. The sentence is spoken by the system's own
// synthesizer into a buffer (nothing recorded is committed to the repository),
// and each line of the left column is a genuine transcription of a longer
// prefix of that buffer, which is how the guess is shown growing and correcting
// itself. The right column's three sounds are made of arithmetic and handed to
// the real classifier; the labels and the numbers are whatever came back.
//
// Marked unstable because both models are the system's: the voice and the
// recognizer can change under us, and the runner verifies this figure without
// rewriting its committed image.
import AVFoundation
import Ollin
import OllinAudio

final class ListeningFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 660) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.14)
    let accent = Color(hex: 0xE4572E)
    let cool = Color(hex: 0x3A6EA5)

    let sentence = "the quick brown fox jumps over the lazy dog"

    /// The spoken audio, and what the recognizer made of growing prefixes of it.
    var wave: [Float] = []
    var guesses: [(fraction: Double, text: String)] = []

    /// Three sounds made of arithmetic, and what the classifier called them.
    var sounds: [(name: String, samples: [Float], heard: [SoundClassification])] = []

    override func setup() {
        noLoop()
        listenToSpeech()
        listenToSounds()
    }

    private func listenToSpeech() {
        guard let spoken = Spoken.write(sentence) else { return }
        wave = spoken.samples
        let rate = spoken.rate
        for fraction in [0.35, 0.6, 0.8, 1.0] {
            let prefix = Array(spoken.samples.prefix(Int(Double(spoken.samples.count) * fraction)))
            // Read everything into locals before the closure: `waitFor` parks
            // this thread, and a sketch property read from inside it would wait
            // on the thread already waiting.
            let text = (try? waitFor {
                try await SpeechListener.transcribe(prefix, sampleRate: rate,
                                                    locale: Locale(identifier: "en_US"))
            }) ?? ""
            guesses.append((fraction, text))
        }
    }

    private func listenToSounds() {
        let rate = 44100.0
        func build(_ seconds: Double, _ gen: (Double) -> Float) -> [Float] {
            (0..<Int(seconds * rate)).map { gen(Double($0) / rate) }
        }
        var seed: UInt64 = 20260809
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53) * 2 - 1
        }
        let made: [(String, [Float])] = [
            ("a steady tone", build(4) { Float(0.5 * sin(2 * .pi * 440 * $0)) }),
            ("taps, every quarter second", build(4) {
                $0.truncatingRemainder(dividingBy: 0.25) < 0.001 ? 0.9 : 0
            }),
            ("bursts of noise", build(4) {
                Float(0.9 * exp(-$0.truncatingRemainder(dividingBy: 0.5) * 60) * noise())
            }),
        ]
        sounds = made.map {
            ($0.0, $0.1, Array(SoundClassifier.classify($0.1, sampleRate: rate).prefix(3)))
        }
    }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        title("Two ways to listen", at: Vector2(48, 52))
        caption("Words that correct themselves, and sounds with names.", at: Vector2(48, 78))

        drawSpeechColumn(x: 48, top: 118, width: 400)
        drawSoundColumn(x: 496, top: 118, width: 336)

        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.left)
        drawText("Both halves of this page are real: the sentence is spoken into a buffer by the "
                 + "system voice, and the three sounds are arithmetic.",
                 in: Rectangle(x: 48, y: 612, width: 784, height: 42))
    }

    // MARK: Speech

    private func drawSpeechColumn(x: Double, top: Double, width: Double) {
        heading("What is being said", at: Vector2(x, top))
        drawWave(in: Rectangle(x: x, y: top + 22, width: width, height: 56))

        guard !guesses.isEmpty else {
            noStroke(); fill(soft); textSize(14); textAlign(.left)
            drawText("no voice installed", at: Vector2(x, top + 110))
            return
        }

        var y = top + 108
        for (index, guess) in guesses.enumerated() {
            let committed = index == guesses.count - 1
            // The bar shows how much of the sentence had been heard when the
            // recognizer was asked.
            noStroke()
            fill(faint)
            drawRect(corner: Vector2(x, y - 24), width: width, height: 3)
            fill(committed ? accent : cool)
            drawRect(corner: Vector2(x, y - 24), width: width * guess.fraction, height: 3)

            fill(committed ? ink : soft)
            textSize(committed ? 17 : 15)
            textAlign(.left)
            drawText(guess.text.isEmpty ? "(nothing yet)" : guess.text,
                     in: Rectangle(x: x, y: y, width: width, height: 44))
            y += 68
        }

        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.left)
        drawText("Each line is the same recognizer, given a little more of the sound. The blue "
                 + "lines are guesses it can still take back; the last one is what it committed "
                 + "to. Draw the guess, act on the commitment.",
                 in: Rectangle(x: x, y: y - 4, width: width, height: 80))
    }

    private func drawWave(in box: Rectangle) {
        noFill()
        stroke(faint)
        strokeWeight(1)
        drawLine(box.x, box.y + box.height / 2, box.x + box.width, box.y + box.height / 2)
        guard !wave.isEmpty else { return }
        stroke(ink.withAlpha(0.75))
        strokeWeight(1)
        let columns = Int(box.width)
        let per = max(1, wave.count / columns)
        for column in 0..<columns {
            let start = column * per
            guard start < wave.count else { break }
            var peak: Float = 0
            for i in start..<min(start + per, wave.count) { peak = max(peak, abs(wave[i])) }
            let h = Double(peak) * box.height * 0.9
            let cx = box.x + Double(column)
            drawLine(cx, box.y + box.height / 2 - h / 2, cx, box.y + box.height / 2 + h / 2)
        }
    }

    // MARK: Sounds

    private func drawSoundColumn(x: Double, top: Double, width: Double) {
        heading("What that sound is", at: Vector2(x, top))

        var y = top + 26
        for sound in sounds {
            noStroke()
            fill(ink)
            textSize(14)
            textAlign(.left)
            drawText(sound.name, at: Vector2(x, y + 12))
            drawWave(sound.samples, in: Rectangle(x: x, y: y + 22, width: width, height: 28))

            var row = y + 60
            for entry in sound.heard {
                noStroke()
                fill(faint)
                drawRect(corner: Vector2(x, row), width: width, height: 12)
                fill(accent.withAlpha(0.75))
                drawRect(corner: Vector2(x, row), width: width * entry.confidence, height: 12)
                fill(ink)
                textSize(12)
                textAlign(.left)
                drawText(entry.label.replacingOccurrences(of: "_", with: " "),
                         at: Vector2(x + 6, row + 9))
                textAlign(.right)
                fill(soft)
                drawText(String(format: "%.2f", entry.confidence), at: Vector2(x + width - 6, row + 9))
                row += 17
            }
            y = row + 22
        }

        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.left)
        drawText("Three hundred everyday names, and it always offers one. A threshold is what "
                 + "turns an opinion into a trigger.",
                 in: Rectangle(x: x, y: y + 6, width: width, height: 60))
    }

    private func drawWave(_ samples: [Float], in box: Rectangle) {
        stroke(cool.withAlpha(0.8))
        strokeWeight(1)
        let columns = Int(box.width)
        let per = max(1, samples.count / columns)
        for column in 0..<columns {
            let start = column * per
            guard start < samples.count else { break }
            var peak: Float = 0
            for i in start..<min(start + per, samples.count) { peak = max(peak, abs(samples[i])) }
            let h = max(1, Double(peak) * box.height)
            let cx = box.x + Double(column)
            drawLine(cx, box.y + box.height / 2 - h / 2, cx, box.y + box.height / 2 + h / 2)
        }
    }

    // MARK: Type

    private func title(_ text: String, at point: Vector2) {
        noStroke(); fill(ink); textAlign(.left); textSize(26)
        drawText(text, at: point)
    }

    private func caption(_ text: String, at point: Vector2) {
        noStroke(); fill(soft); textAlign(.left); textSize(14)
        drawText(text, at: point)
    }

    private func heading(_ text: String, at point: Vector2) {
        noStroke(); fill(ink); textAlign(.left); textSize(16)
        drawText(text, at: point)
    }
}

/// The system voice, written into a buffer rather than played, so the figure
/// has speech to recognize without carrying a recording.
enum Spoken {
    @MainActor
    static func write(_ text: String, timeout: Double = 20) -> (samples: [Float], rate: Double)? {
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { return nil }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice

        final class Collected: @unchecked Sendable {
            var samples: [Float] = []
            var rate = 0.0
            var finished = false
        }
        let collected = Collected()
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            guard pcm.frameLength > 0 else { return collected.finished = true }
            collected.rate = pcm.format.sampleRate
            if let channel = pcm.floatChannelData?[0] {
                collected.samples.append(contentsOf:
                    UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
            }
        }
        // The buffers arrive on the main queue, so the main thread has to be let
        // go rather than blocked. A figure's setup is plain synchronous code, so
        // that means running the loop; from an async context it would mean
        // awaiting instead.
        let deadline = Date().addingTimeInterval(timeout)
        while !collected.finished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard !collected.samples.isEmpty, collected.rate > 0 else { return nil }
        return (collected.samples, collected.rate)
    }
}
