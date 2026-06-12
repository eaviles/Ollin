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

    /// Published results plus which of the two surfaces a sketch actually reads.
    /// Each conversion runs on the analyzer thread only once its surface has been
    /// read at least once (the first read arms it), so a sketch reading only the
    /// matte never pays for the cutout. The images are built fresh per analyzed
    /// frame and handed over whole — the `Segmentation` hand-off justification.
    private struct State {
        var matte: Image?
        var cutout: Image?
        var wantsMatte = false
        var wantsCutout = false
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status = VisionStatus("person segmentation")
    /// One request reused across frames — it's a stateful (video-aware) request,
    /// and the analyzer runs one analysis at a time, so reuse is serial.
    private let request: GeneratePersonSegmentationRequest

    /// The people matte from the most recent analyzed frame — white, alpha =
    /// per-pixel confidence — or `nil` before the first result. Empty (fully
    /// transparent) when no one is in view. The first read arms the conversion,
    /// so it can stay `nil` until the next analyzed frame publishes.
    public var matte: Image? {
        lock.withLockUnchecked { state in
            state.wantsMatte = true
            return state.matte
        }
    }

    /// The frame's pixels where people are, transparent elsewhere, from the most
    /// recent analyzed frame — or `nil` before the first result. The first read
    /// arms the conversion, so it can stay `nil` until the next analyzed frame
    /// publishes.
    public var cutout: Image? {
        lock.withLockUnchecked { state in
            state.wantsCutout = true
            return state.cutout
        }
    }

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
        let matteGray = try observation.cgImage
        guard let matte = SegmentationImages.matteImage(from: matteGray),
              let cutout = SegmentationImages.cutoutImage(frame: source, matte: matteGray) else {
            return nil
        }
        return Segmentation(matte: matte, cutout: cutout)
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
            // Convert only the surfaces some read has armed; nothing read yet
            // means no byte work at all.
            let (wantsMatte, wantsCutout) = lock.withLockUnchecked { ($0.wantsMatte, $0.wantsCutout) }
            guard wantsMatte || wantsCutout, let matteGray = try? observation.cgImage else { return }
            let matte = wantsMatte ? SegmentationImages.matteImage(from: matteGray) : nil
            let cutout = wantsCutout ? SegmentationImages.cutoutImage(frame: cgImage, matte: matteGray) : nil
            lock.withLockUnchecked { state in
                if let matte { state.matte = matte }
                if let cutout { state.cutout = cutout }
            }
        } catch {
            status.recordFailure(error)
        }
    }
}
