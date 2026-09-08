import Foundation

// MARK: - A cue

/// A cue: one named set of parameter values, the look a sketch was tuned to
/// at some moment, kept so it can be called back later. `Sketch.saveCue(_:)`
/// writes one from the parameters as they stand and `Sketch.cue(_:over:)`
/// calls it back, at once or over a fade. The values are keyed by parameter
/// name and carried in the form the inspector persists (`ParamStored`), so a
/// cue holds every kind of parameter and survives a reload and a file.
public struct Cue: Codable, Equatable, Sendable {
    /// The name the cue is called by. Unique within a sheet.
    public var name: String
    /// Every parameter's value at the moment the cue was saved, by name.
    public var values: [String: ParamStored]

    public init(name: String, values: [String: ParamStored]) {
        self.name = name
        self.values = values
    }
}

/// The cues a sketch carries, in the order they were saved, and the file they
/// round-trip through: `Sketch.cues.json` beside `Sketch.swift` in the live
/// hosts, or any path a sketch names through `loadCues(from:)` and
/// `saveCues(to:)`. The file is JSON with a version, so a newer sheet is
/// refused rather than misread.
public struct CueSheet: Codable, Equatable, Sendable {
    /// The format this build writes. A file declaring a higher one is refused.
    public static let currentVersion = 1

    public var version: Int
    public var cues: [Cue]

    public init(cues: [Cue] = []) {
        self.version = CueSheet.currentVersion
        self.cues = cues
    }

    /// Where the cue of that name stands in the sheet, or nil.
    public func index(of name: String) -> Int? {
        cues.firstIndex { $0.name == name }
    }

    /// The cue of that name, or nil.
    public subscript(name: String) -> Cue? {
        cues.first { $0.name == name }
    }

    /// Put a cue in: one of the same name is replaced where it stands, a new
    /// name goes at the end.
    public mutating func store(_ cue: Cue) {
        if let i = index(of: cue.name) {
            cues[i] = cue
        } else {
            cues.append(cue)
        }
    }

    /// Take the cue of that name out; nothing happens for a name not in the sheet.
    public mutating func remove(_ name: String) {
        cues.removeAll { $0.name == name }
    }

    /// Why a file could not be read as a sheet.
    public enum LoadError: Error, CustomStringConvertible {
        /// The file declares a format newer than this build writes.
        case newerVersion(Int)

        public var description: String {
            switch self {
            case .newerVersion(let version):
                return "the cue sheet is version \(version), newer than the \(CueSheet.currentVersion) this build reads"
            }
        }
    }

    /// Read a sheet from a JSON file. A version above `currentVersion` is refused.
    public static func load(from path: String) throws -> CueSheet {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let sheet = try JSONDecoder().decode(CueSheet.self, from: data)
        guard sheet.version <= currentVersion else { throw LoadError.newerVersion(sheet.version) }
        return sheet
    }

    /// Write the sheet as JSON, keys sorted so a diff reads well.
    public func write(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Whether two stored values have something between them: numbers, colors,
    /// vectors, rectangles, insets, and ranges fade; a switch, a menu choice, a
    /// piece of text, and a set of colors do not, and a fade jumps them.
    static func canFade(_ a: ParamStored, _ b: ParamStored) -> Bool {
        switch (a, b) {
        case (.number, .number), (.color, .color), (.vector, .vector), (.vector3, .vector3),
             (.rectangle, .rectangle), (.insets, .insets), (.range, .range):
            return true
        default:
            return false
        }
    }
}

/// One way of asking for a cue, the form a host's controls speak: a name, a
/// position in the sheet (a MIDI program change), or a step from the current
/// cue.
public enum CueRequest: Equatable, Sendable {
    case named(String)
    case number(Int)
    case next
    case previous
}

// MARK: - A cue on its way in

/// One cue arriving over a fade: every parameter it names eased from where it
/// stood when the cue was called to the cue's value, slow at both ends. A kind
/// that has nothing between two values takes the cue's value on the first
/// frame, so a switch flips as the fade starts rather than at its end.
final class CueTransition {
    let name: String
    let duration: Double
    private(set) var elapsed = 0.0
    private let steps: [(handle: ParamHandle, from: ParamStored, to: ParamStored)]

    init(name: String, handles: [ParamHandle], values: [String: ParamStored], duration: Double) {
        self.name = name
        self.duration = max(0, duration)
        steps = handles.compactMap { handle in
            guard let to = values[handle.name] else { return nil }
            return (handle, handle.param.stored, to)
        }
    }

    /// Whether the fade has arrived.
    var isFinished: Bool { elapsed >= duration }

    /// How far along, 0…1.
    var progress: Double { duration > 0 ? min(1, elapsed / duration) : 1 }

