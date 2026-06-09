import Testing
import Ollin
import CoreGraphics
import Foundation
@testable import OllinVision

/// Object tracking is classical (no neural model), so it's fully checkable here on
/// any Mac: render a textured patch that drifts across a synthetic sequence, seed
/// the tracker on its first position, and confirm the reported box follows it — no
/// camera, no asset.
@Suite struct ObjectTrackerTests {

    /// A 320×240 frame with a 4×4 colored grid patch (something with features to
    /// lock onto) whose left edge is at `patchX`, top at y=90.
    private func frame(patchX: Int) -> Image {
        let w = 320, h = 240
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let cols = [CGColor(red: 1, green: 0.3, blue: 0.2, alpha: 1),
                    CGColor(red: 0.2, green: 0.8, blue: 1, alpha: 1),
                    CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1),
                    CGColor(red: 0.4, green: 1, blue: 0.4, alpha: 1)]
        for i in 0..<4 {
            for j in 0..<4 {
                ctx.setFillColor(cols[(i + j) % 4])
                ctx.fill(CGRect(x: patchX + i * 14, y: 90 + j * 14, width: 13, height: 13))
            }
        }
        return Image(cgImage: ctx.makeImage()!)
    }

    @Test func tracksAPatchAcrossFrames() async throws {
        let step = 6, count = 8
        let frames = (0..<count).map { frame(patchX: 60 + $0 * step) }

        // Seed = the patch at frame 0, normalized with a lower-left origin.
        // The patch spans x:60…116 (56 wide), y:90…146 → lower-left y = 240-146 = 94.
        let seed = Rectangle(x: 60.0 / 320, y: 94.0 / 240, width: 56.0 / 320, height: 56.0 / 240)
        let results = try await ObjectTracker.track(seed, across: frames)

        #expect(results.count == count)
        guard let first = results.first, let last = results.last else { return }

        // It locks on confidently at the seed frame…
        #expect(first.confidence > 0.8)
        // …and the box drifts to the right with the patch (the patch moved
        // (count-1)*step / width = 42/320 ≈ 0.131 in normalized x).
        #expect(last.boundingBoxNormalized.x > first.boundingBoxNormalized.x + 0.05)
        let expectedLastX = Double(60 + (count - 1) * step) / 320.0
        #expect(abs(last.boundingBoxNormalized.x - expectedLastX) < 0.06)
    }

    @Test func seedingMapsBoundsBackToCanvas() async throws {
        let seed = Rectangle(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let results = try await ObjectTracker.track(seed, across: [frame(patchX: 60)])
        #expect(results.count == 1)
        // The seed box centered in the frame maps to the center of the canvas rect.
        if let r = results.first {
            let canvas = Rectangle(x: 0, y: 0, width: 200, height: 200)
            let mapped = r.bounds(in: canvas)
            #expect(abs(mapped.center.x - 100) < 30)
            #expect(abs(mapped.center.y - 100) < 30)
        }
    }
}
