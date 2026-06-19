// For the `cgSize` bridge below — AppKit windows and the Metal render target
// speak `CGSize`. (The module-wide re-export that gives sketches `sin`/`cos`/…
// and the CG value types lives in `Exports.swift`.)
import CoreGraphics

/// The resolution a sketch renders and exports at, in whole pixels. A canvas is
/// an integer grid, so dimensions are `Int` (the export PNG is exactly this many
/// pixels). Override `Sketch.canvasSize` with a square, an explicit size, or a
/// named preset, using the leading-dot form:
///
/// ```swift
/// override var canvasSize: CanvasSize { .square(1000) }     // 1000×1000
/// override var canvasSize: CanvasSize { .size(1000, 600) }  // any rectangle
/// override var canvasSize: CanvasSize { .uhd4K }            // a 4K preset
/// override var canvasSize: CanvasSize { .uhd4K.portrait }   // flipped (2160×3840)
/// ```
///
/// Preset names describe the resolution or aspect rather than a brand; the
/// platform a size suits is noted in its comment. Use `portrait` / `landscape`
/// to flip orientation instead of listing every direction.
public enum CanvasSize: Sendable, Equatable {

    /// A square canvas, `side`×`side`. A readable alias for `.size(side, side)`.
    case square(Int)
    /// A canvas of `width`×`height` pixels.
    case size(Int, Int)

    /// Canvas width in pixels.
    public var width: Int {
        switch self {
        case .square(let side): side
        case .size(let w, _): w
        }
    }

    /// Canvas height in pixels.
    public var height: Int {
        switch self {
        case .square(let side): side
        case .size(_, let h): h
        }
    }

    // MARK: Square (1:1)

    /// 1080×1080. The default canvas, and the square social/feed size.
    public static let square1080 = CanvasSize.square(1080)
    /// 1440×1440.
    public static let square1440 = CanvasSize.square(1440)
    /// 2160×2160. A 4K-class square master.
    public static let square2160 = CanvasSize.square(2160)

    // MARK: Landscape (16:9)

    /// 1280×720 (720p / HD).
    public static let hd720 = CanvasSize.size(1280, 720)
    /// 1920×1080 (1080p / Full HD).
    public static let fhd1080 = CanvasSize.size(1920, 1080)
    /// 2560×1440 (1440p / QHD).
    public static let qhd1440 = CanvasSize.size(2560, 1440)
    /// 3840×2160 (4K / UHD). The usual "4K video" deliverable.
    public static let uhd4K = CanvasSize.size(3840, 2160)
    /// 4096×2160 (DCI 4K). Cinema 4K, slightly wider than UHD; for film delivery.
    public static let dci4K = CanvasSize.size(4096, 2160)

    // MARK: Vertical (9:16)

    /// 1080×1920. Full-screen vertical video: stories, reels, TikTok, Shorts.
    public static let vertical1080 = CanvasSize.size(1080, 1920)

    // MARK: Portrait (4:5)

    /// 1080×1350. The portrait feed crop (e.g. Instagram).
    public static let portrait1080 = CanvasSize.size(1080, 1350)

    // MARK: Orientation

    /// The same size oriented tall (long side vertical). A no-op when the size is
    /// already portrait or square.
    public var portrait: CanvasSize { width > height ? .size(height, width) : self }
    /// The same size oriented wide (long side horizontal). A no-op when the size
    /// is already landscape or square.
    public var landscape: CanvasSize { width < height ? .size(height, width) : self }

    // MARK: Interop

    /// The size as a `CGSize`, for the AppKit window and Metal render target,
    /// which speak Core Graphics. (Pixels are integers, so this is exact.)
    public var cgSize: CGSize { CGSize(width: Double(width), height: Double(height)) }
}