    /// Move the fade on by a frame and set every parameter where it now stands.
    func advance(by deltaTime: Double) {
        elapsed = min(duration, elapsed + max(0, deltaTime))
        let t = Automation.Curve.easeInOut.shape(progress)
        for step in steps {
            let value = CueSheet.canFade(step.from, step.to)
                ? Automation.blend(step.from, step.to, t)
                : step.to
            step.handle.param.restore(value)
        }
    }
}

// MARK: - The sketch's cues

extension Sketch {

    /// Save the parameters as they stand under `name`: every `@Param` the sketch
    /// declares, with the value it holds this frame. A cue of that name is
    /// replaced where it stands; a new name goes at the end of the sheet. A
    /// blank name saves nothing.
    public func saveCue(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var values: [String: ParamStored] = [:]
        for handle in parameters() { values[handle.name] = handle.param.stored }
        cueSheet.store(Cue(name: trimmed, values: values))
        currentCue = trimmed
    }

    /// Take the cue of that name out of the sheet.
    public func deleteCue(_ name: String) {
        cueSheet.remove(name)
        if currentCue == name { currentCue = nil }
    }

    /// Call the cue of that name: every parameter it names goes to its saved
    /// value, at once with `over` at 0 or eased there over that many seconds,
    /// slow at both ends. A parameter the cue does not name keeps its value; a
    /// name the sketch no longer declares is skipped. Calling a cue while one
    /// is still fading starts the new fade from wherever the parameters are.
    /// Returns false when no cue has that name.
    @discardableResult
    public func cue(_ name: String, over seconds: Double = 0) -> Bool {
        guard let cue = cueSheet[name] else { return false }
        currentCue = cue.name
        if seconds <= 0 {
            cueTransition = nil
            for handle in parameters() {
                if let value = cue.values[handle.name] { handle.param.restore(value) }
            }
        } else {
            cueTransition = CueTransition(name: cue.name, handles: parameters(),
                                          values: cue.values, duration: seconds)
        }
        return true
    }

    /// Call the cue at that position in the sheet, counting from 0. Returns
    /// false when the sheet has no cue there. A MIDI program change calls a
    /// cue by number this way.
    @discardableResult
    public func cue(_ index: Int, over seconds: Double = 0) -> Bool {
        guard cueSheet.cues.indices.contains(index) else { return false }
        return cue(cueSheet.cues[index].name, over: seconds)
    }

    /// Call the cue after the current one, wrapping to the first past the end;
    /// the first cue when none has been called yet. Returns false on an empty sheet.
    @discardableResult
    public func nextCue(over seconds: Double = 0) -> Bool {
        stepCue(by: 1, over: seconds)
    }

    /// Call the cue before the current one, wrapping to the last before the
    /// first; the last cue when none has been called yet. Returns false on an
    /// empty sheet.
    @discardableResult
    public func previousCue(over seconds: Double = 0) -> Bool {
        stepCue(by: -1, over: seconds)
    }

    private func stepCue(by step: Int, over seconds: Double) -> Bool {
        let count = cueSheet.cues.count
        guard count > 0 else { return false }
        let index: Int
        if let current = currentCue, let at = cueSheet.index(of: current) {
            index = ((at + step) % count + count) % count
        } else {
            index = step > 0 ? 0 : count - 1
        }
        return cue(index, over: seconds)
    }

    /// Call a cue the way a control asks for one. Returns false when the sheet
    /// has nothing to answer with.
    @discardableResult
    public func cue(_ request: CueRequest, over seconds: Double = 0) -> Bool {
        switch request {
        case .named(let name): return cue(name, over: seconds)
        case .number(let index): return cue(index, over: seconds)
        case .next: return nextCue(over: seconds)
        case .previous: return previousCue(over: seconds)
        }
    }

    /// Whether a cue is still fading in.
    public var isCueFading: Bool { cueTransition.map { !$0.isFinished } ?? false }

    /// Read a cue sheet from a JSON file and carry it from here on, replacing
    /// whatever the sketch held. The live hosts do this with `Sketch.cues.json`
    /// beside the sketch; a sketch running on its own names its file here.
    public func loadCues(from path: String) throws {
        cueSheet = try CueSheet.load(from: path)
    }

    /// Write the cue sheet to a JSON file.
    public func saveCues(to path: String) throws {
        try cueSheet.write(to: path)
    }

    /// Move a running fade on by a frame. Called from the frame advance.
    func advanceCue(by deltaTime: Double) {
        guard let transition = cueTransition else { return }
        transition.advance(by: deltaTime)
        if transition.isFinished { cueTransition = nil }
    }
}
