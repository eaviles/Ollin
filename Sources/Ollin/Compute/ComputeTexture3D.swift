import Foundation
import Metal
import os

/// A persistent, GPU-resident 3D texture a compute kernel writes each frame, the
/// box-shaped sibling of `ComputeTexture`: a grid of density a kernel fills and
/// `drawVolume` draws as a cloud, or the state of a simulation in three
/// dimensions. The grid never crosses to the CPU, so a kernel can refill 128
/// samples a side every frame where a `Volume` filled on the CPU holds a frame
/// rate to about 32.
///
/// ```swift
/// let cloud = ComputeTexture3D(width: 128, height: 128, depth: 128)
///
/// override func draw() {
///     compute(fillCloud, writing: cloud)      // one thread per sample, uint3 gid
///     drawVolume(cloud, size: 4, medium: .cloud)
/// }
/// ```
///
/// One 16-bit channel (`.r16Float`) by default, the density a volume reads: a
/// kernel writes `float4(density)` and `drawVolume` reads the red channel. Its
/// samples sit on the lattice a `Volume`'s do, corner to corner across the box,
/// so sample `(0, 0, 0)` is the box's left, bottom, back corner and the last
/// sample the opposite one, with `x` along the width, `y` up the height, and
/// `z` toward the viewer. Each side takes at least 2 samples.
///
/// Like `ComputeTexture`, the Metal texture is created lazily the first time the
/// renderer binds it, so one is constructible with no device, and its samples
/// start at **zero**. It is a `final class` because identity matters: a kernel
/// and the volume draw hold and read the same texture across frames. Storage is
/// `.shared` with `.shaderRead` and `.shaderWrite` usage.
///
/// Marked `@unchecked Sendable`: it carries an `MTLTexture` (not `Sendable`) but
/// is only ever realized or read on the main actor, the boundary `Image` crosses.
public final class ComputeTexture3D: ComputeTextureBindable, @unchecked Sendable {
    /// Samples along the box's width (`x`).
    public let width: Int
    /// Samples up the box's height (`y`).
    public let height: Int
    /// Samples through the box's depth (`z`).
    public let depth: Int
    /// The texel layout.
    public let format: ComputeTextureFormat
    private var texture: MTLTexture?

    /// An identity for the texture itself, for caches keyed on what a volume
    /// reads (a light-transmittance grid): distinct per texture, unlike the
    /// object's address, which a later texture may take over.
    let id: UInt64
    /// How many kernel dispatches writing this texture have been recorded. A
    /// cache of what it holds keys on it beside `id`, so a grid a kernel rewrote
    /// this frame is read again and one left alone is not.
    private(set) var writeCount: UInt64 = 0
    private static let nextID = OSAllocatedUnfairLock(initialState: UInt64(0))

    /// A `width` x `height` x `depth` texture in `format` (default `.r16Float`,
    /// one channel). Its samples start at zero; fill them with a kernel. Each
    /// side is clamped to at least 2 samples.
    public init(width: Int, height: Int, depth: Int, format: ComputeTextureFormat = .r16Float) {
        self.width = max(2, width)
        self.height = max(2, height)
        self.depth = max(2, depth)
        self.format = format
        id = ComputeTexture3D.nextID.withLock { $0 += 1; return $0 }
    }

    /// Count a recorded dispatch that writes this texture (`compute(_:writing:)`).
    func noteWrite() { writeCount &+= 1 }

    func metalTexture(for device: MTLDevice) -> MTLTexture? {
        if let texture { return texture }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = format.metalPixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let t = device.makeTexture(descriptor: descriptor) else { return nil }
        // makeTexture leaves contents undefined; zero them so a fresh texture is a
        // deterministic blank (the 2D texture's rule), and a volume drawn before
        // its first kernel is empty rather than garbage.
        let bytesPerRow = width * format.bytesPerPixel
        let bytesPerImage = bytesPerRow * height
        let zeros = [UInt8](repeating: 0, count: bytesPerImage * depth)
        zeros.withUnsafeBytes {
            t.replace(region: MTLRegionMake3D(0, 0, 0, width, height, depth), mipmapLevel: 0,
                      slice: 0, withBytes: $0.baseAddress!, bytesPerRow: bytesPerRow,
                      bytesPerImage: bytesPerImage)
        }
        t.label = "Ollin compute texture 3D"
        texture = t
        return t
    }

    /// Read the texture's current contents back to the CPU as interleaved floats
    /// (`x` fastest, then `y`, then `z`, `width * height * depth * channels` long):
    /// only valid once the texture has been realized and the GPU work that wrote
    /// it has completed, so it's `@MainActor` (read it on the frame loop after the
    /// render). For the float formats only (returns `nil` for `.rgba8Unorm`, and
    /// `nil` before the texture is first bound). Mainly for tests and debugging; a
    /// per-frame sim never needs it.
    @MainActor public func snapshot() -> [Float]? {
        guard let texture else { return nil }
        let bytesPerRow = width * format.bytesPerPixel
        let bytesPerImage = bytesPerRow * height
        var raw = [UInt8](repeating: 0, count: bytesPerImage * depth)
        raw.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage,
                             from: MTLRegionMake3D(0, 0, 0, width, height, depth), mipmapLevel: 0,
                             slice: 0)
        }
        let count = width * height * depth * format.channels
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

/// A pair of `ComputeTexture3D`s swapped each step, the 3D twin of
/// `PingPongTexture`: the kernel reads `read` (last step's state) and writes
/// `write` (this step's), then `swap()` makes the freshly written texture the new
/// `read`. Two textures, not one, so a step's reads never see its own partial
/// writes and a volume drawn from `read` is a whole, finished grid.
public final class PingPongTexture3D: @unchecked Sendable {
    private let a: ComputeTexture3D
    private let b: ComputeTexture3D
    private var flipped = false

    /// Allocate both textures at `width` x `height` x `depth` in `format` (both
    /// start zeroed).
    public init(width: Int, height: Int, depth: Int, format: ComputeTextureFormat = .r16Float) {
        a = ComputeTexture3D(width: width, height: height, depth: depth, format: format)
        b = ComputeTexture3D(width: width, height: height, depth: depth, format: format)
    }

    /// The texture holding the current state (draw this, or seed it).
    public var read: ComputeTexture3D { flipped ? b : a }
    /// The texture the next step writes into.
    public var write: ComputeTexture3D { flipped ? a : b }
    /// Swap which texture is current; call once after recording a step.
    public func swap() { flipped.toggle() }
}
