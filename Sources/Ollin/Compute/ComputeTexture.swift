import Foundation
import Metal

/// The pixel layout of a `ComputeTexture`. Keeps Metal's pixel-format enum off the
/// public surface and names the choices a sketch actually wants: float formats for
/// simulation state (precision the value evolves through), 8-bit for image kernels.
public enum ComputeTextureFormat: Sendable {
    /// Four 16-bit floats — the default. Float precision a reaction-diffusion or
    /// fluid field needs to evolve smoothly, and the format the renderer composites
    /// in, so a drawn texture lands without a conversion.
    case rgba16Float
    /// Four 32-bit floats — full precision where 16-bit half drifts (long-running
    /// accumulations, sensitive feedback).
    case rgba32Float
    /// Four 8-bit unsigned-normalized channels — for image kernels whose output is
    /// an ordinary 0…1 color (no headroom needed). Not snapshot-readable as floats.
    case rgba8Unorm
    /// One 16-bit float — a single-channel field (a height map, a density).
    case r16Float
    /// One 32-bit float — a single-channel field at full precision.
    case r32Float

    var metalPixelFormat: MTLPixelFormat {
        switch self {
        case .rgba16Float: return .rgba16Float
        case .rgba32Float: return .rgba32Float
        case .rgba8Unorm:  return .rgba8Unorm
        case .r16Float:    return .r16Float
        case .r32Float:    return .r32Float
        }
    }

    /// Number of channels per texel (for `snapshot()` interpretation).
    var channels: Int {
        switch self {
        case .rgba16Float, .rgba32Float, .rgba8Unorm: return 4
        case .r16Float, .r32Float: return 1
        }
    }

    /// Bytes per texel.
    var bytesPerPixel: Int {
        switch self {
        case .rgba16Float: return 8
        case .rgba32Float: return 16
        case .rgba8Unorm:  return 4
        case .r16Float:    return 2
        case .r32Float:    return 4
        }
    }
}

/// Type-erased view of a GPU texture the renderer can realize, so a recorded
/// dispatch can bind textures of any format and the `Image` seam can wrap one
/// without depending on the concrete type.
protocol ComputeTextureBindable: AnyObject {
    var width: Int { get }
    var height: Int { get }
    /// Realize (and cache) the Metal texture on `device`. Renderer-only — called on
    /// the main actor while encoding a frame.
    func metalTexture(for device: MTLDevice) -> MTLTexture?
}

/// A persistent, GPU-resident 2-D texture a compute kernel reads and writes each
/// frame — the texture-half companion to `ComputeBuffer`. It's the storage behind
/// ping-pong simulations (reaction-diffusion, cellular automata, fluid) and image
/// kernels, and it draws like any other image: `texture.image` wraps it for
/// `drawImage`, so the result composites in draw order and rides the transform
/// stack with no CPU round-trip.
///
/// Like `Image`'s texture and `ComputeBuffer`'s buffer, the Metal texture is created
/// lazily the first time the renderer binds it, so a `ComputeTexture` is
/// constructible in a sketch with no device. Fresh textures start **zeroed**, the
/// same deterministic blank state a fresh `ComputeBuffer` starts in — seed a sim's
/// initial state with a one-shot `compute(_:writing:)` on the first frame.
///
/// It's a `final class` because identity matters: a kernel and the render path hold
/// and mutate *the same* texture by reference across frames. Storage is `.shared`
/// (unified memory on Apple silicon — free for the GPU, and directly readable by
/// `snapshot()`), with `.shaderRead` + `.shaderWrite` usage so a kernel can both
/// sample and write it and the render path can sample it.
///
/// Marked `@unchecked Sendable`: it carries an `MTLTexture` (not `Sendable`) but is
/// only ever realized/read on the main actor, the same boundary `Image` crosses.
public final class ComputeTexture: ComputeTextureBindable, @unchecked Sendable {
    /// Pixel width.
    public let width: Int
    /// Pixel height.
    public let height: Int
    /// The texel layout.
    public let format: ComputeTextureFormat
    private var texture: MTLTexture?

