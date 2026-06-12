import Ollin
import Vision
import Foundation
import os

/// One thing the classifier saw in the picture, and how strongly.
public struct Classification: Sendable {

    /// The label's identifier — lowercase with underscores, like `"blue_sky"`
    /// or `"ping_pong"`. The full vocabulary is `ImageClassifier.supportedLabels()`.
    public let label: String
    /// How confident the classifier is that the label applies, `0…1`.
    public let confidence: Double

    /// The label with its underscores opened up — `"blue sky"` — ready to draw.
    public var name: String { label.replacingOccurrences(of: "_", with: " ") }
}

/// Names what a camera's frames (or a still image) show — `"sky"`, `"people"`,
/// `"dog"`, `"food"` — from a fixed vocabulary of about 1,300 everyday labels.
/// No boxes or positions, just *what's in the picture*: read the strongest
/// labels each frame, or ask for one concept by name and let its confidence
/// drive the sketch.
///
/// ```swift
/// let camera = Camera()
/// let classifier = ImageClassifier(camera)
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     for (i, found) in classifier.labels.prefix(5).enumerated() {
///         drawText("\(found.name) \(Int(found.confidence * 100))%", 40, 60 + Double(i) * 30)
///     }
///     let dogness = classifier.confidence(of: "dog")   // 0…1, any label by name
/// }
/// ```
public final class ImageClassifier: VisionTracking, @unchecked Sendable {

    /// Labels below this confidence stay out of `labels` (the full scored
    /// vocabulary is still readable through `confidence(of:)`).
    public let minimumConfidence: Double

    private let lock = OSAllocatedUnfairLock<[Classification]>(initialState: [])
    private let status = VisionStatus("image classification")

    /// What the most recent analyzed frame shows: every label at or above
    /// `minimumConfidence`, strongest first.
    public var labels: [Classification] {
        let floor = minimumConfidence
        return lock.withLock { Array($0.prefix { $0.confidence >= floor }) }
    }

    /// The single strongest label, or `nil` while nothing clears the floor.
    public var top: Classification? { labels.first }

    /// The confidence for one label by name, `0…1` — `0` when it wasn't scored.
    /// Unfiltered, so a concept below `minimumConfidence` still reads its true
    /// (small) value; spaces work in place of underscores (`"blue sky"`).
    public func confidence(of label: String) -> Double {
        let wanted = label.lowercased().replacingOccurrences(of: " ", with: "_")
        return lock.withLock { $0.first { $0.label == wanted }?.confidence ?? 0 }
    }

    /// Whether classification can run on this Mac; `unavailableReason` explains
    /// a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why classification can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Classify `source`'s frames — the live camera, or a playing video.
    @MainActor
    public init(_ source: any FrameSource, minimumConfidence: Double = 0.1) {
        self.minimumConfidence = minimumConfidence
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Classify a still image, once.
    public static func detect(in image: Image,
                              minimumConfidence: Double = 0.1) async throws -> [Classification] {
        let observations = try await ClassifyImageRequest().perform(on: image.currentCGImage())
        return Array(decode(observations).prefix { $0.confidence >= minimumConfidence })
    }

    /// Every label the classifier knows — the full vocabulary `labels` and
    /// `confidence(of:)` draw from, alphabetical.
    public static func supportedLabels() -> [String] {
        ClassifyImageRequest().supportedIdentifiers
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        do {
            let observations = try await ClassifyImageRequest().perform(on: cgImage)
            status.recordSuccess()
            let decoded = ImageClassifier.decode(observations)
            lock.withLock { $0 = decoded }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Helpers

    /// The request scores the *entire* vocabulary every time (~1,300 labels,
    /// most near zero); keep them all, strongest first, so `confidence(of:)`
    /// can answer for any label while `labels` prefixes the meaningful ones.
    private static func decode(_ observations: [ClassificationObservation]) -> [Classification] {
        observations
            .map { Classification(label: $0.identifier, confidence: Double($0.confidence)) }
            .sorted { $0.confidence > $1.confidence }
    }
}
