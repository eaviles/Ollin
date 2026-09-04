import Foundation
import CoreGraphics
import ImageIO
import Metal
import MetalKit

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A loaded raster image — the typed value behind `drawImage`.
///
/// An `Image` decodes its pixels on the CPU (via ImageIO) at load time and holds
/// a `CGImage`; the GPU texture is built lazily the first time the renderer draws
/// it and then cached on the instance, so loading needs no Metal device and the
/// upload happens once. Hold the `Image` (in a property, typically loaded in
/// `setup()`) for as long as you draw it — when it's released, its texture goes
/// with it.
///
/// A reference type on purpose: it owns a GPU resource and is identified by who
/// holds it, not by value.
///
/// ```swift
/// final class Photo: Sketch {
///     var photo: Image?
///     override func setup() { photo = loadImage("/path/to/photo.jpg") }
///     override func draw() {
///         background(.black)
///         if let photo { drawImage(photo, 0, 0, width, height) }
///     }
/// }
/// ```
///
/// An `Image` is **main-thread-affine**: its texture and pixel caches realize
/// lazily on first use, so don't touch the same instance from two threads at once
/// (e.g. don't hand one to a `Task.detached` and read its pixels or draw it while
/// the main draw loop also uses it). Building an image off the main thread and then
/// handing it to the sketch to use on the main thread (as video and the Vision
/// trackers do) is fine; concurrent use of a single instance is not.
public final class Image {

    /// Pixel width of the decoded image.
    public let width: Int
    /// Pixel height of the decoded image.
    public let height: Int

    /// The pixel dimensions as a `Vector2`, ready for the geometry helpers
    /// (`Rectangle(fitting: image.size, in: bounds)` letterboxes an image).
    public var size: Vector2 { Vector2(Double(width), Double(height)) }

    /// The decoded source. The texture is built from this on first draw; also the
    /// interop seam for frameworks that take a `CGImage` (Core Image, Vision, …).
    /// This is the original decode — pixel edits made through the `[x, y]`
    /// subscript aren't reflected here.
    public let cgImage: CGImage

    /// The GPU texture, built once on first draw and cached. Paired with the
    /// device it was made on so a different device (rare) rebuilds rather than
    /// handing back a foreign texture.
    private var cachedTexture: MTLTexture?
    private var cachedDeviceID: ObjectIdentifier?
    // The linear (data) twin of the cache above, for images sampled as *values*
    // rather than colors: a normal map's bytes must reach the shader raw, with
    // no sRGB decode on read. Kept separate so one image can serve both reads.
    private var cachedLinearTexture: MTLTexture?
    private var cachedLinearDeviceID: ObjectIdentifier?

    /// A live, externally-owned texture this image wraps directly (see
    /// `init(texture:)`). When set, the image *is* this texture: `texture(for:)`
    /// hands it back as-is and the CPU pixel paths are inert. Used to draw a GPU
    /// frame that changes every frame (a Syphon feed; later an effects layer)
    /// through `drawImage` without a CPU round-trip.
    private var externalTexture: MTLTexture?

    /// A GPU-resident `ComputeTexture` this image wraps. Unlike `externalTexture`
    /// (a concrete `MTLTexture`), this resolves the live texture *lazily at draw
    /// time* — the compute texture may not be realized when the `Image` is built, and
    /// its contents change every frame — so `drawImage(sim.image)` always composites
    /// the latest kernel write. CPU pixel paths are inert, as for `externalTexture`.
    private var computeTextureSource: ComputeTextureBindable?

    /// A `RenderTarget` (effects layer) this image wraps. Resolved lazily at draw
    /// time (the target's texture is filled by the renderer earlier in the same
    /// frame, before any draw that samples it), so `drawImage(layer.image)` always
    /// composites what was drawn into the layer this frame. CPU pixel paths are inert.
    private var renderTargetSource: RenderTarget?
    /// The layer this image draws, when it is a layer's `image` rather than a
    /// picture: what the web recorder writes down in place of pixels.
    var webRenderTarget: RenderTarget? { renderTargetSource }

