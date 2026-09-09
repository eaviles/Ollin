import Foundation

/// One recorded run, written down so it can be played back exactly: the seed
/// the run grew from, the clock it advanced on, every input event it received,
/// and every `@Param` change, each stamped with the frame it happened at. The
/// same seed and the same inputs walk a fresh instance through the same
/// frames, so frame N of the replay is frame N of the original run.
///
/// A take captures what *drives* a sketch (time, pointer, keys, parameters,
/// randomness), not what it draws. Anything outside that loop (a live camera,
/// a microphone, incoming OSC or MIDI, a wall clock read directly) plays live
/// during a replay and is not reproduced.
///
/// Record with `--record-take <file>` on a windowed run; play back with
/// `--replay <file>`, alone (the window gains transport keys) or beside any
/// export flag, so a live performance re-renders offline, exactly as played.
/// `--seed N` beside `--replay` re-seeds the replayed run on purpose: the same
/// gestures land on a different variation. See `Docs/Core/Replay.md`.
public struct Take: Codable, Equatable, Sendable {

    /// The shape of the file. A take written by an older Ollin is refused
    /// rather than guessed at, so this only moves when the layout changes.
    public static let currentVersion = 1

    /// The clock of one frame: what `advance` was called with.
    public struct Frame: Codable, Equatable, Sendable {
        public var time: Double
        public var deltaTime: Double
        public var frameRate: Double
    }

    /// One input event, in the sketch's own coordinates and types.
    public enum Event: Codable, Equatable, Sendable {
        /// The pointer moved (canvas coordinates, top-left origin).
        case pointer(x: Double, y: Double)
        /// The primary button went down or up; the press and release hooks fire.
        case button(pressed: Bool)
        /// The primary button state alone, with no hooks (a host widget drag).
        case buttonState(pressed: Bool)
        /// The secondary (right) button went down or up.
        case rightButton(pressed: Bool)
        /// How hard the pointer is pressed, and whether the device can vary it.
        case pressure(amount: Double, canVary: Bool)
        /// What the tablet says about the stylus: its lean, its turn, which end
        /// is down, and whether it is over the tablet at all.
        case pen(Pen)
        /// One scroll-wheel event's movement; the `mouseScrolled()` hook fires.
        case scroll(deltaY: Double)
        /// The held modifier keys changed.
        case modifiers(ModifierKeys)
        /// A key went down or up: a printing key carries `character`, a named
        /// key carries `code`, exactly one of the two is set.
        case key(character: String?, code: KeyCode?, pressed: Bool)
        /// The canvas lost keyboard focus and dropped its held keys.
        case keysCleared
    }

    /// An event and the frame it precedes: an event stamped `frame` was
    /// received after frame `frame` drew and applies before frame `frame + 1`.
    public struct StampedEvent: Codable, Equatable, Sendable {
        public var frame: Int
        public var event: Event
    }

    /// A `@Param` value change, applied before frame `frame + 1` draws.
    public struct Change: Codable, Equatable, Sendable {
        public var frame: Int
        public var name: String
        public var value: ParamStored
    }

    public var version: Int
    /// The sketch type this take was recorded from, as a plain check that a
    /// take is being replayed onto the sketch it came from.
    public var sketchType: String
    /// The `variation` seed the run grew from.
    public var seed: Int
    /// The canvas size at recording time, `[width, height]`, informational.
    public var canvas: [Int]
    /// Every `@Param` value at the moment recording started, so a replay
    /// starts from the same parameter settings before `setup()` reads them.
    public var initialParams: [String: ParamStored]
    /// One clock sample per frame: `frames[k]` drove the advance from
    /// `frameCount == k` to `k + 1`.
    public var frames: [Frame]
    public var events: [StampedEvent]
    public var changes: [Change]

    /// How many frames the take holds.
    public var frameCount: Int { frames.count }

    // MARK: Reading and writing

    /// Read a take from disk. Throws when the file is unreadable, is not a
    /// take, or was written in a different format version.
    public static func load(from url: URL) throws -> Take {
        let take = try JSONDecoder().decode(Take.self, from: Data(contentsOf: url))
        guard take.version == currentVersion else {
            throw TakeError.incompatibleVersion(take.version)
        }
        return take
    }

    /// Write the take, atomically, as sorted JSON.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    // MARK: Replay

    /// Prepare a fresh sketch to play this take back: seed it, restore the
    /// recorded starting parameter values, and attach the player that will feed it
    /// the recorded clock and inputs. Call before the first frame, so
    /// `setup()` already runs under the take's seed and parameter values. The
    /// windowed and headless drivers both go through `Sketch.advance`, so
    /// after this call any of them replays the run with no further wiring.
    @MainActor
    public func install(on sketch: Sketch) {
        sketch.takeRecorder = nil
        sketch.seed(seed)
        applyStart(to: sketch)
        sketch.takePlayer = TakePlayer(take: self)
    }

