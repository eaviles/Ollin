import Foundation
import Metal

/// An OpenEXR file, written by hand.
///
/// Why by hand, when the system can write one: the system writer takes a
/// `CGImage`, and a `CGImage` carries four channels and a color space. It passes
/// the numbers through a profile conversion on the way out (a component of 8.0
/// came back as 8.0001, with 0.0001 appearing in channels that held nothing),
/// and it has nowhere to put a fifth channel. Both matter here. This is the
/// frame before the tone map, so the numbers are the point, and depth has to
/// ride in the same file to be any use in a compositor.
///
/// What is written is the simplest thing every reader handles: one part,
/// scanline, uncompressed, one block per row, channels in the alphabetical order
/// the format requires (`A`, `B`, `G`, `R`, then `Z`). Color is half, which is
/// what the renderer already holds, so no component is converted on the way out;
/// depth is 32-bit float, since distance needs the range.
struct OpenEXRFile {
    /// Canvas width in pixels.
    var width: Int
    /// Canvas height in pixels.
    var height: Int
    /// Half-float RGBA, four components per pixel, row-major from the top,
    /// premultiplied linear light. Taken from the renderer as it is.
    var rgba: [UInt16]
    /// Distance from the eye per pixel, row-major from the top, written as `Z`.
    /// Nil leaves the channel out.
    var depth: [Float]?
    /// Written as the standard `comments` attribute, which is where the recipe
    /// that reproduces the frame goes (the PNG writes the same text into its own
    /// text chunks).
    var comments: String?

    /// The channels this file holds, in the order they are written.
    var channelNames: [String] { depth == nil ? ["A", "B", "G", "R"] : ["A", "B", "G", "R", "Z"] }

    /// The file's bytes.
    func encoded() -> Data {
        var out = Data()
        out.reserveCapacity(width * height * (depth == nil ? 8 : 12) + 1024)

        func u8(_ v: UInt8) { out.append(v) }
        func i32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func f32(_ v: Float) { withUnsafeBytes(of: v.bitPattern.littleEndian) { out.append(contentsOf: $0) } }
        func cstr(_ s: String) { out.append(contentsOf: Array(s.utf8)); u8(0) }
        /// One header attribute: its name, its type, then its size in bytes,
        /// which is only known once the body has been written.
        func attribute(_ name: String, _ type: String, _ body: () -> Void) {
            cstr(name)
            cstr(type)
            let sizeAt = out.count
            i32(0)
            let start = out.count
            body()
            withUnsafeBytes(of: Int32(out.count - start).littleEndian) { bytes in
                for (i, byte) in bytes.enumerated() { out[sizeAt + i] = byte }
            }
        }

        i32(20000630)                                    // the format's magic number
        i32(2)                                           // version 2, no flags: one scanline part

        attribute("channels", "chlist") {
            for name in channelNames {
                cstr(name)
                i32(name == "Z" ? 2 : 1)                 // 2 is 32-bit float, 1 is half
                u8(0); u8(0); u8(0); u8(0)               // pLinear, then three reserved bytes
                i32(1); i32(1)                           // x and y sampling: every pixel
            }
            u8(0)                                        // the channel list ends with a null name
        }
        attribute("compression", "compression") { u8(0) }        // none
        attribute("dataWindow", "box2i") {
            i32(0); i32(0); i32(Int32(width - 1)); i32(Int32(height - 1))
        }
        attribute("displayWindow", "box2i") {
            i32(0); i32(0); i32(Int32(width - 1)); i32(Int32(height - 1))
        }
        attribute("lineOrder", "lineOrder") { u8(0) }            // increasing y, so the top row first
        attribute("pixelAspectRatio", "float") { f32(1) }
        attribute("screenWindowCenter", "v2f") { f32(0); f32(0) }
        attribute("screenWindowWidth", "float") { f32(1) }
        if let comments, !comments.isEmpty {
            attribute("comments", "string") { out.append(contentsOf: Array(comments.utf8)) }
        }
        u8(0)                                            // the header ends with a null name

        // Uncompressed means one scanline per block, so the offset table holds one
        // entry per row. The offsets are only known as the rows are written, so the
        // table is reserved here and filled in at the end.
        let tableAt = out.count
        for _ in 0..<height { u64(0) }

        let rowBytes = width * 8 + (depth == nil ? 0 : width * 4)
        var offsets = [UInt64]()
        offsets.reserveCapacity(height)
        for y in 0..<height {
            offsets.append(UInt64(out.count))
            i32(Int32(y))                                // the row this block holds
            i32(Int32(rowBytes))
            for name in channelNames {
                if name == "Z" {
                    guard let depth else { continue }
                    for x in 0..<width { f32(depth[y * width + x]) }
                } else {
                    // The half components sit interleaved in `rgba`; a scanline
                    // block wants each channel's row whole.
                    let component = OpenEXRFile.componentIndex(of: name)
                    for x in 0..<width {
                        let half = rgba[(y * width + x) * 4 + component]
                        withUnsafeBytes(of: half.littleEndian) { out.append(contentsOf: $0) }
                    }
                }
            }
        }
        for (row, offset) in offsets.enumerated() {
            withUnsafeBytes(of: offset.littleEndian) { bytes in
                for (i, byte) in bytes.enumerated() { out[tableAt + row * 8 + i] = byte }
            }
        }
        return out
    }

