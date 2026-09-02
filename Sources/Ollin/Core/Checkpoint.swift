import Foundation

/// The state of a run, written down so a relaunch can pick it up: the seed, the
/// clock, every `@Param` value, and every ``Saved`` property.
///
/// A piece that has been growing for three days cannot be reproduced from its
/// seed in any useful sense, because getting back there means running the three
/// days again. So an installation writes this file on a cadence, and the next
/// launch reads it and carries on.
///
/// The file is JSON, sorted and indented, sitting beside the others in
/// `~/Library/Application Support/Ollin/Checkpoints/`. It is meant to be
/// readable: when a piece comes back wrong, the state it came back with is the
/// first thing worth looking at.
struct Checkpoint {

    /// The shape of the file. A checkpoint written by an older Ollin is ignored
    /// rather than guessed at, so this only moves when the layout changes.
    static let formatVersion = 1

    let sketchType: String
    let savedAt: Date
    let variation: Int
    let time: Double
    let frameCount: Int
    let canvas: [Int]
    let params: [String: ParamStored]
    /// Each `@Saved` property's value, as the JSON it was written as. Held raw
    /// rather than decoded, because only the sketch knows what type each one is.
    let state: [String: Any]

    // MARK: Where it lives

    /// Somewhere else to keep them, which only the tests set: they must not
    /// write into the checkpoints of whatever is actually running on this
    /// machine, and they need a directory they can throw away afterwards.
    @MainActor static var directoryOverride: URL?

    /// The directory checkpoints are kept in, made if it is not there yet.
    @MainActor
    static func directory() -> URL? {
        if let directoryOverride {
            try? FileManager.default.createDirectory(at: directoryOverride,
                                                     withIntermediateDirectories: true)
            return directoryOverride
        }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        let directory = support.appendingPathComponent("Ollin/Checkpoints", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Where this sketch's checkpoint is written. One file per sketch type, so a
    /// piece finds its own state again and two pieces never collide.
    @MainActor
    static func url(for sketch: Sketch) -> URL? {
        url(forSketchNamed: String(describing: type(of: sketch)))
    }

    @MainActor
    static func url(forSketchNamed name: String) -> URL? {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "-" }
        return directory()?.appendingPathComponent(String(safe) + ".json")
    }

    // MARK: Writing

    /// Take everything worth keeping off `sketch` and write it, atomically, so a
    /// machine that loses power mid-write still has the last good file rather
    /// than half of this one.
    ///
    /// `time` comes from the runner, which owns the clock.
    @MainActor
    static func write(_ sketch: Sketch, time: Double) throws {
        guard let url = url(for: sketch) else {
            throw CheckpointError.noDirectory
        }
        var file: [String: Any] = [
            "version": formatVersion,
            "sketch": String(describing: type(of: sketch)),
            "savedAt": ISO8601DateFormatter().string(from: Date()),
            "variation": sketch.variation,
            "time": time,
            "frameCount": sketch.frameCount,
            "canvas": [Int(sketch.width), Int(sketch.height)],
        ]

        var params: [String: Any] = [:]
        for handle in sketch.parameters() {
            if let json = try? jsonObject(encoding: handle.param.stored) {
                params[handle.name] = json
            }
        }
        file["params"] = params

        var state: [String: Any] = [:]
        for handle in sketch.savedProperties() {
            do {
                state[handle.name] = try JSONSerialization.jsonObject(
                    with: handle.property.encodedValue(), options: [.fragmentsAllowed])
            } catch {
                // One property that will not encode must not cost the rest of
                // the run's state, so it is named and skipped.
                ollinInstallationLog("could not save '\(handle.name)': \(error)")
            }
        }
        file["state"] = state

        let data = try JSONSerialization.data(withJSONObject: file,
                                              options: [.sortedKeys, .prettyPrinted])
        try data.write(to: url, options: .atomic)
    }

    // MARK: Reading

    /// The checkpoint for `sketch`, or `nil` when there is nothing to restore:
    /// no file, an unreadable one, one written by a different sketch or a
    /// different format, or a run told to start `--fresh`.
    @MainActor
    static func load(for sketch: Sketch,
                     arguments: [String] = CommandLine.arguments) -> Checkpoint? {
        if arguments.contains("--fresh") {
            ollinInstallationLog("starting fresh; any saved state is left alone")
            return nil
        }
        guard let url = url(for: sketch),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            ollinInstallationLog("the saved state could not be read; starting fresh")
            return nil
        }
        let name = String(describing: type(of: sketch))
        guard file["version"] as? Int == formatVersion, file["sketch"] as? String == name else {
            ollinInstallationLog("the saved state is from another sketch or an older Ollin; starting fresh")
            return nil
        }
        var params: [String: ParamStored] = [:]
        if let raw = file["params"] as? [String: Any] {
            for (key, value) in raw {
                if let stored: ParamStored = try? decode(from: value) { params[key] = stored }
            }
        }
        return Checkpoint(
            sketchType: name,
            savedAt: (file["savedAt"] as? String).flatMap {
                ISO8601DateFormatter().date(from: $0)
            } ?? Date.distantPast,
            variation: file["variation"] as? Int ?? 0,
            time: file["time"] as? Double ?? 0,
            frameCount: file["frameCount"] as? Int ?? 0,
            canvas: file["canvas"] as? [Int] ?? [],
            params: params,
            state: file["state"] as? [String: Any] ?? [:])
    }

