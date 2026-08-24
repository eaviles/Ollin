import Foundation

/// One tile of a photo mosaic: which picture goes where.
public struct MosaicTile: Equatable, Sendable {
    /// The cell's column, counting from the left.
    public let column: Int
    /// The cell's row, counting from the top.
    public let row: Int
    /// Which of the pictures handed in goes here.
    public let picture: Int
    /// The average color the cell of the target had, in sRGB.
    public let target: Color
}

/// A picture rebuilt out of many smaller pictures, one per cell of a grid.
///
/// Each cell of the target is averaged, and the picture whose own average is
/// nearest goes there. Stand back and the cells add up to the target; step
/// forward and every cell is a picture of its own.
///
/// ```swift
/// let mosaic = portrait.mosaic(of: library, columns: 48, rows: 48)
/// for tile in mosaic.tiles {
///     drawImage(library[tile.picture], in: mosaic.frame(of: tile, in: bounds), fit: .cover)
/// }
/// ```
///
/// The averaging happens in **linear light**, which is the only way it can be
/// right: a cell of half black and half white is middle gray at 0.5 in linear
/// light, and averaging the sRGB numbers instead would call it 0.5 there too,
/// which reads far too dark. The same rule decides which picture is nearest.
public struct PhotoMosaic: Sendable {
    /// How many cells across and down.
    public let columns: Int
    public let rows: Int
    /// One entry per cell, in reading order.
    public let tiles: [MosaicTile]

    /// Where a tile goes inside `bounds`.
    public func frame(of tile: MosaicTile, in bounds: Rectangle) -> Rectangle {
        let width = bounds.width / Double(columns)
        let height = bounds.height / Double(rows)
        return Rectangle(x: bounds.x + Double(tile.column) * width,
                         y: bounds.y + Double(tile.row) * height,
                         width: width, height: height)
    }

    /// How many times each of the pictures was used, by index.
    public func uses(of pictures: Int) -> [Int] {
        var counts = [Int](repeating: 0, count: pictures)
        for tile in tiles where tile.picture < pictures { counts[tile.picture] += 1 }
        return counts
    }
}

public extension Image {
    /// The average color of a rectangle of this picture, worked out in linear
    /// light. The rectangle is in pixels, and is clamped to the picture.
    ///
    /// Transparent pixels count for nothing rather than for black, so a cell that
    /// is half a cut-out shape averages the shape's color.
    func averageColor(in region: Rectangle? = nil) -> Color {
        guard let pixels = premultipliedPixels() else { return .clear }
        let box = region ?? Rectangle(x: 0, y: 0, width: Double(width), height: Double(height))
        let x0 = Swift.max(0, Int(box.x.rounded(.down)))
        let y0 = Swift.max(0, Int(box.y.rounded(.down)))
        let x1 = Swift.min(width, Int((box.x + box.width).rounded(.up)))
        let y1 = Swift.min(height, Int((box.y + box.height).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return .clear }

        var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0
        for y in y0 ..< y1 {
            let row = y * width * 4
            for x in x0 ..< x1 {
                let i = row + x * 4
                let a = Double(pixels[i + 3]) / 255
                guard a > 0 else { continue }
                // Premultiplied, so undo the alpha before linearizing.
                red += Color.srgbToLinear(Double(pixels[i]) / 255 / a) * a
                green += Color.srgbToLinear(Double(pixels[i + 1]) / 255 / a) * a
                blue += Color.srgbToLinear(Double(pixels[i + 2]) / 255 / a) * a
                alpha += a
            }
        }
        guard alpha > 0 else { return .clear }
        return Color(red: Color.linearToSrgb(red / alpha),
                     green: Color.linearToSrgb(green / alpha),
                     blue: Color.linearToSrgb(blue / alpha),
                     alpha: alpha / Double((x1 - x0) * (y1 - y0)))
    }

    /// Rebuild this picture out of `pictures`, one per cell of a `columns` by
    /// `rows` grid.
    ///
    /// - Parameters:
    ///   - pictures: the library to build from. Each one's own average is worked
    ///     out once, so a large library costs one pass over each picture.
    ///   - columns: how many cells across.
    ///   - rows: how many cells down.
    ///   - maxUses: how often one picture may be used, or nil for as often as it
    ///     fits. A small library with a low limit runs out, and the cells that
    ///     find nothing left fall back to the nearest picture regardless.
    ///
    /// Cells are filled in reading order, so a limit is spent by the cells that
    /// ask first. That is the honest simple rule; for a library much smaller than
    /// the grid, leave `maxUses` alone and let the repeats happen.
    func mosaic(of pictures: [Image], columns: Int, rows: Int,
                maxUses: Int? = nil) -> PhotoMosaic {
        let columns = Swift.max(1, columns), rows = Swift.max(1, rows)
        guard !pictures.isEmpty else {
            return PhotoMosaic(columns: columns, rows: rows, tiles: [])
        }
        let library = pictures.map { $0.averageColor().linearParts }
        var spent = [Int](repeating: 0, count: pictures.count)
        let cellWidth = Double(width) / Double(columns)
        let cellHeight = Double(height) / Double(rows)

        var tiles: [MosaicTile] = []
        tiles.reserveCapacity(columns * rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let cell = Rectangle(x: Double(column) * cellWidth, y: Double(row) * cellHeight,
                                     width: cellWidth, height: cellHeight)
                let wanted = averageColor(in: cell)
                let parts = wanted.linearParts

                var best = 0, bestCost = Double.infinity
                var bestFree = -1, bestFreeCost = Double.infinity
                for (index, tile) in library.enumerated() {
                    let cost = (tile.0 - parts.0) * (tile.0 - parts.0)
                        + (tile.1 - parts.1) * (tile.1 - parts.1)
                        + (tile.2 - parts.2) * (tile.2 - parts.2)
                    if cost < bestCost { bestCost = cost; best = index }
                    if let limit = maxUses, spent[index] >= limit { continue }
                    if cost < bestFreeCost { bestFreeCost = cost; bestFree = index }
                }
                // Everything is used up, so the nearest picture stands in.
                let picked = bestFree >= 0 ? bestFree : best
                spent[picked] += 1
                tiles.append(MosaicTile(column: column, row: row, picture: picked, target: wanted))
            }
        }
        return PhotoMosaic(columns: columns, rows: rows, tiles: tiles)
    }
}

public extension Sketch {
    /// Draw a mosaic into `bounds`: each cell's picture, cropped to fill its cell.
    ///
    /// `tint` mixes each cell toward the color it stands for, which is the usual
    /// way a mosaic is made to read from further off: 0 leaves the pictures alone,
    /// 1 paints flat color.
    func drawMosaic(_ mosaic: PhotoMosaic, of pictures: [Image],
                    in bounds: Rectangle? = nil, tint: Double = 0) {
        let box = bounds ?? canvasRectangle
        for tile in mosaic.tiles {
            guard tile.picture < pictures.count else { continue }
            let frame = mosaic.frame(of: tile, in: box)
            drawImage(pictures[tile.picture], in: frame, fit: .cover)
            if tint > 0 {
                noStroke()
                fill(tile.target.withAlpha(clamp(tint, 0, 1)))
                drawRect(frame)
            }
        }
    }
}

extension Color {
    /// The color's three parts in linear light, which is where averaging and
    /// distances between colors have to happen.
    var linearParts: (Double, Double, Double) {
        (Color.srgbToLinear(red), Color.srgbToLinear(green), Color.srgbToLinear(blue))
    }
}
