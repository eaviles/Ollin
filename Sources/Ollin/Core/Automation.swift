import Foundation

/// A sketch's parameters written down over time: a value placed at one moment,
/// another placed later, and a curve that carries the first into the second.
/// Where `@Param` gives a sketch a parameter to adjust, an automation moves it, so a
/// piece can be *directed* rather than only tuned.
///
/// Write the tracks in `setup()`, one per parameter:
///
/// ```swift
/// final class Breathing: Sketch {
///     @Param(20...400) var radius = 120.0
///
///     override func setup() {
///         automate($radius) { track in
///             track.key(at: 0, 40)
///             track.key(at: 2, 320, curve: .easeInOut)
///             track.key(at: 4, 40)
///         }
///         automation?.loops = true
///     }
/// }
/// ```
///
/// Each frame, before the sketch draws, every track sets its parameter to the value
/// its curve holds at the sketch clock. The value is set directly rather than
/// eased into, so a parameter that carries `smoothing:` does not glide twice: the
/// curve is the glide.
///
/// The position is a plain reading of the clock, `start + time * speed`, so
/// `speed: 2` runs the whole thing twice as fast and `speed: -1` (with `start`
/// at the duration) runs it backwards. With `loops` on, the position wraps at
/// the duration. Because the exports drive the clock at a fixed step, an
/// automated run renders exactly as it played.
///
/// An automation is a plain codable value, so it also reads and writes as a
/// file (`--automation <file>` attaches one to a standalone run or to any
/// export). See `Docs/Core/Automation.md`.
public struct Automation: Codable, Equatable, Sendable {

    /// The shape of the file. It moves when the layout does. A file written by
    /// an *older* Ollin still reads, because every layout so far only added to
    /// the one before it; a file written by a *newer* one is refused rather
    /// than guessed at, since this Ollin cannot know what it left out.
    ///
    /// Version 2 added a track that carries a ``Formula`` in place of keys.
    /// Version 3 added a track that carries one formula for each part of a
    /// parameter that holds more than one number.
    public static let currentVersion = 3

    // MARK: Curves

    /// How a key's value travels to the next key's value.
    public enum Curve: Codable, Equatable, Sendable {
        /// Stay at this key's value until the next key, then jump.
        case hold
        /// A straight line.
        case linear
        /// Start slowly, arrive fast.
        case easeIn
        /// Start fast, arrive slowly.
        case easeOut
        /// Slow at both ends, fast through the middle.
        case easeInOut
        /// A unit cubic Bezier through two handle points, the timing curve an
        /// editor draws. The handles' `x` stays inside `0...1` so the curve
        /// reads left to right; `y` may travel outside it, which overshoots.
        case bezier(x1: Double, y1: Double, x2: Double, y2: Double)

        /// Shape a `0...1` progress between two keys.
        public func shape(_ progress: Double) -> Double {
            let t = Swift.min(Swift.max(progress, 0), 1)
            switch self {
            case .hold: return 0
            case .linear: return t
            case .easeIn: return Easing.easeIn(t)
            case .easeOut: return Easing.easeOut(t)
            case .easeInOut: return Easing.easeInOut(t)
            case .bezier(let x1, let y1, let x2, let y2):
                return Curve.bezier(t, x1: x1, y1: y1, x2: x2, y2: y2)
            }
        }

        /// The unit cubic Bezier from (0,0) to (1,1) read as a timing curve:
        /// find the parameter whose x is `t`, then answer with its y. Newton
        /// converges in a few passes over most of the curve; where the slope
        /// goes flat it hands over to bisection, which always closes in.
        private static func bezier(_ t: Double, x1: Double, y1: Double,
                                   x2: Double, y2: Double) -> Double {
            let x1 = Swift.min(Swift.max(x1, 0), 1)
            let x2 = Swift.min(Swift.max(x2, 0), 1)
            if x1 == y1, x2 == y2 { return t }          // the identity curve
            func axis(_ a: Double, _ b: Double, _ u: Double) -> Double {
                let v = 1 - u
                return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
            }
            func slope(_ a: Double, _ b: Double, _ u: Double) -> Double {
                let v = 1 - u
                return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
            }
            var u = t
            for _ in 0..<8 {
                let error = axis(x1, x2, u) - t
                if Swift.abs(error) < 1e-9 { return axis(y1, y2, u) }
                let d = slope(x1, x2, u)
                if Swift.abs(d) < 1e-6 { break }
                u -= error / d
            }
            var low = 0.0, high = 1.0
            u = t
            for _ in 0..<40 {
                let x = axis(x1, x2, u)
                if Swift.abs(x - t) < 1e-9 { break }
                if x < t { low = u } else { high = u }
                u = (low + high) / 2
            }
            return axis(y1, y2, u)
        }
    }

