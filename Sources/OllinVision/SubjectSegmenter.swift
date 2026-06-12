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

    /// Published results plus which of the two image surfaces a sketch actually
    /// reads. Each conversion runs on the analyzer thread only once its surface
    /// has been read at least once (the first read arms it), so a sketch reading
    /// only the matte never pays for the cutout. The images are built fresh per
    /// analyzed frame and handed over whole — the `Segmentation` hand-off
    /// justification.
    private struct State {
        var matte: Image?
        var cutout: Image?
        var count = 0
        var wantsMatte = false
        var wantsCutout = false
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status = VisionStatus("subject segmentation")

    /// The combined matte of every subject in the most recent analyzed frame —
    /// white, alpha = per-pixel confidence — or `nil` while nothing is lifted
    /// (no subject in view, or no frame analyzed yet). The first read arms the
    /// conversion, so it can stay `nil` until the next analyzed frame publishes.
    public var matte: Image? {
        lock.withLockUnchecked { state in
            state.wantsMatte = true
            return state.matte
        }
    }

    /// The frame's pixels where the subjects are, transparent elsewhere — or
    /// `nil` while nothing is lifted. The first read arms the conversion, so it
    /// can stay `nil` until the next analyzed frame publishes.
    public var cutout: Image? {
        lock.withLockUnchecked { state in
            state.wantsCutout = true
            return state.cutout
        }
    }

    /// How many distinct subjects the most recent analyzed frame held (`0` when
    /// nothing is lifted).
    public var count: Int { lock.withLockUnchecked { $0.count } }

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
              let matteGray = try matteGray(from: observation),
              let matte = SegmentationImages.matteImage(from: matteGray),
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
        let request = GenerateForegroundInstanceMaskRequest()
        do {
            let observation = try await request.perform(on: cgImage)
            status.recordSuccess()
            guard let observation else {
                // No subject in view — clear, so a lifted subject leaving the
                // frame doesn't linger.
                lock.withLockUnchecked { $0 = State(wantsMatte: $0.wantsMatte,
                                                    wantsCutout: $0.wantsCutout) }
                return
            }
            // Convert only the surfaces some read has armed; `count` comes free
            // from the observation either way.
            let (wantsMatte, wantsCutout) = lock.withLockUnchecked { ($0.wantsMatte, $0.wantsCutout) }
            var matte: Image?
            var cutout: Image?
            if wantsMatte || wantsCutout, let matteGray = try? Self.matteGray(from: observation) {
                if wantsMatte { matte = SegmentationImages.matteImage(from: matteGray) }
                if wantsCutout { cutout = SegmentationImages.cutoutImage(frame: cgImage, matte: matteGray) }
            }
            lock.withLockUnchecked { state in
                state.count = observation.allInstances.count
                // Assign under the arming flag even when conversion came up nil:
                // a lift the model lost must clear, not linger.
                if wantsMatte { state.matte = matte }
                if wantsCutout { state.cutout = cutout }
            }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Decoding

    /// The soft combined mask as a grayscale `CGImage`. `allInstancesMask` holds
    /// instance *labels* (0 background, 1, 2, …), not a soft matte — read as gray
    /// it's all but black. The soft mask comes from `generateMask`, which feeds
    /// the same conversions as the person one.
    private static func matteGray(from observation: InstanceMaskObservation) throws -> CGImage? {
        let mask = try observation.generateMask(for: observation.allInstances)
        return SegmentationImages.grayCGImage(from: mask)
    }
}
