import Foundation
import Ollin
import Testing

/// Laws for the photo mosaic. Two claims carry it: the average of a cell is
/// worked out in linear light, and the picture that goes there is the nearest one
/// by that average.
@Suite
struct PhotoMosaicTests {
    /// A flat picture averages to its own color, whatever size the piece asked for.
    @Test func aFlatPictureAveragesToItself() {
        for color in [Color(red: 0.2, green: 0.6, blue: 0.9),
                      Color(white: 0), Color(white: 1), Color(red: 1, green: 0, blue: 0)] {
            let picture = Image(width: 16, height: 12, color: color)
            let whole = picture.averageColor()
            #expect(near(whole, color), "\(whole) is not \(color)")
            let part = picture.averageColor(in: Rectangle(x: 3, y: 2, width: 5, height: 4))
            #expect(near(part, color))
        }
    }

    /// The law that says the averaging is right: half black and half white is
    /// middle gray in *linear light*, which is 0.5 there and about 0.74 written
    /// back out in sRGB. Averaging the sRGB numbers instead would answer 0.5, a
    /// full quarter too dark, and no picture would say so.
    @Test func halfBlackAndHalfWhiteIsLinearMiddleGray() {
        var pixels = [UInt8]()
        for y in 0 ..< 8 {
            for _ in 0 ..< 8 {
                let white = y < 4
                let level: UInt8 = white ? 255 : 0
                pixels.append(contentsOf: [level, level, level, 255])
            }
        }
        guard let picture = Image(width: 8, height: 8, premultipliedRGBA: pixels) else {
            Issue.record("could not build the picture")
            return
        }
        let average = picture.averageColor()
        #expect(abs(linear(average.red) - 0.5) < 1e-6,
                "linear \(linear(average.red)) is not 0.5")
        #expect(abs(average.red - 0.7354) < 0.002, "sRGB \(average.red) is not about 0.735")
    }

    /// Transparent pixels count for nothing rather than for black, so a cut-out
    /// shape averages the shape's own color.
    @Test func whatIsNotThereDoesNotCountAsBlack() {
        var pixels = [UInt8]()
        for _ in 0 ..< 4 {
            for x in 0 ..< 4 {
                // Premultiplied, so a clear pixel is all zeros.
                if x < 2 { pixels.append(contentsOf: [200, 40, 40, 255]) }
                else { pixels.append(contentsOf: [0, 0, 0, 0]) }
            }
        }
        guard let picture = Image(width: 4, height: 4, premultipliedRGBA: pixels) else {
            Issue.record("could not build the picture")
            return
        }
        let average = picture.averageColor()
        #expect(abs(average.red - 200.0 / 255) < 0.01, "\(average.red)")
        #expect(abs(average.green - 40.0 / 255) < 0.01)
        // And the alpha says how much of the cell was really there.
        #expect(abs(average.alpha - 0.5) < 1e-9)
    }

    /// Every cell takes the nearest picture by average color. Checked against a
    /// brute-force search over the library, in linear light.
    @Test func everyCellTakesTheNearestPicture() {
        let library = (0 ..< 12).map { i -> Image in
            let red: Double = Double(i) / 11
            let green: Double = Double((i * 5) % 12) / 11
            let blue: Double = Double((i * 7) % 12) / 11
            return Image(width: 4, height: 4, color: Color(red: red, green: green, blue: blue))
        }
        let target = ramp(width: 24, height: 16)
        let mosaic = target.mosaic(of: library, columns: 6, rows: 4)
        #expect(mosaic.tiles.count == 24)

        let averages = library.map { $0.averageColor() }
        for tile in mosaic.tiles {
            let wanted = tile.target
            var best = 0, bestCost = Double.infinity
            for (index, average) in averages.enumerated() {
                let distance = cost(average, wanted)
                if distance < bestCost { bestCost = distance; best = index }
            }
            #expect(tile.picture == best,
                    "cell \(tile.column),\(tile.row) took \(tile.picture) rather than \(best)")
        }
    }

    /// A picture whose average is exactly the cell's color is the one that goes
    /// there, and a flat target uses that one picture everywhere.
    @Test func anExactMatchIsAlwaysTheOneChosen() {
        let wanted = Color(red: 0.3, green: 0.75, blue: 0.15)
        let library = [Image(width: 2, height: 2, color: Color(white: 0)),
                       Image(width: 2, height: 2, color: wanted),
                       Image(width: 2, height: 2, color: Color(white: 1))]
        let target = Image(width: 12, height: 12, color: wanted)
        let mosaic = target.mosaic(of: library, columns: 4, rows: 4)
        #expect(mosaic.tiles.allSatisfy { $0.picture == 1 })
        #expect(mosaic.uses(of: 3) == [0, 16, 0])
    }

    /// A limit on how often a picture may be used is kept, and the cells that find
    /// nothing left still get a picture rather than nothing.
    @Test func aLimitOnRepeatsIsKept() {
        let library = (0 ..< 6).map { Image(width: 2, height: 2, color: Color(white: Double($0) / 5)) }
        let target = ramp(width: 20, height: 20)
        let mosaic = target.mosaic(of: library, columns: 5, rows: 4, maxUses: 4)
        #expect(mosaic.tiles.count == 20)
        let uses = mosaic.uses(of: 6)
        #expect(uses.allSatisfy { $0 <= 4 }, "a picture was used \(uses.max() ?? 0) times")
        #expect(uses.reduce(0, +) == 20)

        // With more cells than the limit can cover, every cell is still filled.
        let crowded = target.mosaic(of: library, columns: 6, rows: 6, maxUses: 1)
        #expect(crowded.tiles.count == 36)
    }

    /// Where a tile goes: the cells tile the region exactly, in reading order.
    @Test func theCellsTileTheRegionInReadingOrder() {
        let library = [Image(width: 2, height: 2, color: .white)]
        let mosaic = Image(width: 10, height: 10, color: .black).mosaic(of: library, columns: 5, rows: 2)
        let box = Rectangle(x: 20, y: 30, width: 200, height: 80)
        #expect(mosaic.tiles.map(\.column) == Array(0 ..< 5) + Array(0 ..< 5))
        #expect(mosaic.tiles.map(\.row) == [0, 0, 0, 0, 0, 1, 1, 1, 1, 1])
        let frames = mosaic.tiles.map { mosaic.frame(of: $0, in: box) }
        #expect(frames[0] == Rectangle(x: 20, y: 30, width: 40, height: 40))
        #expect(frames[9] == Rectangle(x: 180, y: 70, width: 40, height: 40))
        let area = frames.reduce(0.0) { $0 + $1.width * $1.height }
        #expect(abs(area - box.width * box.height) < 1e-9)
    }

    /// Nothing to build from, nothing built.
    @Test func anEmptyLibraryBuildsNothing() {
        let target = Image(width: 8, height: 8, color: .white)
        #expect(target.mosaic(of: [], columns: 4, rows: 4).tiles.isEmpty)
        #expect(target.mosaic(of: [Image(width: 1, height: 1, color: .white)],
                              columns: 0, rows: 0).tiles.count == 1)
    }

    // MARK: - Helpers

    private func ramp(width: Int, height: Int) -> Image {
        var pixels = [UInt8]()
        for y in 0 ..< height {
            for x in 0 ..< width {
                pixels.append(UInt8(x * 255 / Swift.max(1, width - 1)))
                pixels.append(UInt8(y * 255 / Swift.max(1, height - 1)))
                pixels.append(UInt8((x + y) * 255 / Swift.max(1, width + height - 2)))
                pixels.append(255)
            }
        }
        return Image(width: width, height: height, premultipliedRGBA: pixels)
            ?? Image(width: width, height: height, color: .black)
    }

    private func cost(_ a: Color, _ b: Color) -> Double {
        let dr = linear(a.red) - linear(b.red)
        let dg = linear(a.green) - linear(b.green)
        let db = linear(a.blue) - linear(b.blue)
        return dr * dr + dg * dg + db * db
    }

    /// The sRGB transfer curve, written out here from its own definition rather
    /// than borrowed, so the laws measure the framework rather than agree with it.
    private func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func near(_ a: Color, _ b: Color) -> Bool {
        abs(a.red - b.red) < 0.005 && abs(a.green - b.green) < 0.005 && abs(a.blue - b.blue) < 0.005
    }
}
