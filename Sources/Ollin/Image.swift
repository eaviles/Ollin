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

    /// Wrap an already-decoded `CGImage`.
    public init(cgImage: CGImage) {
        self.cgImage = cgImage
        self.width = cgImage.width
        self.height = cgImage.height
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

        let loader = MTKTextureLoader(device: device)
        // `.SRGB: false` matches the renderer's non-color-managed pixel format
        // (raw bytes in, raw bytes out), so the image's tones aren't gamma-shifted
        // relative to the solid colors drawn beside it.
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]
        guard let texture = try? loader.newTexture(cgImage: cgImage, options: options) else {
            return nil
        }
        cachedTexture = texture
        cachedDeviceID = id
        return texture
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