    /// Whether this image has a CPU pixel buffer to read and write. A GPU-backed
    /// image (a live texture, a compute texture, an effects layer) has none: the
    /// pixel `subscript` reads `.clear` and writes are dropped. Pixel-reading
    /// transforms check this and bail rather than returning a blank result.
    var hasCPUPixels: Bool {
        externalTexture == nil && computeTextureSource == nil && renderTargetSource == nil
    }

    /// Draw a texture-backed image with its rows flipped (V coordinate inverted).
    /// Syphon textures follow the GL/Syphon bottom-left origin convention, the
    /// opposite of Ollin's top-left image space, so a consumed feed sets this to
    /// land upright. Honored by `Drawer.drawImage`; ignored for CPU-decoded images.
    private(set) var flipsVertically = false

    /// CPU pixel buffer for `subscript` get/set, materialized lazily on first
    /// pixel access (RGBA8, premultiplied alpha, row-major, top-left origin).
    private var pixelBytes: [UInt8]?
    /// Set once a pixel is written (or for a blank image authored here): the GPU
    /// texture then builds from `pixelBytes` rather than the original `cgImage`,
    /// so edits show on the next `drawImage`.
    private var pixelsModified = false
    /// Counts the pixel writes, so a reader that carries the picture somewhere
    /// (the web recorder) can tell an edited image from the one it already
    /// holds without comparing the bytes.
    private(set) var pixelGeneration = 0

    /// The file this image was decoded from, when it came from one: what the
    /// web recorder carries in place of a re-encode, since a browser reads the
    /// same file.
    private(set) var sourceURL: URL?

    /// Wrap an already-decoded `CGImage`.
    public init(cgImage: CGImage) {
        self.cgImage = cgImage
        self.width = cgImage.width
        self.height = cgImage.height
    }

    /// Wrap a live Metal `texture` so it can be drawn with `drawImage` — for a GPU
    /// frame that's produced fresh each frame (a Syphon feed; later an effects
    /// layer) and composited like any other image, riding the transform stack and
    /// `tint`. The texture is used as-is by the renderer (no upload, no copy), so
    /// it must live on the same Metal device the sketch renders on (true on a
    /// single-GPU Mac). The CPU paths — pixel `subscript`, `cgImage`,
    /// `currentCGImage()` — aren't meaningful for a live texture and are inert
    /// (reads return `.clear`; `cgImage` is a 1×1 placeholder).
    ///
    /// Set `flippedVertically` for a texture that follows the GL/Syphon bottom-left
    /// origin convention (a consumed Syphon feed), so it draws upright in Ollin's
    /// top-left space. Leave it `false` for a texture already in Ollin's
    /// orientation (e.g. one Ollin rendered itself).
    public init(texture: MTLTexture, flippedVertically: Bool = false) {
        self.externalTexture = texture
        self.flipsVertically = flippedVertically
        self.width = texture.width
        self.height = texture.height
        self.cgImage = Image.placeholderCGImage
    }

    /// Wrap a `ComputeTexture` so a kernel's output draws through `drawImage` like
    /// any other image. The texture is resolved lazily each frame (see
    /// `computeTextureSource`), so the same `Image` always reflects the latest GPU
    /// contents. Built by `ComputeTexture.image`; CPU pixel paths are inert.
    init(computeTexture source: ComputeTextureBindable) {
        self.computeTextureSource = source
        self.width = source.width
        self.height = source.height
        self.cgImage = Image.placeholderCGImage
    }

    /// Wrap a `RenderTarget` so an effects layer draws through `drawImage` like any
    /// other image, resolved lazily each frame (see `renderTargetSource`). Built by
    /// `RenderTarget.image`; CPU pixel paths are inert.
    init(renderTarget: RenderTarget) {
        self.renderTargetSource = renderTarget
        self.width = renderTarget.width
        self.height = renderTarget.height
        self.cgImage = Image.placeholderCGImage
    }

