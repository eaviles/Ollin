import AVFoundation
import CoreGraphics
import CoreMedia
import CoreML
import Foundation
import Testing
import Ollin
@testable import OllinVision

/// The failure paths and the coordinate math are always-on; the real-model
/// tests run only where the matching model has been downloaded
/// (`Scripts/fetch-models.sh`) — or, for the style model, trained in Create ML —
/// soft-skipping elsewhere (CI never fetches the weights).
@Suite struct ModelTrackerTests {

    /// The repo root, located from this file so the tests don't depend on the
    /// working directory.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OllinVisionTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    static func model(_ name: String) -> URL {
        repoRoot.appendingPathComponent("Models/\(name)")
    }
    static func isFetched(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static let depthModelURL = model("DepthAnythingV2SmallF16.mlpackage")
    static var depthModelIsFetched: Bool { isFetched(depthModelURL) }
    static let detectorModelURL = model("YOLOv3TinyFP16.mlmodel")
    static let digitModelURL = model("MNISTClassifier.mlmodel")
    static let styleModelURL = model("StyleTransfer.mlmodel")
    static let segmentationModelURL = model("DeepLabV3FP16.mlmodel")

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
        let output = ModelOutput(labels: [], objects: [], map: nil, outputImage: nil,
                                 classMask: nil, mapBytes: nil)
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

    /// The class plane behind the segmentation surface, pinned
    /// deterministically: rows are top-down, queries are lower-left
    /// normalized and clamp, coverage counts pixels, and per-class masks
    /// memoize. A 4×2 plane: top row class 1, bottom row class 15 — except
    /// the bottom-right pixel, class 7.
    @Test func classMaskReadsAndMasks() throws {
        var counts = [Int](repeating: 0, count: 256)
        counts[1] = 4; counts[15] = 3; counts[7] = 1
        let mask = ClassMask(plane: [1, 1, 1, 1, 15, 15, 15, 7], width: 4, height: 2,
                             counts: counts, labels: deepLabStyleLabels)

        // Largest first; names follow the vocabulary.
        #expect(mask.presentClasses == [1, 15, 7])
        #expect(mask.presentLabels == ["aeroplane", "person", "car"])
        #expect(mask.coverage(ofClass: 1) == 0.5)
        #expect(mask.coverage(of: "person") == 3.0 / 8)
        #expect(mask.coverage(of: "PERSON") == 3.0 / 8)   // case-insensitive
        #expect(mask.coverage(of: "submarine") == 0)

        // Lower-left normalized: y near 1 is the picture's top.
        #expect(mask.classIndexNormalized(at: Vector2(0.5, 0.9)) == 1)
        #expect(mask.classIndexNormalized(at: Vector2(0.5, 0.1)) == 15)
        #expect(mask.classIndexNormalized(at: Vector2(0.99, 0.1)) == 7)
        // Clamping: far-out points answer, never trap.
        #expect(mask.classIndexNormalized(at: Vector2(5, -3)) == 7)
        #expect(mask.classIndexNormalized(at: Vector2(-1, 2)) == 1)

        // Canvas-space query, the y flip and the mirror.
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(mask.label(at: Vector2(50, 10), in: rect) == "aeroplane")
        #expect(mask.label(at: Vector2(10, 90), in: rect) == "person")
        #expect(mask.label(at: Vector2(90, 90), in: rect) == "car")
        #expect(mask.label(at: Vector2(90, 90), in: rect, mirrored: true) == "person")

        // The per-class mask: white-alpha where the class is, clear elsewhere,
        // and the same instance on a repeated read (memoized).
        let person = try #require(mask.mask(of: "person"))
        #expect(person.width == 4 && person.height == 2)
        #expect(person[0, 1].alpha == 1 && person[0, 1].red == 1)
        #expect(person[0, 0].alpha == 0)
        #expect(person[3, 1].alpha == 0)   // the car pixel
        #expect(mask.mask(ofClass: 15) === person)
        // A class not in frame answers nil.
        #expect(mask.mask(ofClass: 3) == nil)
        #expect(mask.mask(of: "bird") == nil)
    }

    /// The multiarray decode: `[H, W]` Int32 (the DeepLabV3 form), a leading
    /// 1-sized dim squeezed, the Float fallback rounded — and shapes that
    /// aren't a class plane rejected.
    @Test func classMaskDecodesShapedArrays() throws {
        let scalars: [Int32] = [0, 1, 2, 3, 4, 5]
        for shape in [[2, 3], [1, 2, 3]] {
            let array = MLShapedArray<Int32>(scalars: scalars, shape: shape)
            let mask = try #require(ClassMask(featureValue: .init(array), labels: []),
                                    "shape \(shape) should decode")
            #expect(mask.width == 3 && mask.height == 2)
            #expect(mask.classIndexNormalized(at: Vector2(0.99, 0.9)) == 2)   // top-right
            #expect(mask.classIndexNormalized(at: Vector2(0.01, 0.1)) == 3)   // bottom-left
            #expect(mask.presentClasses.count == 6)
        }

        let floats = MLShapedArray<Float>(scalars: [0.2, 0.8, 14.6, 15.4], shape: [2, 2])
        let rounded = try #require(ClassMask(featureValue: .init(floats), labels: []))
        #expect(rounded.classIndexNormalized(at: Vector2(0.1, 0.9)) == 0)
        #expect(rounded.classIndexNormalized(at: Vector2(0.9, 0.9)) == 1)
        #expect(rounded.classIndexNormalized(at: Vector2(0.1, 0.1)) == 15)
        #expect(rounded.classIndexNormalized(at: Vector2(0.9, 0.1)) == 15)

        // Not a class plane: 3D logits and 1D vectors stay undecoded.
        let logits = MLShapedArray<Float>(repeating: 0, shape: [4, 2, 2])
        #expect(ClassMask(featureValue: .init(logits), labels: []) == nil)
        let vector = MLShapedArray<Int32>(repeating: 0, shape: [8])
        #expect(ClassMask(featureValue: .init(vector), labels: []) == nil)
    }

    /// The 21 PASCAL VOC labels in the DeepLabV3 metadata ordering.
    private var deepLabStyleLabels: [String] {
        ["background", "aeroplane", "bicycle", "bird", "boat", "bottle", "bus",
         "car", "cat", "chair", "cow", "diningTable", "dog", "horse",
         "motorbike", "person", "pottedPlant", "sheep", "sofa", "train",
         "tvOrMonitor"]
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

    /// The full-color surface rides the same observation as the gray one: for
    /// the depth model, `outputImage` is the map at face value, so the two must
    /// agree — the picture's pixel values are what the map holds as alpha.
    @Test func outputImageMatchesTheMapItWasDecodedFrom() async throws {
        guard Self.depthModelIsFetched else { return }
        let tracker = ModelTracker(modelAt: Self.depthModelURL)
        let output = try await tracker.detect(in: gradientScene(width: 320, height: 240))
        let map = try #require(output.map)
        let picture = try #require(output.outputImage)
        #expect(picture.width == map.width && picture.height == map.height)
        var mismatched = 0
        for y in stride(from: 0, to: map.height, by: 7) {
            for x in stride(from: 0, to: map.width, by: 11)
            where abs(picture[x, y].red - map[x, y].alpha) > 2.0 / 255 {
                mismatched += 1
            }
        }
        #expect(mismatched == 0)
    }

    /// The `objects` surface over the real detector: YOLOv3-tiny finds the
    /// person in the bundled clip's opening scene — the end-to-end pin for the
    /// fetched model + the labeled-box decode. (Later in the same clip the
    /// flying dancers read as "kite" and "bird" — the model's age, honestly.)
    @Test func detectorFindsThePersonInRealFootage() async throws {
        guard Self.isFetched(Self.detectorModelURL) else { return }
        let frame = try await Self.clipFrame(at: 6)
        let tracker = ModelTracker(modelAt: Self.detectorModelURL)
        let output = try await tracker.detect(in: Image(cgImage: frame))
        let person = try #require(output.objects.first { $0.label == "person" })
        #expect(person.confidence > 0.5)
        let rect = Rectangle(x: 0, y: 0, width: 960, height: 540)
        let bounds = person.bounds(in: rect)
        #expect(bounds.width > 0 && bounds.height > 0)
        // A detector fills only the objects surface.
        #expect(output.labels.isEmpty)
        #expect(output.map == nil)
    }

    /// The classifier surface over a drawn digit: a thick ring on black — a
    /// "0" in the form MNIST was trained on — through the same still path the
    /// DigitReader example uses.
    @Test func digitClassifierReadsADrawnZero() async throws {
        guard Self.isFetched(Self.digitModelURL) else { return }
        let pad = Image(width: 280, height: 280, color: .black)
        let c = 140.0
        for y in 0..<280 {
            for x in 0..<280 {
                let d = ((Double(x) - c) * (Double(x) - c)
                       + (Double(y) - c) * (Double(y) - c)).squareRoot()
                if abs(d - 80) < 18 { pad[x, y] = .white }
            }
        }
        let tracker = ModelTracker(modelAt: Self.digitModelURL)
        let output = try await tracker.detect(in: pad)
        let top = try #require(output.labels.first)
        #expect(top.label == "0")
        #expect(top.confidence > 0.9)
        #expect(output.objects.isEmpty)
    }

    /// A Create ML style-transfer model paints in color: `outputImage` comes
    /// back at the model's size with the style's hues, not a gray map. Gated on
    /// the locally *trained* model (the StyleMirror example's instructions),
    /// not a fetched one.
    @Test func styleModelPaintsInColor() async throws {
        guard Self.isFetched(Self.styleModelURL) else { return }
        let frame = try await Self.clipFrame(at: 6)
        let tracker = ModelTracker(modelAt: Self.styleModelURL)
        let output = try await tracker.detect(in: Image(cgImage: frame))
        let picture = try #require(output.outputImage)
        #expect(picture.width > 0 && picture.height > 0)
        // Styled output is colorful: a healthy share of sampled pixels must
        // have channels that actually differ (a gray decode would have none).
        var colorful = 0, sampled = 0
        for y in stride(from: 0, to: picture.height, by: 13) {
            for x in stride(from: 0, to: picture.width, by: 17) {
                let p = picture[x, y]
                let spread = max(p.red, p.green, p.blue) - min(p.red, p.green, p.blue)
                if spread > 10.0 / 255 { colorful += 1 }
                sampled += 1
            }
        }
        #expect(colorful > sampled / 10)
    }

    /// The class-mask surface over the real segmenter: DeepLabV3 finds the
    /// person pixels in the bundled clip — the end-to-end pin for the fetched
    /// model, the metadata vocabulary, and the top-down plane orientation
    /// (the flyers are in the picture's top half, so their centroid must read
    /// in the normalized upper half — the regression shape that caught the
    /// mirrored point queries elsewhere in the catalog).
    @Test func segmenterLabelsThePersonPixelsInRealFootage() async throws {
        guard Self.isFetched(Self.segmentationModelURL) else { return }
        let frame = try await Self.clipFrame(at: 1)
        let tracker = ModelTracker(modelAt: Self.segmentationModelURL)
        let output = try await tracker.detect(in: Image(cgImage: frame))
        let classes = try #require(output.classMask)
        #expect(classes.width == 513 && classes.height == 513)

        // The model declares its own vocabulary; the load picks it up.
        #expect(classes.labels.count == 21)
        #expect(classes.labels.first == "background")
        #expect(classes.labels[15] == "person")
        #expect(classes.presentLabels.contains("person"))
        let coverage = classes.coverage(of: "person")
        #expect(coverage > 0.005 && coverage < 0.3)

        // Orientation, end to end: the person pixels' centroid sits in the
        // top half (normalized lower-left, so y > 0.5).
        var ySum = 0.0
        var hits = 0
        for gy in 0..<40 {
            for gx in 0..<40 {
                let point = Vector2((Double(gx) + 0.5) / 40, (Double(gy) + 0.5) / 40)
                if classes.classIndexNormalized(at: point) == 15 {
                    ySum += point.y
                    hits += 1
                }
            }
        }
        #expect(hits > 0)
        #expect(ySum / Double(max(hits, 1)) > 0.5)

        // The drawable mask is built from the same plane, so it must agree
        // with the queries cell for cell.
        let person = try #require(classes.mask(of: "person"))
        #expect(person.width == 513 && person.height == 513)
        var mismatched = 0
        for y in stride(from: 0, to: 513, by: 17) {
            for x in stride(from: 0, to: 513, by: 13) {
                let u = (Double(x) + 0.5) / 513
                let v = 1 - (Double(y) + 0.5) / 513
                let isPerson = classes.classIndexNormalized(at: Vector2(u, v)) == 15
                if (person[x, y].alpha == 1) != isPerson { mismatched += 1 }
            }
        }
        #expect(mismatched == 0)

        // A segmenter fills only the class-mask surface.
        #expect(output.labels.isEmpty)
        #expect(output.objects.isEmpty)
        #expect(output.map == nil)
    }

    /// A frame of the bundled CC BY-SA clip (`Examples/Video/VideoPlayback`),
    /// decoded at an exact timestamp so the real-model pins are reproducible.
    static func clipFrame(at seconds: Double) async throws -> CGImage {
        let video = repoRoot.appendingPathComponent("Examples/Video/VideoPlayback/voladores.mp4")
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (frame, _) = try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600))
        return frame
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
    /// loads in the background, and the surfaces publish. Reads `map` and
    /// `outputImage` in the poll loop because each surface's first read arms
    /// its own conversion.
    @Test @MainActor func liveWiringPublishes() async throws {
        guard Self.depthModelIsFetched else { return }
        let source = FrameSourceTests.ManualFrameSource()
        let tracker = ModelTracker(source, modelAt: Self.depthModelURL)
        let frame = gradientScene(width: 160, height: 120)
        let cgImage = frame.currentCGImage()

        // Attaching the tracker installed the analyzer's tap; feed it one
        // frame the way a capture queue would (its background analysis is not
        // waited on: a deadline over it reads a saturated full-suite machine
        // as a failure).
        let tap = try #require(source.frameTap)
        tap(cgImage)

        // The first read of each surface arms its conversion, so the analyzed
        // frame below publishes both.
        #expect(tracker.map == nil)
        #expect(tracker.outputImage == nil)

        // The still path awaits the same shared model load deterministically;
        // then the deterministic drive runs the live analyze path inline.
        _ = try await tracker.detect(in: frame)
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(cgImage))

        #expect(tracker.map != nil)
        #expect(tracker.outputImage != nil)
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