    /// Delete the saved state for `sketch`, so the next launch starts over.
    @MainActor
    static func forget(_ sketch: Sketch) {
        guard let url = url(for: sketch) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Putting it back

    /// The half that has to happen before `setup()`: the seed the run was on,
    /// and the parameter values it was tuned to. A sketch's own `setup()` then builds
    /// from the same numbers it built from last time.
    @MainActor
    func applyBeforeSetup(to sketch: Sketch) {
        sketch.seed(variation)
        // Keyed tolerantly rather than with `uniqueKeysWithValues`, which traps
        // on a repeated name. The compiler makes a repeat hard to write, so this
        // is a guarantee rather than a fix: nothing about restoring should be
        // able to stop a piece from starting. The walk begins at the subclass,
        // so the first of any pair is the one in force.
        let byName = Dictionary(sketch.parameters().map { ($0.name, $0.param) },
                                uniquingKeysWith: { first, _ in first })
        for (name, stored) in params {
            byName[name]?.restore(stored)
        }
    }

    /// The half that has to happen after `setup()`, because that is where a
    /// sketch fills its properties in: the state itself, and the frame number
    /// the piece was on.
    ///
    /// A property that has been renamed finds nothing and keeps its fresh value.
    /// One whose type changed fails to decode, is named, and keeps its fresh
    /// value too, rather than taking the rest of the restore down with it.
    @MainActor
    func applyAfterSetup(to sketch: Sketch) {
        sketch.frameCount = frameCount
        for handle in sketch.savedProperties() {
            guard let json = state[handle.name] else { continue }
            do {
                let data = try JSONSerialization.data(withJSONObject: json,
                                                      options: [.fragmentsAllowed])
                try handle.property.decodeValue(from: data)
            } catch {
                ollinInstallationLog("could not restore '\(handle.name)', so it keeps its "
                                     + "starting value: \(error)")
            }
        }
        if canvas.count == 2, canvas != [Int(sketch.width), Int(sketch.height)] {
            ollinInstallationLog("the saved state is from a \(canvas[0])x\(canvas[1]) canvas, "
                                 + "and this one is \(Int(sketch.width))x\(Int(sketch.height))")
        }
        // Said out loud on every launch that resumes, because a piece silently
        // picking up old state is the one thing about this that can look like a
        // bug from the outside.
        ollinInstallationLog("resumed the run saved at \(Checkpoint.stamp.string(from: savedAt)) "
                             + "(frame \(frameCount), \(Int(time))s in)")
    }
}

extension Checkpoint {
    /// For the log line only, so a resume reads as a time rather than a
    /// timestamp.
    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum CheckpointError: Error {
    case noDirectory
}

// MARK: - Codable plumbing

/// Encode a value and hand back the JSON tree, ready to nest in the file.
private func jsonObject(encoding value: some Encodable) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

/// The way back: a JSON tree read from the file, decoded into a value.
private func decode<T: Decodable>(from json: Any) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])
    return try JSONDecoder().decode(T.self, from: data)
}

// MARK: - Saving on the way out

/// Catches the signals a run is usually stopped with, so the piece writes its
/// state down before it goes.
///
/// A crash cannot be caught safely and a power cut cannot be caught at all, so
/// the cadence is what covers those. This covers the ordinary ways a run ends: a
/// watchdog stopping it, or Control-C in the terminal it was started from.
@MainActor
enum CheckpointSignals {
    private static var sources: [DispatchSourceSignal] = []

    static func catchStops(_ save: @escaping @MainActor () -> Void) {
        guard sources.isEmpty else { return }
        for number in [SIGTERM, SIGINT] {
            // The default action has to be turned off first, or the process dies
            // before the source ever runs.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    save()
                    exit(0)
                }
            }
            source.resume()
            sources.append(source)
        }
    }
}

public extension Sketch {
    /// Write this sketch's state down now, whatever the cadence says: the seed,
    /// the clock, the `@Param` values, and every ``Saved`` property.
    ///
    /// The automatic save is the one to rely on for a piece left running. This
    /// is for the other moments, like saving on a key press.
    @MainActor
    func saveCheckpoint() {
        do {
            try Checkpoint.write(self, time: time)
        } catch {
            ollinInstallationLog("could not save the state: \(error)")
        }
    }

    /// Throw away this sketch's saved state, so the next launch starts over.
    @MainActor
    func forgetCheckpoint() {
        Checkpoint.forget(self)
    }
}
