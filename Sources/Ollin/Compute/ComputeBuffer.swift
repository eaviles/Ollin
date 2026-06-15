import Foundation
import Metal

/// Type-erased view of a GPU buffer the renderer can realize, used so the drawer's
/// recorded dispatches and particle batches can hold buffers of any element type.
protocol ComputeBindable: AnyObject {
    /// The buffer's element count (the natural 1-D dispatch width).
    var count: Int { get }
    /// Realize (and cache) the Metal buffer on `device`, uploading the seed once.
    /// Renderer-only — called on the main actor while encoding a frame.
    func metalBuffer(for device: MTLDevice) -> MTLBuffer?
}

/// A persistent, typed GPU buffer — the storage a compute kernel reads and writes
/// each frame without the data ever round-tripping through the CPU.
///
/// Like `Image`'s texture, the Metal buffer is created lazily (and the optional
/// seed uploaded) the first time the renderer binds it, so a `ComputeBuffer` is
/// constructible in a sketch with no device. It's a `final class` because identity
/// matters: a kernel and the render path hold and mutate *the same* buffer by
/// reference across frames; copying it would fork the GPU state.
///
/// Fresh buffers start zeroed, so a particle whose `life` begins at 0 is "dead" and
/// a kernel can spawn it on the first frame. Seed explicitly with `init(_:)` when
/// you want CPU-authored initial contents.
///
/// Marked `@unchecked Sendable`: it carries an `MTLBuffer` (not `Sendable`) but is
/// only ever realized/read on the main actor, the same boundary `Image` crosses.
public final class ComputeBuffer<Element>: ComputeBindable, @unchecked Sendable {
    /// Number of `Element`s the buffer holds.
    public let count: Int
    private var buffer: MTLBuffer?
    private var seed: [Element]?

    /// An uninitialized buffer of `count` elements. Its bytes start at zero, so a
    /// kernel can treat a zeroed element as "needs spawning".
    public init(count: Int) {
        precondition(count > 0, "ComputeBuffer needs a positive count")
        self.count = count
    }

    /// A buffer seeded with `contents`, uploaded once when first bound.
    public init(_ contents: [Element]) {
        precondition(!contents.isEmpty, "ComputeBuffer needs at least one element")
        self.count = contents.count
        self.seed = contents
    }

    func metalBuffer(for device: MTLDevice) -> MTLBuffer? {
        if let buffer { return buffer }
        let length = count * MemoryLayout<Element>.stride
        guard let b = device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
        if let seed {
            seed.withUnsafeBytes { b.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            self.seed = nil          // uploaded; the GPU owns the contents from here
        } else {
            memset(b.contents(), 0, length)   // deterministic zero start
        }
        buffer = b
        return b
    }

    /// Snapshot the buffer's current contents back to the CPU. Only valid once the
    /// buffer has been realized and the GPU work that wrote it has completed —
    /// mainly for tests and debugging; a per-frame sim never needs it. `nil` before
    /// the buffer is first bound.
    public func snapshot() -> [Element]? {
        guard let buffer else { return nil }
        let ptr = buffer.contents().bindMemory(to: Element.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
}

/// A pair of `ComputeBuffer`s swapped each step: the kernel reads `read` (last
/// frame's state) and writes `write` (this frame's), then `advance()` makes the
/// freshly written buffer the new `read`. Two buffers (not one read-modify-write)
/// so a step's reads can't see its own partial writes and so consecutive frames
/// render different buffers — letting the GPU overlap one frame's render with the
/// next frame's compute. `Particles` owns one of these; reach for it directly when
/// you drive the raw `compute(_:reading:writing:)` form yourself.
public final class PingPong<Element>: @unchecked Sendable {
    private let a: ComputeBuffer<Element>
    private let b: ComputeBuffer<Element>
    private var flipped = false

    /// Allocate both buffers at `count` elements (both start zeroed).
    public init(count: Int) {
        a = ComputeBuffer(count: count)
        b = ComputeBuffer(count: count)
    }

    /// The buffer holding the current state (read this to draw).
    public var read: ComputeBuffer<Element> { flipped ? b : a }
    /// The buffer the next step writes into.
    public var write: ComputeBuffer<Element> { flipped ? a : b }
    /// Swap which buffer is current — call once after recording a step.
    public func advance() { flipped.toggle() }
}

/// An ordered byte-packer for a kernel's custom parameters, bound at buffer index
/// 11. Append values in the order your MSL `constant` struct declares them and mind
/// 16-byte alignment for `float4`/`float2` runs, the usual rules for a Metal
/// constant buffer. For just a few live floats, the `Particles` `custom:` 4-float
/// bag (also index 11) is simpler.
public struct ComputeParams: Sendable {
    public private(set) var bytes: [UInt8] = []
    public init() {}

    public mutating func append(_ value: Float)        { appendBytes(of: value) }
    public mutating func append(_ value: SIMD2<Float>) { appendBytes(of: value) }
    public mutating func append(_ value: SIMD4<Float>) { appendBytes(of: value) }
    public mutating func append(_ value: Int32)        { appendBytes(of: value) }
    public mutating func append(_ value: UInt32)       { appendBytes(of: value) }

    /// Whether anything has been packed (the renderer binds index 11 only if not).
    public var isEmpty: Bool { bytes.isEmpty }

    private mutating func appendBytes<T>(of value: T) {
        withUnsafeBytes(of: value) { bytes.append(contentsOf: $0) }
    }
}

/// One recorded compute dispatch, drained by the renderer into a compute encoder
/// ahead of the frame's render pass (so a step and the draw that consumes it stay
/// ordered within one command buffer). Pure data; references the bound buffers and
/// the packed params bytes (bound at index 11 when non-empty). The standard
/// `OllinComputeUniforms` (index 10) are filled by the renderer.
struct RecordedDispatch {
    let kernel: ComputeKernel
    let threadCount: Int
    let buffers: [ComputeBindable?]   // bound at indices 0… (10/11 are reserved)
    let params: [UInt8]               // index 11 (empty = not bound)
}
