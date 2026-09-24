import Foundation
import Testing
import OllinMutation
@testable import Ollin
@testable import OllinAudio

/// Three more files a sketch is handed: a Standard MIDI File, an IES light
/// profile, and an SVG drawing. Each is read, then read back the way a sketch
/// reads it: the music walked by beat and by second and written out again,
/// the light asked for its intensity in every direction and baked, the
/// drawing's shapes fitted and filled.
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct MusicAndShapeFileMutationTests {

    @Test func midiFiles() {
        let phrase = [
            ScheduledNote(Note("C4", velocity: 0.8, length: .quarter), beat: 0, step: 0),
            ScheduledNote(Note("E4", velocity: 1.0, length: .eighth), beat: 1, step: 1),
            ScheduledNote(Note("G4", velocity: 0.2, length: .half), beat: 1.5, step: 2),
        ]
        var parallel = MIDIFile(phrase, tempo: 112, name: "Phrase")
        parallel.tracks[0].program = 12
        parallel.tracks[0].controls = [MIDIFile.ControlChange(beat: 0.5, controller: 7, value: 0.5)]
        parallel.tracks[0].bends = [MIDIFile.PitchBend(beat: 1, position: -0.5)]
        parallel.markers = [MIDIFile.Marker(beat: 2, text: "turn")]
        parallel.tempoChanges = [MIDIFile.TempoChange(beat: 0, tempo: 90), MIDIFile.TempoChange(beat: 2, tempo: 140)]
        parallel.timeSignatures = [MIDIFile.TimeSignature(beat: 0, count: 6, unit: .eighth)]
        var single = MIDIFile(format: .oneTrack, name: "Both", tracks: [
            MIDIFile.Track(phrase, name: "Keys", channel: 1),
            MIDIFile.Track([ScheduledNote(Note(36, length: .quarter), beat: 0, step: 0)], name: "Drums", channel: 10),
        ])
        single.division = .perSecond(framesPerSecond: 25, ticksPerFrame: 40)
        let seeds = [[UInt8](parallel.data()), [UInt8](single.data())]

        let report = MutationRun.run("midi-file", seeds: seeds, count: 600, allocations: fileBound) { bytes in
            let file = try MIDIFile(data: Data(bytes))
            let end = file.lastBeat
            for beat in [0, end / 2, end, end + 4] {
                _ = file.tempo(at: beat)
                _ = file.timeSignature(at: beat)
                _ = file.beats(at: file.seconds(at: beat))
                _ = file.notes(from: beat, to: beat + 1)
            }
            _ = file.duration
            _ = try MIDIFile(data: file.data())
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func iesProfiles() throws {
        let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Examples/3D/Lighting/LightShaping")
        let seeds = try ["downlight", "batwing", "wallwash"].map {
            [UInt8](try Data(contentsOf: examples.appendingPathComponent("\($0).ies")))
        }
        let included = "IESNA:LM-63-2002\n[TEST] tilt\nTILT=INCLUDE\n1\n2\n0 90\n1 0.8\n1 -1 1 3 2 1 1 0.1 0.1 0\n1 1 50\n0 45 90\n0 180\n100 80 10 90 60 5\n"
        let report = MutationRun.run("ies-profile", seeds: seeds + [included.bytes], count: 300, sweeps: false,
                                     numberSweep: true, allocations: fileBound) { bytes in
            guard let profile = IESProfile(data: Data(bytes)) else { return false }
            for vertical in stride(from: -0.5, through: 3.7, by: 0.3) {
                for horizontal in stride(from: -1.0, through: 7.0, by: 0.9) {
                    _ = profile.intensity(vertical: vertical, horizontal: horizontal)
                }
            }
            _ = profile.bakedTable(width: 8, height: 4)
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func svgDrawings() {
        let drawing = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 80" width="200">
          <g transform="translate(5 5) rotate(10 50 40) scale(1.2, 0.9)" style="fill:#336699;stroke:rgb(10%,20,30);stroke-width:2">
            <path id="wave" d="M0 10 C 10 0, 20 20, 30 10 S 50 0, 60 10 Q 70 20 80 10 T 95 10 A 12 8 30 1 0 40 60 Z m5,5 h10 v10 l-5 5z"/>
            <rect x="10" y="30" width="20" height="10" rx="3" opacity="0.5"/>
            <circle cx="70" cy="50" r="8" fill="none" stroke="tomato"/>
            <ellipse cx="30" cy="60" rx="10" ry="4" fill="#abcd"/>
            <line x1="0" y1="0" x2="100" y2="80" stroke-linecap="round"/>
            <polyline points="0,70 10,65 20,70 30,65" fill="none" stroke="#123456" stroke-linejoin="bevel"/>
            <polygon points="60,60 70,75 50,75" fill-rule="evenodd" transform="skewX(10) matrix(1 0 0 1 2 3)"/>
          </g>
          <defs><path id="hidden" d="M0 0 L10 10"/></defs>
        </svg>
        """
        let report = MutationRun.run("svg-drawing", seeds: [drawing.bytes], count: 600,
                                     numberSweep: true, allocations: fileBound) { bytes in
            guard let svg = SVG(data: Data(bytes)) else { return false }
            let fitted = svg.fitted(in: Rectangle(x: 0, y: 0, width: 400, height: 300))
            for element in fitted.elements {
                _ = element.shape.triangulatedFill()
                for contour in element.shape.contours { _ = contour.length }
            }
            _ = svg.element(named: "wave")
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }
}
