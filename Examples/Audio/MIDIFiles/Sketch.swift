import Foundation
import Ollin
import OllinAudio

/// A piece written out as a `.mid` file, read back in, and played from the
/// file.
///
/// Nothing here is bundled. In `setup()` the sketch works out eight bars for
/// itself, two parts over a chord progression, writes them to a Standard MIDI
/// File, and then forgets them: everything drawn and everything heard comes
/// from reading that file back. So the piano roll is a picture of the file,
/// and the file is the one a sequencer or a notation program would open.
///
/// The playhead runs on the file's own tempo map through `beats(at:)`, and the
/// notes are asked for between where the music is now and where it will be at
/// the end of the frame, so a note lands on its own sample rather than on the
/// frame that asked for it.
@main
final class MIDIFiles: Sketch {

    @Param(icon: "pianokeys", group: "Parts") var playsChords = true
    @Param(icon: "music.note", group: "Parts") var playsMelody = true
    @Param(0.5 ... 2, icon: "speedometer", group: "Time") var speed = 1.0

    /// The piece, as it came back off disk.
    var song = MIDIFile([])
    /// Where the file went, printed on screen so it can be opened elsewhere.
    var path = ""
    /// How many bytes it took.
    var size = 0

    let chords = Synth(.pad, polyphony: 12)
    let melody = Synth(.pluck, polyphony: 6)

    /// Where the music is, in beats, and where it was last frame.
    var beat = 0.0
    var elapsed = 0.0
    /// The notes lit up as the head passes them, and how long ago.
    var struck: [Int: Double] = [:]

    let ink = Color(hex: 0xF5F2EA)
    let chordColor = Color(hex: 0x6C8EBF)
    let melodyColor = Color(hex: 0xE8A33D)