    /// Where a channel's component sits in an interleaved RGBA pixel.
    static func componentIndex(of channel: String) -> Int {
        switch channel {
        case "R": return 0
        case "G": return 1
        case "B": return 2
        default: return 3
        }
    }
}

// MARK: - Writing a frame

extension OllinApp {

    /// What a written EXR turned out to hold, for the line the export prints.
    struct EXRWritten: Sendable, Hashable {
        /// The channels in the file, in written order.
        public let channels: [String]
        /// The file's size in bytes.
        public let bytes: Int
        /// The brightest color component in the frame, as a multiple of white.
        /// Over 1 means the file carries light a PNG would have clipped.
        public let peak: Double
        /// The nearest and farthest distances the depth channel holds, when there
        /// is one.
        public let depthRange: ClosedRange<Double>?
    }

    /// Write a captured linear frame as an OpenEXR file. Returns what the file
    /// holds, or nil when writing failed.
    static func writeEXR(_ frame: MetalRenderer.LinearFrame, to path: String,
                         recipe: String?) -> EXRWritten? {
        let count = frame.width * frame.height * 4
        let halves = frame.color.contents().bindMemory(to: UInt16.self, capacity: count)
        let rgba = [UInt16](UnsafeBufferPointer(start: halves, count: count))
        let file = OpenEXRFile(width: frame.width, height: frame.height, rgba: rgba,
                              depth: frame.depth, comments: recipe)
        let data = file.encoded()
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Ollin: could not write \(path): \(error)\n".utf8))
            return nil
        }
        // The peak is read off the color channels only, and says whether the file
        // is carrying anything the 8-bit formats could not.
        var peak: Float = 0
        for i in stride(from: 0, to: count, by: 4) {
            for c in 0..<3 {
                let value = Float(Float16(bitPattern: rgba[i + c]))
                if value.isFinite { peak = max(peak, value) }
            }
        }
        var range: ClosedRange<Double>?
        if let depth = frame.depth, let low = depth.min(), let high = depth.max() {
            range = Double(low)...Double(high)
        }
        return EXRWritten(channels: file.channelNames, bytes: data.count,
                          peak: Double(peak), depthRange: range)
    }

    /// The sentence an export prints about a written EXR: what the file holds,
    /// and what it is carrying that an 8-bit file could not.
    static func exrNote(_ written: EXRWritten, width: Int, height: Int) -> String {
        let megabytes = Double(written.bytes) / 1_000_000
        var note = "\(width)×\(height), \(written.channels.joined()) linear, "
            + String(format: "%.1f MB", megabytes)
        if written.peak > 1.001 {
            note += String(format: ", peak %.2f× white", written.peak)
        }
        if let range = written.depthRange {
            note += String(format: ", depth %.3f…%.3f", range.lowerBound, range.upperBound)
        }
        return note
    }

    /// Render one frame of `sketch` headlessly and write it as an OpenEXR file:
    /// the frame in linear light, before the tone map that fits it into a screen's
    /// range, before the dither, and before the 8-bit quantization every other
    /// still export ends at. Light brighter than white stays in the file, a
    /// see-through canvas keeps its coverage in the alpha channel, and a frame
    /// drawn through a 3D camera carries the distance from the eye as a `Z`
    /// channel beside the color.
    ///
    /// The file is uncompressed, so it is large: a 1080 square frame with depth
    /// is about 14 MB.
    public static func exportEXR(_ sketch: Sketch, to path: String, frame: Int = 0,
                                 fps: Double = 60, quality: RenderQuality = .detail) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = headlessRenderer(for: sketch, device: device) else {
            fatalError("Ollin: failed to render the frame for export (no Metal device?)")
        }
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        renderer.automaticQuality = quality
        renderer.pathTracing = pathTracedExport
        renderer.renderScale = exportRenderScale
        renderer.capturesLinearFrame = true
        _ = renderImage(of: sketch, frame: frame, fps: fps, renderer: renderer)
        guard let linear = renderer.lastLinearFrame else {
            fatalError("Ollin: failed to render the frame for export")
        }
        let recipe = ExportMetadata.capture(from: sketch, frame: frame, fps: fps).recipe
        guard let written = writeEXR(linear, to: path, recipe: recipe) else {
            fatalError("Ollin: failed to write \(path)")
        }
        print("Ollin: exported frame \(frame) → \(path) "
              + "(\(exrNote(written, width: linear.width, height: linear.height)))")
    }
}
