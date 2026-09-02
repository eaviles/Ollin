import Foundation
import Testing
@testable import Ollin

/// Probes for the state a piece leaves behind, and picks back up.
///
/// The claims worth pinning are not that a value survives a round trip, which is
/// what any encoder does. They are what happens when the sketch has moved on
/// since the file was written: a property renamed, a property whose type
/// changed, a file from another sketch, a file that is not JSON at all. Each of
/// those has to cost exactly the thing it touches and nothing else, because the
/// alternative is a gallery piece that will not start.
@Suite(.serialized)
@MainActor
struct CheckpointTests {

    // MARK: Sketches under test

    private final class Reef: Sketch {
        @Param(0...1) var density = 0.5
        @Saved var polyps: [Vector2] = []
        @Saved var generation = 0
        @Saved var tint = Color(red: 1, green: 0, blue: 0)
        @Saved var depth = 0.0
        var builtInSetup = false

        override func setup() {
            builtInSetup = true
            polyps = [Vector2(1, 1)]     // what a fresh run starts from
            generation = 0
        }
    }

    /// The same piece after an edit: one property renamed, one retyped.
    private final class ReefEdited: Sketch {
        @Saved var polyps: [Vector2] = []
        @Saved var generations = 0        // was `generation`
        @Saved var tint = "red"           // was a Color
        @Saved var depth = 0.0            // declared after the one that fails
    }

    private final class OtherPiece: Sketch {
        @Saved var count = 0
    }

    // MARK: A place to write

