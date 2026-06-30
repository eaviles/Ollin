import Foundation
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
        watcher.stop()
        print("OllinLive watchtest: PASS — observed atomic save of \(swiftPath)")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive watchtest: FAIL — \(message)\n".utf8))
        exit(1)
    }
}
