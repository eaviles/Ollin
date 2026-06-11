import Ollin
import Vision
import CoreGraphics
import Foundation
import os

/// Segments the people out of a camera's frames (or a still image): a soft
/// matte of everyone in view, and the cutout it makes — you, lifted off the
/// background, ready to composite over anything a sketch can draw.
///
/// ```swift
/// let camera = Camera()
/// lazy var people = PersonSegmenter(camera)
/// override func draw() {
///     drawAnimatedBackground()
///     let rect = camera.fittedRect(in: bounds) ?? bounds
///     if let cutout = people.cutout { drawImage(cutout, in: rect) }
/// }
/// ```
///
/// `matte` is the white-alpha silhouette (tint it for shadows and glows),
/// `cutout` the frame's own pixels — see `Segmentation` for both. Draw either
/// into the same rectangle as the frame and they line up with the picture.
/// It's a neural model, so it needs a capable compute device (Apple silicon);
/// on a Mac without one `isAvailable` turns `false` and `unavailableReason`
/// says why instead of just reporting an empty matte.
public final class PersonSegmenter: VisionTracking, @unchecked Sendable {

    /// The speed/quality trade for the segmentation model. `.balanced` is the
    /// live default; `.fast` is the low-latency end (a coarser matte) and
    /// `.accurate` the highest-resolution matte, at still-image cost.
    public enum Quality: Sendable {
        case fast, balanced, accurate

        var visionLevel: GeneratePersonSegmentationRequest.QualityLevel {
            switch self {
            case .fast:     return .fast
            case .balanced: return .balanced
            case .accurate: return .accurate
            }
        }
    }

    private struct Results {
        var matte: FrameBox?
        var cutout: FrameBox?
    }
    private let lock = OSAllocatedUnfairLock<Results>(initialState: Results())
    private let status = VisionStatus("person segmentation")
    /// One request reused across frames — it's a stateful (video-aware) request,
    /// and the analyzer runs one analysis at a time, so reuse is serial.
    private let request: GeneratePersonSegmentationRequest
    private let matteCache = ImageWrapCache()
    private let cutoutCache = ImageWrapCache()

    /// The people matte from the most recent analyzed frame — white, alpha =
    /// per-pixel confidence — or `nil` before the first result. Empty (fully
    /// transparent) when no one is in view.
    public var matte: Image? { matteCache.image(for: lock.withLock { $0.matte }?.cgImage) }

    /// The frame's pixels where people are, transparent elsewhere, from the most
    /// recent analyzed frame — or `nil` before the first result.
    public var cutout: Image? { cutoutCache.image(for: lock.withLock { $0.cutout }?.cgImage) }

    /// Whether person segmentation can run on this Mac. Some Macs lack the
    /// compute device (Neural Engine) the model needs; when so, this is `false`
    /// and `unavailableReason` says why instead of just reporting an empty matte.
    public var isAvailable: Bool { status.isAvailable }
    /// Why person segmentation can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Segment people in `source`'s frames — the live camera, or a playing video.
    @MainActor
    public init(_ source: any FrameSource, quality: Quality = .balanced) {
        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = quality.visionLevel
        self.request = request
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Segment people in a still image, once. The matte comes back even with no
    /// one in the picture (it's simply transparent everywhere); `nil` only if the
    /// matte couldn't be converted. The default quality here is `.accurate` —
    /// a still pays for the best matte, where the live path defaults to `.balanced`.
    public static func detect(in image: Image, quality: Quality = .accurate) async throws -> Segmentation? {
        let request = GeneratePersonSegmentationRequest()
        request.qualityLevel = quality.visionLevel
        let source = image.currentCGImage()
        let observation = try await request.perform(on: source)
        return try segmentation(from: observation, source: source)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        // Once the model is known unavailable on this Mac, stop calling perform —
        // it won't recover this session, and re-trying every frame just wastes
        // work and lets Vision log its own error per frame.
        guard status.isAvailable else { return }
        do {
            let observation = try await request.perform(on: cgImage)
            status.recordSuccess()
            guard let result = try? PersonSegmenter.images(from: observation, source: cgImage) else {
                return
            }
            lock.withLock {
                $0 = Results(matte: FrameBox(result.matte), cutout: FrameBox(result.cutout))
            }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Decoding

    private static func images(from observation: PixelBufferObservation,
                               source: CGImage) throws -> (matte: CGImage, cutout: CGImage)? {
        let matteGray = try observation.cgImage
        guard let matte = SegmentationImages.matteCGImage(from: matteGray),
              let cutout = SegmentationImages.cutoutCGImage(frame: source, matte: matteGray) else {
            return nil
        }
        return (matte, cutout)
    }

    private static func segmentation(from observation: PixelBufferObservation,
                                     source: CGImage) throws -> Segmentation? {
        guard let images = try images(from: observation, source: source) else { return nil }
        return Segmentation(matte: Image(cgImage: images.matte),
                            cutout: Image(cgImage: images.cutout))
    }
}
