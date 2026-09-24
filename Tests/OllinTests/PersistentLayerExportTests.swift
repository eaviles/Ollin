@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import Testing

/// A picture a layer carries from frame to frame on the GPU has to be built by
/// every frame an export runs, including the frames it does not write. These
/// pin the two drives that used to leave it behind: `--skip`'s warmup, which
/// ran the sketch but not the render, so the first written frame started from
/// an empty layer; and the contact sheet, whose later tiles could pass for the
/// tile before them and serve an empty layer instead of drawing.
@Suite
@MainActor
struct PersistentLayerExportTests {

    /// Every frame adds the same light into a float feedback pile.
    private final class Pile: Sketch {
        override var canvasSize: CanvasSize { .square(32) }
        var pile: Feedback!
        override func setup() { pile = makeFeedback(precision: .float32) }
        override func draw() {
            background(.black)
            withFeedback(pile) { previous in
                drawImage(previous, 0, 0)
                blendMode(.add)
                noStroke()
                fill(Color(white: 1, alpha: 0.04))
                drawRect(0, 0, 32, 32)
            }
            drawImage(pile.image, 0, 0)
        }
    }

    /// A canvas painted red through a feedback layer and nothing else.
    private final class RedPile: Sketch {
        override var canvasSize: CanvasSize { .square(32) }
        var pile: Feedback!
        override func setup() { pile = makeFeedback() }
        override func draw() {
            background(.black)
            withFeedback(pile) { _ in
                noStroke()
                fill(.red)
                drawRect(0, 0, 32, 32)
            }
            drawImage(pile.image, 0, 0)
        }
    }

    private func frames(_ sketch: Sketch, count: Int, skip: Int) -> [CGImage] {
        var out: [CGImage] = []
        OllinApp.renderFrames(sketch, frames: count, fps: 30, skipSeconds: Double(skip) / 30) { frame, _ in
            if let image = frame.image { out.append(image) }
        }
        return out
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFirstFrameAfterASkipIsTheFrameItSkippedTo() throws {
        let fresh = try #require(frames(Pile(), count: 1, skip: 0).first)
        let skipped = try #require(frames(Pile(), count: 1, skip: 10).first)
        let straight = try #require(frames(Pile(), count: 11, skip: 0).last)
        let (f, s, t) = (Self.meanRed(fresh), Self.meanRed(skipped), Self.meanRed(straight))
        // The pile built through the skipped frames, to where a run from zero
        // stands at the same moment.
        #expect(s > f + 20, "the skipped frames built the pile: \(f) then \(s)")
        #expect(abs(s - t) < 1, "the frame after the skip is the frame skipped to: \(s) against \(t)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyTileOfAContactSheetDrawsItsFeedbackLayer() throws {
        let sheet = try #require(OllinApp.contactSheet(of: { RedPile() }, seeds: Array(1...6),
                                                       columns: 6, tileWidth: 32))
        let bytes = try #require(Self.rgba(sheet))
        var red = 0
        for i in stride(from: 0, to: bytes.count, by: 4)
        where bytes[i] > 200 && bytes[i + 1] < 60 && bytes[i + 2] < 60 {
            red += 1
        }
        #expect(red >= 6 * 32 * 32 * 9 / 10, "six red tiles, \(red) red pixels")
    }

    /// The mechanism under the sheet, pinned where the allocator can be made
    /// to show it: a drawer made after another is freed can be handed the same
    /// address, and at the same frame it must still read as a new frame, or its
    /// persistent layers serve empty textures instead of drawing. The sheet test
    /// above passes either way on this suite's allocation pattern; this one goes
    /// red with the stamp keyed on the address.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDrawerAtAFreedDrawersAddressStillDraws() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        var address: ObjectIdentifier?
        do {
            let first = Drawer()
            renderer.beginStatefulEncode(first)
            address = ObjectIdentifier(first)
        }
        var others: [Drawer] = []
        var reused: Drawer?
        for _ in 0 ..< 256 {
            let drawer = Drawer()
            if ObjectIdentifier(drawer) == address { reused = drawer; break }
            others.append(drawer)
        }
        let second = try #require(reused, "no drawer landed at the freed one's address")
        renderer.beginStatefulEncode(second)
        #expect(!renderer.statefulEncodeIsRepeat)
        // The same drawer at the same frame is a repeat, which is what the stamp is for.
        renderer.beginStatefulEncode(second)
        #expect(renderer.statefulEncodeIsRepeat)
        _ = others
    }

    // MARK: Support

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        return Array(UnsafeRawBufferPointer(start: data, count: w * h * 4))
    }

    private static func meanRed(_ image: CGImage) -> Double {
        guard let bytes = rgba(image) else { return -1 }
        var sum = 0
        for i in stride(from: 0, to: bytes.count, by: 4) { sum += Int(bytes[i]) }
        return Double(sum) / Double(bytes.count / 4)
    }
}
