import Testing
import Ollin
import CoreImage
import CoreGraphics
import Foundation
@testable import OllinVision

/// Barcode scanning is classical CV, so it's fully checkable with a synthesized
/// code: generate a QR with Core Image, read it back, and confirm the payload
/// round-trips — no camera, no asset.
@Suite struct BarcodeScannerTests {

    /// Render a QR code carrying `payload` to an Ollin `Image` (black on white).
    private func qrImage(_ payload: String) -> Image? {
        guard let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        // Opaque white behind the (otherwise transparent) modules, with a quiet
        // border so the detector has margin to lock onto.
        let margin: CGFloat = 40
        let extent = scaled.extent.insetBy(dx: -margin, dy: -margin)
        let background = CIImage(color: .white).cropped(to: extent)
        let composited = scaled.composited(over: background)
        let context = CIContext()
        guard let cg = context.createCGImage(composited, from: extent) else { return nil }
        return Image(cgImage: cg)
    }

    @Test func readsAGeneratedQRCode() async throws {
        let payload = "https://ollin.example/hello"
        guard let image = qrImage(payload) else { return }   // soft-skip if generation fails
        let codes = try await BarcodeScanner.detect(in: image)
        #expect(codes.contains { $0.payload == payload })
        if let qr = codes.first(where: { $0.payload == payload }) {
            #expect(qr.symbology.lowercased().contains("qr"))
            #expect(qr.corners(in: Rectangle(x: 0, y: 0, width: 100, height: 100)).count == 4)
        }
    }

    @Test func blankImageHasNoBarcodes() async throws {
        let image = Image(width: 128, height: 128, color: .white)
        let codes = try await BarcodeScanner.detect(in: image)
        #expect(codes.isEmpty)
    }
}