    // MARK: Keys and tracks

    /// One value placed at one moment, and the curve that leaves it.
    public struct Key: Codable, Equatable, Sendable {
        /// Seconds from the start of the automation.
        public var time: Double
        /// The parameter's value at that moment.
        public var value: ParamStored
        /// How the value travels to the next key. The last key's curve is
        /// never read.
        public var curve: Curve

        public init(at time: Double, _ value: ParamStored, curve: Curve = .easeInOut) {
            self.time = time
            self.value = value
            self.curve = curve
        }
    }

    /// One parameter's keys, in time order. A track may instead carry a
    /// ``Formula``, and then the parameter is worked out rather than looked up.
    public struct Track: Codable, Equatable, Sendable {
        /// The `@Param` property name this track drives.
        public var name: String
        /// The keys, always sorted by time. Two keys at the same moment keep
        /// the order they were given in, so the later one wins from there on.
        public private(set) var keys: [Key]
        /// A formula worked out every frame, in place of the keys. It reads
        /// `time` (the position in the automation), the canvas and the pointer,
        /// and the sketch's other parameters by name.
        public var formula: Formula?
        /// One formula for each part of a parameter that holds more than one number
        /// (`x` and `y` for a point, `red` for a color), keyed by the part
        /// name. A part with no rule keeps whatever the parameter holds, so a track
        /// can drive one part and leave the rest to the hand.
        public private(set) var parts: [String: Formula]

        public init(name: String, keys: [Key]) {
            self.name = name
            self.keys = keys.enumerated()
                .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
                .map(\.element)
            self.formula = nil
            self.parts = [:]
        }

        /// A track that works its parameter out from a formula rather than from
        /// placed keys.
        public init(name: String, formula: Formula) {
            self.name = name
            self.keys = []
            self.formula = formula
            self.parts = [:]
        }

        /// A track that works some parts of its parameter out from formulas. Each
        /// part is named the way ``Automation/parts(of:)`` names it, and a part
        /// with no formula is left alone.
        public init(name: String, parts: [String: Formula]) {
            self.name = name
            self.keys = []
            self.formula = nil
            self.parts = parts
        }

        /// When the last key falls. A formula has no length of its own, so a
        /// formula track answers zero and leans on the automation's `length`.
        public var duration: Double { keys.last?.time ?? 0 }

        /// The value this track holds at `position`, or `nil` when it carries
        /// neither keys nor a formula. A track of parts has no whole value of
        /// its own, so it answers `nil`; ask ``partValues(at:reading:noise:)``
        /// for its numbers and put them into the parameter's own value with
        /// ``Automation/applying(_:to:)``.
        ///
        /// A formula reads `time` as `position`, whatever else the caller
        /// passes under that name, so a track always agrees with the clock that
        /// drives it. It answers a plain number; the player turns that into a
        /// switch when the parameter it drives is one.
        public func value(at position: Double,
                          reading values: [String: Double] = [:],
                          noise: Formula.NoiseField? = nil) -> ParamStored? {
            if let formula {
                var values = values
                values["time"] = position
                return .number(formula.value(values, noise: noise))
            }
            guard let first = keys.first, let last = keys.last else { return nil }
            if position <= first.time { return first.value }
            if position >= last.time { return last.value }
            var index = 0
            while index + 1 < keys.count, keys[index + 1].time <= position { index += 1 }
            let from = keys[index], to = keys[index + 1]
            let span = to.time - from.time
            guard span > 0 else { return to.value }
            return Automation.blend(from.value, to.value,
                                    from.curve.shape((position - from.time) / span))
        }

        /// The numbers this track's parts hold at `position`, keyed by the
        /// part name, and empty when the track carries no part formulas. Every
        /// part reads `time` as `position`, exactly as a whole-parameter formula
        /// does, so a track always agrees with the clock that drives it.
        public func partValues(at position: Double,
                               reading values: [String: Double] = [:],
                               noise: Formula.NoiseField? = nil) -> [String: Double] {
            guard !parts.isEmpty else { return [:] }
            var values = values
            values["time"] = position
            return parts.mapValues { $0.value(values, noise: noise) }
        }

