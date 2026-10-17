import Testing
import Ollin
import CoreGraphics
import Foundation
@testable import OllinVision

/// Object tracking is classical (no neural model), so it's fully checkable here on
/// any Mac: render a textured square that moves across a synthetic sequence, seed
/// the tracker on its first position, and confirm the reported box follows it, no
/// camera, no asset.
@Suite struct ObjectTrackerTests {

    static let width = 640.0, height = 480.0, side = 64.0

    /// A frame with a 4×4 colored grid square (something with features to lock
    /// onto) of side `side` centered at `center` (canvas space, top-left origin).
    static func frame(center: Vector2, side: Double = side) -> Image {
        let w = Int(width), h = Int(height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let colors = [CGColor(red: 1, green: 0.3, blue: 0.2, alpha: 1),
                      CGColor(red: 0.2, green: 0.8, blue: 1, alpha: 1),
                      CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1),
                      CGColor(red: 0.4, green: 1, blue: 0.4, alpha: 1)]
        let cell = side / 4
        let left = center.x - side / 2, top = center.y - side / 2
        for i in 0..<4 {
            for j in 0..<4 {
                ctx.setFillColor(colors[(i + j * 3) % 4])
                // The context's rows run up from the bottom.
                let y = height - (top + Double(j + 1) * cell)
                ctx.fill(CGRect(x: left + Double(i) * cell, y: y, width: cell, height: cell))
            }
        }
        return Image(cgImage: ctx.makeImage()!)
    }

    /// The square at `center`, as the normalized box (lower-left origin) a seed takes.
    static func seed(at center: Vector2) -> Rectangle {
        Rectangle(x: (center.x - side / 2) / width, y: 1 - (center.y + side / 2) / height,
                  width: side / width, height: side / height)
    }

    static let canvas = Rectangle(x: 0, y: 0, width: width, height: height)

    /// A box drawn over the square on its first frame stays on it for sixty
    /// frames of a curving path, five pixels a frame across and sixty up and
    /// down. Measured: about 1.1 px off on average, 2.7 px at the worst frame,
    /// and the box keeps the square's size.
    @Test func aBoxFollowsAMovingSquareForSixtyFrames() async throws {
        func center(_ k: Int) -> Vector2 {
            Vector2(120 + Double(k) * 5, 240 + sin(Double(k) * 0.15) * 60)
        }
        let frames = (0..<60).map { Self.frame(center: center($0)) }
        let results = try await ObjectTracker.track(Self.seed(at: center(0)), across: frames)
        #expect(results.count == 60)

        var errors: [Double] = []
        for (k, result) in results.enumerated() {
            let box = result.bounds(in: Self.canvas)
            errors.append((box.center - center(k)).length)
            #expect(abs(box.width - Self.side) < 3 && abs(box.height - Self.side) < 3,
                    "frame \(k): the box is \(box.width) by \(box.height)")
            #expect(result.confidence > 0.8, "frame \(k): confidence \(result.confidence)")
        }
        let worst = errors.max() ?? .infinity
        let mean = errors.reduce(0, +) / Double(errors.count)
        #expect(worst < 3, "the worst frame is \(worst) px off")
        #expect(mean < 1.5, "the mean is \(mean) px off")
    }

    /// Once the square leaves the frame the confidence falls, and stays down
    /// while it is gone. Measured: about 0.92 while it is whole, falling from
    /// the frame its edge crosses out, and 0.025 once it is gone; the box
    /// itself stays where it was last seen, so the confidence is the sign.
    @Test func theConfidenceFallsAsTheSquareLeaves() async throws {
        let centers = (0..<40).map { Vector2(480 + Double($0) * 8, 240) }
        let results = try await ObjectTracker.track(Self.seed(at: centers[0]),
                                                    across: centers.map { Self.frame(center: $0) })
        #expect(results.count == centers.count)
        // Whole in the frame: the square's right edge is inside until x = 608.
        let whole = results.indices.filter { centers[$0].x + Self.side / 2 <= Self.width }
        // Gone: the square's left edge is past the right side.
        let gone = results.indices.filter { centers[$0].x - Self.side / 2 > Self.width }
        #expect(!whole.isEmpty && !gone.isEmpty)
        for k in whole {
            #expect(results[k].confidence > 0.85, "whole at frame \(k): \(results[k].confidence)")
        }
        for k in gone {
            #expect(results[k].confidence < 0.1, "gone at frame \(k): \(results[k].confidence)")
        }
    }

    /// Re-targeting through the live path builds a new request each time, and
    /// forty in a row keep tracking: the new seed is what the next frame
    /// follows, and nothing wears out.
    @Test func reseedingFortyTimesKeepsTracking() async throws {
        let tracker = await MainActor.run {
            ObjectTracker(StillFrames(Self.frame(center: Vector2(200, 200))))
        }
        let size = CGSize(width: Self.width, height: Self.height)
        for round in 0..<40 {
            let start = Vector2(100 + Double(round % 8) * 50, 150 + Double(round % 5) * 40)
            tracker.track(normalized: Self.seed(at: start))
            for step in 0..<3 {
                let center = start + Vector2(Double(step) * 4, 0)
                await tracker.analyze(Self.frame(center: center).currentCGImage(), size: size)
            }
            let box = try #require(tracker.trackedObject, "round \(round) has no result")
            let expected = start + Vector2(8, 0)
            #expect((box.bounds(in: Self.canvas).center - expected).length < 3,
                    "round \(round): \(box.bounds(in: Self.canvas).center) against \(expected)")
            #expect(box.confidence > 0.8, "round \(round): confidence \(box.confidence)")
        }
        #expect(tracker.isTracking)
        #expect(tracker.isAvailable)
    }

    /// A result comes back in the rectangle the frame was drawn into, and a
    /// mirrored feed flips it about that rectangle's middle.
    @Test func aResultMapsBackIntoTheRectangleTheFrameWasDrawnIn() async throws {
        let center = Vector2(200, 240)
        let results = try await ObjectTracker.track(Self.seed(at: center),
                                                    across: [Self.frame(center: center)])
        let result = try #require(results.first)
        // The square spans 168...232 of 640 across and 208...272 of 480 down.
        let drawnIn = Rectangle(x: 100, y: 50, width: 200, height: 150)
        let box = result.bounds(in: drawnIn)
        #expect(abs(box.center.x - (100 + 200.0 / 640 * 200)) < 1)
        #expect(abs(box.center.y - (50 + 240.0 / 480 * 150)) < 1)
        #expect(abs(box.width - 64.0 / 640 * 200) < 1 && abs(box.height - 64.0 / 480 * 150) < 1)
        let flipped = result.bounds(in: drawnIn, mirrored: true)
        #expect(abs(flipped.center.x - (100 + (1 - 200.0 / 640) * 200)) < 1)
        #expect(abs(flipped.center.y - box.center.y) < 1e-9)
    }
}
