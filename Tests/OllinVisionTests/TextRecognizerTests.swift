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

        // `.fast` is the level a live feed reads at, and it round-trips the
        // rendered word here.
        let quick = try await TextRecognizer.detect(in: image, level: .fast)
        #expect(quick.map(\.text).joined(separator: " ").uppercased().contains("OLLIN"))

        // `.accurate` reaches a second, precompiled model, and on this machine
        // (macOS 27 beta, 2026-08-29) building its compute operation fails
        // inside the system's own execution runtime, every time, alone as well
        // as in a batch: `e5rt_execution_stream_operation_create_precompiled_
        // compute_operation_with_options call failed`. The `.fast` read above
        // is the counterfactual that says the request and the image are both
        // fine, so this is the system rather than the recognizer. Marked
        // intermittent so it reports as a known issue where it fails and stays
        // green where the model builds, which is what keeps a full run's red
        // meaning something.
        await withKnownIssue("the accurate text model does not build on this system",
                             isIntermittent: true) {
            let lines = try await TextRecognizer.detect(in: image, level: .accurate)
            let all = lines.map(\.text).joined(separator: " ").uppercased()
            #expect(all.contains("OLLIN"))
        }
    }
}
