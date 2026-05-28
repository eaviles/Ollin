// Re-exported so a sketch that only `import Ollin` can still name `CGSize` (and
// `CGFloat`/`CGPoint`/`CGRect`) when overriding `canvasSize`, without a second
// import.
@_exported import CoreGraphics

/// Common export resolutions as named `CGSize` presets for a sketch's
/// `canvasSize`. They use the leading-dot form, so a sketch can write:
///
/// ```swift
/// override var canvasSize: CGSize { .uhd4K }            // 4K landscape master
/// override var canvasSize: CGSize { .uhd4K.portrait }   // 4K vertical (2160×3840)
/// ```
///
/// Names describe the resolution or aspect rather than a brand; the platform a
/// size suits is noted in its comment. Use `portrait` / `landscape` to flip
/// orientation instead of listing every direction.
public extension CGSize {

    // MARK: Square (1:1)

    /// 1080×1080. The default canvas, and the square social/feed size.
    static let square1080 = CGSize(width: 1080, height: 1080)
    /// 1440×1440.
    static let square1440 = CGSize(width: 1440, height: 1440)
    /// 2160×2160. A 4K-class square master.
    static let square2160 = CGSize(width: 2160, height: 2160)

    // MARK: Landscape (16:9)

    /// 1280×720 (720p / HD).
    static let hd720 = CGSize(width: 1280, height: 720)
    /// 1920×1080 (1080p / Full HD).
    static let fhd1080 = CGSize(width: 1920, height: 1080)
    /// 2560×1440 (1440p / QHD).
    static let qhd1440 = CGSize(width: 2560, height: 1440)
    /// 3840×2160 (4K / UHD). The usual "4K video" deliverable.
    static let uhd4K = CGSize(width: 3840, height: 2160)
    /// 4096×2160 (DCI 4K). Cinema 4K, slightly wider than UHD; for film delivery.
    static let dci4K = CGSize(width: 4096, height: 2160)

    // MARK: Vertical (9:16)

    /// 1080×1920. Full-screen vertical video: stories, reels, TikTok, Shorts.
    static let vertical1080 = CGSize(width: 1080, height: 1920)

    // MARK: Portrait (4:5)

    /// 1080×1350. The portrait feed crop (e.g. Instagram).
    static let portrait1080 = CGSize(width: 1080, height: 1350)

    // MARK: Orientation

    /// The same size oriented tall (long side vertical). A no-op when the size is
    /// already portrait or square.
    var portrait: CGSize { width > height ? CGSize(width: height, height: width) : self }
    /// The same size oriented wide (long side horizontal). A no-op when the size
    /// is already landscape or square.
    var landscape: CGSize { width < height ? CGSize(width: height, height: width) : self }
}
