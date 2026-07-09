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
    /// A canvas that renders a physical page at higher than 72 dpi: the pixel
    /// dimensions carry the render/export resolution, the point dimensions the
    /// true page size the PDF export writes. Made by `dpi(_:)`; rarely spelled
    /// directly.
    case page(width: Int, height: Int, pointWidth: Int, pointHeight: Int)

    /// Canvas width in pixels.
    public var width: Int {
        switch self {
        case .square(let side): side
        case .size(let w, _): w
        case .page(let w, _, _, _): w
        }
    }

    /// Canvas height in pixels.
    public var height: Int {
        switch self {
        case .square(let side): side
        case .size(_, let h): h
        case .page(_, let h, _, _): h
        }
    }

    /// The physical page size in PDF points (72 per inch): the declared page
    /// for a `dpi(_:)`-scaled canvas, else the pixel dimensions (one pixel is
    /// one point, the PDF export mapping).
    var pointSize: (width: Int, height: Int) {
        if case let .page(_, _, pw, ph) = self { return (pw, ph) }
        return (width, height)
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

    // MARK: Paper (PDF points)

    // Standard paper sizes in PDF points (72 per inch), portrait like the
    // physical sheet; add `.landscape` to flip. PDF export maps one canvas pixel
    // to one point, so a sketch on one of these exports as a true-to-size page
    // (`--export-pdf`), and the vector output prints sharp at any resolution.
    // For a print-resolution *raster* too, add `dpi(_:)`: `.a4.dpi(300)` renders
    // at 300 dots per inch while the PDF page stays exactly A4.

    /// 612×792: US Letter, 8.5×11 in.
    public static let usLetter = CanvasSize.size(612, 792)
    /// 612×1008: US Legal, 8.5×14 in.
    public static let usLegal = CanvasSize.size(612, 1008)
    /// 842×1191: ISO A3, 297×420 mm.
    public static let a3 = CanvasSize.size(842, 1191)
    /// 595×842: ISO A4, 210×297 mm.
    public static let a4 = CanvasSize.size(595, 842)
    /// 420×595: ISO A5, 148×210 mm.
    public static let a5 = CanvasSize.size(420, 595)

    // MARK: Orientation

    /// The same size oriented tall (long side vertical). A no-op when the size is
    /// already portrait or square.
    public var portrait: CanvasSize { width > height ? flipped : self }
    /// The same size oriented wide (long side horizontal). A no-op when the size
    /// is already landscape or square.
    public var landscape: CanvasSize { width < height ? flipped : self }

    /// Width and height swapped (a page swaps its point size too).
    private var flipped: CanvasSize {
        if case let .page(w, h, pw, ph) = self {
            return .page(width: h, height: w, pointWidth: ph, pointHeight: pw)
        }
        return .size(height, width)
    }

    // MARK: Resolution

    /// The same canvas rendered at `dpi` dots per inch instead of the native 72:
    /// the pixel dimensions scale by `dpi / 72` while the physical page size
    /// stays what it was, so `.a4.dpi(300)` renders and raster-exports at print
    /// resolution and a PDF export still writes a true-to-size A4 page. Works on
    /// any size (the size it's called on is taken as the 72-dpi page), and 72
    /// returns the plain size unchanged.
    public func dpi(_ dpi: Int) -> CanvasSize {
        let (pw, ph) = pointSize
        guard dpi > 0, dpi != 72 else {
            if case .page = self { return .size(pw, ph) }   // back to one pixel per point
            return self
        }
        func scaled(_ points: Int) -> Int {
            max(1, Int((Double(points) * Double(dpi) / 72).rounded()))
        }
        return .page(width: scaled(pw), height: scaled(ph), pointWidth: pw, pointHeight: ph)
    }

    // MARK: Interop

    /// The size as a `CGSize`, for the AppKit window and Metal render target,
    /// which speak Core Graphics. (Pixels are integers, so this is exact.)
    public var cgSize: CGSize { CGSize(width: Double(width), height: Double(height)) }
}
