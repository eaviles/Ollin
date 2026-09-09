import Foundation

/// A short film that ships with Ollin, for the techniques that need motion
/// rather than a still: optical flow, contour tracing, a slit scan, a skeleton
/// or a matte that moves.
///
/// It lives beside the photographs and is vended as a URL rather than as a
/// player, because opening a film belongs to `OllinVideo` and a satellite
/// never depends on another satellite:
///
///     let clip = VideoPlayer(url: SampleClip.dance.url)
///     clip.loops = true
///     clip.play()
///
/// A `VideoPlayer` is both a `FrameSource` and a `VideoFeed`, so it goes
/// wherever a camera goes and every tracker reads it unchanged.
public struct SampleClip: Hashable, Sendable {
    /// The file name inside the bundle, without its extension.
    public let name: String
    /// A few words on what the film shows.
    public let subject: String
    /// Who made it, where, and under which terms.
    public let credit: SamplePhoto.Credit

    /// Where the film is, inside this library's own bundle.
    public var url: URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "mp4") else {
            preconditionFailure("OllinSamplePhotos: \(name).mp4 is missing from the bundle")
        }
        return url
    }

    /// One dancer on a plain studio ground, thirty seconds of it, the camera
    /// locked off. Almost two thirds of the frame never changes, which is what
    /// optical flow and a slit scan want, and the body model finds all nineteen
    /// joints in every frame sampled across the whole run, which no still can
    /// show moving. Cut to a square from a wider frame: he reaches the edge
    /// later in the original, and never once inside this window.
    public static let dance = SampleClip(
        name: "dance",
        subject: "a man dancing on a plain studio ground, the camera still",
        credit: SamplePhoto.Credit(
            photographer: "Antoni Shkraba", place: "location not given",
            source: "https://www.pexels.com/video/video-of-a-man-dancing-7571381/",
            license: "Pexels License", licenseURL: "https://www.pexels.com/license/"))

    /// Every bundled film.
    public static let all: [SampleClip] = [.dance]
}
