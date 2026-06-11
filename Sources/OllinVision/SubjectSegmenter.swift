import Ollin
import Vision
import CoreGraphics
import Foundation
import os

/// Lifts the salient subject(s) out of a camera's frames (or a still image) —
/// the thing held up to the camera, the object on the table — as a soft matte
/// and the cutout it makes. Where `PersonSegmenter` knows specifically about
/// people, this is the general "subject lift": it finds whatever stands out as
/// foreground, people included.
///
/// ```swift
/// let camera = Camera()
/// lazy var subjects = SubjectSegmenter(camera)
/// override func draw() {
///     let rect = camera.fittedRect(in: bounds) ?? bounds
///     if let frame = camera.frame { tint(Color(white: 0.25)); drawImage(frame, in: rect); noTint() }
///     if let cutout = subjects.cutout { drawImage(cutout, in: rect) }
/// }
/// ```
///
/// `matte` is the white-alpha silhouette of all subjects combined, `cutout` the
/// frame's own pixels — see `Segmentation` for both; `count` is how many distinct
/// subjects the model found. Draw either image into the same rectangle as the
/// frame and they line up with the picture. It's a neural model, so it needs a
/// capable compute device (Apple silicon); on a Mac without one `isAvailable`
/// turns `false` and `unavailableReason` says why.
public final class SubjectSegmenter: VisionTracking, @unchecked Sendable {

    private struct Results {
        var matte: FrameBox?
        var cutout: FrameBox?
        var count = 0
    }
    private let lock = OSAllocatedUnfairLock<Results>(initialState: Results())
    private let status = VisionStatus("subject segmentation")
    private let matteCache = ImageWrapCache()
    private let cutoutCache = ImageWrapCache()

    /// The combined matte of every subject in the most recent analyzed frame —
    /// white, alpha = per-pixel confidence — or `nil` while nothing is lifted
    /// (no subject in view, or no frame analyzed yet).
    public var matte: Image? { matteCache.image(for: lock.withLock { $0.matte }?.cgImage) }

    /// The frame's pixels where the subjects are, transparent elsewhere — or
    /// `nil` while nothing is lifted.
    public var cutout: Image? { cutoutCache.image(for: lock.withLock { $0.cutout }?.cgImage) }

    /// How many distinct subjects the most recent analyzed frame held (`0` when
    /// nothing is lifted).
    public var count: Int { lock.withLock { $0.count } }

    /// Whether subject lifting can run on this Mac. Some Macs lack the compute
    /// device (Neural Engine) the model needs; when so, this is `false` and
    /// `unavailableReason` says why instead of just reporting no subjects.
    public var isAvailable: Bool { status.isAvailable }
    /// Why subject lifting can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Lift subjects out of `source`'s frames — the live camera, or a playing video.
    @MainActor
    public init(_ source: any FrameSource) {
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Lift the subject(s) out of a still image, once. `nil` when the model finds
    /// no subject to lift.
    public static func detect(in image: Image) async throws -> Segmentation? {
        let request = GenerateForegroundInstanceMaskRequest()
        let source = image.currentCGImage()
        guard let observation = try await request.perform(on: source),
              let images = try images(from: observation, source: source) else { return nil }
        return Segmentation(matte: Image(cgImage: images.matte),
                            cutout: Image(cgImage: images.cutout))
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        // Once the model is known unavailable on this Mac, stop calling perform —
        // it won't recover this session, and re-trying every frame just wastes
        // work and lets Vision log its own error per frame.
        guard status.isAvailable else { return }
        let request = GenerateForegroundInstanceMaskRequest()
        do {
            let observation = try await request.perform(on: cgImage)
            status.recordSuccess()
            guard let observation,
                  let images = try? SubjectSegmenter.images(from: observation, source: cgImage) else {
                // No subject in view — clear, so a lifted subject leaving the
                // frame doesn't linger.
                lock.withLock { $0 = Results() }
                return
            }
            lock.withLock {
                $0 = Results(matte: FrameBox(images.matte),
                             cutout: FrameBox(images.cutout),
                             count: observation.allInstances.count)
            }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Decoding

    private static func images(from observation: InstanceMaskObservation,
                               source: CGImage) throws -> (matte: CGImage, cutout: CGImage)? {
        // `allInstancesMask` holds instance *labels* (0 background, 1, 2, …), not
        // a soft matte — read as gray it's all but black. The soft mask comes
        // from `generateMask`, which feeds the same conversions as the person one.
        let mask = try observation.generateMask(for: observation.allInstances)
        guard let matteGray = SegmentationImages.grayCGImage(from: mask),
              let matte = SegmentationImages.matteCGImage(from: matteGray),
              let cutout = SegmentationImages.cutoutCGImage(frame: source, matte: matteGray) else {
            return nil
        }
        return (matte, cutout)
    }
}
