import Ollin
import Vision
import Foundation
import os

/// One detected face, in normalized coordinates (`0…1`, lower-left origin). Use
/// the `in:` helpers to place it on the canvas — pass the same rectangle you drew
/// the frame into so the overlay lines up.
///
/// ```swift
/// for face in faces.faces {
///     drawRect(face.bounds(in: bounds))
///     drawPolyline(face.landmarks(.faceContour, in: bounds))
/// }
/// ```
public struct Face: Sendable, Identifiable {

    /// A stable identifier for this face within a detection (Vision's own UUID).
    public let id: UUID
    /// Detection confidence, `0…1`.
    public let confidence: Double
    /// Head roll, in radians (tilt of the head toward a shoulder).
    public let roll: Double
    /// Head yaw, in radians (turn left/right).
    public let yaw: Double
    /// Head pitch, in radians (nod up/down).
    public let pitch: Double
    /// A `0…1` capture-quality score (sharpness, lighting, expression neutrality)
    /// when available — handy for picking the best frame of a face. `nil` if the
    /// detector didn't score it.
    public let quality: Double?

    /// The face bounding box in normalized coordinates (lower-left origin). Most
    /// sketches want `bounds(in:)` instead, which maps it to canvas space.
    public let boundingBoxNormalized: Rectangle

    /// Normalized landmark points per region (lower-left origin). Empty when the
    /// detector returned no landmarks.
    let landmarkPoints: [FaceLandmark: [Vector2]]

    /// Whether landmark points are present.
    public var hasLandmarks: Bool { !landmarkPoints.isEmpty }

    /// The bounding box mapped into `rect` (canvas space). Set `mirrored` when the
    /// frame is drawn flipped left-to-right.
    public func bounds(in rect: Rectangle, mirrored: Bool = false) -> Rectangle {
        VisionSpace.rectangle(boundingBoxNormalized, in: rect, mirrored: mirrored)
    }

    /// The center of the face, mapped into `rect`.
    public func center(in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        bounds(in: rect, mirrored: mirrored).center
    }

    /// A landmark region's points mapped into `rect`. Returns an empty array when
    /// the region wasn't detected. A region like `.faceContour` or `.outerLips`
    /// reads as an open polyline; `.leftEye` / `.outerLips` close into a loop.
    public func landmarks(_ region: FaceLandmark, in rect: Rectangle,
                          mirrored: Bool = false) -> [Vector2] {
        (landmarkPoints[region] ?? []).map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }
}

/// A face landmark region. The points within one are ordered along the feature.
public enum FaceLandmark: Sendable, CaseIterable {
    case faceContour
    case leftEye, rightEye
    case leftEyebrow, rightEyebrow
    case nose, noseCrest
    case medianLine
    case outerLips, innerLips
    case leftPupil, rightPupil
    /// Every landmark point the detector produced, in one bag.
    case allPoints
}

/// Finds faces — their bounding box, head pose, capture quality, and 76-point
/// landmarks (eyes, brows, nose, lips, jaw, pupils) — in a camera's frames or in
/// a still image.
///
/// Live, over a camera:
/// ```swift
/// let camera = Camera()
/// let faces = FaceTracker(camera)
/// override func setup() { try? camera.start() }
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     for face in faces.faces { drawRect(face.bounds(in: bounds)) }
/// }
/// ```
///
/// One-shot, on an image you loaded:
/// ```swift
/// let found = try await FaceTracker.detect(in: loadImage("crowd.jpg")!)
/// ```
public final class FaceTracker: VisionTracking, @unchecked Sendable {

    private let faceLock = OSAllocatedUnfairLock<[Face]>(initialState: [])
    private let status = VisionStatus("face tracking")

    /// The faces seen in the most recent analyzed frame (empty when none). Read it
    /// in `draw()`.
    public var faces: [Face] { faceLock.withLock { $0 } }

    /// How many faces are present right now.
    public var count: Int { faceLock.withLock { $0.count } }

    /// Whether face tracking can run on this Mac (`false` only if the Vision model
    /// has no compute device here); `unavailableReason` explains a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why face tracking can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Track faces in `camera`'s live feed. Registers with the camera; results
    /// arrive in `faces` as frames are analyzed.
    @MainActor
    public init(_ camera: Camera) {
        camera.register(self)
    }

    /// Detect faces in a still image, once. The still-image path every tracker
    /// offers: it needs no camera, runs on any loaded `Image`, and is how the
    /// tests exercise detection.
    public static func detect(in image: Image) async throws -> [Face] {
        let request = DetectFaceLandmarksRequest()
        let observations = try await request.perform(on: image.currentCGImage())
        return decode(observations, imageSize: CGSize(width: image.width, height: image.height))
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        let request = DetectFaceLandmarksRequest()
        // A transient failure leaves the previous results in place; an empty
        // success (no faces) clears them, which is what a sketch wants.
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            faceLock.withLock { $0 = FaceTracker.decode(observations, imageSize: size) }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Decoding

    private static func decode(_ observations: [FaceObservation], imageSize: CGSize) -> [Face] {
        let w = Double(imageSize.width), h = Double(imageSize.height)
        return observations.map { obs in
            let box = obs.boundingBox
            let rect = Rectangle(x: Double(box.origin.x), y: Double(box.origin.y),
                                 width: Double(box.width), height: Double(box.height))

            var points: [FaceLandmark: [Vector2]] = [:]
            if let landmarks = obs.landmarks, w > 0, h > 0 {
                // Use Vision's own point→image conversion rather than composing the
                // bounding box by hand: the landmark normalization isn't a plain
                // `origin + point·size`, so the manual form over-spreads the
                // features. `pointsInImageCoordinates` returns pixels (lower-left
                // origin); normalizing by the frame size gives image-normalized
                // points the shared mapping then flips onto the canvas.
                func capture(_ region: FaceObservation.Landmarks2D.Region) -> [Vector2] {
                    region.pointsInImageCoordinates(imageSize, origin: .lowerLeft).map { point in
                        Vector2(Double(point.x) / w, Double(point.y) / h)
                    }
                }
                points[.faceContour]  = capture(landmarks.faceContour)
                points[.leftEye]      = capture(landmarks.leftEye)
                points[.rightEye]     = capture(landmarks.rightEye)
                points[.leftEyebrow]  = capture(landmarks.leftEyebrow)
                points[.rightEyebrow] = capture(landmarks.rightEyebrow)
                points[.nose]         = capture(landmarks.nose)
                points[.noseCrest]    = capture(landmarks.noseCrest)
                points[.medianLine]   = capture(landmarks.medianLine)
                points[.outerLips]    = capture(landmarks.outerLips)
                points[.innerLips]    = capture(landmarks.innerLips)
                points[.leftPupil]    = capture(landmarks.leftPupil)
                points[.rightPupil]   = capture(landmarks.rightPupil)
                points[.allPoints]    = capture(landmarks.allPoints)
                points = points.filter { !$0.value.isEmpty }
            }

            return Face(
                id: obs.uuid,
                confidence: Double(obs.confidence),
                roll: obs.roll.converted(to: .radians).value,
                yaw: obs.yaw.converted(to: .radians).value,
                pitch: obs.pitch.converted(to: .radians).value,
                quality: obs.captureQuality.map { Double($0.score) },
                boundingBoxNormalized: rect,
                landmarkPoints: points
            )
        }
    }
}
