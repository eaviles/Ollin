import Foundation
import CoreGraphics
import ImageIO

/// A picture the page carries for `drawImage`: the bytes of the file the
/// sketch loaded when a browser decodes that format (PNG, JPEG, GIF, WebP), or
/// a PNG of the pixels the Mac's texture was uploaded from, for a picture
/// painted in memory, edited, or read from a format a browser does not open.
struct WebPicture: Equatable {
    var data: Data
    /// The MIME type the page hands the browser's decoder.
    var mime: String
    var width: Int
    var height: Int
}

/// A glyph atlas page the page carries for `textMode(.atlas)`: the rows down
/// to the last packed shelf as an 8-bit gray PNG, `size` texels wide. The page
/// puts them at the top of a `size` by `size` texture, since the glyph quads
/// address the whole page.
struct WebAtlas: Equatable {
    var png: Data
    var size: Int
    var rows: Int
}

/// Encodes the pictures and atlases a page carries.
enum WebAssetEncoder {

    /// The picture for `image`, or `nil` for one that has no pixels on the CPU
    /// (a live texture, a compute texture; a layer's image crosses another way).
    static func picture(of image: Image) -> WebPicture? {
        if image.drawsSourceFile, let url = image.sourceURL,
           let data = try? Data(contentsOf: url), let mime = browserFormat(of: data) {
            return WebPicture(data: data, mime: mime, width: image.width, height: image.height)
        }
        guard let bytes = image.premultipliedPixels(),
              let cg = Image.makeCGImage(bytes, width: image.width, height: image.height),
              let png = png(of: cg) else { return nil }
        return WebPicture(data: png, mime: "image/png", width: image.width, height: image.height)
    }

    /// The atlas asset for `page`, `size` texels wide and `rows` tall.
    static func atlas(page: [UInt8], size: Int, rows: Int) -> WebAtlas? {
        guard rows > 0, page.count >= size * rows,
              let provider = CGDataProvider(data: Data(page[0 ..< size * rows]) as CFData),
              let cg = CGImage(width: size, height: rows, bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent),
              let png = png(of: cg) else { return nil }
        return WebAtlas(png: png, size: size, rows: rows)
    }

    /// The MIME type of an image file a browser decodes, read from its first
    /// bytes, or `nil` for any other format.
    static func browserFormat(of data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let head = [UInt8](data.prefix(12))
        if head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 { return "image/png" }
        if head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return "image/jpeg" }
        if head[0] == 0x47, head[1] == 0x49, head[2] == 0x46, head[3] == 0x38 { return "image/gif" }
        if head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return "image/webp" }
        return nil
    }

    /// `image` as a PNG.
    static func png(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
