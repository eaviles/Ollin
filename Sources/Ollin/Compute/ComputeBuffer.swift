import Foundation
import Metal
import simd
import COllinShaders

/// A GPU buffer a compute dispatch can bind, whatever its element type: the
/// type-erased face of `ComputeBuffer<Element>`, so one `compute(_:buffers:)` call
/// can hand a kernel a segment list, a lookup table, and a particle buffer at once.
/// Only `ComputeBuffer` conforms; the renderer realizes the Metal buffer through an
/// internal seam, so a conformance of your own would bind nothing.
public protocol ComputeBindable: AnyObject {
    /// The buffer's element count (the natural 1-D dispatch width).
    var count: Int { get }
}

/// The renderer's half of `ComputeBindable`: realize (and cache) the Metal buffer
/// on `device`, uploading the seed once. Called on the main actor while encoding a
/// frame. Internal, so the public protocol carries no Metal type.
protocol ComputeRealizable: ComputeBindable {
    func metalBuffer(for device: MTLDevice) -> MTLBuffer?
}

extension ComputeBindable {
    /// The Metal buffer behind a bindable, or `nil` for a type the renderer does
    /// not know how to realize.
    func realizedBuffer(for device: MTLDevice) -> MTLBuffer? {
        (self as? ComputeRealizable)?.metalBuffer(for: device)
    }
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
public final class ComputeBuffer<Element>: ComputeRealizable, @unchecked Sendable {
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

    /// Snapshot the buffer's current contents back to the CPU. Only valid once the GPU
    /// work that wrote it has completed, so it's `@MainActor`: read it on the frame loop
    /// after the render, mainly for tests and debugging (a per-frame sim never needs
    /// it).
    ///
    /// Before the buffer has ever been bound this hands back what it was seeded with,
    /// which is what it holds: a sketch that reads a sim's state in `setup()` should see
    /// the state it just built, not a buffer of zeros. `nil` only for a buffer that was
    /// never seeded and never bound, which has no contents to report yet.
    @MainActor public func snapshot() -> [Element]? {
        guard let buffer else { return seed }
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

    /// Allocate both buffers at `contents.count`, seeding the initial `read` buffer
    /// with `contents` (the `write` buffer starts zeroed; the first step overwrites
    /// it). The CPU-authored start a stateful sim needs when a zeroed buffer isn't
    /// its "empty" state.
    public init(_ contents: [Element]) {
        precondition(!contents.isEmpty, "PingPong needs at least one element")
        a = ComputeBuffer(contents)
        b = ComputeBuffer(count: contents.count)
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
///
/// `append(camera:aspect:)` packs a `Camera3D` as an `OllinCameraMatrices` (its
/// view and projection, 128 bytes), so a kernel can project world points through
/// the sketch's own camera with the library's `ollin_project`; a `Sketch` builds
/// one for its active camera with `cameraParams()`.
public struct ComputeParams: Sendable {
    public private(set) var bytes: [UInt8] = []
    public init() {}

    public mutating func append(_ value: Float)        { appendBytes(of: value) }
    public mutating func append(_ value: SIMD2<Float>) { appendBytes(of: value) }
    public mutating func append(_ value: SIMD4<Float>) { appendBytes(of: value) }
    public mutating func append(_ value: Int32)        { appendBytes(of: value) }
    public mutating func append(_ value: UInt32)       { appendBytes(of: value) }
    /// A column-major 4x4 matrix (64 bytes, 16-aligned): a kernel reads it as a
    /// `float4x4`.
    public mutating func append(_ value: simd_float4x4) { appendBytes(of: value) }

    /// A camera's view and projection matrices, as the `OllinCameraMatrices` the
    /// library's `ollin_project(camera, world, u.resolution)` takes. `aspect` is the
    /// canvas width over its height (the projection depends on it), which is what
    /// `Sketch.cameraParams()` fills in for you. Append it first and start your
    /// kernel's `constant` struct with an `OllinCameraMatrices` field, or bind the
    /// struct alone as `constant OllinCameraMatrices &camera [[buffer(11)]]`.
    public mutating func append(camera: Camera3D, aspect: Double) {
        appendBytes(of: camera.matrices(aspect: aspect))
    }

    /// Whether anything has been packed (the renderer binds index 11 only if not).
    public var isEmpty: Bool { bytes.isEmpty }

    private mutating func appendBytes<T>(of value: T) {
        withUnsafeBytes(of: value) { bytes.append(contentsOf: $0) }
    }
}

/// One recorded compute dispatch, drained by the renderer into a compute encoder
/// ahead of the frame's render pass (so a step and the draw that consumes it stay
/// ordered within one command buffer). Pure data; references the bound buffers
/// and/or textures and the packed params bytes (bound at index 11 when non-empty).
/// The standard `OllinComputeUniforms` (index 10) are filled by the renderer.
///
/// The grid is up to 2-D: a buffer dispatch is `gridWidth × 1` (one thread per
/// element), a texture dispatch is `gridWidth × gridHeight` (one thread per texel).
struct RecordedDispatch {
    let kernel: ComputeKernel
    let gridWidth: Int
    let gridHeight: Int
    let buffers: [ComputeBindable?]          // bound at buffer indices 0… (10/11 reserved)
    let textures: [ComputeTextureBindable?]  // bound at texture indices 0…
    let params: [UInt8]                      // buffer index 11 (empty = not bound)

    /// Total thread count, also the `OllinComputeUniforms.particleCount` value.
    var threadCount: Int { gridWidth * gridHeight }

    /// A 1-D buffer dispatch (`threadCount × 1`). Keeps the buffer call sites
    /// unchanged as the struct grew the texture/2-D fields.
    init(kernel: ComputeKernel, threadCount: Int, buffers: [ComputeBindable?], params: [UInt8]) {
        self.kernel = kernel
        self.gridWidth = threadCount
        self.gridHeight = 1
        self.buffers = buffers
        self.textures = []
        self.params = params
    }

    /// A 2-D texture dispatch (`gridWidth × gridHeight`, one thread per texel).
    init(kernel: ComputeKernel, gridWidth: Int, gridHeight: Int,
         textures: [ComputeTextureBindable?], buffers: [ComputeBindable?] = [], params: [UInt8]) {
        self.kernel = kernel
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.buffers = buffers
        self.textures = textures
        self.params = params
    }
}
