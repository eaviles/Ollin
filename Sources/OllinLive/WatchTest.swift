import Foundation
import OllinRuntime
import os

/// `swift run OllinLive --watchtest` — a headless check that the FSEvents
/// `FileWatcher` fires on an atomic file save (the way editors write). Needs no
/// window: FSEvents delivers on a dispatch queue, so we just wait on a semaphore.
enum WatchTest {
    static func run() -> Never {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinLive-watchtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let file = (dir as NSString).appendingPathComponent("Sketch.swift")
        try? "// v1".write(toFile: file, atomically: true, encoding: .utf8)

        let fired = DispatchSemaphore(value: 0)
        let observed = OSAllocatedUnfairLock<[String]>(initialState: [])
        let watcher = FileWatcher(paths: [dir]) { changed in
            observed.withLock { $0 = changed }
            fired.signal()
        }
        watcher.start()

        // Let FSEvents arm, then save the file the way an editor does (atomic
        // write = temp file + rename over the original).
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            try? "// v2 — changed".write(toFile: file, atomically: true, encoding: .utf8)
        }

        guard fired.wait(timeout: .now() + 5) == .success else {
            fail("watcher did not fire within 5s of a save")
        }
        let observedPaths = observed.withLock { $0 }
        guard let swiftPath = observedPaths.first(where: { $0.hasSuffix(".swift") }) else {
            fail("watcher fired but reported no .swift path: \(observedPaths)")
        }

        // A target's files sit in folders of their own below the sketch, and
        // a save there must reload it too: the watch reaches every level.
        let nested = (dir as NSString).appendingPathComponent("Shapes")
        try? FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        let helper = (nested as NSString).appendingPathComponent("Ring.swift")
        // Drain whatever the folder's creation reported before the save.
        _ = fired.wait(timeout: .now() + 0.5)
        observed.withLock { $0 = [] }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            try? "// a helper".write(toFile: helper, atomically: true, encoding: .utf8)
        }
        var sawHelper = false
        let deadline = Date().addingTimeInterval(5)
        repeat {
            sawHelper = observed.withLock { $0.contains { $0.hasSuffix("Shapes/Ring.swift") } }
            if sawHelper { break }
            _ = fired.wait(timeout: .now() + 0.5)
        } while Date() < deadline
        guard sawHelper else { fail("a save in a folder below the watched one went unreported") }
        watcher.stop()
        print("OllinLive watchtest: PASS: observed atomic saves of \(swiftPath) and of a file a folder below")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive watchtest: FAIL — \(message)\n".utf8))
        exit(1)
    }
}
