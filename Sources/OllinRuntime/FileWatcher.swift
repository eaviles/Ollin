import Foundation
import CoreServices

/// Watches one or more directories for file changes via FSEvents and reports the
/// changed paths, coalesced over a short debounce window.
///
/// It watches *directories* on purpose: editors save by writing a temp file and
/// renaming it over the original, which invalidates a file-descriptor watch but
/// shows up fine as a directory event.
package final class FileWatcher {
    private let paths: [String]
    private let debounce: TimeInterval
    private let onChange: @Sendable ([String]) -> Void

    private let queue = DispatchQueue(label: "studio.ollin.filewatcher")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var changed = Set<String>()

    package init(paths: [String], debounce: TimeInterval = 0.15, onChange: @escaping @Sendable ([String]) -> Void) {
        self.paths = paths
        self.debounce = debounce
        self.onChange = onChange
    }

    package func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        // C callback: no captures — pulls `self` back out of the context info.
        let callback: FSEventStreamCallback = { _, info, count, pathsPointer, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
            watcher.received(paths)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,   // coalescing latency (s)
            // UseCFTypes makes `eventPaths` a CFArray of CFString (castable to
            // [String]); without it it's a C `char **` and the cast crashes.
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer))
        else {
            FileHandle.standardError.write(Data("Ollin: couldn't start file watcher\n".utf8))
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    package func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Called on `queue` for each FSEvents batch; coalesce + debounce, then fire.
    private func received(_ paths: [String]) {
        changed.formUnion(paths)
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let batch = Array(self.changed)
            self.changed.removeAll()
            self.onChange(batch)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
