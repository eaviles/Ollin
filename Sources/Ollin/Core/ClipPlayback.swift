import Foundation

/// A recording being played from a file, with a playhead: the two things an
/// analysis that reads the *whole* file ahead of time needs, to find the file
/// and to line its results up with the picture on screen. The video player
/// conforms; an analysis (the vision satellite's `DepthClip`) binds to one and
/// answers for wherever the playhead stands, which under a headless export is
/// the frame the export clock has reached.
@MainActor
public protocol ClipPlayback: AnyObject {
    /// The file being played.
    var url: URL { get }

    /// The playhead, in seconds from the start of the file.
    var currentTime: Double { get }
}
