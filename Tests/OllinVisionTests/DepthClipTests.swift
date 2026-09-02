import CoreGraphics
import Foundation
import Testing
import Ollin
@testable import OllinVision

/// The scheduler (windows, keyframes, the fit between windows, the blend
/// across the overlap, padding and trimming) and the pass file are always-on,
/// driven by a window runner of the test's own. The real-model test runs only
/// where the clip window package and the reference file have been built
/// (`Scripts/fetch-models.sh`), soft-skipping elsewhere (CI never fetches the
/// weights), and checks the whole pass against the upstream inference's
/// result on the same clip.
@Suite struct DepthClipTests {

    static let modelURL = ModelTrackerTests.model("VideoDepthAnythingSmallClipF16.mlpackage")
    static let referenceURL = ModelTrackerTests.model("VideoDepthClipReference.bin")
    static var modelIsFetched: Bool { ModelTrackerTests.isFetched(modelURL) }
    static var referenceIsFetched: Bool { ModelTrackerTests.isFetched(referenceURL) }

    /// A stand-in for the model: each frame has a true depth (a smooth field
    /// that moves with the frame index), and every window reads it through
    /// its own scale and shift, the way one window's relative depth relates
    /// to the next. The scheduler's job is to undo that.
    final class DistortingRunner: WindowRunner {
        let width = 16
        let height = 12
        let index: [ObjectIdentifier: Int]
        private(set) var windows = 0

        init(images: [CGImage]) {
            var index: [ObjectIdentifier: Int] = [:]
            for (i, image) in images.enumerated() { index[ObjectIdentifier(image)] = i }
            self.index = index
        }

        func trueDepth(frame: Int) -> [Float] {
            (0..<height * width).map { i in
                let row = i / width, col = i % width
                return 1 + 0.5 * sin(Float(frame) / 7 + Float(col) / 3) + 0.3 * cos(Float(row) / 2)
            }
        }

        func run(_ window: [CGImage]) throws -> [[Float]] {
            defer { windows += 1 }
            let scale = 1 + 0.4 * Float(windows), shift = 0.7 * Float(windows)
            return window.map { image in
                trueDepth(frame: index[ObjectIdentifier(image)]!).map { $0 * scale + shift }
            }
        }
    }

    /// Distinct tiny images, one per frame, so the runner can tell frames apart.
    static func tags(_ count: Int) -> [CGImage] {
        (0..<count).map { _ in
            let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                    bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return context.makeImage()!
        }
    }

