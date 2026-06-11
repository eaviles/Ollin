import Testing
import Ollin
import CoreGraphics
import CoreVideo
import Foundation
@testable import OllinVision

/// Trajectory detection is classical (no neural model), so it's fully checkable
/// here on any Mac: render a ball flying along a known parabola across a
/// synthetic sequence and confirm the detector reports an arc whose points lie
/// on it — no camera, no asset.
@Suite struct TrajectoryTrackerTests {

    private let width = 320, height = 240

    /// A dark frame with a bright disk (radius 6) centered at `(x, y)` in
    /// top-left pixel coordinates.
    private func frame(x: Double, y: Double) -> Image {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        // CGContext is lower-left origin; flip y to place in top-left coordinates.
        ctx.fillEllipse(in: CGRect(x: x - 6, y: Double(height) - y - 6, width: 12, height: 12))
        return Image(cgImage: ctx.makeImage()!)
    }

    /// The thrown-ball path: x sweeps left to right, y rises and falls (top-left
    /// pixel coordinates, so the peak is the *smallest* y).
    private func ballPosition(_ i: Int, count: Int) -> (x: Double, y: Double) {
        let t = Double(i) / Double(count - 1)
        return (30 + t * 260, 200 - 170 * (4 * t * (1 - t)))
    }

    @Test func detectsAThrownBall() async throws {
        let count = 60
        let frames = (0..<count).map { i -> Image in
            let (x, y) = ballPosition(i, count: count)
            return frame(x: x, y: y)
        }

        let perFrame = try await TrajectoryTracker.detect(across: frames)
        #expect(perFrame.count == count)

        // The arc takes `trajectoryLength` observations to appear, then should be
        // reported on most of the remaining frames.
        let hits = perFrame.filter { !$0.isEmpty }
        #expect(hits.count > 20)

        let last = try #require(perFrame.last(where: { !$0.isEmpty })?.first)
        #expect(last.confidence > 0.9)
        #expect(last.detectedPointsNormalized.count == 10)

        // Every detected point lies near the true parabola: mapping the point into
        // pixel space, its y must match the ball path's y at that x.
        let canvas = Rectangle(x: 0, y: 0, width: Double(width), height: Double(height))
        for point in last.detectedPoints(in: canvas) {
            let t = (point.x - 30) / 260
            let trueY = 200 - 170 * (4 * t * (1 - t))
            #expect(abs(point.y - trueY) < 15, "point \(point) strays from the arc (true y \(trueY))")
        }

        // The points run in travel order, left to right.
        let xs = last.detectedPointsNormalized.map(\.x)
        #expect(xs == xs.sorted())
    }

    @Test func arcKeepsItsIdentityAcrossFrames() async throws {
        let count = 40
        let frames = (0..<count).map { i -> Image in
            let (x, y) = ballPosition(i, count: count)
            return frame(x: x, y: y)
        }
        let perFrame = try await TrajectoryTracker.detect(across: frames)
        let ids = Set(perFrame.flatMap { $0.map(\.id) })
        // One ball, one arc: the same trajectory id persists across the frames.
        #expect(ids.count == 1)
    }

    @Test func sampleBufferWrapsTheFramePixels() throws {
        let image = frame(x: 100, y: 100)
        let sample = try #require(TrajectoryTracker.sampleBuffer(from: image.currentCGImage(),
                                                                 at: 0.5))
        #expect(sample.presentationTimeStamp.seconds == 0.5)
        let pixelBuffer = try #require(sample.imageBuffer)
        #expect(CVPixelBufferGetWidth(pixelBuffer) == width)
        #expect(CVPixelBufferGetHeight(pixelBuffer) == height)
    }
}
