import Ollin
import Vision
import Foundation
import os

/// A recognized line of text — what it says, how sure the recognizer is, and
/// where it sits, in normalized coordinates.
public struct DetectedText: Sendable {

    /// The recognized text of this line.
    public let text: String
    /// Recognition confidence, `0…1`.
    public let confidence: Double

    // Normalized corners (lower-left origin), image order.
    let topLeftN: Vector2
    let topRightN: Vector2
    let bottomRightN: Vector2
    let bottomLeftN: Vector2

    /// The four corners of the line mapped into `rect`, in perimeter order.
    public func corners(in rect: Rectangle, mirrored: Bool = false) -> [Vector2] {
        [topLeftN, topRightN, bottomRightN, bottomLeftN]
            .map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// The axis-aligned box around the line, mapped into `rect`.
    public func bounds(in rect: Rectangle, mirrored: Bool = false) -> Rectangle {
        let c = corners(in: rect, mirrored: mirrored)
        let xs = c.map(\.x), ys = c.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return Rectangle(x: minX, y: minY,
                         width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }
}

/// Reads text out of a camera's frames (or a still image) — Apple's OCR, with the
/// same language coverage as Live Text. Read signs, labels, handwriting, and
/// pages; the recognized lines come back with their text and position.
///
/// ```swift
/// let camera = Camera()
/// let reader = TextRecognizer(camera)
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     for line in reader.lines {
///         drawRect(line.bounds(in: bounds))
///         drawText(line.text, line.bounds(in: bounds).corner)
///     }
/// }
/// ```
public final class TextRecognizer: VisionTracking, @unchecked Sendable {

    /// How hard the recognizer works: `.fast` keeps up with a live feed,
    /// `.accurate` reads more (and slower) — the default for still images.
    public enum Level: Sendable { case fast, accurate }

    /// The recognition level for the live feed.
    public let level: Level

    private let lock = OSAllocatedUnfairLock<[DetectedText]>(initialState: [])
    private let status = VisionStatus("text recognition")

    /// The lines of text found in the most recent analyzed frame.
    public var lines: [DetectedText] { lock.withLock { $0 } }
    /// All recognized lines joined with newlines — the whole block of text.
    public var text: String { lines.map(\.text).joined(separator: "\n") }
    /// How many lines were recognized.
    public var count: Int { lock.withLock { $0.count } }

    /// Whether text recognition can run on this Mac; `unavailableReason` explains
    /// a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why text recognition can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Recognize text in `source`'s frames — the live camera, or a playing
    /// video. Defaults to `.fast` so it keeps up.
    @MainActor
    public init(_ source: any FrameSource, level: Level = .fast) {
        self.level = level
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Recognize text in a still image, once. Defaults to `.accurate`.
    public static func detect(in image: Image, level: Level = .accurate) async throws -> [DetectedText] {
        let request = makeRequest(level: level)
        let observations = try await request.perform(on: image.currentCGImage())
        return observations.map(decode)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        let request = TextRecognizer.makeRequest(level: level)
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { $0 = observations.map(TextRecognizer.decode) }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Helpers

    private static func makeRequest(level: Level) -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = (level == .fast) ? .fast : .accurate
        request.usesLanguageCorrection = (level == .accurate)
        return request
    }

    private static func decode(_ observation: RecognizedTextObservation) -> DetectedText {
        func vec(_ p: NormalizedPoint) -> Vector2 { Vector2(Double(p.x), Double(p.y)) }
        return DetectedText(
            text: observation.transcript,
            confidence: Double(observation.confidence),
            topLeftN: vec(observation.topLeft),
            topRightN: vec(observation.topRight),
            bottomRightN: vec(observation.bottomRight),
            bottomLeftN: vec(observation.bottomLeft)
        )
    }
}
