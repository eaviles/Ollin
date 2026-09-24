import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Ollin

/// Building the references a sketch declares.
///
/// The wire type itself (`PhoneReference`, in `PhoneWire.swift`) is plain bytes,
/// because that file compiles into the phone app too and may not reach for
/// ImageIO. Reading a file and fitting a picture for the cable is Mac work, so it
/// lives here.
public extension PhoneReference {

    /// The longest edge a picture travels at, in pixels.
    ///
    /// ARKit wants *detail*, not size: it finds a print by the features in it, and
    /// a picture larger than this adds none it can use while costing the cable and
    /// the phone's memory. A file already within this and small enough for one
    /// frame travels untouched, which keeps a hand-made PNG exact; anything larger
    /// is redrawn to fit and re-encoded as JPEG.
    static let maxPictureEdge = 1024

    /// A picture bundled with the sketch: a poster, a card, a page, given the width
    /// it is printed at in **meters**.
    ///
    /// The name is what a find is matched on. Left out, it is the file's own name
    /// with any size taken off the end, the same rule the capture app's folder
    /// uses, so `poster@30cm.png` declares the marker `poster` either way.
    ///
    /// Throws a `FileError`: `missing` when the bundle has no such file,
    /// `unreadable` when the pixels will not read.
    static func picture(resource: String, withExtension ext: String, in bundle: Bundle,
                        printedWidth: Double, named name: String? = nil) throws -> PhoneReference {
        let url = try FileError.resource(resource, withExtension: ext, in: bundle)
        return try picture(path: url.path, printedWidth: printedWidth, named: name)
    }

    /// A picture read from a path, given the width it is printed at in meters.
    /// Throws a `FileError`: `missing` when no file is there, `unreadable` when
    /// the pixels will not read.
    static func picture(path: String, printedWidth: Double,
                        named name: String? = nil) throws -> PhoneReference {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let contents = try FileError.contents(of: url)
        let markerName = name ?? PhoneWire.markerName(fromFileName: url.lastPathComponent)
        guard let fitted = fitPicture(contents) else {
            throw FileError.unreadable(url, "is not a picture ImageIO can decode")
        }
        return PhoneReference(name: markerName, kind: .image,
                              printedWidth: printedWidth, contents: fitted)
    }

    /// A picture the sketch already holds: a photograph it loaded, or something it
    /// drew and exported, given the width it is printed at in meters.
    static func picture(_ image: Image, printedWidth: Double,
                        named name: String) -> PhoneReference? {
        // Straight to the fitting, so a picture already in memory is encoded once
        // rather than compressed at full size and then compressed again.
        guard let fitted = fitPixels(image.cgImage) else { return nil }
        return PhoneReference(name: name, kind: .image,
                              printedWidth: printedWidth, contents: fitted)
    }

    /// A solid object somebody scanned into an `.arobject` file, bundled with the
    /// sketch. An object archive already carries its own size and origin, so there
    /// is no width to state.
    /// Throws a `FileError` when the bundle has no such file.
    static func object(resource: String, in bundle: Bundle,
                       named name: String? = nil) throws -> PhoneReference {
        let url = try FileError.resource(resource, withExtension: PhoneWire.markerObjectExtension,
                                         in: bundle)
        return try object(path: url.path, named: name)
    }

    /// A scanned object read from a path. Throws a `FileError`: `missing` when
    /// no file is there, `unreadable` when it is larger than the cable carries.
    static func object(path: String, named name: String? = nil) throws -> PhoneReference {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let contents = try FileError.contents(of: url)
        guard contents.count <= PhoneWire.maxPayloadBytes else {
            throw FileError.unreadable(url, "is \(contents.count) bytes, more than the cable carries "
                                       + "(\(PhoneWire.maxPayloadBytes))")
        }
        let markerName = name ?? PhoneWire.markerName(fromFileName: url.lastPathComponent)
        return PhoneReference(name: markerName, kind: .object,
                              printedWidth: 0, contents: contents)
    }

    /// Cut a picture down to what the cable carries, or hand back the file's own
    /// bytes when it already fits. Returns `nil` only when the pixels will not read
    /// at all, or when even a small JPEG of them would not fit one frame (which
    /// takes a picture no camera produces).
    private static func fitPicture(_ contents: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(contents as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        // Untouched when it is already within both limits: a hand-made PNG stays
        // exactly the picture the sketch shipped.
        if max(image.width, image.height) <= maxPictureEdge, contents.count <= budget {
            return contents
        }
        return fitPixels(image)
    }

    /// Redraw a picture down to the cable's edge and encode it once.
    private static func fitPixels(_ image: CGImage) -> Data? {
        let longest = max(image.width, image.height)
        let scale = min(1, Double(maxPictureEdge) / Double(longest))
        let fitted = scale < 1 ? resize(image, scale: scale) ?? image : image
        // Two qualities, then give up. The first is what a photograph wants; the
        // second is the escape hatch for a picture whose detail is so dense that
        // a good JPEG of it still overflows one frame.
        for quality in [0.9, 0.6] {
            if let data = encodeJPEG(fitted, quality: quality), data.count <= budget {
                return data
            }
        }
        return nil
    }

    /// What one reference frame may spend on pixels: the wire's own payload cap,
    /// less enough room for the name and the fixed fields around it.
    private static var budget: Int { PhoneWire.maxPayloadBytes - 4096 }

    private static func resize(_ image: CGImage, scale: Double) -> CGImage? {
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