        /// Whether anything here is worked out rather than looked up.
        var isWorkedOut: Bool { formula != nil || !parts.isEmpty }

        /// Whether any formula here reads a noise field.
        var usesNoise: Bool {
            formula?.usesNoise == true || parts.values.contains(where: \.usesNoise)
        }

        /// Every name the formulas here read, the whole-parameter one and the parts
        /// together, in a fixed order. The order is fixed on purpose: a plan
        /// built from these names must be a function of the tracks, and never
        /// of the way a dictionary happened to be walked.
        var readNames: [String] {
            var names = formula?.variables ?? []
            for part in parts.keys.sorted() { names += parts[part]?.variables ?? [] }
            return names
        }

        private enum CodingKeys: String, CodingKey { case name, keys, formula, parts }

        /// A formula travels as the text it was written as, so the file stays
        /// readable and a person can edit it there.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = try container.decode(String.self, forKey: .name)
            if let source = try container.decodeIfPresent(String.self, forKey: .formula) {
                do {
                    self.init(name: name, formula: try Formula(source))
                } catch let error as FormulaError {
                    throw DecodingError.dataCorruptedError(
                        forKey: .formula, in: container,
                        debugDescription: "the formula driving '\(name)' cannot be read: \(error)")
                }
                return
            }
            if let sources = try container.decodeIfPresent([String: String].self, forKey: .parts) {
                var parts: [String: Formula] = [:]
                for (part, source) in sources {
                    do {
                        parts[part] = try Formula(source)
                    } catch let error as FormulaError {
                        throw DecodingError.dataCorruptedError(
                            forKey: .parts, in: container,
                            debugDescription:
                                "the rule driving '\(name).\(part)' cannot be read: \(error)")
                    }
                }
                self.init(name: name, parts: parts)
                return
            }
            self.init(name: name,
                      keys: try container.decodeIfPresent([Key].self, forKey: .keys) ?? [])
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            if let formula {
                try container.encode(formula.source, forKey: .formula)
            } else if !parts.isEmpty {
                try container.encode(parts.mapValues(\.source), forKey: .parts)
            } else {
                try container.encode(keys, forKey: .keys)
            }
        }
    }

    // MARK: The automation itself

    public var version: Int
    /// One track per automated parameter, keyed by the property name.
    public var tracks: [Track]
    /// Whether the position wraps at `duration` instead of holding the last key.
    public var loops: Bool
    /// How fast the clock reads. `2` runs it twice as fast; a negative speed
    /// runs it backwards, which wants `start` at the duration.
    public var speed: Double
    /// The position at sketch time zero.
    public var start: Double
    /// The length of one pass, or `nil` to run to the last key of the longest
    /// track. Set it to hold past the last key before a loop comes around.
    public var length: Double?

    public init(tracks: [Track] = [], loops: Bool = false, speed: Double = 1,
                start: Double = 0, length: Double? = nil) {
        self.version = Automation.currentVersion
        self.tracks = tracks
        self.loops = loops
        self.speed = speed
        self.start = start
        self.length = length
    }

    /// One pass, in seconds.
    public var duration: Double { length ?? tracks.map(\.duration).max() ?? 0 }

    /// Where the automation stands when the sketch clock reads `time`.
    public func position(at time: Double) -> Double {
        let raw = start + time * speed
        guard loops, duration > 0 else { return raw }
        let wrapped = raw.truncatingRemainder(dividingBy: duration)
        return wrapped < 0 ? wrapped + duration : wrapped
    }

    /// The track driving `name`, if there is one.
    public func track(named name: String) -> Track? {
        tracks.first { $0.name == name }
    }

    /// Add a track, replacing any track already driving the same parameter.
    public mutating func setTrack(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.name == track.name }) {
            tracks[index] = track
        } else {
            tracks.append(track)
        }
    }

    /// The value `name` holds at sketch time `time`, or `nil` when nothing
    /// drives it.
    public func value(of name: String, at time: Double) -> ParamStored? {
        track(named: name)?.value(at: position(at: time))
    }

    // MARK: Blending

    /// Blend two stored values. The numeric kinds interpolate component by
    /// component and colors take the even path a fade wants; a switch, a menu
    /// choice, a piece of text, and a set of colors have nothing between two
    /// values, so they hold the one they left until the next key. Two values
    /// of different kinds hold as well.
    static func blend(_ from: ParamStored, _ to: ParamStored, _ t: Double) -> ParamStored {
        if t <= 0 { return from }
        if t >= 1 { return to }
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        switch (from, to) {
        case (.number(let a), .number(let b)):
            return .number(lerp(a, b))
        case (.color(let ar, let ag, let ab, let aa), .color(let br, let bg, let bb, let ba)):
            let mixed = Color.mix(Color(red: ar, green: ag, blue: ab, alpha: aa),
                                  Color(red: br, green: bg, blue: bb, alpha: ba), t)
            return .color(red: mixed.red, green: mixed.green, blue: mixed.blue, alpha: mixed.alpha)
        case (.vector(let ax, let ay), .vector(let bx, let by)):
            return .vector(x: lerp(ax, bx), y: lerp(ay, by))
        case (.vector3(let ax, let ay, let az), .vector3(let bx, let by, let bz)):
            return .vector3(x: lerp(ax, bx), y: lerp(ay, by), z: lerp(az, bz))
        case (.rectangle(let ax, let ay, let aw, let ah), .rectangle(let bx, let by, let bw, let bh)):
            return .rectangle(x: lerp(ax, bx), y: lerp(ay, by),
                         width: lerp(aw, bw), height: lerp(ah, bh))
        case (.insets(let at, let ar, let ab, let al), .insets(let bt, let br, let bb, let bl)):
            return .insets(top: lerp(at, bt), right: lerp(ar, br),
                           bottom: lerp(ab, bb), left: lerp(al, bl))
        case (.range(let al, let au), .range(let bl, let bu)):
            return .range(lower: lerp(al, bl), upper: lerp(au, bu))
        default:
            return from
        }
    }

    // MARK: The parts of a parameter

    /// The numbers a stored value is made of, keyed by the part name: `x` and
    /// `y` for a point, `x`, `y`, `z` for a point in space, `red`, `green`,
    /// `blue`, `alpha` for a color, `x`, `y`, `width`, `height` for a
    /// rectangle, `top`, `right`, `bottom`, `left` for insets, and `lower`,
    /// `upper` for a pair of ends. A plain number, a switch, a menu choice, a
    /// piece of text, and a set of colors have no parts.
    public static func parts(of stored: ParamStored) -> [String: Double] {
        switch stored {
        case .color(let red, let green, let blue, let alpha):
            return ["red": red, "green": green, "blue": blue, "alpha": alpha]
        case .vector(let x, let y):
            return ["x": x, "y": y]
        case .vector3(let x, let y, let z):
            return ["x": x, "y": y, "z": z]
        case .rectangle(let x, let y, let width, let height):
            return ["x": x, "y": y, "width": width, "height": height]
        case .insets(let top, let right, let bottom, let left):
            return ["top": top, "right": right, "bottom": bottom, "left": left]
        case .range(let lower, let upper):
            return ["lower": lower, "upper": upper]
        case .number, .boolean, .option, .text, .colors:
            return [:]
        }
    }

    /// Put worked-out numbers back into a stored value. A part with no number
    /// keeps what it had, so a rule for `x` alone leaves `y` where the hand
    /// left it.
    ///
    /// A pair of ends stays ordered, because a crossed pair is not a value the
    /// parameter can hold at all. The lower end wins and the upper end is lifted to
    /// meet it, which is what the parameter's own two-thumb slider does when a
    /// minimum is pushed past its maximum.
    public static func applying(_ parts: [String: Double],
                                to stored: ParamStored) -> ParamStored {
        guard !parts.isEmpty else { return stored }
        func number(_ part: String, _ current: Double) -> Double { parts[part] ?? current }
        switch stored {
        case .color(let red, let green, let blue, let alpha):
            return .color(red: number("red", red), green: number("green", green),
                          blue: number("blue", blue), alpha: number("alpha", alpha))
        case .vector(let x, let y):
            return .vector(x: number("x", x), y: number("y", y))
        case .vector3(let x, let y, let z):
            return .vector3(x: number("x", x), y: number("y", y), z: number("z", z))
        case .rectangle(let x, let y, let width, let height):
            return .rectangle(x: number("x", x), y: number("y", y),
                         width: number("width", width), height: number("height", height))
        case .insets(let top, let right, let bottom, let left):
            return .insets(top: number("top", top), right: number("right", right),
                           bottom: number("bottom", bottom), left: number("left", left))
        case .range(let lower, let upper):
            let low = number("lower", lower)
            return .range(lower: low, upper: Swift.max(low, number("upper", upper)))
        case .number, .boolean, .option, .text, .colors:
            return stored
        }
    }

    /// The parameter a name reaches, which is the whole name for a plain parameter and
    /// the part before the dot for one of a parameter's parts.
    static func baseName(of name: String) -> String {
        String(name.prefix { $0 != "." })
    }

    // MARK: Reading and writing

    /// Read an automation from disk. Throws when the file is unreadable, is
    /// not an automation, or was written in a different format version.
    public static func load(from url: URL) throws -> Automation {
        let automation = try JSONDecoder().decode(Automation.self, from: Data(contentsOf: url))
        guard automation.version <= currentVersion else {
            throw AutomationError.incompatibleVersion(automation.version)
        }
        return automation
    }

    /// Write the automation, atomically, as sorted JSON.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    // MARK: Building a track in code

    /// Collects one parameter's keys in the sketch's own value type, so a track is
    /// written as the numbers the sketch already speaks rather than as stored
    /// payloads. Handed to the closure of `Sketch.automate(_:_:)`.
    public struct TrackBuilder<Value: ParamValue> {
        public private(set) var keys: [Key] = []

        /// Place `value` at `time`, and give the curve that leaves it.
        public mutating func key(at time: Double, _ value: Value, curve: Curve = .easeInOut) {
            keys.append(Key(at: time, Value.stored(value), curve: curve))
        }

        /// Place `value` at `time` and hold it there until the next key.
        public mutating func hold(at time: Double, _ value: Value) {
            key(at: time, value, curve: .hold)
        }
    }
}

