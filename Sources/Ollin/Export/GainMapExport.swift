import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// A still image has nowhere to put brightness above white. PNG and HEIC both
// stop at 1.0, so an `extended` frame's highlights are flattened to white on the
// way out, and the one thing that setting exists for is the one thing the file
// cannot hold.
//
// A gain map is the way a still keeps them. The file carries two things: an
// ordinary picture that every reader already understands, and a second image
// recording, per pixel, how much light was thrown away making it. A display with
// headroom multiplies one by the other and gets the frame back; a display
// without headroom shows the ordinary picture and never knows. The rules for
// what the second image means are ISO 21496-1.
//
// Three decisions in here are load-bearing, and each was settled by measuring:
//
// - **The gain map is worked out here rather than by Core Image.** Asked to
//   derive one from a pair of images, it picks the ceiling from a percentile of
//   the frame rather than from the peak, so a *small* highlight is thrown away:
//   measured, a highlight covering 0.1% of the frame at 4x white came back at
//   0.99x, which is the highlight gone. Small highlights are the ordinary case
//   in a sketch (a lamp core, a spark, a specular hit), so the ceiling here is
//   the frame's true peak. Declaring `contentHeadroom` does not change what it
//   writes, and handing it a ready-made map writes the older auxiliary type
//   instead of the standard one, so the file is assembled through ImageIO.
// - **The map carries a gain per channel rather than one for all three.** A
//   single channel can only scale a pixel's color, and a bright color clamps
//   unevenly: an amber core of (4.0, 2.2, 0.72) clamps to (1, 1, 0.72), which
//   needs three different multipliers. Measured with one channel, the green
//   came back 81% high and the blue 300% high. With three, every channel lands
//   within 0.6%.
// - **The base picture is the frame clamped at white**, which is exactly what
//   the PNG export writes. So the fallback everybody sees is the shipped still,
//   and the gain map is an addition to it.

public extension OllinApp {

    /// What a still carried out of the sketch.
    struct StillExport: Sendable, Hashable {
        /// The brightest component the frame held, as a multiple of white. 1.0
        /// means the frame never went above white.
        public let peak: Double
        /// Whether a gain map went with the picture, carrying the values above
        /// white. False when the frame had none to carry.
        public let keepsHighlights: Bool
    }

    /// Write `image` as a HEIC still, keeping brightness above white in an ISO
    /// gain map when the frame has any.
    ///
    /// The picture in the file is the frame clamped at white, so any reader
    /// shows what the PNG export would have written. Where the frame ran
    /// brighter, a gain map beside it records by how much, and a display with
    /// headroom puts it back.
    ///
    /// Returns `nil` if the file could not be written.
    @discardableResult
    static func writeHEIC(_ image: CGImage, to path: String) -> StillExport? {
        writeHEIC(image, to: path, recipe: nil)
    }
}

extension OllinApp {

    /// The write behind the public one, plus the reproduction recipe every
    /// export carries (the `Software` and user-comment fields here, matching
    /// what the PNG puts in its text chunks).
    static func writeHEIC(_ image: CGImage, to path: String, recipe: String?) -> StillExport? {
        let context = GainMap.makeContext()
        // Only a float frame can hold anything above white. An 8-bit one goes
        // into the file as it stands, which is the whole story for an ordinary
        // sketch.
        let frame = GainMap.floatSamples(of: image, context: context)
        let built = frame.flatMap { GainMap.build(from: $0, context: context) }
        let base = built?.base ?? image
        let peak = frame.map(\.peak) ?? 1

        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, 1, nil) else { return nil }

        var exif: [CFString: Any] = [:]
        if let recipe { exif[kCGImagePropertyExifUserComment] = recipe }
        var properties: [CFString: Any] = [
            // 1.0 asks for lossless, so a still export stays as faithful as the
            // PNG it replaces rather than quietly costing quality.
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: "Ollin"],
        ]
        if !exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif }

        CGImageDestinationAddImage(destination, base, properties as CFDictionary)
        if let info = built?.auxiliaryInfo {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination, kCGImageAuxiliaryDataTypeISOGainMap, info as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return StillExport(peak: Double(peak), keepsHighlights: built?.auxiliaryInfo != nil)
    }
}

