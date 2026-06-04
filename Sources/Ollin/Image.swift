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
public final class Image {

    /// Pixel width of the decoded image.
    public let width: Int
    /// Pixel height of the decoded image.
    public let height: Int

    /// The decoded source. The texture is built from this on first draw.
    let cgImage: CGImage

    /// The GPU texture, built once on first draw and cached. Paired with the
    /// device it was made on so a different device (rare) rebuilds rather than
    /// handing back a foreign texture.
    private var cachedTexture: MTLTexture?
    private var cachedDeviceID: ObjectIdentifier?

    /// CPU pixel buffer for `subscript` get/set, materialized lazily on first
    /// pixel access (RGBA8, premultiplied alpha, row-major, top-left origin).
    private var pixelBytes: [UInt8]?
    /// Set once a pixel is written (or for a blank image authored here): the GPU
    /// texture then builds from `pixelBytes` rather than the original `cgImage`,
    /// so edits show on the next `drawImage`.
    private var pixelsModified = false

    /// Wrap an already-decoded `CGImage`.
    public init(cgImage: CGImage) {
        self.cgImage = cgImage
        self.width = cgImage.width
        self.height = cgImage.height
    }

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

    /// Decode an image file at `url` (PNG, JPEG, HEIC, TIFF, GIF — anything
    /// ImageIO reads). Returns `nil` if the file can't be read or decoded.
    public convenience init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        self.init(cgImage: image)
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
    public convenience init?(resource name: String, extension ext: String?, in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        self.init(contentsOf: url)
    }

    /// The Metal texture for this image on `device`, built and cached on first
    /// use. Called by the renderer on the main thread during encoding.
    func texture(for device: MTLDevice) -> MTLTexture? {
        let id = ObjectIdentifier(device)
        if let cachedTexture, cachedDeviceID == id { return cachedTexture }

        // After a pixel write (or for a blank image authored in memory), upload the
        // edited buffer; otherwise upload the original decode unchanged.
        let source = (pixelsModified ? bufferBackedCGImage() : nil) ?? cgImage
        let loader = MTKTextureLoader(device: device)
        // `.SRGB: false` matches the renderer's non-color-managed pixel format
        // (raw bytes in, raw bytes out), so the image's tones aren't gamma-shifted
        // relative to the solid colors drawn beside it.
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]
        guard let texture = try? loader.newTexture(cgImage: source, options: options) else {
            return nil
        }
        cachedTexture = texture
        cachedDeviceID = id
        return texture
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
            _ = materializePixels()
            let (r, g, b, a) = Image.premultipliedBytes(newValue)
            let i = (y * width + x) * 4
            pixelBytes?[i] = r; pixelBytes?[i + 1] = g; pixelBytes?[i + 2] = b; pixelBytes?[i + 3] = a
            pixelsModified = true
            cachedTexture = nil
            cachedDeviceID = nil
        }
    }

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
    private static func makeCGImage(_ buffer: [UInt8], width: Int, height: Int) -> CGImage? {
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
