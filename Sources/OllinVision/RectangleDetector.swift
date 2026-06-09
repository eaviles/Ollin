import Ollin
import Vision
import Foundation
import os

/// A detected rectangle — a four-corner quad, possibly seen in perspective (a
/// document, a screen, a card on a desk), in normalized coordinates. The corners
/// are in image order (top-left, top-right, bottom-right, bottom-left); map them
/// onto the canvas with the `in:` helpers.
public struct DetectedRectangle: Sendable {

    /// Detection confidence, `0…1`.
    public let confidence: Double

    // Normalized corners (lower-left origin), image order.
    let topLeftN: Vector2
    let topRightN: Vector2
    let bottomRightN: Vector2
    let bottomLeftN: Vector2

    /// The four corners mapped into `rect`, in perimeter order (top-left,
    /// top-right, bottom-right, bottom-left) — ready to `drawPolygon` as a closed
    /// quad, perspective and all.
    public func corners(in rect: Rectangle, mirrored: Bool = false) -> [Vector2] {
        [topLeftN, topRightN, bottomRightN, bottomLeftN]
            .map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// The center of the quad, mapped into `rect`.
    public func center(in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        let c = corners(in: rect, mirrored: mirrored)
        let sum = c.reduce(Vector2.zero, +)
        return sum / Double(c.count)
    }
}

/// Finds rectangular shapes — documents, screens, cards, signs — even seen at an
/// angle, and reports their four corners. A classical detector (no ML model), so
/// it runs on any Mac. Useful for framing, scanning, and warping the thing you
/// point at into a flat view.
///
/// ```swift
/// let camera = Camera()
/// let rects = RectangleDetector(camera)
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     noFill(); stroke(.green)
///     for r in rects.rectangles { drawPolygon(r.corners(in: bounds)) }
/// }
/// ```
public final class RectangleDetector: VisionTracking, @unchecked Sendable {

    /// The narrowest quad to report, as the ratio of short side to long side
    /// (`1` = square, lower = more elongated allowed).
    public let minimumAspectRatio: Float
    /// The widest quad to report (`1` = square).
    public let maximumAspectRatio: Float
    /// The smallest quad to report, as a fraction of the image.
    public let minimumSize: Float
    /// The confidence a quad must reach to be reported, `0…1`.
    public let minimumConfidence: Float
    /// The most quads to report per frame.
    public let maximumCount: Int

    private let lock = OSAllocatedUnfairLock<[DetectedRectangle]>(initialState: [])
    private let status = VisionStatus("rectangle detection")

    /// The rectangles found in the most recent analyzed frame.
    public var rectangles: [DetectedRectangle] { lock.withLock { $0 } }
    /// How many rectangles are present right now.
    public var count: Int { lock.withLock { $0.count } }

    /// Whether rectangle detection can run here (it's classical, so effectively
    /// always `true`); `unavailableReason` would explain a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why rectangle detection can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Detect rectangles in `camera`'s live feed.
    @MainActor
    public init(_ camera: Camera,
                minimumAspectRatio: Float = 0.2,
                maximumAspectRatio: Float = 1.0,
                minimumSize: Float = 0.1,
                minimumConfidence: Float = 0.6,
                maximumCount: Int = 8) {
        self.minimumAspectRatio = minimumAspectRatio
        self.maximumAspectRatio = maximumAspectRatio
        self.minimumSize = minimumSize
        self.minimumConfidence = minimumConfidence
        self.maximumCount = max(1, maximumCount)
        camera.register(self)
    }

    /// Detect rectangles in a still image, once.
    public static func detect(in image: Image,
                              minimumAspectRatio: Float = 0.2,
                              maximumAspectRatio: Float = 1.0,
                              minimumSize: Float = 0.1,
                              minimumConfidence: Float = 0.6,
                              maximumCount: Int = 8) async throws -> [DetectedRectangle] {
        let request = makeRequest(minimumAspectRatio: minimumAspectRatio,
                                  maximumAspectRatio: maximumAspectRatio,
                                  minimumSize: minimumSize,
                                  minimumConfidence: minimumConfidence,
                                  maximumCount: maximumCount)
        let observations = try await request.perform(on: image.currentCGImage())
        return observations.map(decode)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        let request = RectangleDetector.makeRequest(minimumAspectRatio: minimumAspectRatio,
                                                    maximumAspectRatio: maximumAspectRatio,
                                                    minimumSize: minimumSize,
                                                    minimumConfidence: minimumConfidence,
                                                    maximumCount: maximumCount)
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { $0 = observations.map(RectangleDetector.decode) }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Helpers

    private static func makeRequest(minimumAspectRatio: Float, maximumAspectRatio: Float,
                                    minimumSize: Float, minimumConfidence: Float,
                                    maximumCount: Int) -> DetectRectanglesRequest {
        var request = DetectRectanglesRequest()
        request.minimumAspectRatio = minimumAspectRatio
        request.maximumAspectRatio = maximumAspectRatio
        request.minimumSize = minimumSize
        request.minimumConfidence = minimumConfidence
        request.maximumObservations = max(1, maximumCount)
        return request
    }

    private static func decode(_ observation: RectangleObservation) -> DetectedRectangle {
        func vec(_ p: NormalizedPoint) -> Vector2 { Vector2(Double(p.x), Double(p.y)) }
        return DetectedRectangle(
            confidence: Double(observation.confidence),
            topLeftN: vec(observation.topLeft),
            topRightN: vec(observation.topRight),
            bottomRightN: vec(observation.bottomRight),
            bottomLeftN: vec(observation.bottomLeft)
        )
    }
}
