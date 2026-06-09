import Testing
import Ollin
import CoreText
import CoreGraphics
import Foundation
@testable import OllinVision

/// OCR is checkable on a rendered string: draw text with Core Text, read it back,
/// and confirm it round-trips. (This also reveals whether the recognizer can run
/// on this machine at all.)
@Suite struct TextRecognizerTests {

    /// Render `text` as black on white to an Ollin `Image` via Core Text (CPU).
    private func textImage(_ text: String, width: Int, height: Int) -> Image? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: black]
        guard let attr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary) else { return nil }
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 30, y: Double(height) / 2 - 24)
        CTLineDraw(line, ctx)
        guard let cg = ctx.makeImage() else { return nil }
        return Image(cgImage: cg)
    }

    @Test func readsRenderedText() async throws {
        guard let image = textImage("OLLIN", width: 420, height: 160) else { return }
        let lines = try await TextRecognizer.detect(in: image, level: .accurate)
        let all = lines.map(\.text).joined(separator: " ").uppercased()
        #expect(all.contains("OLLIN"))
    }
}
