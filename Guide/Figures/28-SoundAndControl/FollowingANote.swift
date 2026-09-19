// figure: frame=0 themed
//
// Guide diagram (Chapter 28): four seconds of a real recording, the bundled
// solo violin, read for its pitch by the shipped detector. Top: the pitch
// trace on a strip of semitones, one dot per window, each as solid as the
// detector was sure. Middle: the twelve pitch classes over the same seconds,
// every octave folded onto twelve rows, the melody drawing itself as a path
// through the note names. Bottom: the tuner's face at one marked instant, the
// nearest note and the cents away from it. Every value is the analyzer's own;
// only the air has been replaced by the file.
import AVFoundation
import Ollin
import OllinAudio
import OllinDiagram

final class FollowingANote: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.55) }
    var faint: Color { theme.ink(0.14) }
    var accent: Color { theme.accent }

    /// Where the recording starts being read, and for how long.
    let start = 1.0
    let seconds = 4.0
    /// The instant the tuner face reads, as a fraction of the stretch.
    let marked = 0.62

    struct Reading {
        var time: Double
        var pitch: DetectedPitch?
        var chroma: [Float]
    }
    var readings: [Reading] = []
    var names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    let left = 96.0, plotWidth = 724.0
    let lowest = 48.0, highest = 84.0          // C3 to C6, where the violin plays here

    /// The bundled violin clip, found by walking up from the working directory,
    /// which the runner sets to the repository root.
    var clipURL: URL {
        let tail = "Examples/Audio/FilePlayer/fandanguito.m4a"
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while true {
            let candidate = directory.appendingPathComponent(tail)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { return candidate }
            directory = parent
        }
    }

    override func setup() {
        readings = listen()
    }

    /// Decodes the stretch and feeds it to a real analyzer a sixtieth of a
    /// second at a time, the way a live tap would, keeping each window's
    /// reads.
    func listen() -> [Reading] {
        guard let file = try? AVAudioFile(forReading: clipURL) else {
            print("FollowingANote: could not open \(clipURL.path)")
            return []
        }
        let rate = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)
        let frames = AVAudioFrameCount(rate * seconds)
        file.framePosition = AVAudioFramePosition(rate * start)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: buffer, frameCount: frames)) != nil,
              let data = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: count)
        for c in 0..<channels {
            for i in 0..<count { mono[i] += data[c][i] / Float(channels) }
        }

        let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: rate, smoothing: 0)
        let chunk = Int(rate / 60)
        var out: [Reading] = []
        var offset = 0
        while offset + chunk <= count {
            mono.withUnsafeBufferPointer {
                analyzer.analyze(samples: $0.baseAddress! + offset, count: chunk)
            }
            offset += chunk
            out.append(Reading(time: Double(offset) / rate, pitch: analyzer.pitch, chroma: analyzer.chroma))
        }
        return out
    }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let trace = Rectangle(x: left, y: 44, width: plotWidth, height: 196)
        let classes = Rectangle(x: left, y: 290, width: plotWidth, height: 150)
        let face = Rectangle(x: left, y: 484, width: plotWidth, height: 64)
        diagramFrame(trace, title: "pitch", theme: theme)
        diagramFrame(classes, title: "chroma", theme: theme)
        diagramFrame(face, title: "note and cents, at the marked instant", theme: theme)
        drawText("one dot per window, as solid as the detector is sure", trace.topRight.x, trace.y - 20,
                 size: 15, color: soft, align: .right, .middle)
        drawText("the twelve classes, every octave folded", classes.topRight.x, classes.y - 20,
                 size: 15, color: soft, align: .right, .middle)

        drawTrace(in: trace)
        drawClasses(in: classes)
        drawFace(in: face)
        drawText("four seconds of the violin read by the analyzer, time left to right; the dashed line is the instant the face reads",
                 width / 2, 578, size: 15, color: soft, align: .center, .middle)
    }

    func x(of time: Double, in rect: Rectangle) -> Double {
        rect.x + time / seconds * rect.width
    }

    func marker(in rect: Rectangle) {
        let mx = x(of: marked * seconds, in: rect)
        stroke(theme.ink(0.5))
        strokeWeight(1.2)
        var y = rect.y + 2
        while y < rect.y + rect.height - 2 {
            drawLine(mx, y, mx, min(y + 5, rect.y + rect.height - 2))
            y += 9
        }
        noStroke()
    }

    /// The pitch on a strip of semitones, with the C and G of each octave named.
    func drawTrace(in rect: Rectangle) {
        func y(_ midi: Double) -> Double {
            rect.y + rect.height - (midi - lowest) / (highest - lowest) * rect.height
        }
        noStroke()
        for midi in stride(from: lowest, through: highest, by: 1) {
            let index = Int(midi) % 12
            let named = index == 0 || index == 7
            fill(named ? theme.ink(0.3) : faint)
            drawRect(rect.x, y(midi) - 0.5, rect.width, 1)
            if named {
                drawText("\(Pitch(midi))", rect.x - 8, y(midi), size: 13, color: soft, align: .right, .middle)
            }
        }
        for reading in readings {
            guard let heard = reading.pitch, heard.midi >= lowest, heard.midi <= highest else { continue }
            fill(accent.withAlpha(0.12 + Double(heard.confidence) * 0.88))
            drawCircle(x(of: reading.time, in: rect), y(heard.midi), 2.6)
        }
        marker(in: rect)
    }

    /// The chroma as twelve rows over time, ink by strength.
    func drawClasses(in rect: Rectangle) {
        let rowHeight = rect.height / 12
        noStroke()
        for row in 0..<12 {
            let index = 11 - row                 // C at the bottom, like the strip above
            let top = rect.y + Double(row) * rowHeight
            drawText(names[index], rect.x - 8, top + rowHeight / 2, size: 12, color: soft, align: .right, .middle)
            fill(faint)
            drawRect(rect.x, top + rowHeight - 0.5, rect.width, 1)
        }
        guard readings.count > 1 else { return }
        let cell = rect.width / Double(readings.count)
        for (i, reading) in readings.enumerated() {
            guard reading.chroma.count == 12 else { continue }
            for index in 0..<12 {
                let value = Double(reading.chroma[index])
                guard value > 0.04 else { continue }
                let top = rect.y + Double(11 - index) * rowHeight
                fill(accent.withAlpha(0.08 + value * 0.92))
                drawRect(rect.x + Double(i) * cell, top + 1, cell + 0.5, rowHeight - 2)
            }
        }
        marker(in: rect)
    }

    /// The tuner's face at the marked instant: the note, and the needle on a
    /// scale from fifty cents flat to fifty sharp.
    func drawFace(in rect: Rectangle) {
        let index = min(readings.count - 1, max(0, Int(marked * Double(readings.count))))
        guard readings.indices.contains(index), let heard = readings[index].pitch else {
            drawText("no note heard", rect.center.x, rect.center.y, size: 17, color: soft, align: .center, .middle)
            return
        }
        drawText("\(heard.nearestPitch)", rect.x + 60, rect.center.y, size: 30, color: ink, align: .center, .middle)
        let sign = heard.cents >= 0 ? "+" : ""
        drawText("\(sign)\(Int(heard.cents.rounded())) cents", rect.x + 170, rect.center.y,
                 size: 17, color: ink, align: .center, .middle)
        drawText(String(format: "%.0f Hz, confidence %.2f", heard.frequency, heard.confidence),
                 rect.x + rect.width - 16, rect.center.y, size: 15, color: soft, align: .right, .middle)

        let scaleLeft = rect.x + 270, scaleRight = rect.x + 470
        let y = rect.center.y + 10
        noStroke()
        fill(theme.ink(0.3))
        drawRect(scaleLeft, y - 1, scaleRight - scaleLeft, 2)
        for cents in stride(from: -50, through: 50, by: 10) {
            let tx = map(Double(cents), -50, 50, scaleLeft, scaleRight)
            let tall = cents % 50 == 0 ? 9.0 : (cents % 20 == 0 ? 6.0 : 3.5)
            fill(theme.ink(cents == 0 ? 0.7 : 0.35))
            drawRect(tx - 0.75, y - tall, 1.5, tall * 2)
        }
        drawText("-50", scaleLeft, y + 16, size: 11, color: soft, align: .center, .middle)
        drawText("+50", scaleRight, y + 16, size: 11, color: soft, align: .center, .middle)
        let nx = map(heard.cents, -50, 50, scaleLeft, scaleRight)
        fill(accent)
        drawTriangle(nx, y - 5, nx - 6, y - 19, nx + 6, y - 19)
    }
}
