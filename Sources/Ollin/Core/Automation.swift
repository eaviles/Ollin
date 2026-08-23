import Foundation

/// A sketch's knobs written down over time: a value placed at one moment,
/// another placed later, and a curve that carries the first into the second.
/// Where `@Param` gives a sketch a knob to turn, an automation turns it, so a
/// piece can be *directed* rather than only tuned.
///
/// Write the tracks in `setup()`, one per knob:
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
/// Each frame, before the sketch draws, every track sets its knob to the value
/// its curve holds at the sketch clock. The value is set directly rather than
/// eased into, so a knob that carries `smoothing:` does not glide twice: the
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

    /// The shape of the file. An automation written by an older Ollin is
    /// refused rather than guessed at, so this only moves when the layout does.
    public static let currentVersion = 1

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
        /// The knob's value at that moment.
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

    /// One knob's keys, in time order.
    public struct Track: Codable, Equatable, Sendable {
        /// The `@Param` property name this track drives.
        public var name: String
        /// The keys, always sorted by time. Two keys at the same moment keep
        /// the order they were given in, so the later one wins from there on.
        public private(set) var keys: [Key]

        public init(name: String, keys: [Key]) {
            self.name = name
            self.keys = keys.enumerated()
                .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
                .map(\.element)
        }

        /// When the last key falls.
        public var duration: Double { keys.last?.time ?? 0 }

        /// The value this track holds at `position`, or `nil` when it has no
        /// keys. Before the first key and after the last one the track holds
        /// that key's value, so a short track is a constant outside its span.
        public func value(at position: Double) -> ParamStored? {
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

        private enum CodingKeys: String, CodingKey { case name, keys }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(name: try container.decode(String.self, forKey: .name),
                      keys: try container.decode([Key].self, forKey: .keys))
        }
    }

    // MARK: The automation itself

    public var version: Int
    /// One track per automated knob, keyed by the property name.
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

    /// Add a track, replacing any track already driving the same knob.
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
    /// choice, and a piece of text have nothing between two values, so they
    /// hold the one they left until the next key. Two values of different
    /// kinds hold as well.
    static func blend(_ from: ParamStored, _ to: ParamStored, _ t: Double) -> ParamStored {
        if t <= 0 { return from }
        if t >= 1 { return to }
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        switch (from, to) {
        case (.number(let a), .number(let b)):
            return .number(lerp(a, b))
        case (.color(let ar, let ag, let ab, let aa), .color(let br, let bg, let bb, let ba)):
            let mixed = Color.mix(Color(red: ar, green: ag, blue: ab, alpha: aa),
                                  Color(red: br, green: bg, blue: bb, alpha: ba), t: t)
            return .color(red: mixed.red, green: mixed.green, blue: mixed.blue, alpha: mixed.alpha)
        case (.vector(let ax, let ay), .vector(let bx, let by)):
            return .vector(x: lerp(ax, bx), y: lerp(ay, by))
        case (.vector3(let ax, let ay, let az), .vector3(let bx, let by, let bz)):
            return .vector3(x: lerp(ax, bx), y: lerp(ay, by), z: lerp(az, bz))
        case (.rect(let ax, let ay, let aw, let ah), .rect(let bx, let by, let bw, let bh)):
            return .rect(x: lerp(ax, bx), y: lerp(ay, by),
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

    // MARK: Reading and writing

    /// Read an automation from disk. Throws when the file is unreadable, is
    /// not an automation, or was written in a different format version.
    public static func load(from url: URL) throws -> Automation {
        let automation = try JSONDecoder().decode(Automation.self, from: Data(contentsOf: url))
        guard automation.version == currentVersion else {
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

    /// Collects one knob's keys in the sketch's own value type, so a track is
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
                + "this Ollin reads version \(Automation.currentVersion)"
        }
    }
}

// MARK: - Playback

/// Drives a sketch's knobs from an automation. `Sketch.advance` hands it the
/// clock the frame is about to draw at, before the frame draws and before a
/// take recorder samples the knobs, so a recorded run writes down the values
/// the automation actually held. Attached by `Sketch.automation`; a sketch
/// never touches it.
@MainActor
final class AutomationPlayer {

    var automation: Automation
    /// The parameter handles, walked once: the `@Param` set of a sketch is
    /// fixed, and reflecting over the instance every frame would cost real time.
    private var handles: [String: any AnyParam]?

    init(_ automation: Automation) {
        self.automation = automation
    }

    /// Set every automated knob to the value its track holds at `time`.
    func apply(to sketch: Sketch, at time: Double) {
        guard !automation.tracks.isEmpty else { return }
        let handles = self.handles ?? {
            var found: [String: any AnyParam] = [:]
            for handle in sketch.parameters() { found[handle.name] = handle.param }
            self.handles = found
            return found
        }()
        let position = automation.position(at: time)
        for track in automation.tracks {
            guard let value = track.value(at: position), let param = handles[track.name] else { continue }
            param.restore(value)
        }
    }
}

// MARK: - The sketch surface

public extension Sketch {

    /// The automation driving this sketch's knobs, or `nil` when none is
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

    /// Write one knob's values down over time. The closure places the keys, in
    /// the knob's own type:
    ///
    /// ```swift
    /// automate($radius) { track in
    ///     track.key(at: 0, 40)
    ///     track.key(at: 2, 320, curve: .easeInOut)
    /// }
    /// ```
    ///
    /// Calling it again for the same knob replaces that knob's track. A
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

    /// Add a track by knob name, replacing any track already driving it. The
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
}