    /// A 1×1 transparent `CGImage`, the `cgImage` stand-in for a texture-backed
    /// image (which has no CPU-side decode).
    private static let placeholderCGImage: CGImage =
        CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data([0, 0, 0, 0]) as CFData)!,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)!

    /// Create a blank `width`×`height` image filled with `color` (transparent by
    /// default), ready to author pixel by pixel via `image[x, y] = …`. The way to
    /// build an image from scratch: make it here, write its pixels, then
    /// `drawImage` it. Dimensions are clamped to at least `1×1`.
    public init(width: Int, height: Int, color: Color = .clear) {
        let w = max(1, width), h = max(1, height)
        self.width = w
        self.height = h
        let (r, g, b, a) = Image.premultipliedBytes(color)
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        var i = 0
        while i < buffer.count {
            buffer[i] = r; buffer[i + 1] = g; buffer[i + 2] = b; buffer[i + 3] = a
            i += 4
        }
        self.cgImage = Image.makeCGImage(buffer, width: w, height: h)
            ?? CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data([0, 0, 0, 0]) as CFData)!,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        self.pixelBytes = buffer
        self.pixelsModified = true
    }

    /// Wrap raw pixels: `bytes` is `width × height × 4` RGBA8, premultiplied
    /// alpha, row-major from the top-left — the layout the pixel `subscript`
    /// stores. The image takes the buffer as its own pixels (no decode, no
    /// conversion), so this is the fast lane for pixels produced in bulk by
    /// other code: the GPU texture uploads straight from the buffer. Returns
    /// `nil` when the count doesn't match the dimensions.
    public init?(width: Int, height: Int, premultipliedRGBA bytes: [UInt8]) {
        guard width > 0, height > 0, bytes.count == width * height * 4,
              let cgImage = Image.makeCGImage(bytes, width: width, height: height) else {
            return nil
        }
        self.width = width
        self.height = height
        self.cgImage = cgImage
        self.pixelBytes = bytes
        self.pixelsModified = true
    }

    /// Decode an image file at `url` (PNG, JPEG, HEIC, TIFF, GIF — anything
    /// ImageIO reads). Returns `nil` if the file can't be read or decoded.
    public convenience init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        self.init(cgImage: image)
        self.sourceURL = url
    }

    /// Decode image file `data` (the bytes of a PNG, JPEG, …). Returns `nil` if
    /// the data isn't a decodable image.
    public convenience init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        self.init(cgImage: image)
    }

    /// Decode a bundled image resource. `in:` has no default on purpose: a
    /// default argument would resolve to Ollin's own bundle, never the caller's —
    /// pass `.module` from the sketch that bundles the asset.
    public convenience init?(resource name: String, withExtension ext: String?, in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        self.init(contentsOf: url)
    }

    /// The current pixels as a `CGImage`, reflecting edits made through the
    /// `[x, y]` subscript (and the contents of a blank image authored in memory).
    /// Unlike `cgImage` — which is always the original decode — this is what
    /// interop that must see the *live* pixels (Vision, Core Image) should use.
    public func currentCGImage() -> CGImage {
        (pixelsModified ? bufferBackedCGImage() : nil) ?? cgImage
    }

    /// The Metal texture for this image on `device`, built and cached on first
    /// use. Called by the renderer on the main thread during encoding.
    func texture(for device: MTLDevice) -> MTLTexture? {
        // A texture-backed image hands its live texture straight through (it's
        // already on the GPU; the renderer composites it as-is each frame).
        if let externalTexture { return externalTexture }
        // A compute-texture-backed image resolves the kernel's output texture now,
        // at draw time (realizing it on first use), so it picks up this frame's write.
        if let computeTextureSource { return computeTextureSource.metalTexture(for: device) }
        // An effects layer hands back the texture the renderer filled for it earlier
        // this frame (linear rgba16Float, premultiplied; the image path composites
        // it correctly, no flip).
        if let renderTargetSource { return renderTargetSource.texture }

        let id = ObjectIdentifier(device)
        if let cachedTexture, cachedDeviceID == id { return cachedTexture }

        // Edited or authored pixels upload straight from the buffer: it's already
        // the texture's byte layout (premultiplied RGBA8, top-left rows), so the
        // loader's decode, the context redraw, and the sRGB self-heal below are
        // all skipped. This is what keeps per-frame published images (a
        // segmentation matte) off the expensive path.
        if pixelsModified, let pixelBytes,
           let direct = Image.sRGBTexture(premultipliedRGBA: pixelBytes, width: width,
                                          height: height, on: device) {
            cachedTexture = direct
            cachedDeviceID = id
            return direct
        }

        // After a pixel write (or for a blank image authored in memory), upload the
        // edited buffer; otherwise upload the original decode unchanged.
        let source = (pixelsModified ? bufferBackedCGImage() : nil) ?? cgImage
        let loader = MTKTextureLoader(device: device)
        // `.SRGB: true` makes the texture sRGB, so the GPU decodes each sample to
        // linear on read — matching the renderer's linear-light blending, where
        // the shaders also linearize the solid colors drawn beside the image.
        // `.generateMipmaps` builds the smaller levels the sampler reads when a
        // texture lands on fewer pixels than it has (a floor running to the
        // horizon, a picture drawn small). Each level averages in *linear* light
        // because the format is sRGB, which is the light the renderer blends in.
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: true,
            .generateMipmaps: NSNumber(value: true),
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]
        guard var texture = try? loader.newTexture(cgImage: source, options: options) else {
            return nil
        }
        // The loader honors `.SRGB` only for ImageIO-backed sources: a CGImage
        // made by a bitmap context (a pixel-authored image, a camera frame, any
        // CG drawing) comes back in a *linear* pixel format holding the same
        // sRGB-encoded bytes, so sampling skips the decode and everything washes
        // out lighter. When that happens, rebuild the texture by hand in the
        // sRGB format. The loader also keeps a straight-alpha source straight
        // (ImageIO decodes a PNG with alpha that way), while the image pipeline
        // blends premultiplied, so a straight texture draws a translucent pixel
        // too bright; the rebuild draws through a premultiplied context, which
        // premultiplies too.
        let straight = source.alphaInfo == .last || source.alphaInfo == .first
        if straight || (texture.pixelFormat != .bgra8Unorm_srgb && texture.pixelFormat != .rgba8Unorm_srgb),
           let rebuilt = Image.sRGBTexture(from: source, on: device) {
            texture = rebuilt
        }
        cachedTexture = texture
        cachedDeviceID = id
        return texture
    }

    /// The Metal texture for this image sampled as *data* rather than color:
    /// the bytes reach the shader raw, with no sRGB decode on read. This is what
    /// a normal map (or any value-encoding map) must sample through, since
    /// decoding its bytes as color would bend every stored direction. Built and
    /// cached on first use, separately from the color texture, so one image can
    /// serve both reads. GPU-backed images pass their live texture through
    /// unchanged (a compute-written float texture is already linear data).
    func linearTexture(for device: MTLDevice) -> MTLTexture? {
        if let externalTexture { return externalTexture }
        if let computeTextureSource { return computeTextureSource.metalTexture(for: device) }
        if let renderTargetSource { return renderTargetSource.texture }

        let id = ObjectIdentifier(device)
        if let cachedLinearTexture, cachedLinearDeviceID == id { return cachedLinearTexture }

        // Edited or authored pixels upload straight from the buffer, exactly like
        // the color path, but into the non-sRGB format so the bytes read back as
        // the values that were written.
        if pixelsModified, let pixelBytes,
           let direct = Image.linearTexture(rgba: pixelBytes, width: width,
                                            height: height, on: device) {
            cachedLinearTexture = direct
            cachedLinearDeviceID = id
            return direct
        }

        let source = (pixelsModified ? bufferBackedCGImage() : nil) ?? cgImage
        let loader = MTKTextureLoader(device: device)
        // `.SRGB: false` asks for the raw-bytes format. Unlike the color path,
        // a context-made CGImage needs no self-heal here: the loader's linear
        // format holding the file's bytes is exactly the data read we want.
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            // A value map needs its own mip chain as much as a color one: without
            // it a normal map keeps flickering at a distance the base color has
            // stopped flickering at, which reads as sparkle. The levels average
            // the stored values (no sRGB decode, the format is linear), and the
            // fragment renormalizes the bent normal, so a shortened average
            // direction stays a direction.
            .generateMipmaps: NSNumber(value: true),
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]
        guard let texture = try? loader.newTexture(cgImage: source, options: options) else {
            return nil
        }
        cachedLinearTexture = texture
        cachedLinearDeviceID = id
        return texture
    }

    /// Upload RGBA8 `bytes` as a plain `.rgba8Unorm` texture: the bytes pass
    /// through verbatim and read back as the same values. The data twin of
    /// `sRGBTexture(premultipliedRGBA:...)` below.
    ///
    /// One level, no mip chain: this is the path a sketch that writes pixels
    /// takes *every frame*, and building the chain there costs about 0.7 ms a
    /// frame at canvas size to smooth a read that a full-size image never makes.
    /// The decoded-once paths above, which is where a mesh's maps come from,
    /// carry the chain.
    private static func linearTexture(rgba bytes: [UInt8], width: Int,
                                      height: Int, on device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = ollinUploadStorageMode
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: base, bytesPerRow: width * 4)
        }
        return texture
    }

    /// Upload premultiplied RGBA8 `bytes` as an `.rgba8Unorm_srgb` texture: the
    /// bytes pass through verbatim, and each sample decodes sRGB → linear on
    /// read. The fast path for buffer-backed pixels: no decode, no redraw, and
    /// one level for the reason stated above.
    private static func sRGBTexture(premultipliedRGBA bytes: [UInt8], width: Int,
                                    height: Int, on device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = ollinUploadStorageMode
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: base, bytesPerRow: width * 4)
        }
        return texture
    }

    /// Upload `source` as a `.bgra8Unorm_srgb` texture by hand: draw it into a
    /// premultiplied BGRA sRGB bitmap (the byte layout the texture stores) and
    /// copy the rows in. The fallback for sources `MTKTextureLoader` won't give
    /// an sRGB texture for.
    private static func sRGBTexture(from source: CGImage, on device: MTLDevice) -> MTLTexture? {
        let width = source.width, height = source.height
        let bytesPerRow = width * 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue),
              let bytes = context.data else { return nil }
        // The straight draw lands the image's top row in row 0, matching the
        // loader's (and the image quad's) orientation.
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: true)
        descriptor.usage = .shaderRead
        descriptor.storageMode = ollinUploadStorageMode
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: bytesPerRow)
        Image.fillSmallerLevels(of: texture, on: device)
        return texture
    }

    /// Fill a hand-built texture's smaller levels. `MTKTextureLoader` runs this
    /// blit itself for the textures it makes; a texture uploaded by hand asks for
    /// it. An sRGB format averages each level in linear light (a black-and-white
    /// checker comes back 188, not 128), so a level agrees with the light the
    /// renderer blends in.
    private static func fillSmallerLevels(of texture: MTLTexture, on device: MTLDevice) {
        guard texture.mipmapLevelCount > 1,
              let queue = device.makeCommandQueue(),
              let buffer = queue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
    }

    // MARK: Pixel access

    /// Read or write one pixel's color. `(0, 0)` is the top-left; coordinates run
    /// to `(width - 1, height - 1)`. Reading out of range returns `.clear`; writing
    /// out of range does nothing — so a loop that strays off the edge is harmless.
    ///
    /// A write shows on the next `drawImage` (the GPU texture rebuilds from the
    /// edited pixels), so author in `setup()` when you can rather than every frame.
    /// Colors pass through the image's premultiplied storage, so round-tripping a
    /// translucent color can shift it by a step of `1/255`.
    public subscript(x: Int, y: Int) -> Color {
        get {
            guard x >= 0, x < width, y >= 0, y < height else { return .clear }
            // A texture-backed image has no CPU pixels to read.
            if externalTexture != nil { return .clear }
            let buffer = materializePixels()
            let i = (y * width + x) * 4
            let a = Double(buffer[i + 3]) / 255
            guard a > 0 else { return .clear }
            // Un-premultiply (straight = premultiplied / alpha); clamp for rounding.
            return Color(red:   min(1, Double(buffer[i])     / 255 / a),
                         green: min(1, Double(buffer[i + 1]) / 255 / a),
                         blue:  min(1, Double(buffer[i + 2]) / 255 / a),
                         alpha: a)
        }
        set {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            if externalTexture != nil { return }   // texture-backed: no CPU pixels to write
            _ = materializePixels()
            let (r, g, b, a) = Image.premultipliedBytes(newValue)
            let i = (y * width + x) * 4
            pixelBytes?[i] = r; pixelBytes?[i + 1] = g; pixelBytes?[i + 2] = b; pixelBytes?[i + 3] = a
            pixelsModified = true
            pixelGeneration += 1
            cachedTexture = nil
            cachedDeviceID = nil
            cachedLinearTexture = nil
            cachedLinearDeviceID = nil
        }
    }

    /// The premultiplied RGBA8 pixel buffer (row-major, top-left origin),
    /// materialized on first access, or `nil` for a GPU-backed image, which has
    /// no CPU pixels. The bulk read for whole-image transforms (dithering), so
    /// they can walk bytes instead of paying the per-pixel `subscript`.
    func premultipliedPixels() -> [UInt8]? {
        guard hasCPUPixels else { return nil }
        return materializePixels()
    }

    /// Whether the picture drawn is the file it was decoded from, untouched: the
    /// web recorder then carries the file's own bytes, which a browser decodes
    /// as the Mac did, instead of a re-encode of the pixels.
    var drawsSourceFile: Bool { sourceURL != nil && !pixelsModified && hasCPUPixels }

    /// Build (once) and return the CPU RGBA8 buffer, drawing the source `cgImage`
    /// into a top-left-origin, premultiplied, device-RGB bitmap.
    private func materializePixels() -> [UInt8] {
        if let pixelBytes { return pixelBytes }
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // No flip: this bitmap context lays out memory row 0 as the image's
            // *top* row, matching the CGImage's native orientation and `drawImage`.
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        pixelBytes = buffer
        return buffer
    }

    /// A `CGImage` over the edited pixel buffer, for re-uploading after writes.
    private func bufferBackedCGImage() -> CGImage? {
        guard let pixelBytes else { return nil }
        return Image.makeCGImage(pixelBytes, width: width, height: height)
    }

    /// A straight RGBA `Color` premultiplied into four `0...255` bytes.
    private static func premultipliedBytes(_ color: Color) -> (UInt8, UInt8, UInt8, UInt8) {
        let a = clampUnit(color.alpha)
        return (unitByte(clampUnit(color.red)   * a),
                unitByte(clampUnit(color.green) * a),
                unitByte(clampUnit(color.blue)  * a),
                unitByte(a))
    }

    private static func clampUnit(_ v: Double) -> Double { max(0, min(1, v)) }
    private static func unitByte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }

    /// Build a top-left-origin `CGImage` over RGBA8 premultiplied `buffer`.
    static func makeCGImage(_ buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, buffer.count == width * height * 4,
              let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

extension Sketch {
    /// Load an image from a file path, for `drawImage`. Returns `nil` if the file
    /// can't be read or decoded. Call it in `setup()` and keep the result in a
    /// property — decoding every frame is wasteful. Sugar over `Image(contentsOf:)`.
    public func loadImage(_ path: String) -> Image? {
        Image(contentsOf: URL(fileURLWithPath: path))
    }

    /// Load an image from a file `url`. Sugar over `Image(contentsOf:)`.
    public func loadImage(_ url: URL) -> Image? {
        Image(contentsOf: url)
    }
}

/// How a picture meets a box it does not have the shape of.
///
/// The three answers to one question: the box has an aspect ratio, the picture
/// has another, and something has to give. Pass one to
/// ``Sketch/drawImage(_:in:fit:)``.
public enum ImageFit: Sendable, CaseIterable {
    /// Squash the picture to the box. Every pixel of both is used, and the
    /// picture's proportions are not kept. The default, and what
    /// `drawImage(_:in:)` does on its own.
    case stretch
    /// Keep the proportions and put the whole picture inside the box. The
    /// picture is centered, and the box is left showing along two of its edges.
    case contain
    /// Keep the proportions and cover the box completely. The picture is
    /// centered, and what runs past two of the edges is cropped away.
    case cover
}
