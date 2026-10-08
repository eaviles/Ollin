import Foundation
import Metal
import os

/// A box of density samples in 3D: smoke, a cloud, a scanned volume, a field of
/// noise. `drawVolume(_:size:medium:)` draws one as a glowing or light-absorbing
/// cloud in a 3D scene, marched per pixel through the scene's depth, so a solid
/// inside it is hidden by what lies in front of it and hides what lies behind it.
///
/// ```swift
/// let smoke = Volume(width: 64, height: 64, depth: 64) { u, v, w in
///     let fromCenter = Vector3(u, v, w).distance(to: Vector3(0.5, 0.5, 0.5))
///     return max(0, fbm(u * 4, v * 4, w * 4) - 2 * fromCenter)
/// }
/// drawVolume(smoke, size: 4, medium: .smoke)
/// ```
///
/// The samples sit on a lattice that spans the box corner to corner: sample
/// `(0, 0, 0)` is the box's left, bottom, back corner and sample
/// `(width - 1, height - 1, depth - 1)` the opposite one, with `x` along the
/// box's width, `y` up its height, and `z` toward the viewer through its depth.
/// Between samples the value is interpolated trilinearly, and outside the box
/// it is zero. A value of 1 is the medium's full `density`; values below 0 read
/// as 0.
///
/// A volume is a value: copies are cheap (they share one buffer until one of
/// them is written), and the grid reaches the GPU once per distinct buffer, so a
/// volume built in `setup()` costs nothing to redraw. Refilling one every frame
/// is fine at modest sizes; `Volume.noise(width:height:depth:frequency:octaves:seed:)`
/// fills across every core for that.
public struct Volume: Sendable {
    /// Samples along the box's width (`x`).
    public let width: Int
    /// Samples up the box's height (`y`).
    public let height: Int
    /// Samples through the box's depth (`z`).
    public let depth: Int

    var storage: VolumeStorage

    /// A volume of `value` everywhere. Each side takes at least 2 samples.
    public init(width: Int, height: Int, depth: Int, repeating value: Double = 0) {
        let w = max(2, width), h = max(2, height), d = max(2, depth)
        self.width = w
        self.height = h
        self.depth = d
        storage = VolumeStorage(values: [Float](repeating: Float(value), count: w * h * d))
    }

    /// A volume from explicit samples, `x` fastest, then `y`, then `z`
    /// (`values[(z * height + y) * width + x]`). `values.count` must be
    /// `width * height * depth`, and each side at least 2.
    public init(width: Int, height: Int, depth: Int, values: [Double]) {
        precondition(width >= 2 && height >= 2 && depth >= 2,
                     "Volume needs at least 2 samples on each side")
        precondition(values.count == width * height * depth,
                     "Volume needs width * height * depth values")
        self.width = width
        self.height = height
        self.depth = depth
        storage = VolumeStorage(values: values.map { Float($0) })
    }

    /// A volume sampled from a function of normalized coordinates: `field(u, v, w)`
    /// is called once per sample with `u`, `v`, `w` in `0…1` across the box's
    /// width, height, and depth (corner to corner).
    ///
    /// ```swift
    /// let ball = Volume(width: 48, height: 48, depth: 48) { u, v, w in
    ///     max(0, 1 - 2 * Vector3(u, v, w).distance(to: Vector3(0.5, 0.5, 0.5)))
    /// }
    /// ```
    public init(width: Int, height: Int, depth: Int,
                _ field: (Double, Double, Double) -> Double) {
        let w = max(2, width), h = max(2, height), d = max(2, depth)
        var values = [Float]()
        values.reserveCapacity(w * h * d)
        for z in 0 ..< d {
            let wz = Double(z) / Double(d - 1)
            for y in 0 ..< h {
                let vy = Double(y) / Double(h - 1)
                for x in 0 ..< w {
                    values.append(Float(field(Double(x) / Double(w - 1), vy, wz)))
                }
            }
        }
        self.width = w
        self.height = h
        self.depth = d
        storage = VolumeStorage(values: values)
    }

