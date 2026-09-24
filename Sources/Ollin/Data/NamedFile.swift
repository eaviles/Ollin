import Foundation

/// A file that another file names inside itself: a model's buffer or picture,
/// a material's texture, a shader's include.
///
/// The name comes from the file, and a file may name anything: a folder, a
/// socket, or a device such as `/dev/zero`, which reads without end and would
/// take the sketch's memory with it. Reading only regular files of a known
/// size keeps a file handed over from asking for more than is on the disk.
package enum NamedFile {

    /// The bytes at `url`, or `nil` when the path does not lead to a regular
    /// file, or leads to one larger than `limit` bytes.
    package static func data(at url: URL, limit: Int = 1 << 30) -> Data? {
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) <= limit else { return nil }
        return try? Data(contentsOf: resolved)
    }

    /// The text at `url` (a shader's include), read under the same rule.
    package static func text(at url: URL, limit: Int = 64 << 20) -> String? {
        data(at: url, limit: limit).map { String(decoding: $0, as: UTF8.self) }
    }
}