public enum AutomationError: Error, CustomStringConvertible {
    case incompatibleVersion(Int)

    public var description: String {
        switch self {
        case .incompatibleVersion(let version):
            return "this automation was written in format version \(version); "
                + "this Ollin reads version \(Automation.currentVersion) and earlier"
        }
    }
}

// MARK: - Playback

/// Drives a sketch's parameters from an automation. `Sketch.advance` hands it the
/// clock the frame is about to draw at, before the frame draws and before a
/// take recorder samples the parameters, so a recorded run writes down the values
/// the automation actually held. Attached by `Sketch.automation`; a sketch
/// never touches it.
@MainActor
final class AutomationPlayer {

    var automation: Automation {
        didSet {
            plan = nil
            toldAboutRings = false      // a new set of tracks is worth a new word
        }
    }
    /// The parameter handles, walked once: the `@Param` set of a sketch is
    /// fixed, and reflecting over the instance every frame would cost real time.
    private var handles: [String: any AnyParam]?
    /// The order to apply the tracks in, worked out once per set of tracks.
    private var plan: Plan?
    private var toldAboutRings = false

    init(_ automation: Automation) {
        self.automation = automation
    }

    /// The order the tracks apply in, and the ones that cannot play.
    private struct Plan {
        var order: [Int]
        var rings: [String]
        var readsFormulas: Bool
        var readsNoise: Bool
    }

