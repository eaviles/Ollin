import Foundation

/// What stopped an export: the file it was writing, the frame it had reached,
/// and what went wrong, in a sentence.
///
/// Every `OllinApp.export…` call throws one rather than stopping the process,
/// so a sketch, a test, or a build step that exports can say what happened
/// and carry on. From the command line the export flags print the sentence
/// and exit with status 1, which is what a script running the export sees.
///
/// ```swift
/// do {
///     try OllinApp.exportVideo(Loop(), to: "loop.mp4", frames: 240)
/// } catch let error as ExportError {
///     print(error)    // "loop.mp4: the encoder refused frame 17: …"
/// }
/// ```
public struct ExportError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {

    /// The kind of trouble, for a caller that answers one differently from
    /// another.
    public enum Kind: Sendable, Equatable {
        /// The request cannot be met as asked: a file extension no writer
        /// takes, a codec the container cannot carry, a rate control this
        /// Mac's encoder lacks, a parameter the sketch does not declare, a
        /// sketch that names no inks. Nothing was drawn.
        case unsupported
        /// A frame was not drawn: no Metal device, a renderer that would not
        /// start, a frame that did not come back from the GPU.
        case unrendered
        /// The frame was drawn and the file would not take it: the writer
        /// would not start, stopped taking frames, refused one, or could not
        /// finish.
        case unwritable
    }

    /// The kind of trouble.
    public let kind: Kind
    /// The file the export was writing (a folder, for the calls that write
    /// several); empty for a drive that writes no file.
    public let path: String
    /// The written frame the export had reached when it stopped, counted from
    /// 0; `nil` when it stopped before the first frame or after the last.
    public let frame: Int?
    /// What went wrong, in a sentence.
    public let problem: String

    /// A failure of this kind for this file, said in a sentence.
    public init(_ kind: Kind, path: String, frame: Int? = nil, problem: String) {
        self.kind = kind
        self.path = path
        self.frame = frame
        self.problem = problem
    }

    public var description: String { path.isEmpty ? problem : "\(path): \(problem)" }

    public var errorDescription: String? { description }
}