    /// Restore the recorded starting `@Param` values (a parameter the sketch has
    /// since renamed or retyped is skipped; the new default wins).
    @MainActor
    func applyStart(to sketch: Sketch) {
        guard !initialParams.isEmpty else { return }
        for handle in sketch.parameters() {
            if let value = initialParams[handle.name] { handle.param.restore(value) }
        }
    }
}

public enum TakeError: Error, CustomStringConvertible {
    case incompatibleVersion(Int)

    public var description: String {
        switch self {
        case .incompatibleVersion(let version):
            return "this take was written in format version \(version); this Ollin reads version \(Take.currentVersion)"
        }
    }
}

// MARK: - Recording

/// Builds a `Take` while a run plays: `Sketch.advance` hands it each frame's
/// clock (where it also diffs the `@Param` values), and the input functions
/// hand it each event as it arrives. Attached by the runner when the host
/// asked to record; a sketch never sees it.
@MainActor
final class TakeRecorder {

    private(set) var take: Take
    /// The parameter handles, walked once: the `@Param` set of a sketch is
    /// fixed, and reflecting over the instance every frame would cost real time.
    private let handles: [ParamHandle]
    private var lastStored: [String: ParamStored]

    init(sketch: Sketch) {
        handles = sketch.parameters()
        var initial: [String: ParamStored] = [:]
        for handle in handles { initial[handle.name] = handle.param.stored }
        lastStored = initial
        take = Take(version: Take.currentVersion,
                    sketchType: String(describing: type(of: sketch)),
                    seed: sketch.variation,
                    canvas: [Int(sketch.width), Int(sketch.height)],
                    initialParams: initial,
                    frames: [], events: [], changes: [])
    }

    /// Log one input event, stamped with the frames advanced so far.
    func log(_ event: Take.Event, at frame: Int) {
        take.events.append(Take.StampedEvent(frame: frame, event: event))
    }

    /// Record one frame's clock, and any parameter values that moved since the
    /// last frame. Called from `Sketch.advance`, before the frame draws.
    func recordFrame(of sketch: Sketch, time: Double, deltaTime: Double, frameRate: Double) {
        // The recorder can attach before the canvas size is known (the runner
        // attaches it ahead of the first frame); fill the size in when it is.
        if take.canvas.first == 0 || take.canvas.count < 2 {
            take.canvas = [Int(sketch.width), Int(sketch.height)]
        }
        let stamp = take.frames.count
        for handle in handles {
            let now = handle.param.stored
            if lastStored[handle.name] != now {
                lastStored[handle.name] = now
                take.changes.append(Take.Change(frame: stamp, name: handle.name, value: now))
            }
        }
        take.frames.append(Take.Frame(time: time, deltaTime: deltaTime, frameRate: frameRate))
    }
}

// MARK: - Playback

/// Feeds a recorded take back into a sketch: `Sketch.advance` asks it for each
/// frame's clock, and it applies that frame's events and parameter changes first,
/// through the same paths live input takes, so the hooks fire again. Past the
/// end of the take the clock keeps advancing on the caller's step, so a run
/// can play on beyond its recording.
@MainActor
final class TakePlayer {

    let take: Take
    private var eventCursor = 0
    private var changeCursor = 0
    /// The clock past the end of the take, grown one caller step at a time
    /// from the last recorded moment.
    private var timePastEnd: Double?

    init(take: Take) {
        self.take = take
    }

    /// Back to the start, so a rewound run replays the whole timeline again.
    func rewind() {
        eventCursor = 0
        changeCursor = 0
        timePastEnd = nil
    }

    /// Whether frame `frame` is past the recorded end.
    func isPastEnd(_ frame: Int) -> Bool { frame >= take.frames.count }

    /// Apply everything stamped for the frame about to draw, then hand back
    /// its recorded clock. `frame` is the sketch's pre-increment `frameCount`.
    func step(_ sketch: Sketch, frame: Int,
              fallback: (time: Double, deltaTime: Double, frameRate: Double))
        -> (time: Double, deltaTime: Double, frameRate: Double) {
        while eventCursor < take.events.count, take.events[eventCursor].frame <= frame {
            sketch.ingest(take.events[eventCursor].event)
            eventCursor += 1
        }
        while changeCursor < take.changes.count, take.changes[changeCursor].frame <= frame {
            let change = take.changes[changeCursor]
            changeCursor += 1
            for handle in sketch.parameters() where handle.name == change.name {
                handle.param.restore(change.value)
            }
        }
        if frame < take.frames.count {
            let sample = take.frames[frame]
            timePastEnd = sample.time
            return (sample.time, sample.deltaTime, sample.frameRate)
        }
        let dt = max(fallback.deltaTime, 0)
        let t = (timePastEnd ?? take.frames.last?.time ?? 0) + dt
        timePastEnd = t
        return (t, dt, take.frames.last?.frameRate ?? fallback.frameRate)
    }
}
