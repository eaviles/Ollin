import Foundation
import Metal

/// A layer that keeps a running **mean** of what is drawn into it, frame after
/// frame: the substrate of progressive light accumulation, where every frame
/// scatters another pass of faint samples and the picture is the average of all
/// of them so far. The renderer keeps the sum in single-precision float and the
/// number of passes beside it, and `image` hands back the mean, so the picture
/// *converges* as passes pile up rather than brightening without end. That is the
/// difference between this and a `noClear()` canvas, which only ever adds.
///
/// ```swift
/// var light: Accumulator!
/// override func setup() { light = makeAccumulator() }   // make once, store it
///
/// override func draw() {
///     background(.black)
///     withAccumulator(light) {                           // one pass of samples
///         blendMode(.add)
///         drawParticles(spray, style: .light)
///     }
///     drawImage(light.developed(exposure: 40).image, 0, 0)   // the mean, printed
/// }
/// ```
///
/// A pass is one visit to the block; a block that draws several passes' worth
/// of samples says so with `withAccumulator(_:passes:_:)`, and the mean divides
/// by the passes counted. `reset()` starts the average over, which is what a
/// moved camera or a turned lens wants (`LineSpray` does it for you).
///
/// Like `Feedback`, it's **persistent**: create it once in `setup()` and hold it.
/// Its identity is what ties one frame's sum to the next; make a fresh one each
/// `draw()` and it never converges. A reference type for the same reason
/// `RenderTarget` is: it names GPU resources the renderer fills.
public final class Accumulator {

    /// The layer's logical size in canvas points: the size `image` draws at and
    /// the coordinate space a `withAccumulator` block uses.
    public let width: Int
    public let height: Int

    /// Internal resolution as a fraction of the logical size (1 = full), like
    /// `RenderTarget.scale`. Clamped to a sane range.
    public let scale: Double

    /// How many passes the running sum holds so far: what `image` divides by. It
    /// counts at record time, so a sketch can read it in the same `draw()` that
    /// added a pass. Zero after `reset()` and before the first block.
    public private(set) var passes: Int = 0

    /// The drawer that owns the recording. Weak: the drawer outlives per-frame
    /// work; the sketch owns the `Accumulator`.
    weak var drawer: Drawer?

    /// This frame's write surface: the block's geometry lands here (a transient
    /// layer the renderer clears every frame), and the renderer then adds it into
    /// the persistent sum. Tagged `.accumulate(self)` so the renderer routes it.
    let writeLayer: RenderTarget

    /// A read-only texture carrier the renderer points at the mean each frame,
    /// so `image` resolves to it. Not drawn into; reused so `image` is a steady
    /// handle.
    let meanLayer: RenderTarget

    /// The same carrier for the raw sum, for a sketch that would rather divide
    /// in its own shader.
    let sumLayer: RenderTarget

    /// Set by `reset()`, consumed by the renderer at the next encode: the sum is
    /// zeroed before this frame's pass is added.
    var needsClear = true

    /// The passes the most recent block asked to add, read by the renderer when
    /// it divides. Kept beside `passes` so a second encode of one frame (a frame
    /// grab) divides by the same count.
    var passesAtRecord: Int = 0

    /// Pixel dimensions of the backing textures (logical size × `scale`, ≥ 1).
    var pixelWidth: Int { max(1, Int((Double(width) * scale).rounded())) }
    var pixelHeight: Int { max(1, Int((Double(height) * scale).rounded())) }

    init(width: Int, height: Int, scale: Double, drawer: Drawer?) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.scale = min(4, max(0.05, scale))
        self.drawer = drawer
        self.writeLayer = RenderTarget(width: self.width, height: self.height,
                                       scale: self.scale, drawer: drawer)
        self.meanLayer = RenderTarget(width: self.width, height: self.height,
                                      scale: self.scale, drawer: drawer)
        self.sumLayer = RenderTarget(width: self.width, height: self.height,
                                     scale: self.scale, drawer: drawer, precision: .float32)
        self.writeLayer.origin = .accumulate(self)
    }

    /// The running mean, as a drawable `Image`: the sum so far over the passes
    /// so far, linear light. Composite it with `drawImage`, or print it with
    /// `developed(exposure:ground:)`. Resolves the renderer's mean texture lazily
    /// at draw time.
    public var image: Image { meanLayer.image }

    /// The raw running sum (single-precision float), for a sketch that divides
    /// by `passes` in a shader of its own.
    public var sum: Image { sumLayer.image }

    /// The mean through a `Filter`, returning a new layer to composite: the
    /// same effects substrate every layer uses. The running state stays untouched.
    public func filtered(_ filter: Filter) -> RenderTarget { meanLayer.filtered(filter) }

    /// The mean printed as a picture: scaled by `exposure`, rolled off by the
    /// Reinhard curve, and laid on `ground`, which is added after the curve as a
    /// display color (see `Filter.develop(exposure:ground:)`). Composite the
    /// result with `drawImage(light.developed(exposure: 40).image, 0, 0)`.
    public func developed(exposure: Double, ground: Color = .black) -> RenderTarget {
        meanLayer.filtered(.develop(exposure: exposure, ground: ground))
    }

    /// Start the average over: the next pass begins a fresh sum, and `passes`
    /// returns to zero. Call it when the scene, the camera, or the lens moved,
    /// since the samples drawn before no longer describe the picture.
    public func reset() {
        needsClear = true
        passes = 0
    }

    /// Record one visit to the block: `count` passes join the sum. Called by the
    /// drawer as the block opens, so `passes` reads right inside it.
    func notePasses(_ count: Int) {
        passes += max(0, count)
        passesAtRecord = passes
    }
}
