@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// Drawing part of an image: a source rectangle in the image's own pixels.
///
/// The promise is that a cell of a sheet reads like the same cell cropped out first,
/// at its own size and larger, so the check draws a sheet of seeded noise cell by cell
/// and compares it with each cell cropped to its own image and drawn whole. Noise
/// makes every texel differ from its neighbors, so a read one texel off, or one that
/// filters in the next cell's border, shows at once. The planted case draws through
/// the plain crop `.cover` uses, which does read across the edge, so the comparison
/// is shown to see a bleed when there is one.
@Suite
@MainActor
struct ImageSourceTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func aCellDrawsLikeTheSameCellCroppedFirst() throws {
        for scale in [1.0, 3.0, 4.5] {
            let fromSheet = try OllinApp.image(of: SheetProbe(mode: .sheet, scale: scale), frame: 0)
            let cropped = try OllinApp.image(of: SheetProbe(mode: .cropped, scale: scale), frame: 0)
            let (differing, worst) = Self.compare(fromSheet, cropped)
            #expect(differing == 0, "at \(scale)x, \(differing) pixels differ, by up to \(worst) levels")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theComparisonSeesANeighborsBorder() throws {
        // The same cells through the crop that reads past its edge: magnified, each
        // cell's border filters in its neighbor's texels, and the comparison above
        // must count that.
        let bleeding = try OllinApp.image(of: SheetProbe(mode: .plainCrop, scale: 3), frame: 0)
        let cropped = try OllinApp.image(of: SheetProbe(mode: .cropped, scale: 3), frame: 0)
        let (differing, worst) = Self.compare(bleeding, cropped)
        #expect(differing > 500, "a crop that reads past its edge differed on only \(differing) pixels")
        #expect(worst > 32, "the bleed should be plain to see, was \(worst) levels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPartThatRunsOffThePictureDrawsOnlyWhatIsOnIt() throws {
        // Half the rectangle lies past the sheet's right edge: the half on it lands in
        // the left half of the box, and the right half stays background.
        let image = try OllinApp.image(of: SheetProbe(mode: .offTheEdge, scale: 4), frame: 0)
        let data = Self.rgba(image)
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * image.width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
        // Inside the left half: a picture texel, never the black background.
        let left = pixel(8 + 16, 8 + 16)
        #expect(left.0 + left.1 + left.2 > 30, "expected the sheet's last column, got \(left)")
        // Inside the right half: background.
        #expect(pixel(8 + 3 * 32, 8 + 16) == (0, 0, 0))
    }

    @Test func aSourceRectangleIsReadInTheImagesPixels() {
        // The drawer records the part as texture coordinates and holds the read to it.
        let drawer = Drawer()
        let sheet = Image(width: 64, height: 32)
        drawer.drawImage(sheet, in: Rectangle(x: 0, y: 0, width: 10, height: 10),
                         sourcePixels: Rectangle(x: 16, y: 8, width: 16, height: 8))
        #expect(drawer.batches.last?.imageBounds == SIMD4(0.25, 0.25, 0.5, 0.5))
        let uvs = drawer.imageVertices.map(\.uv)
        #expect(uvs.first == SIMD2(0.25, 0.25) && uvs[2] == SIMD2(0.5, 0.5))
        // A whole picture and a cover crop read the whole texture.
        drawer.drawImage(sheet, in: Rectangle(x: 0, y: 0, width: 10, height: 10))
        #expect(drawer.batches.last?.imageBounds == nil)
        drawer.drawImage(sheet, in: Rectangle(x: 0, y: 0, width: 10, height: 30), fit: .cover)
        #expect(drawer.batches.last?.imageBounds == nil)
        // A part entirely off the picture, or with no area, draws nothing.
        let before = drawer.batches.count
        drawer.drawImage(sheet, in: Rectangle(x: 0, y: 0, width: 10, height: 10),
                         sourcePixels: Rectangle(x: 70, y: 0, width: 8, height: 8))
        drawer.drawImage(sheet, in: Rectangle(x: 0, y: 0, width: 10, height: 10),
                         sourcePixels: Rectangle(x: 0, y: 0, width: 0, height: 8))
        #expect(drawer.batches.count == before)
    }

    /// The image's bytes as RGBA, row by row from the top.
    static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// How many pixels differ between two renders, and by how much at most.
    static func compare(_ a: CGImage, _ b: CGImage) -> (differing: Int, worst: Int) {
        let da = rgba(a), db = rgba(b)
        var differing = 0, worst = 0
        for i in stride(from: 0, to: min(da.count, db.count), by: 4) {
            var largest = 0
            for c in 0 ..< 3 { largest = max(largest, abs(Int(da[i + c]) - Int(db[i + c]))) }
            if largest > 0 { differing += 1; worst = max(worst, largest) }
        }
        return (differing, worst)
    }
}

/// A 3-by-2 sheet of 16-pixel cells of seeded noise, drawn cell by cell at `magnification`,
/// at whole and fractional positions, three ways.
private final class SheetProbe: Sketch {
    enum Mode {
        /// Each cell through a source rectangle.
        case sheet
        /// Each cell cropped to its own image first, drawn whole.
        case cropped
        /// Each cell through the plain crop that reads past its edge (the planted bleed).
        case plainCrop
        /// One rectangle of the sheet's last column of cells and as much again past it.
        case offTheEdge
    }
    var mode: Mode = .sheet
    var magnification = 1.0
    static let cell = 16
    let sheet: Image = {
        let sheet = Image(width: 48, height: 32)
        var random = SplitMix64(seed: 9)
        func next() -> Double { Double.random(in: 0 ... 1, using: &random) }
        for y in 0 ..< 32 {
            for x in 0 ..< 48 {
                sheet[x, y] = Color(red: next(), green: next(), blue: next(), alpha: 1)
            }
        }
        return sheet
    }()
    var cells: [Image] = []

    convenience init(mode: Mode, scale: Double) {
        self.init()
        self.mode = mode
        self.magnification = scale
    }

    override var canvasSize: CanvasSize { .square(512) }

    override func setup() {
        let c = Self.cell
        cells = (0 ..< 6).map { sheet.cropped(x: ($0 % 3) * c, y: ($0 / 3) * c, width: c, height: c) }
    }

    override func draw() {
        background(.black)
        let c = Double(Self.cell)
        if mode == .offTheEdge {
            drawImage(sheet, 8, 8, 2 * c * magnification, c * magnification, 2 * c, 0, 2 * c, c)
            return
        }
        for i in 0 ..< 6 {
            let side = c * magnification
            // Whole positions on the first row, a quarter pixel off on the second.
            let x = 8 + Double(i % 3) * (side + 12) + (i < 3 ? 0 : 0.25)
            let y = 8 + Double(i / 3) * (side + 12) + (i < 3 ? 0 : 0.25)
            let source = Rectangle(x: Double(i % 3) * c, y: Double(i / 3) * c, width: c, height: c)
            switch mode {
            case .sheet:
                drawImage(sheet, in: Rectangle(x: x, y: y, width: side, height: side), source: source)
            case .cropped:
                drawImage(cells[i], x, y, side, side)
            case .plainCrop:
                drawer.drawImage(sheet, in: Rectangle(x: x, y: y, width: side, height: side),
                                 source: Rectangle(x: source.x / 48, y: source.y / 32,
                                                   width: c / 48, height: c / 32))
            case .offTheEdge:
                break
            }
        }
    }
}
