import Foundation
import Ollin
import Testing
@testable import OllinVision

/// What steadying does to a recording, in numbers. Shared by the tests, which
/// hold the numbers to bounds, and by the report below, which prints them for
/// a grid of settings.
struct SteadiedMeasure {

    /// The canvas the measures are stated on, in pixels across.
    static let canvas = 1080.0
    /// Frames the sketch draws a second.
    static let drawRate = 60.0

    /// The largest step any point of any showing thing takes between two
    /// drawn frames, in canvas pixels, one value a drawn frame.
    var steps: [Double] = []
    /// How many things appeared over the run, and how many were let go.
    var appeared = 0
    var letGo = 0
    /// Things showing, summed over the drawn frames.
    var shownFrames = 0
    var drawnFrames = 0
    /// Each drawn frame's showing things, by number, at their steadied points.
    var history: [[Int: [Vector2]]] = []
    /// Each thing's own steps, one a drawn frame it was showing.
    var stepsByThing: [Int: [Double]] = [:]
    /// How far each showing thing sat from where it was last found, in canvas
    /// pixels, one value a thing a drawn frame it was being found.
    var behind: [Double] = []

    /// How far a thing's outline moved between two frames, in canvas pixels:
    /// the farthest any corner went. An outline whose corners are the same
    /// points named in another order has not moved, so the corners are
    /// compared at whichever turn brings them nearest.
    static func step(from a: [Vector2], to b: [Vector2]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var least = Double.infinity
        for turn in 0..<(a.count > 2 ? a.count : 1) {
            var far = 0.0
            for i in a.indices {
                let other = b[(i + turn) % b.count]
                far = max(far, abs(a[i].x - other.x) * canvas, abs(a[i].y - other.y) * canvas)
            }
            least = min(least, far)
        }
        return least
    }

    func quantile(_ p: Double) -> Double {
        let sorted = steps.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
    }

    /// Runs `frames` through a steadier the way a sketch would: every analysis
    /// read for as many drawn frames as fit between two of them.
    static func run<Thing: Steadiable>(_ frames: [[Thing]], rate: Double,
                                       steadier: Steadier<Thing>, skip: Int = 0) -> SteadiedMeasure {
        var steadier = steadier
        var measure = SteadiedMeasure()
        let hold = max(1, Int((drawRate / rate).rounded()))
        var before: [Int: [Vector2]] = [:]
        for (index, found) in frames.enumerated() {
            for _ in 0..<hold {
                let things = steadier.steady(found, deltaTime: 1 / drawRate)
                var now: [Int: [Vector2]] = [:]
                for thing in things { now[thing.id] = thing.value.steadyPoints }
                if index >= skip {
                    for thing in things where thing.unseenFor == 0 {
                        measure.behind.append(step(from: thing.found.steadyPoints, to: thing.value.steadyPoints))
                    }
                    var step = 0.0
                    for (id, points) in now {
                        guard let last = before[id] else { continue }
                        let moved = Self.step(from: last, to: points)
                        measure.stepsByThing[id, default: []].append(moved)
                        step = max(step, moved)
                    }
                    if !now.isEmpty { measure.steps.append(step) }
                    measure.appeared += now.keys.filter { before[$0] == nil }.count
                    measure.letGo += before.keys.filter { now[$0] == nil }.count
                    measure.shownFrames += now.count
                    measure.drawnFrames += 1
                    measure.history.append(now)
                }
                before = now
            }
        }
        return measure
    }

    /// The same measures for the findings as they are: each finding matched
    /// to the nearest of the frame before by overlap, with no memory.
    static func raw<Thing: Steadiable>(_ frames: [[Thing]], rate: Double, skip: Int = 0) -> SteadiedMeasure {
        let passThrough = Steadier<Thing>(Steadiness(appearDelay: 0, holdTime: 0, minConfidence: 0,
                                                     minKeptConfidence: 0, minOverlap: 0.2, minCutoff: 1e6, beta: 0))
        return run(frames, rate: rate, steadier: passThrough, skip: skip)
    }
}

/// Prints the measures for a grid of settings. Runs only when asked:
///
///     OLLIN_STEADY_REPORT="1,5,0.1,0.3;1,10,0.1,0.3" Scripts/test.sh SteadiedReport
///
/// Each group is `minCutoff,beta`, then optionally `appearDelay`, `holdTime`,
/// `minOverlap` and `minKeptOverlap`, which are the type's own when left out.
/// `OLLIN_STEADY_REPORT_THINGS` adds a line for each thing.
@Suite struct SteadiedReport {
    static let grid = ProcessInfo.processInfo.environment["OLLIN_STEADY_REPORT"]
    static let folder = ProcessInfo.processInfo.environment["OLLIN_STEADY_RECORDINGS"]

    static func steadiness(_ values: [Double], _ own: Steadiness) -> Steadiness {
        var steadiness = own
        steadiness.minCutoff = values[0]
        steadiness.beta = values[1]
        if values.count > 2 { steadiness.appearDelay = values[2] }
        if values.count > 3 { steadiness.holdTime = values[3] }
        if values.count > 4 { steadiness.minOverlap = values[4] }
        if values.count > 5 { steadiness.minKeptOverlap = values[5] }
        return steadiness
    }