    static func passFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DepthClipTests-\(UUID().uuidString).depthclip")
    }

    // MARK: Always-on

    @Test func theFitRecoversAnAffineRelationExactly() {
        let target: [Float] = (0..<200).map { Float($0) * 0.01 + sin(Float($0)) }
        let prediction = target.map { $0 * 2.5 - 0.75 }
        let (scale, shift) = DepthClip.fit(prediction: prediction, target: target)
        #expect(abs(scale - 0.4) < 1e-5)
        #expect(abs(shift - 0.3) < 1e-5)
        let flat = [Float](repeating: 3, count: 50)
        let identity = DepthClip.fit(prediction: flat, target: flat)
        #expect(identity.scale == 1 && identity.shift == 0)
    }

    /// 50 frames: three windows (22 apart), padding to fill the last one,
    /// the padding's maps dropped again. Every frame's aligned map is the
    /// first window's reading of the true depth, whatever scale the later
    /// windows read it through.
    @Test func theSchedulerUndoesEachWindowsOwnScale() throws {
        let count = 50
        let images = Self.tags(count)
        let runner = DistortingRunner(images: images)
        var frames = ArrayFrames(images.enumerated().map { ($1, Double($0) / 30) })
        let file = Self.passFile()
        var reported: [Double] = []
        try DepthClip.writePass(from: &frames, through: runner, to: file) { reported.append($0) }
        let pass = try DepthClipPass(contentsOf: file)

        #expect(runner.windows == 3)
        #expect(pass.times.count == count)
        #expect(pass.width == 16 && pass.height == 12)
        #expect(reported.last == 1)
        #expect(reported == reported.sorted())
        var worst: Float = 0
        for frame in 0..<count {
            let truth = runner.trueDepth(frame: frame)
            for row in 0..<pass.height {
                for col in 0..<pass.width {
                    worst = max(worst, abs(pass.value(frame: frame, row: row, col: col) - truth[row * 16 + col]))
                }
            }
        }
        #expect(worst < 2e-3, "a window's own scale survived the alignment (max \(worst))")
        #expect(pass.range.lowerBound > 0.1 && pass.range.upperBound < 1.9)
        try? FileManager.default.removeItem(at: file)
    }

    @Test func aShortClipIsOneWindowAndKeepsItsOwnLength() throws {
        let images = Self.tags(5)
        let runner = DistortingRunner(images: images)
        var frames = ArrayFrames(images.enumerated().map { ($1, Double($0) * 0.5) })
        let file = Self.passFile()
        try DepthClip.writePass(from: &frames, through: runner, to: file) { _ in }
        let pass = try DepthClipPass(contentsOf: file)
        #expect(runner.windows == 1)
        #expect(pass.times == [0, 0.5, 1, 1.5, 2])
        #expect(pass.frameIndex(at: -1) == 0)
        #expect(pass.frameIndex(at: 0.49) == 0)
        #expect(pass.frameIndex(at: 0.5) == 1)
        #expect(pass.frameIndex(at: 1.2) == 2)
        #expect(pass.frameIndex(at: 99) == 4)
        try? FileManager.default.removeItem(at: file)
    }

    @Test func missingModelFileSurfacesInsteadOfFailingSilently() {
        let clip = DepthClip(frames: [(Self.tags(1)[0], 0)],
                             modelAt: URL(fileURLWithPath: "/nowhere/NoSuchClipModel.mlpackage"))
        clip.run()
        #expect(!clip.isAvailable)
        #expect(clip.unavailableReason?.contains("NoSuchClipModel") == true)
        #expect(!clip.isReady)
        #expect(clip.map(at: 0) == nil)
        #expect(clip.value(at: Vector2(1, 1), in: Rectangle(x: 0, y: 0, width: 2, height: 2), time: 0) == 0)
    }

    // MARK: Real model

    /// The reference clip, drawn the way the converter draws it (whole
    /// numbers only, so both sides hold the same bytes): two gradients, a
    /// drifting stripe field, two moving discs, a bright bar that wraps.
    static func referenceFrame(_ t: Int, width: Int = 518, height: Int = 392) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let bar = (width * (t % 20)) / 20
        for y in 0..<height {
            for x in 0..<width {
                var r = (x * 255) / (width - 1)
                var g = (y * 255) / (height - 1)
                var b = ((x + y + 3 * t) * 7) % 256
                let dx1 = x - (100 + 5 * t), dy1 = y - 200
                if dx1 * dx1 + dy1 * dy1 < 60 * 60 { (r, g, b) = (30, 60, 200) }
                let dx2 = x - (400 - 3 * t), dy2 = y - (120 + t)
                if dx2 * dx2 + dy2 * dy2 < 45 * 45 { (r, g, b) = (220, 200, 40) }
                if x >= bar && x < bar + width / 10 { (r, g, b) = (240, 240, 240) }
                let i = (y * width + x) * 4
                bytes[i] = UInt8(r); bytes[i + 1] = UInt8(g); bytes[i + 2] = UInt8(b)
            }
        }
        let data = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: data, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    struct Reference {
        var frames: Int, columns: Int, rows: Int, width: Int, height: Int
        var samples: [Float]
        init(contentsOf url: URL) throws {
            let data = try Data(contentsOf: url)
            func word(_ i: Int) -> Int {
                Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i, as: UInt32.self) })
            }
            try #require(String(decoding: data.prefix(4), as: UTF8.self) == "OLDC")
            try #require(word(4) == 1)
            frames = word(8); columns = word(12); rows = word(16); width = word(20); height = word(24)
            samples = data.dropFirst(28).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            try #require(samples.count == frames * rows * columns)
        }
    }

    /// The whole pass, frames in hand, against the upstream `infer_video_depth`
    /// on the same 60 frames (three windows, the fit and the blend between
    /// them, the padding): the same maps, to the tolerance of the half-float
    /// model.
    @Test(.enabled(if: modelIsFetched && referenceIsFetched)) func thePassMatchesThePublishedInference() throws {
        let reference = try Reference(contentsOf: Self.referenceURL)
        let frames = (0..<reference.frames).map {
            (image: Self.referenceFrame($0, width: reference.width, height: reference.height),
             seconds: Double($0) / 30)
        }
        let clip = DepthClip(frames: frames, modelAt: Self.modelURL)
        clip.run()
        try #require(clip.isReady, "\(clip.unavailableReason ?? "not ready")")
        #expect(clip.frameCount == reference.frames)
        let map = try #require(clip.map(at: 0.5))
        #expect(map.width == reference.width && map.height == reference.height)
        let range = try #require(clip.range)
        #expect(range.upperBound > range.lowerBound)

        var low = Float.greatestFiniteMagnitude, high = -Float.greatestFiniteMagnitude
        for s in reference.samples { low = min(low, s); high = max(high, s) }
        let spread = high - low
        var worst: Float = 0, total: Float = 0
        for frame in 0..<reference.frames {
            for r in 0..<reference.rows {
                let y = ((2 * r + 1) * reference.height) / (2 * reference.rows)
                for c in 0..<reference.columns {
                    let x = ((2 * c + 1) * reference.width) / (2 * reference.columns)
                    let expected = reference.samples[(frame * reference.rows + r) * reference.columns + c]
                    let got = try #require(clip.modelValue(frame: frame, row: y, col: x))
                    let diff = abs(got - expected)
                    worst = max(worst, diff)
                    total += diff
                }
            }
        }
        let mean = total / Float(reference.samples.count)
        print("DepthClip vs the published pass: max \(worst / spread), mean \(mean / spread) of a spread of \(spread)")
        #expect(worst / spread < 0.05, "max \(worst / spread) of the depth spread from the published pass")
        #expect(mean / spread < 0.01, "mean \(mean / spread) of the depth spread from the published pass")
        // The frame at a time: the one starting at or before it.
        #expect(clip.frameIndex(at: 0.0334) == 1)
        #expect(clip.value(at: Vector2(10, 10), in: Rectangle(x: 0, y: 0, width: 100, height: 100), time: 1) >= 0)
    }
}