/// Building an ISO 21496-1 gain map from a frame that runs above white.
enum GainMap {

    /// The frame's pixels, in the extended linear space the wide-gamut present
    /// pass writes, plus the brightest component in it.
    struct Samples {
        var pixels: [Float]        // RGBA, four per pixel
        var width: Int
        var height: Int
        var peak: Float
    }

    /// The picture that goes in the file, and the gain map beside it. The map
    /// is absent when the frame never went above white, which leaves an
    /// ordinary wide-gamut still.
    struct Built {
        var base: CGImage
        var auxiliaryInfo: [CFString: Any]?
    }

    /// The namespace the gain map's metadata lives in.
    private static let namespaceURI = "http://ns.apple.com/HDRToneMap/1.0/"
    private static let prefixName = "HDRToneMap"

    /// The small constant the reconstruction adds to both sides before taking
    /// the ratio, so a black pixel has a defined gain rather than a division by
    /// zero. The standard's own form; the value is the one written into the
    /// file, so encode and decode agree whatever it is.
    private static let offset: Float = 1.0 / 65536

    /// A context for the two passes a write makes. Extended linear Display P3 is
    /// the space the frame is already in, so reading it back is a copy rather
    /// than a conversion. Built per export (there is one per file written), not
    /// held in a global, so nothing is shared across threads.
    static func makeContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) as Any,
            .workingFormat: CIFormat.RGBAh,
        ])
    }

    /// Read `image` back as floats, or `nil` if it is not a float frame (an
    /// 8-bit one cannot hold anything above white, so there is nothing to do).
    static func floatSamples(of image: CGImage, context: CIContext) -> Samples? {
        guard image.bitsPerComponent == 16,
              image.bitmapInfo.contains(.floatComponents),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [Float](repeating: 0, count: width * height * 4)
        let source = CIImage(cgImage: image)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(source, toBitmap: base, rowBytes: width * 16,
                           bounds: source.extent, format: .RGBAf, colorSpace: space)
        }
        var peak: Float = 0
        for p in stride(from: 0, to: pixels.count, by: 4) {
            peak = max(peak, max(pixels[p], max(pixels[p + 1], pixels[p + 2])))
        }
        return Samples(pixels: pixels, width: width, height: height, peak: peak)
    }

    /// The picture for `samples`, with a gain map when the frame went above
    /// white. Every float frame gets its picture built the same way, so a
    /// wide-gamut still and an extended one differ only by the map.
    static func build(from samples: Samples, context: CIContext) -> Built? {
        guard let base = clampedBase(of: samples, context: context) else { return nil }
        let maxStops = log2(max(samples.peak, 1))
        guard maxStops > 0.0001, let metadata = metadata(maxStops: maxStops) else {
            return Built(base: base, auxiliaryInfo: nil)
        }

        // One gain per channel, packed the way the description below declares.
        // Rows are padded to a 16-byte boundary, which is what the imaging
        // stack's own maps do.
        let bytesPerRow = (samples.width * 4 + 15) & ~15
        var bytes = [UInt8](repeating: 255, count: bytesPerRow * samples.height)
        for y in 0..<samples.height {
            let row = y * bytesPerRow
            for x in 0..<samples.width {
                let p = (y * samples.width + x) * 4
                let out = row + x * 4
                bytes[out + 0] = encode(samples.pixels[p + 2], maxStops: maxStops)   // blue
                bytes[out + 1] = encode(samples.pixels[p + 1], maxStops: maxStops)   // green
                bytes[out + 2] = encode(samples.pixels[p + 0], maxStops: maxStops)   // red
                bytes[out + 3] = 255
            }
        }
        let info: [CFString: Any] = [
            kCGImageAuxiliaryDataInfoData: Data(bytes) as CFData,
            kCGImageAuxiliaryDataInfoDataDescription: [
                "Width": samples.width, "Height": samples.height,
                "BytesPerRow": bytesPerRow,
                "PixelFormat": 0x4247_5241,      // 'BGRA', one gain per channel
            ] as CFDictionary,
            kCGImageAuxiliaryDataInfoMetadata: metadata,
        ]
        return Built(base: base, auxiliaryInfo: info)
    }

    /// One channel's gain, as the fraction of the frame's ceiling it sits at.
    /// The base is this channel clamped at white, so the gain is what turns one
    /// back into the other.
    private static func encode(_ value: Float, maxStops: Float) -> UInt8 {
        let clamped = min(max(value, 0), 1)
        let stops = log2((max(value, 0) + offset) / (clamped + offset))
        let fraction = min(max(stops / maxStops, 0), 1)
        return UInt8((fraction * 255).rounded())
    }

    /// The picture the file shows: the frame clamped at white, in 8-bit Display
    /// P3. The same pixels the PNG export writes.
    private static func clampedBase(of samples: Samples, context: CIContext) -> CGImage? {
        var clamped = samples.pixels
        for i in 0..<clamped.count { clamped[i] = min(max(clamped[i], 0), 1) }
        let data = clamped.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let linear = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3),
              let display = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.floatComponents.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue
                                | CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let float = CGImage(width: samples.width, height: samples.height,
                                  bitsPerComponent: 32, bitsPerPixel: 128,
                                  bytesPerRow: samples.width * 16, space: linear,
                                  bitmapInfo: info, provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: samples.width, height: samples.height)
        return context.createCGImage(CIImage(cgImage: float), from: bounds,
                                     format: .RGBA8, colorSpace: display)
    }

    // MARK: - Metadata

    /// How the reader turns the map back into light: the ceiling the map's top
    /// stands for, the gamma along the way, and the offsets the ratio was taken
    /// with. One entry per channel, because the map carries three.
    private static func metadata(maxStops: Float) -> CGImageMetadata? {
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(metadata, namespaceURI as CFString,
                                                  prefixName as CFString, nil)
        let channels = (0..<3).compactMap { channelTag(index: $0, maxStops: maxStops) }
        guard channels.count == 3,
              let list = tag("ChannelMetadata", .arrayOrdered, channels as CFArray),
              let version = tag("Version", .string, "1" as CFString),
              let baseHeadroom = numberTag("BaseHeadroom", 0),
              let alternateHeadroom = numberTag("AlternateHeadroom", maxStops),
              let working = tag("BaseColorIsWorkingColor", .string, "True" as CFString)
        else { return nil }
        let written = set(metadata, "HDRToneMap:Version", version)
            && set(metadata, "HDRToneMap:BaseHeadroom", baseHeadroom)
            && set(metadata, "HDRToneMap:AlternateHeadroom", alternateHeadroom)
            && set(metadata, "HDRToneMap:ChannelMetadata", list)
            && set(metadata, "HDRToneMap:BaseColorIsWorkingColor", working)
        return written ? metadata : nil
    }

    private static func channelTag(index: Int, maxStops: Float) -> CGImageMetadataTag? {
        guard let low = numberTag("GainMapMin", 0),
              let high = numberTag("GainMapMax", maxStops),
              let gamma = numberTag("Gamma", 1),
              let baseOffset = numberTag("BaseOffset", offset),
              let alternateOffset = numberTag("AlternateOffset", offset) else { return nil }
        return tag("ChannelMetadata[\(index)]", .structure, [
            "GainMapMin" as CFString: low, "GainMapMax" as CFString: high,
            "Gamma" as CFString: gamma, "BaseOffset" as CFString: baseOffset,
            "AlternateOffset" as CFString: alternateOffset,
        ] as CFDictionary)
    }

    private static func tag(_ name: String, _ type: CGImageMetadataType,
                            _ value: CFTypeRef) -> CGImageMetadataTag? {
        CGImageMetadataTagCreate(namespaceURI as CFString, prefixName as CFString,
                                 name as CFString, type, value)
    }

    private static func numberTag(_ name: String, _ value: Float) -> CGImageMetadataTag? {
        tag(name, .string, String(format: "%f", value) as CFString)
    }

    private static func set(_ metadata: CGMutableImageMetadata, _ path: String,
                            _ tag: CGImageMetadataTag) -> Bool {
        CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
    }
}