    /// A `width`×`height` texture in `format` (default `.rgba16Float`). Its texels
    /// start at zero; seed any initial state with a kernel on the first frame.
    /// Dimensions are clamped to at least `1×1`.
    public init(width: Int, height: Int, format: ComputeTextureFormat = .rgba16Float) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.format = format
    }

    func metalTexture(for device: MTLDevice) -> MTLTexture? {
        if let texture { return texture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format.metalPixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let t = device.makeTexture(descriptor: descriptor) else { return nil }
        // makeTexture leaves contents undefined; zero them so a fresh texture is a
        // deterministic blank (matching ComputeBuffer's zeroed start), and a kernel
        // that reads a not-yet-seeded cell sees 0 rather than garbage.
        let bytesPerRow = width * format.bytesPerPixel
        let zeros = [UInt8](repeating: 0, count: bytesPerRow * height)
        zeros.withUnsafeBytes {
            t.replace(region: MTLRegionMake2D(0, 0, width, height),
                      mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: bytesPerRow)
        }
        texture = t
        return t
    }

    /// Wrap this texture as an `Image` for `drawImage` — the current GPU contents,
    /// resolved at draw time (so it always reflects the latest kernel write). The
    /// texels are treated as **linear** color by the render pipeline; author sRGB
    /// tones through `srgbToLinear` in the kernel (the prelude provides it), and keep
    /// the alpha channel at 1 for opaque, predictable compositing.
    public var image: Image { Image(computeTexture: self) }

    /// Read the texture's current contents back to the CPU as interleaved floats
    /// (row-major, `width * height * channels` long) — only valid once the texture
    /// has been realized and the GPU work that wrote it has completed. For the float
    /// formats only (returns `nil` for `.rgba8Unorm`, and `nil` before the texture is
    /// first bound). Mainly for tests and debugging; a per-frame sim never needs it.
    public func snapshot() -> [Float]? {
        guard let texture else { return nil }
        let bytesPerRow = width * format.bytesPerPixel
        var raw = [UInt8](repeating: 0, count: bytesPerRow * height)
        raw.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        let count = width * height * format.channels
        switch format {
        case .rgba32Float, .r32Float:
            return raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        case .rgba16Float, .r16Float:
            return raw.withUnsafeBytes { ptr in
                let halves = ptr.bindMemory(to: UInt16.self)
                return (0..<count).map { Float(Float16(bitPattern: halves[$0])) }
            }
        case .rgba8Unorm:
            return nil
        }
    }
}

/// A pair of `ComputeTexture`s swapped each step — the texture-half companion to
/// `PingPong`: the kernel reads `read` (last step's state) and writes `write` (this
/// step's), then `advance()` makes the freshly written texture the new `read`. Two
/// textures, not one, so a step's reads can't see its own partial writes and the
/// render path can sample a stable frame. `Simulation` owns one of these; reach for
/// it directly when you drive the raw `compute(_:reading:writing:)` form yourself.
public final class PingPongTexture: @unchecked Sendable {
    private let a: ComputeTexture
    private let b: ComputeTexture
    private var flipped = false

    /// Allocate both textures at `width`×`height` in `format` (both start zeroed).
    public init(width: Int, height: Int, format: ComputeTextureFormat = .rgba16Float) {
        a = ComputeTexture(width: width, height: height, format: format)
        b = ComputeTexture(width: width, height: height, format: format)
    }

    /// The texture holding the current state (read this to draw or to seed).
    public var read: ComputeTexture { flipped ? b : a }
    /// The texture the next step writes into.
    public var write: ComputeTexture { flipped ? a : b }
    /// Swap which texture is current — call once after recording a step.
    public func advance() { flipped.toggle() }
}