    /// The sample at lattice point `(x, y, z)`; each index must be in range.
    public subscript(x: Int, y: Int, z: Int) -> Double {
        get { Double(storage.values[(z * height + y) * width + x]) }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height && z >= 0 && z < depth,
                         "Volume sample index out of range")
            if !isKnownUniquelyReferenced(&storage) || storage.isPublished {
                storage = VolumeStorage(values: storage.values)
            }
            storage.values[(z * height + y) * width + x] = Float(newValue)
        }
    }

    /// The value at normalized coordinates `u`, `v`, `w` (each `0…1` corner to
    /// corner, clamped), interpolated trilinearly between the eight samples
    /// around it: the same reading the march takes.
    public func value(u: Double, v: Double, w: Double) -> Double {
        func cell(_ t: Double, _ n: Int) -> (Int, Double) {
            let p = min(max(t, 0), 1) * Double(n - 1)
            let i = min(Int(p.rounded(.down)), n - 2)
            return (i, p - Double(i))
        }
        let (x0, fx) = cell(u, width)
        let (y0, fy) = cell(v, height)
        let (z0, fz) = cell(w, depth)
        let s = storage.values
        func at(_ x: Int, _ y: Int, _ z: Int) -> Double { Double(s[(z * height + y) * width + x]) }
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let c00 = lerp(at(x0, y0, z0), at(x0 + 1, y0, z0), fx)
        let c10 = lerp(at(x0, y0 + 1, z0), at(x0 + 1, y0 + 1, z0), fx)
        let c01 = lerp(at(x0, y0, z0 + 1), at(x0 + 1, y0, z0 + 1), fx)
        let c11 = lerp(at(x0, y0 + 1, z0 + 1), at(x0 + 1, y0 + 1, z0 + 1), fx)
        return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz)
    }

    /// A volume of fractal noise, filled across every core: each sample is
    /// `fbm(u * frequency, v * frequency, w * frequency, octaves: octaves)` with
    /// `u`, `v`, `w` in `0…1`, read from the noise a sketch seeded with
    /// `noiseSeed(seed)` reads, so the closure form over the sketch's own `fbm`
    /// gives the same samples, only slower. Values sit in about `0…1`; shape
    /// them into a cloud with the closure form, reading this one through
    /// `value(u:v:w:)`.
    public static func noise(width: Int, height: Int, depth: Int,
                             frequency: Double = 4, octaves: Int = 4, seed: Int = 0) -> Volume {
        let fields = NoiseFields(seed: seed)
        return filled(width: width, height: height, depth: depth) { u, v, w in
            fields.fbm(u * frequency, v * frequency, w * frequency, octaves: octaves)
        }
    }

    /// A volume of fractal noise that loops as `loop` runs `0…1`: every octave
    /// tours its own closed circle, so a cloud refilled each frame from
    /// `loop: t` drifts and comes home each lap (see `fbm(_:_:_:loop:radius:)`).
    /// Filled across every core, like the non-looping form.
    public static func noise(width: Int, height: Int, depth: Int,
                             loop: Double, radius: Double = 1,
                             frequency: Double = 4, octaves: Int = 4, seed: Int = 0) -> Volume {
        let fields = NoiseFields(seed: seed)
        return filled(width: width, height: height, depth: depth) { u, v, w in
            fields.fbm(u * frequency, v * frequency, w * frequency,
                       loop: loop, radius: radius, octaves: octaves)
        }
    }

    /// Fill a lattice from a pure function of `(u, v, w)`, one z slab per task.
    private static func filled(width: Int, height: Int, depth: Int,
                               _ field: @Sendable (Double, Double, Double) -> Double) -> Volume {
        let w = max(2, width), h = max(2, height), d = max(2, depth)
        let slab = w * h
        var values = [Float](repeating: 0, count: slab * d)
        values.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: d) { z in
                let wz = Double(z) / Double(d - 1)
                var i = z * slab
                for y in 0 ..< h {
                    let vy = Double(y) / Double(h - 1)
                    for x in 0 ..< w {
                        base[i] = Float(field(Double(x) / Double(w - 1), vy, wz))
                        i += 1
                    }
                }
            }
        }
        var volume = Volume(width: w, height: h, depth: d)
        volume.storage = VolumeStorage(values: values)
        return volume
    }

    /// The samples as the GPU holds them, uploaded once per buffer.
    func texture(for device: MTLDevice) -> MTLTexture? {
        storage.texture(for: device, width: width, height: height, depth: depth)
    }

    /// An identity for this buffer of samples, for caches keyed on what a volume
    /// holds rather than where it is: a write makes a new one.
    var contentID: UInt64 { storage.id }
}

extension Volume: Equatable {
    public static func == (a: Volume, b: Volume) -> Bool {
        a.width == b.width && a.height == b.height && a.depth == b.depth
            && (a.storage === b.storage || a.storage.values == b.storage.values)
    }
}

/// The samples behind a `Volume`, shared by its copies. Written in place only
/// while one copy holds it and the renderer has not uploaded it; any later write
/// copies first, so an upload never goes stale and a frame in flight never reads
/// a buffer changing under it.
final class VolumeStorage: @unchecked Sendable {
    private static let nextID = OSAllocatedUnfairLock(initialState: UInt64(0))

    var values: [Float]
    let id: UInt64
    private let cache = OSAllocatedUnfairLock<(texture: MTLTexture?, device: ObjectIdentifier?)>(
        uncheckedState: (nil, nil))

    init(values: [Float]) {
        self.values = values
        id = VolumeStorage.nextID.withLock { $0 += 1; return $0 }
    }

    /// Whether the renderer has uploaded these samples (after which they are
    /// never written again).
    var isPublished: Bool { cache.withLockUnchecked { $0.texture != nil } }

    func texture(for device: MTLDevice, width: Int, height: Int, depth: Int) -> MTLTexture? {
        let deviceID = ObjectIdentifier(device)
        if let cached = cache.withLockUnchecked({ $0.device == deviceID ? $0.texture : nil }) {
            return cached
        }
        // Half floats: every density a sketch writes is far inside their range,
        // they filter on every Apple GPU, and they halve the upload.
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Float
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let halves = values.map { Float16(min(max($0, -65_000), 65_000)) }
        halves.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake3D(0, 0, 0, width, height, depth),
                            mipmapLevel: 0, slice: 0, withBytes: raw.baseAddress!,
                            bytesPerRow: width * 2, bytesPerImage: width * height * 2)
        }
        texture.label = "Ollin volume"
        cache.withLockUnchecked { $0 = (texture, deviceID) }
        return texture
    }
}
