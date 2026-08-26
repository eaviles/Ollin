import AppKit
import Ollin
import os

/// Windowed smoke tests for the gallery, in the house `--selftest` idiom but
/// against the real window (switching examples exercises the view swap, the
/// loader, and each sketch's own machinery, none of which run headless).
///
///   swift run OllinExamples --cycletest [count]
///
/// walks the selection through `count` examples spread across the catalog
/// (default 40), waits for each to load and run a beat, then verifies that
/// every outgoing `Sketch` instance actually deallocated. That release is what
/// stops a previous example's sound and returns its resources, so a strong
/// reference leaking anywhere fails loudly here instead of surfacing as sound
/// bleeding between examples and an eventual crash after enough switches.
///
///   swift run OllinExamples --self-shot <path.png>
///
/// writes a capture of the window into `path.png` a few seconds after launch,
/// drawn by the window itself (`cacheDisplay`), so it needs no screen-recording
/// permission. The Metal canvas draws outside AppKit and comes out empty; the
/// chrome (sidebars, title bar) is what this is for.
enum GalleryHarness {
    /// How many examples `--cycletest` visits, when requested.
    static let cycleCount: Int? = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--cycletest") else { return nil }
        if arguments.indices.contains(flag + 1), let count = Int(arguments[flag + 1]) {
            return max(1, count)
        }
        return 40
    }()

    /// `--cycle-filter a,b,c` narrows `--cycletest` to examples whose id
    /// contains one of the given substrings, in catalog order. For pinning a
    /// leak down to one example against a known-good one.
    static let cycleFilter: [String]? = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--cycle-filter"),
              arguments.indices.contains(flag + 1) else { return nil }
        return arguments[flag + 1].split(separator: ",").map(String.init)
    }()

    /// `--cycle-hold` keeps the app alive after the cycletest verdict, so an
    /// inspection tool (`leaks`, `heap`) can be pointed at the live process.
    static let cycleHold = CommandLine.arguments.contains("--cycle-hold")

    /// Where `--self-shot` writes the window capture, when requested.
    static let shotPath: String? = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--self-shot"),
              arguments.indices.contains(flag + 1) else { return nil }
        return arguments[flag + 1]
    }()

    /// A watchdog on its own thread, because the condition it guards against
    /// takes the main thread down with it: an example whose `draw()` blocks
    /// (say, a file scan waiting on an unanswered privacy prompt) wedges the
    /// whole app, and the cycle's own 60s timeout can never fire from a
    /// blocked main actor. The cycle beats it per example; if a beat goes
    /// stale the watchdog names the example on stderr and exits 2, so an
    /// unattended run reports the wedge instead of hanging forever.
    final class Watchdog: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock<(name: String, beat: Date, finished: Bool)>(
            initialState: ("(starting)", Date(), false))

        func beat(_ name: String) {
            state.withLock { $0 = (name, Date(), false) }
        }

        func finish() {
            state.withLock { $0.finished = true }
        }

        func start(limit: TimeInterval = 90) {
            DispatchQueue.global(qos: .utility).async { [self] in
                while true {
                    Thread.sleep(forTimeInterval: 5)
                    let (name, beat, finished) = state.withLock { $0 }
                    if finished { return }
                    if Date().timeIntervalSince(beat) > limit {
                        let message = "OllinExamples cycletest: WEDGED on \(name): "
                            + "the main thread has been stuck over \(Int(limit))s; exiting\n"
                        FileHandle.standardError.write(Data(message.utf8))
                        _exit(2)
                    }
                }
            }
        }
    }

    /// A sketch instance held only weakly, so the harness can ask "did the
    /// gallery let go of it?" without keeping it alive itself.
    final class WeakSketch {
        weak var sketch: Sketch?
        let name: String

        init(_ sketch: Sketch, name: String) {
            self.sketch = sketch
            self.name = name
        }
    }

    /// Draw the (frontmost) gallery window into a PNG. Returns whether both the
    /// capture and the write succeeded.
    @MainActor
    static func writeWindowShot(to path: String) -> Bool {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}
