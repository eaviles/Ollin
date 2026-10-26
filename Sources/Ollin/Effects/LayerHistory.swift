import Foundation

/// A ring of a layer's past frames, kept on the GPU, for a slit scan of a
/// sketch's own drawing. Make one in `setup()` and hold it, as a `Feedback`
/// layer is held: its identity is what ties one frame's picture to the next.
/// Each frame a `Filter.slitScan(_:delay:)` over a layer appends that layer to
/// the ring and composes its output from the frames held, every pixel read
/// from the frame its delay names.
///
/// ```swift
/// var history: LayerHistory!
/// override func setup() { history = makeLayerHistory(capacity: 90) }
///
/// override func draw() {
///     let scene = makeRenderTarget()
///     withTarget(scene) { drawMovingShapes() }
///     drawImage(scene.filtered(.slitScan(history, delay: .across)).image, 0, 0)
/// }
/// ```
///
/// The ring takes the size and precision of the first layer filtered through
/// it; a layer of another size starts it over. It holds `capacity` frames of
/// `width x height x 8` bytes each at half precision, so a full 1080-pixel
/// canvas at 90 frames is about 840 MB; filter a layer made at a lower `scale`
/// for a longer reach. Where the picture is painted on the CPU, `SlitScan`
/// holds the same history as CPU pixels.
public final class LayerHistory: @unchecked Sendable {

    /// How many frames the ring holds once full.
    public let capacity: Int

    init(capacity: Int) {
        self.capacity = min(max(capacity, 1), 2048)
    }
}

/// How far into the past each pixel of a `Filter.slitScan` reads: 0 is the
/// newest frame held, 1 the oldest.
public enum SlitScanDelay: @unchecked Sendable {
    /// Left to right: the left edge is now, the right edge the oldest frame.
    case across
    /// Top to bottom: the top edge is now, the bottom the oldest frame.
    case down
    /// From the center outward: the middle is now, the corners the oldest frame.
    case radial
    /// By a picture's brightness: black reads now, white the oldest frame, and a
    /// gray a frame between. Any image serves, a file, a painted `Image`, a
    /// layer's `image`, or a generator's output, sampled across the layer.
    case map(Image)

    /// The shader's mode index.
    var rawIndex: Float {
        switch self {
        case .across: return 0
        case .down: return 1
        case .radial: return 2
        case .map: return 3
        }
    }
}

public extension Filter {

    /// A slit scan of the layer over its own past, on the GPU. The layer is
    /// appended to `history` (once a frame, however many scans read it), and
    /// every pixel of the result is read from the frame `delay` names there:
    /// 0 the newest frame, 1 the oldest held, a value between them the frame
    /// between, each pixel rounded to the nearest frame as `SlitScan` rounds.
    /// A left-to-right delay is the classic scan, a radial delay ripples time
    /// outward, and a `.map` makes any picture the lens.
    ///
    /// ```swift
    /// var history: LayerHistory!
    /// override func setup() { history = makeLayerHistory(capacity: 90) }
    ///
    /// override func draw() {
    ///     let scene = makeRenderTarget()
    ///     withTarget(scene) { drawMovingShapes() }
    ///     drawImage(scene.filtered(.slitScan(history, delay: .across)).image, 0, 0)
    /// }
    /// ```
    ///
    /// The result matches `SlitScan` fed the same frames to within a level:
    /// that one holds CPU pixels, this one keeps the picture on the GPU, which
    /// is what a large canvas wants. A web page export stops at it and names
    /// the call.
    static func slitScan(_ history: LayerHistory, delay: SlitScanDelay = .across) -> Filter {
        Filter(kind: .slitScan(history: history, delay: delay))
    }
}
