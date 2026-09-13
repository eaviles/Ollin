import Foundation

/// A sheet of paper, or the stock on a machine bed, in millimeters.
///
/// The machine exports ask for real units, and most of the time the real unit
/// is a sheet somebody already owns: `GCode(.plotter(), paper: .a4)` plans a
/// drawing that fits an A4 page, margin included, and `DXF(paper: .a3)` sizes
/// a drawing for an A3 board. A size that is not on the list is spelled out,
/// `PaperSize(width: 500, height: 700)`.
///
/// ```swift
/// GCode(.plotter(), paper: .a4)                    // 10 mm in from every edge
/// GCode(.plotter(), paper: .a3.landscape, margin: 15)
/// DXF(paper: .usLetter)
/// override var canvasSize: CanvasSize { PaperSize.a5.canvasSize(dpi: 300) }
/// ```
///
/// The ISO sizes are portrait, like the sheet in the ream; add `.landscape` to
/// turn one. Names match `CanvasSize`'s page presets, which are the same
/// sheets in PDF points, and `canvasSize(dpi:)` is the bridge between them.
public struct PaperSize: Hashable, Sendable {
    /// The sheet's width in millimeters.
    public var width: Double
    /// The sheet's height in millimeters.
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    // MARK: ISO 216, A series (portrait)

    /// 841 × 1189 mm.
    public static let a0 = PaperSize(width: 841, height: 1189)
    /// 594 × 841 mm.
    public static let a1 = PaperSize(width: 594, height: 841)
    /// 420 × 594 mm.
    public static let a2 = PaperSize(width: 420, height: 594)
    /// 297 × 420 mm.
    public static let a3 = PaperSize(width: 297, height: 420)
    /// 210 × 297 mm.
    public static let a4 = PaperSize(width: 210, height: 297)
    /// 148 × 210 mm.
    public static let a5 = PaperSize(width: 148, height: 210)
    /// 105 × 148 mm.
    public static let a6 = PaperSize(width: 105, height: 148)

    // MARK: US sizes (portrait)

    /// 8.5 × 11 in, which is 215.9 × 279.4 mm.
    public static let usLetter = PaperSize(width: 215.9, height: 279.4)
    /// 8.5 × 14 in, which is 215.9 × 355.6 mm.
    public static let usLegal = PaperSize(width: 215.9, height: 355.6)
    /// 11 × 17 in, which is 279.4 × 431.8 mm. Also called ledger when it lies
    /// on its side.
    public static let usTabloid = PaperSize(width: 279.4, height: 431.8)

    /// Every named size, by the name it is spelled here.
    static let catalog: [(name: String, size: PaperSize)] = [
        ("a0", .a0), ("a1", .a1), ("a2", .a2), ("a3", .a3), ("a4", .a4), ("a5", .a5), ("a6", .a6),
        ("usLetter", .usLetter), ("usLegal", .usLegal), ("usTabloid", .usTabloid),
    ]

    /// The named size for a name as it is spelled here (`"a4"`, `"usLetter"`),
    /// case-insensitively; the US sizes also answer to their bare names
    /// (`"letter"`, `"legal"`, `"tabloid"`). Nothing else matches.
    public init?(named name: String) {
        let key = name.lowercased()
        let bare = key.hasPrefix("us") ? key : "us" + key
        for entry in Self.catalog where entry.name.lowercased() == key || entry.name.lowercased() == bare {
            self = entry.size
            return
        }
        return nil
    }

    // MARK: Orientation

    /// The same sheet standing tall (long side vertical). A no-op when it
    /// already is, or when it is square.
    public var portrait: PaperSize { width > height ? PaperSize(width: height, height: width) : self }
    /// The same sheet lying wide (long side horizontal). A no-op when it
    /// already is, or when it is square.
    public var landscape: PaperSize { width < height ? PaperSize(width: height, height: width) : self }

    // MARK: Bridges

    /// The sheet as a canvas: the page in PDF points (72 to the inch, so
    /// `PaperSize.a4.canvasSize()` is `CanvasSize.a4`), and at any other `dpi`
    /// a page-carrying canvas the way `CanvasSize.dpi(_:)` makes one, so a PDF
    /// export prints at true size and a raster export carries the resolution.
    /// The pixels are counted from the millimeters directly rather than from
    /// the rounded points, so A4 at 300 dpi is 2480 by 3508, the size a print
    /// shop expects.
    public func canvasSize(dpi: Int = 72) -> CanvasSize {
        func at(_ millimeters: Double, _ perInch: Int) -> Int {
            max(1, Int((millimeters / 25.4 * Double(perInch)).rounded()))
        }
        guard dpi > 0, dpi != 72 else { return .size(at(width, 72), at(height, 72)) }
        return .page(width: at(width, dpi), height: at(height, dpi),
                     pointWidth: at(width, 72), pointHeight: at(height, 72))
    }
}
