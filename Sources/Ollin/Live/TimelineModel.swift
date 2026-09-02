import Foundation
import Observation

/// The parameter timeline's model: a lens over the running sketch's
/// `Automation`. It holds what the panel needs beyond the automation itself
/// (the playhead, the selection, the file the tracks round-trip to) and the
/// edits the panel makes: keys placed at the playhead, moved, removed, and
/// curves chosen. Every edit lands on the sketch's own automation, so the
/// panel edits exactly what the frames play.
///
/// The transport half rides the runner's clock transport (`setClockPaused`,
/// `scrubClock`, `stepClock`), so a scrub here is the deterministic clock
/// moving, not a second clock beside it.
@MainActor
@Observable
public final class TimelineModel {

    /// The runner whose clock and sketch this timeline works on.
    @ObservationIgnored package weak var runner: SketchRunner?

    /// Where edits write, or `nil` when this run keeps them in memory.
    public private(set) var fileURL: URL?

    /// Whether the tracks as edited are on disk.
    public enum SaveState: Equatable {
        /// Nothing to write, or the last write landed.
        case saved
        /// Edits exist that have not reached the file (or there is no file).
        case unsaved
        /// The last write failed.
        case failed(String)
    }
    public private(set) var saveState: SaveState = .saved

    /// The clock the lanes draw the playhead at, ticked while the panel shows.
    public private(set) var playhead: Double = 0
    /// Whether the transport is holding the clock, mirrored from the runner.
    public private(set) var isPaused = false

    /// One key on one track, the panel's selection.
    public struct KeySelection: Equatable {
        public var track: String
        public var index: Int
        public init(track: String, index: Int) {
            self.track = track
            self.index = index
        }
    }
    public var selection: KeySelection?

    /// Bumped on every edit, so a view that draws the automation re-reads it.
    public private(set) var editCount = 0

    /// Told after every edit, with the automation as it now stands. A live
    /// session holds it here so the tracks survive a reload swap.
    @ObservationIgnored public var automationChanged: ((Automation?) -> Void)?

    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// How close to the playhead a key counts as being on it: half a frame
    /// at the transport's step rate.
    package static let keyEpsilon = 0.5 / SketchRunner.clockStepRate

    public init() {}

    /// Point the timeline at its file. An existing automation is not read
    /// here; the host installs the file's tracks on the sketch itself.
    public func setFile(_ url: URL?) {
        fileURL = url
    }

    // MARK: What the panel reads

    package var sketch: Sketch? { runner?.sketch }

    /// The automation as the sketch plays it, empty when none is attached.
    public var automation: Automation { sketch?.automation ?? Automation() }

    /// The last moment any track reaches, for the ruler's span.
    public var contentDuration: Double { automation.duration }

    /// Whether a track drives `name`.
    public func hasTrack(named name: String) -> Bool {
        automation.track(named: name) != nil
    }

    /// Whether the track driving `name` has a key on the playhead.
    public func hasKeyAtPlayhead(named name: String) -> Bool {
        keyIndex(near: playhead, in: automation.track(named: name)) != nil
    }

    /// The parameters no track drives yet, in declaration order.
    public func addableParameters() -> [ParamHandle] {
        (sketch?.parameters() ?? []).filter { automation.track(named: $0.name) == nil }
    }

    private func keyIndex(near time: Double, in track: Automation.Track?) -> Int? {
        guard let track else { return nil }
        return track.keys.firstIndex { abs($0.time - time) <= TimelineModel.keyEpsilon }
    }

    // MARK: Transport

    /// The loop region, in the panel's own axis (the automation's position).
    /// Held on the runner's transport, mapped onto the clock the frames
    /// actually advance on. Never written into the file.
    public var loopRegion: ClosedRange<Double>? {
        get { storedLoopRegion }
        set {
            storedLoopRegion = newValue
            if let region = newValue {
                let a = clockTime(forPosition: region.lowerBound)
                let b = clockTime(forPosition: region.upperBound)
                runner?.clockLoopRegion = min(a, b)...max(a, b)
            } else {
                runner?.clockLoopRegion = nil
            }
            editCount += 1     // chrome only; the automation is untouched
        }
    }
    @ObservationIgnored private var storedLoopRegion: ClosedRange<Double>?

    /// The sketch clock that lands the automation on `position`. The panel's
    /// axis is the automation's own (`start + time * speed` read backwards),
    /// so a scrub goes where the lanes say; with no tracks the axis is the
    /// clock itself.
    package func clockTime(forPosition position: Double) -> Double {
        let automation = self.automation
        guard !automation.tracks.isEmpty, automation.speed != 0 else { return position }
        return max(0, (position - automation.start) / automation.speed)
    }