    /// Set every automated parameter to the value its track holds at `time`.
    func apply(to sketch: Sketch, at time: Double) {
        guard !automation.tracks.isEmpty else { return }
        let handles = self.handles ?? {
            var found: [String: any AnyParam] = [:]
            for handle in sketch.parameters() { found[handle.name] = handle.param }
            self.handles = found
            return found
        }()
        let position = automation.position(at: time)
        let plan = self.plan ?? {
            let made = AutomationPlayer.plan(for: automation)
            self.plan = made
            return made
        }()
        if !plan.rings.isEmpty, !toldAboutRings {
            toldAboutRings = true
            FileHandle.standardError.write(Data(
                ("Ollin: \(plan.rings.joined(separator: ", ")) are worked out from each other, "
                 + "which cannot settle on one frame; they are left alone\n").utf8))
        }
        // The numbers a formula reads are this frame's, and they are read as
        // each track sets them, in an order where a parameter worked out from
        // another lands after the one it names. That is what keeps a formula a
        // plain function of the clock: the same time gives the same value at
        // any frame rate, which is the promise the exports rest on.
        var values = plan.readsFormulas
            ? AutomationPlayer.reading(sketch, handles: handles) : [:]
        let noise = plan.readsNoise ? sketch.noiseField() : nil
        for index in plan.order {
            let track = automation.tracks[index]
            guard let param = handles[track.name] else { continue }
            var value: ParamStored
            if !track.parts.isEmpty {
                // A parameter of more than one number takes a rule for each part,
                // and the parts no rule names keep what the parameter holds, so a
                // rule for `x` alone leaves `y` to the hand.
                value = Automation.applying(
                    track.partValues(at: position, reading: values, noise: noise),
                    to: param.stored)
            } else if let whole = track.value(at: position, reading: values, noise: noise) {
                value = whole
            } else {
                continue
            }
            // A formula answers a number. A switch reads that number as on when
            // it is anything but zero, which is the only way a formula can
            // drive one.
            if case .number(let v) = value, case .boolean = param.stored {
                value = .boolean(FormulaNode.isTrue(v))
            }
            param.restore(value)
            // Read the parameter back rather than trusting the number: a parameter holds
            // its own range, so what the next formula names is what the sketch
            // will actually see.
            guard plan.readsFormulas else { continue }
            switch param.stored {
            case .number(let v): values[track.name] = v
            case .boolean(let v): values[track.name] = v ? 1 : 0
            default:
                for (part, number) in Automation.parts(of: param.stored) {
                    values["\(track.name).\(part)"] = number
                }
            }
        }
    }

