import Ollin
import Vision
import Foundation
import simd
import os

/// Contours found in an image — a tree of closed outlines, each possibly
/// containing nested contours (a shape with holes, a ring inside a disk). The
/// points are normalized (`0…1`, lower-left origin); the `in:` helpers map them
/// onto the canvas as Ollin geometry.
///
/// This is the bridge that makes a camera frame *vector*: `shapes(in:)` returns
/// Ollin `Shape`s you can fill, stroke, hatch, or write to SVG for a pen plotter,
/// and `contours(in:)` returns the raw closed `Contour`s for line work.
public struct DetectedContours: Sendable {

    /// One contour and the contours nested inside it.
    public struct Node: Sendable {
        /// The closed outline in normalized coordinates (lower-left origin).
        public let points: [Vector2]
        /// Contours enclosed by this one (holes, then islands, alternating).
        public let children: [Node]

        public init(points: [Vector2], children: [Node]) {
            self.points = points
            self.children = children
        }
    }

    /// The outermost contours; each may have `children`.
    public let topLevel: [Node]
    /// Total number of contours, nesting included.
    public let count: Int

    public init(topLevel: [Node], count: Int) {
        self.topLevel = topLevel
        self.count = count
    }

    /// No contours.
    public static let empty = DetectedContours(topLevel: [], count: 0)

    /// Every contour (top-level and nested) as a closed `Contour`, mapped into
    /// `rect`. Good for stroking the outlines as line work.
    public func contours(in rect: Rectangle, mirrored: Bool = false) -> [Contour] {
        var result: [Contour] = []
        func walk(_ node: Node) {
            let mapped = node.points.map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
            if mapped.count >= 2 { result.append(Contour(mapped, closed: true)) }
            node.children.forEach(walk)
        }
        topLevel.forEach(walk)
        return result
    }

    /// Each top-level contour and its nested contours collected into one
    /// even-odd `Shape`, mapped into `rect`. Even-odd winding makes the nesting
    /// read correctly — a hole inside a shape, an island inside a hole — so the
    /// result fills, hatches, and exports the way the picture looks.
    public func shapes(in rect: Rectangle, mirrored: Bool = false) -> [Shape] {
        topLevel.compactMap { node in
            var contours: [Contour] = []
            func collect(_ n: Node) {
                let mapped = n.points.map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
                if mapped.count >= 3 { contours.append(Contour(mapped, closed: true)) }
                n.children.forEach(collect)
            }
            collect(node)
            guard !contours.isEmpty else { return nil }
            return Shape(contours: contours, winding: .evenOdd)
        }
    }
}

/// Traces the outlines in a camera's frames (or a still image) into vector
/// contours. Where the other trackers find *things*, this one finds *edges* —
/// the boundaries between light and dark — and hands them back as Ollin geometry,
/// so a live scene becomes line art you can plot, hatch, or reshape.
///
/// ```swift
/// let camera = Camera()
/// let contours = ContourDetector(camera)
/// override func draw() {
///     background(.white)
///     stroke(.black); noFill()
///     for shape in contours.shapes(in: bounds) { drawShape(shape) }
/// }
/// ```
public final class ContourDetector: VisionTracking, @unchecked Sendable {

    /// Trace boundaries from dark shapes on a light background (the default, good
    /// for line art and documents). Set at creation.
    public let detectsDarkOnLight: Bool
    /// Edge contrast boost, `0…3` (higher finds fainter edges, and more noise).
    public let contrastAdjustment: Float

    private let lock = OSAllocatedUnfairLock<DetectedContours>(initialState: .empty)
    private let status = VisionStatus("contour detection")

    /// The contours found in the most recent analyzed frame.
    public var contourTree: DetectedContours { lock.withLock { $0 } }
    /// How many contours were found, nesting included.
    public var count: Int { lock.withLock { $0.count } }

    /// Whether contour detection can run on this Mac (`false` only if it has no
    /// compute device here); `unavailableReason` explains a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why contour detection can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// The contours mapped into `rect` (canvas space) — see
    /// `DetectedContours.contours(in:)`.
    public func contours(in rect: Rectangle, mirrored: Bool = false) -> [Contour] {
        contourTree.contours(in: rect, mirrored: mirrored)
    }

    /// The contours as even-odd `Shape`s mapped into `rect` — see
    /// `DetectedContours.shapes(in:)`.
    public func shapes(in rect: Rectangle, mirrored: Bool = false) -> [Shape] {
        contourTree.shapes(in: rect, mirrored: mirrored)
    }

    /// Trace contours in `source`'s frames — the live camera, or a playing video.
    @MainActor
    public init(_ source: any FrameSource, detectsDarkOnLight: Bool = true, contrastAdjustment: Float = 1) {
        self.detectsDarkOnLight = detectsDarkOnLight
        self.contrastAdjustment = contrastAdjustment
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Trace contours in a still image, once.
    public static func detect(in image: Image,
                              detectsDarkOnLight: Bool = true,
                              contrastAdjustment: Float = 1,
                              maximumDimension: Int = 1024) async throws -> DetectedContours {
        let request = ContourDetector.makeRequest(darkOnLight: detectsDarkOnLight,
                                                  contrast: contrastAdjustment,
                                                  maxDimension: maximumDimension)
        let observation = try await request.perform(on: image.currentCGImage())
        return decode(observation)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        // Cap the working resolution: full-res contour detection is slow, and a
        // live feed doesn't need every pixel of edge detail.
        guard status.isAvailable else { return }
        let request = ContourDetector.makeRequest(darkOnLight: detectsDarkOnLight,
                                                  contrast: contrastAdjustment,
                                                  maxDimension: 512)
        do {
            let observation = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { $0 = ContourDetector.decode(observation) }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Helpers

    private static func makeRequest(darkOnLight: Bool, contrast: Float, maxDimension: Int) -> DetectContoursRequest {
        var request = DetectContoursRequest()
        request.detectsDarkOnLight = darkOnLight
        request.contrastAdjustment = contrast
        request.maximumImageDimension = max(64, maxDimension)
        return request
    }

    private static func decode(_ observation: ContoursObservation) -> DetectedContours {
        func node(_ contour: ContoursObservation.Contour) -> DetectedContours.Node {
            let points = contour.normalizedPoints.map { Vector2(Double($0.x), Double($0.y)) }
            return DetectedContours.Node(points: points, children: contour.childContours.map(node))
        }
        return DetectedContours(topLevel: observation.topLevelContours.map(node),
                                count: observation.contourCount)
    }
}