    override func setup() {
        noStroke()
        chords.gain = 0.22
        chords.reverb = Reverb(.hall, mix: 0.3)
        melody.gain = 0.35
        melody.reverb = Reverb(.room, mix: 0.2)

        let file = compose()
        path = FileManager.default.temporaryDirectory
            .appendingPathComponent("OllinMIDIFiles.mid").path
        do {
            try file.write(to: path)
            // From here on the sketch knows nothing the file does not say.
            song = try MIDIFile(contentsOf: path)
            size = (try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? 0
        } catch {
            print("Ollin: the piece could not be written or read back (\(error)).")
        }
    }

    /// Eight bars worked out with the composition tier, as two parts and a
    /// marker on every chord.
    private func compose() -> MIDIFile {
        let key = Scale(.dorian, root: "D3")
        let changes = Progression("i IV i VII", in: key)
        var arp = Arpeggiator(.upDown, octaves: 2, rate: .eighth)
        arp.swing = 0.56

        var chordNotes: [ScheduledNote] = []
        var melodyNotes: [ScheduledNote] = []
        var markers: [MIDIFile.Marker] = []

        for bar in 0 ..< 8 {
            let beat = Double(bar) * 4
            let pitches = changes.pitches(at: bar)
            markers.append(MIDIFile.Marker(beat: beat, text: changes.root(at: bar).description))

            // The chord, held for the bar.
            for pitch in pitches {
                chordNotes.append(ScheduledNote(
                    Note(pitch, velocity: 0.5, length: NoteLength(beats: 3.8)),
                    beat: beat, step: chordNotes.count))
            }

            // A figure over it, the ladder restarted on the new chord.
            arp.notes = pitches.map { $0.transposed(by: 12) }
            arp.reset(to: beat)
            for note in arp.events(upTo: beat + 4) {
                melodyNotes.append(ScheduledNote(
                    Note(note.pitch, velocity: note.velocity * 0.8, length: .eighth),
                    beat: note.beat, step: melodyNotes.count))
            }
        }

        var file = MIDIFile(
            format: .parallelTracks, name: "Eight Bars",
            tracks: [
                MIDIFile.Track(chordNotes, name: "Chords", channel: 1, program: 89),
                MIDIFile.Track(melodyNotes, name: "Melody", channel: 2, program: 46),
            ],
            tempoChanges: [
                MIDIFile.TempoChange(beat: 0, tempo: 96),
                // The last two bars lean back, which the playhead then follows
                // without the sketch knowing anything about it.
                MIDIFile.TempoChange(beat: 24, tempo: 80),
            ],
            timeSignatures: [MIDIFile.TimeSignature(count: 4, unit: .quarter)])
        file.markers = markers
        return file
    }

    override func draw() {
        background(Color(hex: 0x14161C))
        guard !song.tracks.isEmpty else { return }

        // The file's own clock. Its tempo map is what turns the sketch's
        // seconds into beats, so the slowing at bar seven is the file's doing.
        let length = max(1, song.lastBeat)
        elapsed += deltaTime * speed
        let was = beat
        beat = song.beats(at: elapsed).truncatingRemainder(dividingBy: length)
        let looped = beat < was

        for (index, track) in song.tracks.enumerated() {
            let synth = index == 0 ? chords : melody
            guard index == 0 ? playsChords : playsMelody else { continue }
            let notes = looped
                ? track.notes.filter { $0.beat >= was } + track.notes.filter { $0.beat < beat }
                : track.notes.filter { $0.beat >= was && $0.beat < beat }
            synth.play(notes, tempo: song.tempo(at: beat))
            for note in notes { struck[key(of: note, in: index)] = time }
        }

        drawRoll(length: length)
        drawLabels()
    }

    private func key(of note: ScheduledNote, in track: Int) -> Int {
        track * 100_000 + Int(note.beat * 16) * 128 + Int(note.pitch.midi)
    }

    /// The piano roll: one row a semitone, one column a beat.
    private func drawRoll(length: Double) {
        let frame = Rectangle(corner: Vector2(80, 170), width: width - 160, height: height - 320)
        let pitches = song.notes.map(\.pitch.midi)
        let low = (pitches.min() ?? 48) - 2
        let high = (pitches.max() ?? 72) + 2
        let row = frame.height / max(1, high - low)

        fill(Color(hex: 0x1C2029))
        drawRect(corner: frame.corner, width: frame.width, height: frame.height)

        // A line at every bar, from the file's own time signature.
        let bar = song.timeSignature(at: 0).barLength.beats
        fill(Color(hex: 0x262B36))
        for line in stride(from: 0.0, through: length, by: bar) {
            let x = frame.corner.x + frame.width * line / length
            drawRect(corner: Vector2(x, frame.corner.y), width: 1, height: frame.height)
        }

        for (index, track) in song.tracks.enumerated() {
            let color = index == 0 ? chordColor : melodyColor
            let dim = (index == 0 ? playsChords : playsMelody) ? 1.0 : 0.25
            for note in track.notes {
                let x = frame.corner.x + frame.width * note.beat / length
                let w = max(3, frame.width * note.length.beats / length - 1)
                let y = frame.corner.y + frame.height - (note.pitch.midi - low + 1) * row
                let age = time - (struck[key(of: note, in: index)] ?? -10)
                let lit = age < 0.35 ? 1 - age / 0.35 : 0
                fill(color.lighter(by: lit * 0.5).withAlpha((0.35 + 0.5 * note.velocity) * dim))
                drawRect(corner: Vector2(x, y), width: w, height: max(2, row - 1))
            }
        }

        // The markers the file carries, and the head running over them.
        fill(ink.withAlpha(0.5))
        textSize(13)
        for marker in song.markers {
            let x = frame.corner.x + frame.width * marker.beat / length
            drawText(marker.text, x + 4, frame.corner.y - 8)
        }
        fill(Color(hex: 0xE8564A))
        drawRect(corner: Vector2(frame.corner.x + frame.width * beat / max(1, song.lastBeat),
                                 frame.corner.y - 4),
                 width: 2, height: frame.height + 8)
    }

    private func drawLabels() {
        fill(ink)
        textSize(30)
        drawText(song.name.isEmpty ? "Untitled" : song.name, 80, 90)

        textSize(14)
        fill(ink.withAlpha(0.55))
        let parts = song.tracks.map { "\($0.name.isEmpty ? "part" : $0.name) on channel \($0.channel)" }
        drawText(parts.joined(separator: ", "), 80, 118)
        let fastest = Int(song.tempo.beatsPerMinute.rounded())
        let slowest = Int((song.tempoChanges.last?.tempo.beatsPerMinute ?? 0).rounded())
        drawText("\(song.notes.count) notes, \(fastest) to \(slowest) beats a minute, "
                 + "\(String(format: "%.1f", song.duration)) seconds, \(size) bytes",
                 80, 140)
        drawText("written to \(path)", 80, height - 110)
        drawText("everything above was read back out of that file", 80, height - 88)

        for (index, track) in song.tracks.enumerated() {
            let color = index == 0 ? chordColor : melodyColor
            fill(color)
            drawRect(corner: Vector2(80 + Double(index) * 160, height - 60), width: 12, height: 12)
            fill(ink.withAlpha(0.7))
            drawText(track.name, 100 + Double(index) * 160, height - 49)
        }
    }
}