    /// Work out the order to apply the tracks in. A track whose formula names
    /// another track's parameter goes after it, so both land on the same frame's
    /// numbers. Names that lead back to themselves cannot all be settled on one
    /// frame, so the whole ring is dropped and reported rather than played at a
    /// value that would depend on the frame rate.
    ///
    /// Depth-first over the tracks in the order they were given, so the plan is
    /// a function of the tracks and never of the order they happened to arrive.
    private static func plan(for automation: Automation) -> Plan {
        let tracks = automation.tracks
        var indexOf: [String: Int] = [:]
        for (i, track) in tracks.enumerated() where indexOf[track.name] == nil { indexOf[track.name] = i }

        var order: [Int] = []
        var rings: Set<String> = []
        var state = [Int](repeating: 0, count: tracks.count)   // 0 unvisited, 1 on the path, 2 done

        func visit(_ i: Int, path: inout [Int]) {
            if state[i] == 2 { return }
            if state[i] == 1 {                                  // the path came back here
                if let start = path.firstIndex(of: i) {
                    for j in path[start...] { rings.insert(tracks[j].name) }
                }
                return
            }
            state[i] = 1
            path.append(i)
            for name in tracks[i].readNames {
                // A built-in name is never a parameter, so it never orders anything.
                guard !Automation.readableNames.contains(name) else { continue }
                // A part names the parameter it belongs to, so `center.x` orders the
                // track driving `center`.
                guard let j = indexOf[Automation.baseName(of: name)] else { continue }
                visit(j, path: &path)
            }
            path.removeLast()
            state[i] = 2
            order.append(i)
        }

        for i in tracks.indices {
            var path: [Int] = []
            visit(i, path: &path)
        }
        let playable = order.filter { !rings.contains(tracks[$0].name) }
        return Plan(order: playable,
                    rings: rings.sorted(),
                    readsFormulas: tracks.contains(where: \.isWorkedOut),
                    readsNoise: tracks.contains(where: \.usesNoise))
    }

    /// The numbers a formula may name: the sketch's own clock and canvas, the
    /// pointer, every parameter that is a plain number or a switch, and every part
    /// of a parameter that holds more than one (`center.x`).
    ///
    /// The built-in names win over a parameter of the same spelling, so a formula can
    /// always depend on what `time` and `width` mean. `frame` is the number the
    /// frame about to be drawn will carry, because this runs before the sketch
    /// steps its counter.
    private static func reading(_ sketch: Sketch,
                                handles: [String: any AnyParam]) -> [String: Double] {
        var values: [String: Double] = [:]
        for (name, param) in handles {
            switch param.stored {
            case .number(let v): values[name] = v
            case .boolean(let v): values[name] = v ? 1 : 0
            default:
                for (part, number) in Automation.parts(of: param.stored) {
                    values["\(name).\(part)"] = number
                }
            }
        }
        values["frame"] = Double(sketch.frameCount + 1)
        values["width"] = sketch.width
        values["height"] = sketch.height
        values["mouseX"] = sketch.mouseX
        values["mouseY"] = sketch.mouseY
        return values
    }
}

// MARK: - The sketch surface

public extension Sketch {

    /// The automation driving this sketch's parameters, or `nil` when none is
    /// attached. Assign one read from a file, or build the tracks with
    /// `automate(_:_:)`; reach through it to change how it plays
    /// (`automation?.loops = true`).
    var automation: Automation? {
        get { automationPlayer?.automation }
        set {
            guard let newValue else {
                automationPlayer = nil
                return
            }
            // Keep the player when there already is one: it caches the
            // parameter handles, and rebuilding it would walk the mirror again.
            if let player = automationPlayer {
                player.automation = newValue
            } else {
                automationPlayer = AutomationPlayer(newValue)
            }
        }
    }

