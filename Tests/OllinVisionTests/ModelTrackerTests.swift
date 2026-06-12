import CoreGraphics
import Foundation
import Testing
import Ollin
@testable import OllinVision

/// The failure paths and the coordinate math are always-on; the real-model
/// tests run only where the depth model has been downloaded
/// (`Scripts/fetch-models.sh`), soft-skipping elsewhere (CI never fetches the
/// weights).
@Suite struct ModelTrackerTests {

    /// The depth model the fetch script downloads, located from this file so
    /// the tests don't depend on the working directory.
    static let depthModelURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OllinVisionTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Models/DepthAnythingV2SmallF16.mlpackage")

    static var depthModelIsFetched: Bool {
        FileManager.default.fileExists(atPath: depthModelURL.path)
    }

    // MARK: Always-on

    @Test func missingModelFileSurfacesInsteadOfFailingSilently() async {
        let tracker = ModelTracker(modelAt: URL(fileURLWithPath: "/nowhere/NoSuchModel.mlpackage"))
        let image = Image(width: 32, height: 32, color: .white)
        await #expect(throws: ModelTracker.Error.self) {
            _ = try await tracker.detect(in: image)
        }
        #expect(!tracker.isAvailable)
        #expect(tracker.unavailableReason?.contains("NoSuchModel") == true)
        #expect(!tracker.isLoaded)
    }

    @Test func detectedObjectMapsIntoCanvasSpace() {
        // A normalized box in the picture's upper-left quarter (lower-left
        // origin: x 0…0.5, y 0.5…1) lands in the canvas rect's top-left
        // quarter, y flipped.
        let object = DetectedObject(label: "cat", confidence: 0.9,
                                    boundsN: Rectangle(x: 0, y: 0.5, width: 0.5, height: 0.5))
        let rect = Rectangle(x: 100, y: 100, width: 200, height: 100)
        let bounds = object.bounds(in: rect)
        #expect(abs(bounds.x - 100) < 1e-9)
        #expect(abs(bounds.y - 100) < 1e-9)
        #expect(abs(bounds.width - 100) < 1e-9)
        #expect(abs(bounds.height - 50) < 1e-9)
        let center = object.center(in: rect)
        #expect(abs(center.x - 150) < 1e-9)
        #expect(abs(center.y - 125) < 1e-9)
        // Mirrored flips left-to-right within the rect.
        let mirrored = object.bounds(in: rect, mirrored: true)
        #expect(abs(mirrored.x - 200) < 1e-9)
    }

    @Test func emptyOutputReadsZero() {
        let output = ModelOutput(labels: [], objects: [], map: nil, mapBytes: nil)
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(output.value(at: Vector2(50, 50), in: rect) == 0)
        #expect(output.valueNormalized(at: Vector2(0.5, 0.5)) == 0)
    }

    /// The byte plane behind every value query, pinned deterministically: rows
    /// are top-down, the input point is lower-left normalized, and any
    /// out-of-range query clamps. (The plane exists because Vision's
    /// `pixel(at:)` misindexes multi-channel buffers — queries must come from
    /// our own bytes, the same ones the drawable map is built from.)
    @Test func mapBytesOrientationAndClamping() {
        // A 4×2 plane: top row dark (10), bottom row bright (200).
        let map = MapBytes(bytes: [10, 10, 10, 10, 200, 200, 200, 200], width: 4, height: 2)
        // Lower-left normalized: y near 1 is the picture's top.
        #expect(map.value(at: Vector2(0.5, 0.9)) == 10.0 / 255)
        #expect(map.value(at: Vector2(0.5, 0.1)) == 200.0 / 255)
        // Clamping: corners and far-out points answer, never trap.
        #expect(map.value(at: Vector2(1.0, 1.0)) == 10.0 / 255)
        #expect(map.value(at: Vector2(5, -3)) == 200.0 / 255)
        #expect(map.value(at: Vector2(-1, 2)) == 10.0 / 255)
    }

    // MARK: Real model (soft-gated on the downloaded weights)

    /// A still image through the real depth model: the map publishes, values
    /// stay in range, and edge queries clamp instead of trapping (the
    /// optical-flow lesson, re-applied here).
    @Test func depthModelProducesAQueryableMap() async throws {
        guard Self.depthModelIsFetched else { return }
        let tracker = ModelTracker(modelAt: Self.depthModelURL)
        let image = gradientScene(width: 320, height: 240)
        let output = try await tracker.detect(in: image)
        #expect(tracker.isLoaded)
        #expect(tracker.isAvailable)

        let map = try #require(output.map)
        #expect(map.width > 0 && map.height > 0)

        let rect = Rectangle(x: 0, y: 0, width: 320, height: 240)
        var lo = Double.infinity, hi = -Double.infinity
        for gy in 0..<8 {
            for gx in 0..<8 {
                let v = output.value(at: Vector2((Double(gx) + 0.5) * 40,
                                                 (Double(gy) + 0.5) * 30), in: rect)
                lo = min(lo, v); hi = max(hi, v)
            }
        }
        #expect(lo >= 0 && hi <= 1)
        #expect(hi > lo)   // a scene with structure gets *some* depth spread

        // The far edge and beyond: clamped, never trapping.
        #expect(output.valueNormalized(at: Vector2(0.999999, 0.999999)) >= 0)
        #expect(output.value(at: Vector2(1000, 1000), in: rect) >= 0)
        #expect(output.value(at: Vector2(-50, -50), in: rect) >= 0)

        // A depth model fills only the map surface.
        #expect(output.labels.isEmpty)
        #expect(output.objects.isEmpty)

        // The query surface and the published map are built from the same gray
        // plane, so they must agree *exactly*, cell for cell — the regression
        // that caught Vision's `pixel(at:)` misindexing multi-channel buffers
        // (queries used to land at scattered offsets, read live as diagonal
        // banding over the picture).
        var mismatched = 0
        for y in stride(from: 0, to: map.height, by: 7) {
            for x in stride(from: 0, to: map.width, by: 11) {
                let u = (Double(x) + 0.5) / Double(map.width)
                let v = 1 - (Double(y) + 0.5) / Double(map.height)
                if abs(output.valueNormalized(at: Vector2(u, v)) - map[x, y].alpha) > 1.0 / 255 {
                    mismatched += 1
                }
            }
        }
        #expect(mismatched == 0)
    }

    /// The compile cache hands back the same stable path for the same source —
    /// what keeps every launch after the first in milliseconds.
    @Test func compileCacheIsStable() async throws {
        guard Self.depthModelIsFetched else { return }
        let first = try await ModelTracker.compiledModelURL(for: Self.depthModelURL)
        let second = try await ModelTracker.compiledModelURL(for: Self.depthModelURL)
        #expect(first == second)
        #expect(first.pathExtension == "mlmodelc")
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    /// The live path over a hand-fired frame source: frames flow, the model
    /// loads in the background, and the surfaces publish. Reads `map` in the
    /// poll loop because its first read arms the conversion.
    @Test @MainActor func liveWiringPublishes() async throws {
        guard Self.depthModelIsFetched else { return }
        let source = FrameSourceTests.ManualFrameSource()
        let tracker = ModelTracker(source, modelAt: Self.depthModelURL)
        let frame = gradientScene(width: 160, height: 120)
        let cgImage = try #require(frame.currentCGImage())

        let deadline = Date().addingTimeInterval(30)
        var map: Image?
        while map == nil, Date() < deadline {
            source.frameTap?(cgImage)
            map = tracker.map
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(map != nil)
        #expect(tracker.isLoaded)
        let rect = Rectangle(x: 0, y: 0, width: 160, height: 120)
        let v = tracker.value(at: Vector2(80, 60), in: rect)
        #expect(v >= 0 && v <= 1)
    }

    // MARK: Helpers

    /// A scene with enough structure for a depth model to chew on: a bright
    /// floor gradient and a dark "object" disk.
    private func gradientScene(width: Int, height: Int) -> Image {
        let image = Image(width: width, height: height, color: .white)
        for y in 0..<height {
            let shade = UInt8(255 - (y * 160) / height)
            for x in 0..<width {
                image[x, y] = Color(red: Double(shade) / 255,
                                    green: Double(shade) / 255, blue: 1, alpha: 1)
            }
        }
        let cx = width / 2, cy = (height * 2) / 3, r = height / 4
        for y in (cy - r)...(cy + r) {
            for x in (cx - r)...(cx + r) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r {
                image[x, y] = Color(red: 0.15, green: 0.1, blue: 0.1, alpha: 1)
            }
        }
        return image
    }
}