    /// Writes each recording's steadied things, a drawn frame at a time, for
    /// a picture of what steadying does. Runs only when asked:
    ///
    ///     OLLIN_STEADY_DUMP=<folder> Scripts/test.sh SteadiedReport
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_STEADY_DUMP"] != nil))
    func writesWhatWasSteadied() throws {
        let out = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OLLIN_STEADY_DUMP"]))
        let folder = Self.folder.map { URL(fileURLWithPath: $0) } ?? SteadiedRecording.folder
        struct Shown: Codable { var id: Int; var l: String; var p: [Double]; var a: Double }
        struct Dump: Codable { var rate: Double; var frames: [[Shown]] }
        func dump<Thing: Steadiable>(_ name: String, _ frames: [[Thing]], rate: Double, label: (Thing) -> String) throws {
            var steadier = Steadier<Thing>()
            var dump = Dump(rate: SteadiedMeasure.drawRate, frames: [])
            for found in frames {
                for _ in 0..<Int(SteadiedMeasure.drawRate / rate) {
                    let things = steadier.steady(found, deltaTime: 1 / SteadiedMeasure.drawRate)
                    dump.frames.append(things.map {
                        Shown(id: $0.id, l: label($0.value), p: $0.value.steadyPoints.flatMap { [$0.x, $0.y] },
                              a: 1 - $0.unseenFor / steadier.steadiness.holdTime)
                    })
                }
            }
            try JSONEncoder().encode(dump).write(to: out.appendingPathComponent("\(name)-steady.json"))
        }
        for name in ["objects-quiet", "objects-noisy", "objects-film", "rectangles-quiet", "rectangles-noisy"] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).json")) else { continue }
            let recording = try JSONDecoder().decode(SteadiedRecording.self, from: data)
            if name.hasPrefix("objects") {
                try dump(name, recording.frames.map { $0.map(\.detection) }, rate: recording.rate) { $0.label }
            } else {
                try dump(name, recording.frames.map { $0.map(\.rectangle) }, rate: recording.rate) { _ in "" }
            }
        }
    }

    @Test(.enabled(if: grid != nil)) func printsTheGrid() throws {
        let folder = Self.folder.map { URL(fileURLWithPath: $0) } ?? SteadiedRecording.folder
        func load(_ name: String) throws -> SteadiedRecording {
            try JSONDecoder().decode(SteadiedRecording.self,
                                     from: Data(contentsOf: folder.appendingPathComponent("\(name).json")))
        }
        var lines: [String] = []
        func line<Thing: Steadiable>(_ name: String, _ frames: [[Thing]], rate: Double, _ steadier: Steadier<Thing>?) {
            let m = steadier.map { SteadiedMeasure.run(frames, rate: rate, steadier: $0, skip: 15) }
                ?? SteadiedMeasure.raw(frames, rate: rate, skip: 15)
            let behind = m.behind.sorted()
            func at(_ p: Double) -> Double { behind.isEmpty ? 0 : behind[min(behind.count - 1, Int(Double(behind.count) * p))] }
            lines.append(String(format: "  %@ step med %.2f p95 %.2f p99 %.2f max %.1f px | appeared %d let go %d | showing %.2f a frame | behind med %.1f p95 %.1f max %.1f px",
                                name.padding(toLength: 18, withPad: " ", startingAt: 0),
                                m.quantile(0.5), m.quantile(0.95), m.quantile(0.99), m.steps.max() ?? 0,
                                m.appeared, m.letGo, Double(m.shownFrames) / Double(max(1, m.drawnFrames)),
                                at(0.5), at(0.95), behind.last ?? 0))
            if ProcessInfo.processInfo.environment["OLLIN_STEADY_REPORT_THINGS"] != nil {
                for (id, steps) in m.stepsByThing.sorted(by: { $0.key < $1.key }) {
                    let sorted = steps.sorted()
                    lines.append(String(format: "      thing %d: %d frames, step med %.2f p95 %.2f max %.1f px", id, steps.count,
                                        sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last ?? 0))
                }
            }
        }
        let names = ["objects-quiet", "objects-noisy", "objects-film", "rectangles-quiet", "rectangles-noisy"]
        var settings: [[Double]?] = [nil]
        settings += try #require(Self.grid).split(separator: ";").map { $0.split(separator: ",").compactMap { Double($0) } }
        for setting in settings {
            lines.append(setting.map { "minCutoff \($0[0]) beta \($0[1]), then the type's own unless given: appearDelay \($0.count > 2 ? "\($0[2])" : "own") holdTime \($0.count > 3 ? "\($0[3])" : "own") minOverlap \($0.count > 4 ? "\($0[4])" : "own") minKeptOverlap \($0.count > 5 ? "\($0[5])" : "own")" } ?? "as found")
            for name in names {
                guard let recording = try? load(name) else { continue }
                if name.hasPrefix("objects") {
                    let frames = recording.frames.map { $0.map(\.detection) }
                    line(name, frames, rate: recording.rate, setting.map {
                        Steadier<Detection>(Self.steadiness($0, Detection.steadiness))
                    })
                } else {
                    let frames = recording.frames.map { $0.map(\.rectangle) }
                    line(name, frames, rate: recording.rate, setting.map {
                        Steadier<DetectedRectangle>(Self.steadiness($0, DetectedRectangle.steadiness))
                    })
                }
            }
        }
        FileHandle.standardError.write(Data(("STEADY REPORT\n" + lines.joined(separator: "\n") + "\n").utf8))
    }
}