    /// Write one parameter's values down over time. The closure places the keys, in
    /// the parameter's own type:
    ///
    /// ```swift
    /// automate($radius) { track in
    ///     track.key(at: 0, 40)
    ///     track.key(at: 2, 320, curve: .easeInOut)
    /// }
    /// ```
    ///
    /// Calling it again for the same parameter replaces that parameter's track. A
    /// property that is not a `@Param` on this sketch cannot be named, so it
    /// is reported and left alone.
    func automate<Value: ParamValue>(_ param: Param<Value>,
                                     _ build: (inout Automation.TrackBuilder<Value>) -> Void) {
        guard let name = parameterName(of: param) else {
            FileHandle.standardError.write(Data(
                "Ollin: automate() was handed a parameter this sketch does not declare\n".utf8))
            return
        }
        var builder = Automation.TrackBuilder<Value>()
        build(&builder)
        automate(Automation.Track(name: name, keys: builder.keys))
    }

    /// Add a track by parameter name, replacing any track already driving it. The
    /// name is the property name, the same key the take format and the host
    /// inspectors use.
    func automate(_ track: Automation.Track) {
        var current = automation ?? Automation()
        current.setTrack(track)
        automation = current
    }

    /// The property name of a declared `@Param`, found by identity.
    private func parameterName<Value: ParamValue>(of param: Param<Value>) -> String? {
        for handle in parameters() {
            if let typed = handle.param as? Param<Value>, typed === param { return handle.name }
        }
        return nil
    }

    // MARK: Driving a parameter from a formula

    /// Drive a parameter from a formula worked out every frame, in place of placed
    /// keys:
    ///
    /// ```swift
    /// override func setup() {
    ///     drive($radius, "120 + sin(time * 2) * 40")
    /// }
    /// ```
    ///
    /// The formula reads `time` (where the automation stands, in seconds),
    /// `frame`, `width`, `height`, `mouseX`, `mouseY`, and this sketch's other
    /// parameters by name, so one parameter can be worked out from another. It is the
    /// same track a keyed parameter uses, so `loops`, `speed`, and `start` shape it
    /// the same way and it travels in the same file.
    ///
    /// Text that cannot be read is reported and the parameter is left alone, so a
    /// typo costs that one parameter rather than the sketch. To handle the error
    /// yourself, build the ``Formula`` with `try` and pass it instead.
    func drive(_ param: Param<Double>, _ formula: String) { driveNumber(param, formula) }
    /// Drive a whole-number parameter from a formula. The number is rounded.
    func drive(_ param: Param<Int>, _ formula: String) { driveNumber(param, formula) }
    /// Drive a switch from a formula. It is on whenever the number is anything
    /// but zero, so `"time % 2 < 1"` blinks once a second.
    func drive(_ param: Param<Bool>, _ formula: String) { driveNumber(param, formula) }

    /// Drive a parameter from a formula you read yourself, which is how to see a
    /// parse error rather than have it reported.
    func drive(_ param: Param<Double>, _ formula: Formula) { driveNumber(param, formula) }
    func drive(_ param: Param<Int>, _ formula: Formula) { driveNumber(param, formula) }
    func drive(_ param: Param<Bool>, _ formula: Formula) { driveNumber(param, formula) }

    /// Drive the parts of a parameter that holds more than one number, one rule
    /// for each part:
    ///
    /// ```swift
    /// override func setup() {
    ///     drive($center, x: "width / 2 + sin(time) * 200", y: "height / 2")
    /// }
    /// ```
    ///
    /// A part with no rule is left alone, so a rule for `x` alone leaves `y`
    /// to the hand or to a keyed track. The rules read the same names a
    /// whole-parameter rule reads, and one part of any parameter is one of those names:
    /// `"center.x"` gives this frame's x.
    ///
    /// One call carries the whole parameter, so a second call replaces what the
    /// first one set. Give every part in one call.
    ///
    /// A rule that cannot be read is reported and that part is left alone; the
    /// parts beside it still play.
    func drive(_ param: Param<Vector2>, x: String? = nil, y: String? = nil) {
        driveParts(param, [("x", x), ("y", y)])
    }

    /// Drive the parts of a point in space.
    func drive(_ param: Param<Vector3>, x: String? = nil, y: String? = nil,
               z: String? = nil) {
        driveParts(param, [("x", x), ("y", y), ("z", z)])
    }