    /// Each test gets its own directory, so nothing here can touch the
    /// checkpoints of a piece actually running on this machine.
    private func inTemporaryStore(_ body: () throws -> Void) rethrows {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-checkpoint-tests-\(UUID().uuidString)")
        Checkpoint.directoryOverride = directory
        defer {
            Checkpoint.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try body()
    }

    // MARK: The round trip

    @Test func aRunComesBackWhereItLeftOff() throws {
        try inTemporaryStore {
            let saved = Reef()
            saved.seed(4242)
            saved.setup()
            saved.polyps = [Vector2(10, 20), Vector2(30, 40)]
            saved.generation = 17
            saved.tint = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
            saved.density = 0.87
            saved.frameCount = 9000
            try Checkpoint.write(saved, time: 3600.5)

            let fresh = Reef()
            let checkpoint = try #require(Checkpoint.load(for: fresh, arguments: []))
            checkpoint.applyBeforeSetup(to: fresh)
            fresh.setup()
            checkpoint.applyAfterSetup(to: fresh)

            #expect(fresh.variation == 4242)
            #expect(fresh.density == 0.87)
            #expect(fresh.polyps == [Vector2(10, 20), Vector2(30, 40)])
            #expect(fresh.generation == 17)
            #expect(fresh.tint.blue == 0.75)
            #expect(fresh.frameCount == 9000)
            #expect(checkpoint.time == 3600.5)
        }
    }

    /// The parameters have to be back before `setup()` runs, or a sketch that builds
    /// itself from a parameter builds from the default and the restore is a lie.
    @Test func theParametersAreBackBeforeSetupRuns() throws {
        try inTemporaryStore {
            let saved = Reef()
            saved.density = 0.3
            try Checkpoint.write(saved, time: 0)

            let fresh = Reef()
            let checkpoint = try #require(Checkpoint.load(for: fresh, arguments: []))
            checkpoint.applyBeforeSetup(to: fresh)
            #expect(fresh.density == 0.3)
            #expect(!fresh.builtInSetup)      // setup() has not run yet
        }
    }

    /// The state has to be put back *after* `setup()`, because that is where a
    /// sketch fills its properties in. Restoring first would be overwritten.
    @Test func theStateIsBackAfterSetupRuns() throws {
        try inTemporaryStore {
            let saved = Reef()
            saved.polyps = [Vector2(5, 5), Vector2(6, 6), Vector2(7, 7)]
            try Checkpoint.write(saved, time: 0)

            let fresh = Reef()
            let checkpoint = try #require(Checkpoint.load(for: fresh, arguments: []))
            fresh.setup()                       // sets polyps to one point
            #expect(fresh.polyps.count == 1)
            checkpoint.applyAfterSetup(to: fresh)
            #expect(fresh.polyps.count == 3)
        }
    }

    // MARK: What happens when the sketch has moved on

    /// A renamed property finds nothing and keeps what `setup()` gave it. A
    /// retyped one fails to decode and does the same. Neither costs the piece
    /// the properties that did not change.
    @Test func anEditedSketchKeepsWhatItCanAndDropsTheRest() throws {
        try inTemporaryStore {
            let saved = Reef()
            saved.polyps = [Vector2(1, 2), Vector2(3, 4)]
            saved.generation = 12
            saved.tint = Color(red: 0, green: 1, blue: 0)
            saved.depth = 3.5
            try Checkpoint.write(saved, time: 0)

            // Same sketch name, different properties: the file is still read.
            let edited = ReefEdited()
            let checkpoint = try #require(Checkpoint.load(forSketchNamed: "Reef"))
            checkpoint.applyAfterSetup(to: edited)

            #expect(edited.polyps == [Vector2(1, 2), Vector2(3, 4)])   // unchanged, restored
            #expect(edited.generations == 0)                            // renamed, left alone
            #expect(edited.tint == "red")                               // retyped, left alone
            // Declared after the one that could not be read: a property that
            // fails costs itself and nothing behind it.
            #expect(edited.depth == 3.5)
        }
    }

    @Test func aFileFromAnotherSketchIsIgnored() throws {
        try inTemporaryStore {
            let other = OtherPiece()
            other.count = 5
            try Checkpoint.write(other, time: 0)
            #expect(Checkpoint.load(for: Reef(), arguments: []) == nil)
        }
    }

    @Test func aFileThatIsNotJSONIsIgnored() throws {
        try inTemporaryStore {
            let sketch = Reef()
            let url = try #require(Checkpoint.url(for: sketch))
            try Data("half a file".utf8).write(to: url)
            #expect(Checkpoint.load(for: sketch, arguments: []) == nil)
        }
    }

    @Test func aFileFromAnotherFormatIsIgnored() throws {
        try inTemporaryStore {
            let sketch = Reef()
            try Checkpoint.write(sketch, time: 0)
            let url = try #require(Checkpoint.url(for: sketch))
            var file = try #require(JSONSerialization.jsonObject(
                with: Data(contentsOf: url)) as? [String: Any])
            file["version"] = Checkpoint.formatVersion + 1
            try JSONSerialization.data(withJSONObject: file).write(to: url)
            #expect(Checkpoint.load(for: sketch, arguments: []) == nil)
        }
    }

    @Test func startingFreshLeavesTheFileAlone() throws {
        try inTemporaryStore {
            let sketch = Reef()
            sketch.generation = 3
            try Checkpoint.write(sketch, time: 0)
            #expect(Checkpoint.load(for: sketch, arguments: ["x", "--fresh"]) == nil)
            // Ignored, not deleted: the state is still there for the next launch.
            let url = try #require(Checkpoint.url(for: sketch))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func forgettingRemovesTheFile() throws {
        try inTemporaryStore {
            let sketch = Reef()
            try Checkpoint.write(sketch, time: 0)
            let url = try #require(Checkpoint.url(for: sketch))
            #expect(FileManager.default.fileExists(atPath: url.path))
            Checkpoint.forget(sketch)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: The file itself

    /// It is JSON somebody can open, because the first thing worth doing when a
    /// piece comes back wrong is reading the state it came back with.
    @Test func theFileIsReadable() throws {
        try inTemporaryStore {
            let sketch = Reef()
            sketch.polyps = [Vector2(1, 2)]
            try Checkpoint.write(sketch, time: 12.5)
            let url = try #require(Checkpoint.url(for: sketch))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("\"sketch\" : \"Reef\""))
            #expect(text.contains("\"polyps\""))
            #expect(text.contains("\"time\" : 12.5"))
            // Nested as real JSON rather than a string of escaped JSON.
            let file = try #require(JSONSerialization.jsonObject(
                with: Data(contentsOf: url)) as? [String: Any])
            let state = try #require(file["state"] as? [String: Any])
            #expect(state["polyps"] is [Any])
        }
    }

    // MARK: The declaration

    @Test func checkpointingIsOffUntilItIsAskedFor() {
        #expect(Installation.on.checkpoint.interval == nil)
        #expect(Installation.off.checkpoint.interval == nil)
        #expect(Installation(checkpoint: .every(seconds: 60)).checkpoint.interval == 60)
        // A cadence of nothing is no cadence.
        #expect(Installation(checkpoint: .every(seconds: 0)).checkpoint.interval == nil)
    }
}

private extension Checkpoint {
    /// Load whatever is stored under `name`, whichever sketch is asking. Only
    /// the tests need this: it is how an edited sketch reads the file its
    /// earlier self wrote.
    @MainActor
    static func load(forSketchNamed name: String) -> Checkpoint? {
        final class Stand: Sketch {}
        guard let url = url(forSketchNamed: name),
              let data = try? Data(contentsOf: url),
              let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return Checkpoint(
            sketchType: name,
            savedAt: Date(),
            variation: file["variation"] as? Int ?? 0,
            time: file["time"] as? Double ?? 0,
            frameCount: file["frameCount"] as? Int ?? 0,
            canvas: file["canvas"] as? [Int] ?? [],
            params: [:],
            state: file["state"] as? [String: Any] ?? [:])
    }
}
