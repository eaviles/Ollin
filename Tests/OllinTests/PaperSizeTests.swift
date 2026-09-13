import Foundation
@testable import Ollin
import Testing

/// The sheet sizes: the ISO series halves as the standard says, the names
/// resolve, orientation flips, and the millimeter sheet is the same page the
/// canvas presets already name in points.
struct PaperSizeTests {

    @Test func theISOSeriesHalvesTheSheetAbove() {
        let series: [PaperSize] = [.a0, .a1, .a2, .a3, .a4, .a5, .a6]
        for (larger, smaller) in zip(series, series.dropFirst()) {
            #expect(smaller.height == larger.width)
            #expect(smaller.width == (larger.height / 2).rounded(.down))
        }
        #expect(PaperSize.a4.width == 210 && PaperSize.a4.height == 297)
    }

    @Test func theUSSizesAreInchesInMillimeters() {
        #expect(abs(PaperSize.usLetter.width - 8.5 * 25.4) < 1e-9)
        #expect(abs(PaperSize.usLetter.height - 11 * 25.4) < 1e-9)
        #expect(abs(PaperSize.usLegal.height - 14 * 25.4) < 1e-9)
        #expect(abs(PaperSize.usTabloid.width - 11 * 25.4) < 1e-9)
        #expect(abs(PaperSize.usTabloid.height - 17 * 25.4) < 1e-9)
    }

    @Test func namesResolveHoweverTheyAreCased() {
        #expect(PaperSize(named: "a4") == .a4)
        #expect(PaperSize(named: "A3") == .a3)
        #expect(PaperSize(named: "usLetter") == .usLetter)
        #expect(PaperSize(named: "letter") == .usLetter)
        #expect(PaperSize(named: "LEGAL") == .usLegal)
        #expect(PaperSize(named: "tabloid") == .usTabloid)
        #expect(PaperSize(named: "b5") == nil)
        #expect(PaperSize(named: "") == nil)
    }

    @Test func orientationFlipsAndIsIdempotent() {
        let wide = PaperSize.a4.landscape
        #expect(wide.width == 297 && wide.height == 210)
        #expect(wide.landscape == wide)
        #expect(wide.portrait == .a4)
        #expect(PaperSize.a4.portrait == .a4)
        let square = PaperSize(width: 100, height: 100)
        #expect(square.landscape == square && square.portrait == square)
    }

    @Test func theSheetIsTheCanvasPresetInPoints() {
        // One vocabulary: the millimeter sheet and the point page agree.
        #expect(PaperSize.a3.canvasSize() == CanvasSize.a3)
        #expect(PaperSize.a4.canvasSize() == CanvasSize.a4)
        #expect(PaperSize.a5.canvasSize() == CanvasSize.a5)
        #expect(PaperSize.usLetter.canvasSize() == CanvasSize.usLetter)
        #expect(PaperSize.usLegal.canvasSize() == CanvasSize.usLegal)
        // At print resolution the pixels come from the millimeters (the point
        // route lands one short at 2479) and the page stays the page.
        let print = PaperSize.a4.canvasSize(dpi: 300)
        #expect(print.width == 2480 && print.height == 3508)
        #expect(print.pointSize.width == 595 && print.pointSize.height == 842)
        #expect(PaperSize.a4.canvasSize(dpi: 0) == CanvasSize.a4)
    }
}