    /// Drive the parts of a color. They are the sRGB numbers in `0...1`, and
    /// nothing holds them there, because a color parameter carries no range of its
    /// own. Use `saturate(...)` in the rule where you want one.
    func drive(_ param: Param<Color>, red: String? = nil, green: String? = nil,
               blue: String? = nil, alpha: String? = nil) {
        driveParts(param, [("red", red), ("green", green),
                           ("blue", blue), ("alpha", alpha)])
    }

    /// Drive the parts of a rectangle.
    func drive(_ param: Param<Rectangle>, x: String? = nil, y: String? = nil,
               width: String? = nil, height: String? = nil) {
        driveParts(param, [("x", x), ("y", y), ("width", width), ("height", height)])
    }

    /// Drive the parts of a set of insets.
    func drive(_ param: Param<Insets>, top: String? = nil, right: String? = nil,
               bottom: String? = nil, left: String? = nil) {
        driveParts(param, [("top", top), ("right", right),
                           ("bottom", bottom), ("left", left)])
    }

    /// Drive the two ends of a range. The pair stays ordered: a lower end that
    /// climbs past the upper one lifts it along, the way the parameter's own
    /// two-thumb slider does.
    func drive(_ param: Param<ClosedRange<Double>>, lower: String? = nil,
               upper: String? = nil) {
        driveParts(param, [("lower", lower), ("upper", upper)])
    }

    private func driveParts<Value: ParamValue>(_ param: Param<Value>,
                                               _ sources: [(part: String, source: String?)]) {
        guard let name = parameterName(of: param) else {
            report("drive() was handed a parameter this sketch does not declare")
            return
        }
        let given = sources.compactMap { pair in pair.source.map { (pair.part, $0) } }
        guard !given.isEmpty else {
            report("drive() was given no rule for any part of '\(name)'")
            return
        }
        let known = readableNames()
        var parts: [String: Formula] = [:]
        for (part, source) in given {
            let formula: Formula
            do {
                formula = try Formula(source)
            } catch {
                // A rule that cannot be read costs that one part, the way a
                // whole-parameter one costs that one parameter.
                report("drive() could not read \"\(source)\" for '\(name).\(part)': \(error)")
                continue
            }
            let unknown = formula.variables.filter { !known.contains($0) }
            if !unknown.isEmpty {
                report("the rule driving '\(name).\(part)' names "
                       + "\(unknown.joined(separator: ", ")), which nothing here supplies; "
                       + "it will read as 0")
            }
            parts[part] = formula
        }
        guard !parts.isEmpty else { return }
        automate(Automation.Track(name: name, parts: parts))
    }

    /// Every name a rule written on this sketch can read: the built-in ones,
    /// each parameter, and each part of a parameter that holds more than one number.
    private func readableNames() -> Set<String> {
        var known = Set(Automation.readableNames)
        for handle in parameters() {
            known.insert(handle.name)
            for part in Automation.parts(of: handle.param.stored).keys {
                known.insert("\(handle.name).\(part)")
            }
        }
        return known
    }

    private func driveNumber<Value: ParamValue>(_ param: Param<Value>, _ source: String) {
        do {
            driveNumber(param, try Formula(source))
        } catch {
            report("drive() could not read \"\(source)\": \(error)")
        }
    }

    private func driveNumber<Value: ParamValue>(_ param: Param<Value>, _ formula: Formula) {
        guard let name = parameterName(of: param) else {
            report("drive() was handed a parameter this sketch does not declare")
            return
        }
        // A name nothing will ever supply reads as zero every frame, which
        // draws something rather than nothing and is the hardest kind of
        // mistake to see. Say it once, here, rather than never.
        let known = readableNames()
        let unknown = formula.variables.filter { !known.contains($0) }
        if !unknown.isEmpty {
            report("the formula driving '\(name)' names \(unknown.joined(separator: ", ")), "
                   + "which nothing here supplies; it will read as 0")
        }
        automate(Automation.Track(name: name, formula: formula))
    }

    private func report(_ message: String) {
        FileHandle.standardError.write(Data("Ollin: \(message)\n".utf8))
    }
}

public extension Automation {
    /// The names a track's formula can read besides the sketch's own parameters.
    /// A parameter spelled the same as one of these cannot be reached, because the
    /// built-in name wins.
    static let readableNames = ["time", "frame", "width", "height", "mouseX", "mouseY"]
}
