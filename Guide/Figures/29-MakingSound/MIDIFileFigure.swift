// figure: frame=0 themed
//
// Guide diagram (Chapter 29): what a Standard MIDI File carries, and the one
// thing about it that is not obvious. The piece is composed here, written to
// bytes, and read back, so every mark is read off a real `MIDIFile` rather
// than drawn to look like one. Top: the file as a piano roll, two parts on
// two channels, bar lines from its own time signature, markers where the
// chords change. Bottom: the same four bars on two rulers, beats as the file
// counts them and seconds as the clock runs them, with the tempo dropping by
// half at bar three, which is what the tempo map has to be walked for.
import Ollin
import OllinAudio
import OllinDiagram

final class MIDIFileFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.14) }
    var accent: Color { theme.accent }
    var second: Color { Color(hex: 0x6C8EBF) }

    let left = 120.0
    let right = 840.0
    var span: Double { right - left }

    /// The piece, after a round trip through the bytes of a `.mid` file.
    lazy var song: MIDIFile = {
        let written = compose()
        return (try? MIDIFile(data: written.data())) ?? written
    }()

    /// Four bars: a chord held under a figure, slowing by half at bar three.
    private func compose() -> MIDIFile {
        let key = Scale(.minor, root: "A3")
        let changes = Progression("i VI III VII", in: key)
        var chords: [ScheduledNote] = []
        var melody: [ScheduledNote] = []
        var markers: [MIDIFile.Marker] = []
        var arp = Arpeggiator(.up, octaves: 1, rate: .eighth)

        for bar in 0 ..< 4 {
            let beat = Double(bar) * 4
            let pitches = changes.pitches(at: bar)
            markers.append(MIDIFile.Marker(beat: beat, text: changes.root(at: bar).description))
            for pitch in pitches {
                chords.append(ScheduledNote(Note(pitch, velocity: 0.5, length: NoteLength(beats: 3.7)),
                                            beat: beat, step: chords.count))
            }
            arp.notes = pitches.map { $0.transposed(by: 12) }
            arp.reset(to: beat)
            for note in arp.events(upTo: beat + 4) {
                melody.append(ScheduledNote(Note(note.pitch, velocity: 0.75, length: .eighth),
                                            beat: note.beat, step: melody.count))
            }
        }

        var file = MIDIFile(
            format: .parallelTracks, name: "Four Bars",
            tracks: [MIDIFile.Track(chords, name: "Chords", channel: 1),
                     MIDIFile.Track(melody, name: "Melody", channel: 2)],
            tempoChanges: [MIDIFile.TempoChange(beat: 0, tempo: 120),
                           MIDIFile.TempoChange(beat: 8, tempo: 60)],
            timeSignatures: [MIDIFile.TimeSignature(count: 4, unit: .quarter)])
        file.markers = markers
        return file
    }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)
        noStroke()

        drawRoll(top: 40)
        drawRulers(top: 350)
    }

    private func heading(_ text: String, at y: Double) {
        fill(ink)
        textSize(15)
        textAlign(.left, .middle)
        drawText(text, left, y)
    }

    // MARK: The file as a picture

    private func drawRoll(top: Double) {
        heading("the file: \(song.tracks.count) parts, \(song.notes.count) notes, "
                + "\(Int(song.lastBeat)) beats", at: top)

        let height = 190.0
        let y0 = top + 34
        let length = max(1, song.lastBeat)
        let pitches = song.notes.map(\.pitch.midi)
        let low = (pitches.min() ?? 48) - 1
        let high = (pitches.max() ?? 72) + 1
        let row = height / max(1, high - low)

        // A line at every bar, counted off the file's own time signature.
        let bar = song.timeSignature(at: 0).barLength.beats
        for line in stride(from: 0.0, through: length, by: bar) {
            let x = left + span * line / length
            fill(theme.ink(0.22))
            drawRect(x - 0.5, y0, 1, height)
        }
        fill(faint)
        drawRect(left, y0 + height, span, 1)

        for (index, track) in song.tracks.enumerated() {
            let color = index == 0 ? second : accent
            for note in track.notes {
                let x = left + span * note.beat / length
                let w = max(3, span * note.length.beats / length - 1.5)
                let y = y0 + height - (note.pitch.midi - low + 1) * row
                fill(color.withAlpha(0.35 + 0.55 * note.velocity))
                drawRect(x, y, w, max(2.5, row - 1.5))
            }
        }

        // The markers it carries: where the chords change.
        textSize(12)
        textAlign(.left, .middle)
        for marker in song.markers {
            fill(soft)
            drawText(marker.text, left + span * marker.beat / length + 4, y0 - 10)
        }

        // Which part is which, named from the file rather than from here.
        var x = left
        for (index, track) in song.tracks.enumerated() {
            fill(index == 0 ? second : accent)
            drawRect(x, y0 + height + 14, 10, 10)
            fill(soft)
            textSize(12)
            drawText("\(track.name), channel \(track.channel)", x + 16, y0 + height + 19)
            x += 150
        }
    }

    // MARK: Beats against seconds

    private func drawRulers(top: Double) {
        heading("one piece on two rulers", at: top)
        fill(soft)
        textSize(12)
        textAlign(.left, .middle)
        drawText("every position in a file is a beat; the tempo map is what turns one into a second",
                 left, top + 20)

        let length = max(1, song.lastBeat)
        let seconds = max(0.001, song.duration)
        let beatsY = top + 88
        let secondsY = top + 168

        fill(faint)
        drawRect(left, beatsY, span, 1)
        drawRect(left, secondsY, span, 1)

        // The same eight half-bars, placed once by beat and once by clock.
        for step in stride(from: 0.0, through: length, by: 2) {
            let onBeats = left + span * step / length
            let onClock = left + span * song.seconds(at: step) / seconds
            let isBar = step.truncatingRemainder(dividingBy: 4) == 0

            fill(isBar ? theme.ink(0.45) : theme.ink(0.2))
            drawRect(onBeats - 0.5, beatsY - 7, 1, 14)
            drawRect(onClock - 0.5, secondsY - 7, 1, 14)

            // The line between them is the tempo map, drawn.
            stroke(step < 8 ? theme.ink(0.22) : accent.withAlpha(0.5))
            strokeWeight(isBar ? 1.4 : 0.9)
            drawLine(onBeats, beatsY + 8, onClock, secondsY - 8)
            noStroke()

            if isBar {
                fill(soft)
                textSize(11)
                textAlign(.center, .middle)
                drawText("\(Int(step))", onBeats, beatsY - 17)
                drawText("\(String(format: "%.1f", song.seconds(at: step)))s", onClock, secondsY + 18)
            }
        }

        // Each ruler named at its own end, clear of the numbers on it.
        fill(ink)
        textSize(12)
        textAlign(.right, .middle)
        drawText("beats", left - 14, beatsY)
        drawText("seconds", left - 14, secondsY)

        // Where the file changes speed, and what that does to the spacing.
        if let change = song.tempoChanges.last, change.beat > 0 {
            let x = left + span * change.beat / length
            fill(accent)
            drawRect(x - 0.5, beatsY - 7, 1, 14)
            textSize(12)
            textAlign(.right, .middle)
            drawText("\(Int(change.tempo.beatsPerMinute)) a minute from beat \(Int(change.beat)), "
                     + "so the same bar takes twice the clock",
                     right, top + 42)
        }
    }
}
