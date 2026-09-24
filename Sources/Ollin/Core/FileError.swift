import Foundation

/// What stopped a file being read or written: which file, what kind of
/// trouble, and what was wrong, in a sentence.
///
/// Every loader that takes a file, a bundled resource, or bytes throws one
/// rather than answering `nil`, so a missing file and a file in the wrong
/// format each say what they are: `Image`, `Mesh`, `Scene`, `SVG`, `Palette`,
/// `Table`, `JSON`, `IESProfile`, `ICCProfile`, the three fonts, and
/// `ComputeKernel`, with their `load…` calls on the sketch. The mesh and scene
/// writers throw one too.
///
/// `setup()` does not throw, so a sketch picks one of two answers there:
///
/// ```swift
/// photo = try! loadImage("photo.jpg")      // stop, naming the file and why
/// logo = try? loadSVG("logo.svg")          // carry on without it
/// ```
public struct FileError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {

    /// The kind of trouble, for a sketch that answers one differently from
    /// another.
    public enum Kind: Sendable, Equatable {
        /// No file at that path, or no resource by that name in the bundle.
        case missing
        /// The file is there, but its bytes are not what the loader reads.
        case unreadable
        /// The file could not be written.
        case unwritable
    }

    /// The kind of trouble.
    public let kind: Kind
    /// The file's path, or the resource's name; `nil` for bytes handed over
    /// in memory.
    public let path: String?
    /// What was wrong, in a sentence.
    public let problem: String

    /// A failure of this kind for this file, said in a sentence. For an
    /// extension's own loader, so it fails the way the built-in ones do.
    public init(_ kind: Kind, path: String?, problem: String) {
        self.kind = kind
        self.path = path
        self.problem = problem
    }

    public var description: String {
        guard let path else { return problem }
        return "\(path): \(problem)"
    }

    public var errorDescription: String? { description }
}

extension FileError {

    /// Bytes that are not what the loader reads, from a file at `url` (or in
    /// memory, when there is none).
    package static func unreadable(_ url: URL?, _ problem: String) -> FileError {
        FileError(.unreadable, path: url?.path, problem: problem)
    }

    /// A file that could not be written.
    package static func unwritable(_ url: URL, _ problem: String) -> FileError {
        FileError(.unwritable, path: url.path, problem: problem)
    }

    /// Throw `missing` unless a file (not a folder) is at `url`. A network
    /// address is left for the read itself to answer.
    package static func requireFile(_ url: URL) throws {
        guard url.isFileURL else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileError(.missing, path: url.path, problem: "no such file")
        }
        guard !isDirectory.boolValue else {
            throw FileError(.unreadable, path: url.path, problem: "is a folder, not a file")
        }
    }

    /// The bytes of the file at `url`, or `missing` / `unreadable`. A network
    /// address that answers with nothing is `missing`.
    package static func contents(of url: URL) throws -> Data {
        try requireFile(url)
        do {
            return try Data(contentsOf: url)
        } catch {
            guard url.isFileURL else {
                throw FileError(.missing, path: url.absoluteString,
                                problem: "could not be fetched: \(error.localizedDescription)")
            }
            throw FileError(.unreadable, path: url.path, problem: "could not be read: \(error.localizedDescription)")
        }
    }

    /// The text of the file at `url` as UTF-8, or `missing` / `unreadable`.
    package static func text(of url: URL) throws -> String {
        let data = try contents(of: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw FileError(.unreadable, path: url.path, problem: "is not UTF-8 text")
        }
        return text
    }

    /// Where a bundled resource is, or `missing` naming what was looked for.
    package static func resource(_ name: String, withExtension ext: String?, in bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        let file = ext.map { $0.isEmpty ? name : "\(name).\($0)" } ?? name
        throw FileError(.missing, path: file,
                        problem: "no resource by that name in \(bundle.bundleURL.lastPathComponent)")
    }
}
