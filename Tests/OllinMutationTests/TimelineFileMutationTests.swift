import Foundation
import Testing
import OllinMutation
@testable import Ollin

/// The files that carry a run over time: a take, an automation, and a cue
/// sheet, each JSON a sketch did not necessarily write, and the formula text an
/// automation carries. Each is decoded, then played the way the runner plays
/// it: a take installed on a sketch and stepped frame by frame, an automation
/// applied at a spread of times, a cue sheet's values restored.
@MainActor
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct TimelineFileMutationTests {

    /// A sketch with a parameter of every kind a file can name.
    final class Target: Sketch {
        @Param(0...10) var amount = 2.0
        @Param(1...50) var count = 4
        @Param var on = true
        @Param var tint = Color.red
        @Param(x: 0...100, y: 0...100) var spot = Vector2(10, 20)
        @Param(x: 0...100, y: 0...100, width: 0...100, height: 0...100)
        var box = Rectangle(x: 0, y: 0, width: 5, height: 5)
        @Param(in: 0...100) var span = 10.0...20.0
        @Param var label = "hi"
    }

    static func json(_ value: some Encodable) -> [UInt8] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { [UInt8]($0) } ?? []
    }

    @Test func takeFiles() {
        let sketch = Target()
        let take = Take(version: Take.currentVersion, sketchType: "Target", seed: 7, canvas: [640, 480],
                        initialParams: ["amount": .number(3), "count": .number(5), "tint": .color(red: 0, green: 1, blue: 0, alpha: 1)],
                        frames: (0..<4).map { Take.Frame(time: Double($0) / 60, deltaTime: 1.0 / 60, frameRate: 60) },
                        events: [.init(frame: 0, event: .pointer(x: 5, y: 6)),
                                 .init(frame: 1, event: .button(pressed: true)),
                                 .init(frame: 1, event: .scroll(deltaY: 2)),
                                 .init(frame: 2, event: .key(character: "a", code: nil, pressed: true)),
                                 .init(frame: 3, event: .pressure(amount: 0.5, canVary: true))],
                        changes: [.init(frame: 2, name: "count", value: .number(9)),
                                  .init(frame: 3, name: "span", value: .range(lower: 3, upper: 90))])
        let report = MutationRun.run("take-file", seeds: [Self.json(take)], count: 400,
                                     numberSweep: true, allocations: fileBound) { bytes in
            let read = try JSONDecoder().decode(Take.self, from: Data(bytes))
            guard read.version == Take.currentVersion else { return false }
            read.install(on: sketch)
            let player = TakePlayer(take: read)
            for frame in 0..<min(read.frames.count + 2, 64) {
                _ = player.step(sketch, frame: frame, fallback: (time: 0, deltaTime: 1.0 / 60, frameRate: 60))
            }
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func automationFiles() throws {
        let sketch = Target()
        var automation = Automation(tracks: [
            .init(name: "amount", keys: [.init(at: 0, .number(1)), .init(at: 2, .number(8), curve: .bezier(x1: 0.2, y1: 1.4, x2: 0.8, y2: -0.3)),
                                         .init(at: 3, .number(2), curve: .hold)]),
            .init(name: "tint", keys: [.init(at: 0, .color(red: 1, green: 0, blue: 0, alpha: 1)),
                                       .init(at: 1, .color(red: 0, green: 0, blue: 1, alpha: 0.5), curve: .linear)]),
            .init(name: "count", formula: try Formula("amount * 3 + sin(time) * 2")),
            .init(name: "spot", parts: ["x": try Formula("width / 2 + noise(time, 1) * 10"), "y": try Formula("mod(frame, 7)")]),
            .init(name: "on", formula: try Formula("amount > 4 && !(count < 2)")),
        ], loops: true, speed: 1.5, start: 0.25)
        automation.length = 3
        let report = MutationRun.run("automation-file", seeds: [Self.json(automation)], count: 400,
                                     numberSweep: true, allocations: fileBound) { bytes in
            let read = try JSONDecoder().decode(Automation.self, from: Data(bytes))
            guard read.version <= Automation.currentVersion else { return false }
            let player = AutomationPlayer(read)
            for time in [-1.0, 0, 0.5, 1.7, 3, 100] {
                player.apply(to: sketch, at: time)
                for track in read.tracks { _ = read.value(of: track.name, at: time) }
            }
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func cueSheets() {
        let sketch = Target()
        let sheet = CueSheet(cues: [
            Cue(name: "open", values: ["amount": .number(1), "spot": .vector(x: 3, y: 4), "on": .boolean(false)]),
            Cue(name: "loud", values: ["amount": .number(9), "tint": .color(red: 1, green: 1, blue: 0, alpha: 1),
                                       "box": .rectangle(x: 1, y: 2, width: 3, height: 4), "label": .text("yo")]),
        ])
        let report = MutationRun.run("cue-sheet", seeds: [Self.json(sheet)], count: 400,
                                     numberSweep: true, allocations: fileBound) { bytes in
            let read = try JSONDecoder().decode(CueSheet.self, from: Data(bytes))
            guard read.version <= CueSheet.currentVersion else { return false }
            let handles = sketch.parameters()
            for cue in read.cues {
                let fade = CueTransition(name: cue.name, handles: handles, values: cue.values, duration: 0.5)
                for step in 0..<4 { fade.advance(by: 0.2 * Double(step)) }
                for handle in handles { if let value = cue.values[handle.name] { handle.param.restore(value) } }
            }
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func formulaText() {
        let seeds = ["sin(time * 2) * amount + 3", "if(x > 1, mod(-7, 3), clamp(y, 0, 1)) ^ -0.5",
                     "map(noise(x, y, t), 0, 1, -2, 2) + 1.5e3 - spot.x", "!(a == b || c != d) && e <= f"]
        let report = MutationRun.run("formula-text", seeds: seeds.map(\.bytes), count: 600,
                                     numberSweep: true, allocations: fileBound) { bytes in
            let formula = try Formula(String(decoding: bytes, as: UTF8.self))
            _ = formula.value(formula.variables.map { _ in 0.5 })
            _ = formula.usesNoise
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }
}
