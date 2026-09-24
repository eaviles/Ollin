import Foundation
import Testing
import OllinMutation

/// What a reader of a file may ask for in one block while it reads: the
/// harness's floor, plus sixty-four bytes for every byte of the file, which is
/// more than any reader here needs to turn text into numbers or a record into
/// its value. A reader that sets aside what a count in the file declares,
/// before checking the count against the bytes that remain, asks for far more.
let fileBound = AllocationBound(perInputByte: 64)

/// Why the file suites stand down under Thread Sanitizer.
let fileRunReason: Comment = "a reader of a file holds no handoff between threads, the allocation watch cannot see past the sanitizer's own allocator, and under it a run takes many times as long; the plain run holds these"

/// A folder of its own for the readers that only open a path: each case is
/// written over the same file, so a run leaves one file behind at most, and
/// the folder goes when the test ends.
final class ScratchFolder {
    let url: URL

    init(_ name: String) {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-mutation-files-\(name)-\(ProcessInfo.processInfo.processIdentifier)",
                                    isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Writes `bytes` to `name` in the folder and returns where.
    @discardableResult
    func write(_ bytes: [UInt8], named name: String) -> URL {
        let file = url.appendingPathComponent(name)
        FileManager.default.createFile(atPath: file.path, contents: Data(bytes))
        return file
    }
}

extension String {
    /// The text as the bytes a file would hold.
    var bytes: [UInt8] { Array(utf8) }
}
