import Foundation
import os
import Testing
@testable import OllinRuntime

/// The watcher behind live reload: a change in a watched folder is reported,
/// and a watcher that was stopped reports nothing more, however many times it
/// was started.
@Suite(.serialized) struct FileWatcherTests {

    private func makeFolder() throws -> String {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-watch-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        // FSEvents reports the path the system resolved, and the stream
        // starts from now: give it a moment to be listening.
        return folder
    }

    private func touch(_ folder: String, _ name: String) {
        FileManager.default.createFile(atPath: folder + "/" + name, contents: Data(UUID().uuidString.utf8))
    }

    /// Wait until `probe` holds, the probe before the clock.
    private func wait(upTo seconds: Double, _ probe: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            if probe() { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test func aWatcherStartedTwiceAndStoppedReportsNothingMore() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let reports = OSAllocatedUnfairLock(initialState: 0)
        let watcher = FileWatcher(paths: [folder], debounce: 0.05) { _ in reports.withLock { $0 += 1 } }

        // The control: started (twice), a change is reported.
        watcher.start()
        watcher.start()
        try await Task.sleep(nanoseconds: 300_000_000)
        touch(folder, "a.txt")
        #expect(await wait(upTo: 10) { reports.withLock { $0 } >= 1 }, "a running watcher reported nothing")

        // Stopped, it is stopped: the stream a second start() opened must
        // not have left the first one running behind it.
        watcher.stop()
        try await Task.sleep(nanoseconds: 300_000_000)
        let before = reports.withLock { $0 }
        touch(folder, "b.txt")
        try await Task.sleep(nanoseconds: 800_000_000)
        let after = reports.withLock { $0 }
        #expect(after == before, "a stopped watcher reported \(after - before) more changes")
    }
}
