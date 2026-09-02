import CoreGraphics
import Foundation
import Testing
import Ollin
@testable import OllinVision

/// The failure path and the range-following math are always-on; the
/// real-model tests run only where the video depth model has been built
/// (`Scripts/fetch-models.sh`), soft-skipping elsewhere (CI never fetches the
/// weights).
@Suite struct DepthTrackerTests {

    static let modelURL = ModelTrackerTests.model("VideoDepthAnythingSmallF16.mlpackage")
    static var modelIsFetched: Bool { ModelTrackerTests.isFetched(modelURL) }

    /// A synthetic frame with structure: a diagonal gradient and a bright bar
    /// whose position `phase` moves, so two frames can be alike or not.
    static func frame(phase: Double, width: Int = 160, height: Int = 120) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<height {
            for x in 0..<width {
                let shade = Double(x + y) / Double(width + height)
                context.setFillColor(CGColor(red: shade, green: 0.5, blue: 1 - shade, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: Double(width) * phase, y: Double(height) * 0.2,
                            width: Double(width) * 0.1, height: Double(height) * 0.6))
        return context.makeImage()!
    }

    // MARK: Always-on

    @Test func missingModelFileSurfacesInsteadOfFailingSilently() async {
        let tracker = DepthTracker(modelAt: URL(fileURLWithPath: "/nowhere/NoSuchDepth.mlpackage"))
        let frame = Self.frame(phase: 0.3)
        await tracker.analyze(frame, size: CGSize(width: frame.width, height: frame.height))
        await tracker.ensureLoading().value
        #expect(!tracker.isAvailable)
        #expect(tracker.unavailableReason?.contains("NoSuchDepth") == true)
        #expect(!tracker.isLoaded)
        #expect(tracker.map == nil)
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(tracker.value(at: Vector2(50, 50), in: rect) == 0)
    }

    /// A session's first frame takes its own 1st and 99th percentiles; a later
    /// frame that reaches beyond the range pulls it out halfway at once, and
    /// one that falls short of it lets it creep in by two percent.
    @Test func rangeFollowsTheSceneOutFastAndBackSlowly() {
        let plane = (0..<10_000).map { Float($0) / 10_000 }   // 0…1, uniform
        let first = DepthTracker.followedRange(of: plane, after: nil)
        #expect(abs(first.lowerBound - 0.01) < 0.01)
        #expect(abs(first.upperBound - 0.99) < 0.01)

        let wider = plane.map { $0 * 2 }                       // 0…2
        let out = DepthTracker.followedRange(of: wider, after: 0...1)
        #expect(abs(out.lowerBound - 0) < 0.02)                // the low end barely moved
        #expect(out.upperBound > 1.45 && out.upperBound < 1.55) // halfway to ~1.98

        let narrower = plane.map { $0 * 0.5 }                  // 0…0.5
        let back = DepthTracker.followedRange(of: narrower, after: 0...1)
        #expect(back.upperBound > 0.98 && back.upperBound < 1)  // two percent of the way
    }

    @Test func bytesReadFarAsZeroAndNearAsFull() {
        let bytes = DepthTracker.bytes(from: [-1, 0, 0.5, 1, 2], range: 0...1)
        #expect(bytes == [0, 0, 127, 255, 255])
    }

    // MARK: Real model

    /// The stateful plumbing end to end: the model loads on CPU and GPU,
    /// publishes a map at its own output size, answers in `0…1`, reads the
    /// same frame the same way twice once its window is full (the session
    /// state carries no garbage), counts its frames, and `reset()` starts the
    /// count over. The warm-up is the model's own: a session's first frame is
    /// read on its own and anchors the window, and the reading settles as the
    /// window fills over the next 31 frames, even on a still scene.
    @Test(.enabled(if: modelIsFetched)) func aStillSceneReadsTheSameTwice() async throws {
        let tracker = DepthTracker(modelAt: Self.modelURL)
        await tracker.ensureLoading().value
        try #require(tracker.isLoaded, "\(tracker.unavailableReason ?? "not loaded")")

        let frame = Self.frame(phase: 0.3)
        let size = CGSize(width: frame.width, height: frame.height)
        _ = tracker.map                                        // arm the map
        let warmUp = 34
        for _ in 0..<warmUp {
            await tracker.analyze(frame, size: size)
        }
        let map = try #require(tracker.map)
        #expect(map.width == 518 && map.height == 392)
        #expect(tracker.analyzedFrames == warmUp)
        let range = try #require(tracker.range)
        #expect(range.upperBound > range.lowerBound)

        let rect = Rectangle(x: 0, y: 0, width: 518, height: 392)
        var first: [Double] = []
        for y in stride(from: 20, to: 392, by: 40) {
            for x in stride(from: 20, to: 518, by: 50) {
                let v = tracker.value(at: Vector2(Double(x), Double(y)), in: rect)
                #expect(v >= 0 && v <= 1)
                first.append(v)
            }
        }
        await tracker.analyze(frame, size: size)
        var worst = 0.0
        var index = 0
        for y in stride(from: 20, to: 392, by: 40) {
            for x in stride(from: 20, to: 518, by: 50) {
                let v = tracker.value(at: Vector2(Double(x), Double(y)), in: rect)
                worst = max(worst, abs(v - first[index]))
                index += 1
            }
        }
        #expect(worst < 0.03, "the same frame read differently twice (max \(worst))")

        tracker.reset()
        #expect(tracker.analyzedFrames == 0)
        await tracker.analyze(Self.frame(phase: 0.7), size: size)
        #expect(tracker.analyzedFrames == 1)
        #expect(tracker.isAvailable)
    }
}