    public func togglePlay() {
        guard let runner else { return }
        runner.setClockPaused(!runner.isClockPaused)
        syncFromRunner()
    }

    public func pause() {
        runner?.setClockPaused(true)
        syncFromRunner()
    }

    /// The playhead to the loop region's start, or to zero.
    public func toStart() {
        scrub(to: loopRegion?.lowerBound ?? 0)
    }

    /// The playhead to the last key any track holds. Under a looping
    /// automation the exact end wraps to zero, so it lands a frame short.
    public func toEnd() {
        let end = automation.loops && contentDuration > 0
            ? max(0, contentDuration - 1 / SketchRunner.clockStepRate)
            : contentDuration
        scrub(to: end)
    }

    public func step(byFrames frames: Int) {
        runner?.stepClock(byFrames: frames)
        syncFromRunner()
    }

    public func scrub(to time: Double) {
        runner?.scrubClock(to: clockTime(forPosition: max(0, time)))
        syncFromRunner()
    }

    private func syncFromRunner() {
        guard let runner else { return }
        // The playhead rides the automation's own position, so a looping
        // pass shows the playhead coming around while the clock runs on.
        let raw = runner.clockTime
        let automation = self.automation
        playhead = automation.tracks.isEmpty ? raw : automation.position(at: raw)
        isPaused = runner.isClockPaused
    }

    /// Follow the clock while the panel shows: the playhead at a steady
    /// cadence of its own, because the stats readout refreshes too coarsely
    /// for a moving playhead to ride it.
    public func beginFollowingClock() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.syncFromRunner()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    public func endFollowingClock() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: Edits

    /// Put a key on `name`'s track at the playhead, holding the parameter's
    /// current value; on a key already there, take that key away instead.
    /// The parameter-row diamond calls this. A track worked out from a formula
    /// has no keys to place, so it is left alone.
    public func toggleKey(param name: String) {
        guard let sketch else { return }
        var automation = self.automation
        if let track = automation.track(named: name) {
            guard !track.isWorkedOut else { return }
            if let index = keyIndex(near: playhead, in: track) {
                var keys = track.keys
                keys.remove(at: index)
                if keys.isEmpty {
                    automation.tracks.removeAll { $0.name == name }
                } else {
                    automation.setTrack(Automation.Track(name: name, keys: keys))
                }
                apply(automation)
                return
            }
        }
        guard let handle = sketch.parameters().first(where: { $0.name == name }) else { return }
        addKey(named: name, at: playhead, value: handle.param.stored, to: &automation)
        apply(automation)
    }

    /// Place `value` on `name`'s track at `time`, replacing a key already on
    /// that moment.
    public func placeKey(param name: String, at time: Double, value: ParamStored,
                         curve: Automation.Curve = .easeInOut) {
        var automation = self.automation
        if automation.track(named: name)?.isWorkedOut == true { return }
        addKey(named: name, at: time, value: value, curve: curve, to: &automation)
        apply(automation)
    }

    private func addKey(named name: String, at time: Double, value: ParamStored,
                        curve: Automation.Curve = .easeInOut,
                        to automation: inout Automation) {
        var keys = automation.track(named: name)?.keys ?? []
        keys.removeAll { abs($0.time - time) <= TimelineModel.keyEpsilon }
        keys.append(Automation.Key(at: max(0, time), value, curve: curve))
        automation.setTrack(Automation.Track(name: name, keys: keys))
    }

    public func removeKey(track name: String, at index: Int) {
        var automation = self.automation
        guard let track = automation.track(named: name), track.keys.indices.contains(index),
              !track.isWorkedOut else { return }
        var keys = track.keys
        keys.remove(at: index)
        if keys.isEmpty {
            automation.tracks.removeAll { $0.name == name }
            if selection?.track == name { selection = nil }
        } else {
            automation.setTrack(Automation.Track(name: name, keys: keys))
            if selection == KeySelection(track: name, index: index) { selection = nil }
        }
        apply(automation)
    }

    /// Move a key to `time`, keeping its value and curve. Answers the key's
    /// index after the track re-sorts, so a drag can keep holding it.
    @discardableResult
    public func moveKey(track name: String, at index: Int, to time: Double) -> Int {
        var automation = self.automation
        guard let track = automation.track(named: name), track.keys.indices.contains(index),
              !track.isWorkedOut else { return index }
        var keys = track.keys
        var moved = keys.remove(at: index)
        moved.time = max(0, time)
        keys.append(moved)
        let sorted = Automation.Track(name: name, keys: keys)
        automation.setTrack(sorted)
        apply(automation)
        let landed = sorted.keys.firstIndex { $0.time == moved.time && $0.value == moved.value }
        let result = landed ?? index
        if selection?.track == name { selection = KeySelection(track: name, index: result) }
        return result
    }

    /// Give the curve that leaves one key.
    public func setCurve(track name: String, at index: Int, _ curve: Automation.Curve) {
        var automation = self.automation
        guard let track = automation.track(named: name), track.keys.indices.contains(index),
              !track.isWorkedOut else { return }
        var keys = track.keys
        keys[index].curve = curve
        automation.setTrack(Automation.Track(name: name, keys: keys))
        apply(automation)
    }

    public func removeTrack(named name: String) {
        var automation = self.automation
        automation.tracks.removeAll { $0.name == name }
        if selection?.track == name { selection = nil }
        apply(automation)
    }

    /// Start a track for `name` with one key at the playhead. The "+ Track"
    /// menu's action; the same move the row diamond makes.
    public func addTrack(named name: String) {
        toggleKey(param: name)
    }

    private func apply(_ automation: Automation) {
        guard let sketch else { return }
        sketch.automation = automation.tracks.isEmpty && automation.length == nil
            ? nil : automation
        editCount += 1
        automationChanged?(sketch.automation)
        scheduleWrite()
        runner?.refreshClockFrame()    // a change made while paused must show
    }

    // MARK: The file

    private func scheduleWrite() {
        saveState = .unsaved
        guard fileURL != nil else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    // MARK: What the lanes draw

    /// The panel's time axis: the span the ruler shows and the mapping between
    /// moments and points. Pure, so the mapping is a law a test can hold.
    package struct Scale: Equatable {
        package var span: Double

        package init(contentDuration: Double) {
            // At least five seconds on the ruler, and a breath past the last
            // key, rounded up to a whole second so the ticks land cleanly.
            span = max(5, (contentDuration * 1.05).rounded(.up))
        }

        package func x(of time: Double, width: Double) -> Double {
            span > 0 ? time / span * width : 0
        }

        package func time(at x: Double, width: Double) -> Double {
            guard width > 0 else { return 0 }
            return min(max(0, x / width * span), span)
        }

        /// The labeled tick cadence, in seconds: every second up to a short
        /// span, then a whole number that keeps about ten labels.
        package var majorTick: Double {
            span <= 12 ? 1 : (span / 10).rounded(.up)
        }
    }

    /// A track's value drawn across the span: evenly spaced samples plus one
    /// height per key, every height normalized to `0...1` over the values the
    /// samples reach. `nil` for a track whose values have no height to plot (a
    /// menu choice, text, a set of colors), whose keys sit on the centerline.
    package struct LanePlot: Equatable {
        package var samples: [Double]
        package var keyHeights: [Double]
    }

    /// The number a stored value plots at, or `nil` when it has none.
    package static func plotValue(_ stored: ParamStored) -> Double? {
        switch stored {
        case .number(let value): return value
        case .boolean(let value): return value ? 1 : 0
        default: return nil
        }
    }

    package static func plot(_ track: Automation.Track, span: Double,
                             samples count: Int = 120) -> LanePlot? {
        guard !track.isWorkedOut, !track.keys.isEmpty, span > 0, count > 1 else { return nil }
        var values: [Double] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            let time = span * Double(index) / Double(count - 1)
            guard let stored = track.value(at: time),
                  let value = TimelineModel.plotValue(stored) else { return nil }
            values.append(value)
        }
        let keyValues = track.keys.compactMap { TimelineModel.plotValue($0.value) }
        guard keyValues.count == track.keys.count else { return nil }
        let low = min(values.min() ?? 0, keyValues.min() ?? 0)
        let high = max(values.max() ?? 0, keyValues.max() ?? 0)
        let range = high - low
        func normalized(_ value: Double) -> Double {
            range > 0 ? (value - low) / range : 0.5
        }
        return LanePlot(samples: values.map(normalized),
                        keyHeights: keyValues.map(normalized))
    }

    /// Write the tracks to the file now. Quiet without a file.
    public func writeNow() {
        guard let url = fileURL else { return }
        writeTask?.cancel()
        writeTask = nil
        do {
            if let automation = sketch?.automation {
                try automation.write(to: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                // Every track was taken away: an empty automation still
                // round-trips, which keeps the file honest about it.
                try Automation().write(to: url)
            }
            saveState = .saved
        } catch {
            saveState = .failed("\(error.localizedDescription)")
        }
    }
}
