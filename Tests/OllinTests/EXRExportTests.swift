import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Ollin

/// `--export-exr` writes the frame as the renderer composited it: linear light,
/// half-float components free to run above white, coverage in the alpha channel,
/// and the distance from the eye as a `Z` channel when the frame was drawn
/// through a 3D camera. The laws here read the written file back with a parser of
/// their own (never the writer's structures) and, for the color channels, with
/// the system's own OpenEXR reader as a second opinion.
@Suite
@MainActor
struct EXRExportTests {

    // MARK: Reading a file back

    /// An OpenEXR file parsed from its bytes: enough of the format to check what
    /// a writer claimed to put there.
    struct ParsedEXR {
        var version: Int32
        var attributes: [String: (type: String, bytes: [UInt8])] = [:]
        /// Channel name, sample type (1 half, 2 float), in file order.
        var channels: [(name: String, type: Int32)] = []
        var dataWindow: (xMin: Int32, yMin: Int32, xMax: Int32, yMax: Int32) = (0, 0, 0, 0)
        var compression: UInt8 = 255
        /// Every channel's samples, row-major from the top, as Doubles.
        var samples: [String: [Double]] = [:]
        /// The byte offset each scanline block started at, as the table said.
        var offsets: [UInt64] = []

        var width: Int { Int(dataWindow.xMax - dataWindow.xMin) + 1 }
        var height: Int { Int(dataWindow.yMax - dataWindow.yMin) + 1 }

        func at(_ channel: String, x: Int, y: Int) -> Double {
            samples[channel]![y * width + x]
        }

        func text(_ attribute: String) -> String? {
            guard let value = attributes[attribute] else { return nil }
            return String(decoding: value.bytes, as: UTF8.self)
        }
    }

    /// Parse a scanline OpenEXR file: the header, the offset table, and every
    /// sample of every channel.
    func parse(_ url: URL) throws -> ParsedEXR {
        let data = try Data(contentsOf: url)
        var i = 0
        func u8() -> UInt8 { defer { i += 1 }; return data[i] }
        func i32() -> Int32 {
            defer { i += 4 }
            return data[i..<(i + 4)].withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        }
        func u64() -> UInt64 {
            defer { i += 8 }
            return data[i..<(i + 8)].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        }
        func f32() -> Float {
            defer { i += 4 }
            return data[i..<(i + 4)].withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        }
        func f16() -> Float {
            defer { i += 2 }
            let bits = data[i..<(i + 2)].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            return Float(Float16(bitPattern: bits))
        }
        func cstr() -> String {
            var bytes = [UInt8]()
            while data[i] != 0 { bytes.append(data[i]); i += 1 }
            i += 1
            return String(decoding: bytes, as: UTF8.self)
        }

        #expect(i32() == 20000630, "the file does not start with the format's magic number")
        var out = ParsedEXR(version: i32())
        while true {
            let name = cstr()
            if name.isEmpty { break }
            let type = cstr()
            let size = Int(i32())
            let bytes = [UInt8](data[i..<(i + size)])
            let after = i + size
            switch (name, type) {
            case ("channels", _):
                while data[i] != 0 {
                    let channel = cstr()
                    let sampleType = i32()
                    i += 4                                  // pLinear and three reserved bytes
                    i += 8                                  // x and y sampling
                    out.channels.append((channel, sampleType))
                }
            case ("dataWindow", _):
                out.dataWindow = (i32(), i32(), i32(), i32())
            case ("compression", _):
                out.compression = u8()
            default:
                break
            }
            out.attributes[name] = (type, bytes)
            i = after
        }

        let rows = out.height
        for _ in 0..<rows { out.offsets.append(u64()) }
        for channel in out.channels { out.samples[channel.name] = [] }
        for row in 0..<rows {
            #expect(UInt64(i) == out.offsets[row], "scanline \(row) is not where the table says")
            #expect(i32() == Int32(row), "scanline \(row) carries the wrong row number")
            let declared = Int(i32())
            let started = i
            for channel in out.channels {
                for _ in 0..<out.width {
                    let value = channel.type == 2 ? f32() : f16()
                    out.samples[channel.name]!.append(Double(value))
                }
            }
            #expect(i - started == declared, "scanline \(row) holds a different size than it declared")
        }
        #expect(i == data.count, "the file has bytes past its last scanline")
        return out
    }

    // MARK: Sketches

    /// A flat canvas: one ground color, and an optional pair of overlapping white
    /// disks summed together so the frame runs above white.
    private final class Flat: Sketch {
        var ground = Color(white: 0.5)
        var sums = false
        var translucent = false
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            background(ground)
            noStroke()
            if sums {
                blendMode(.add)
                fill(.white)
                drawCircle(24, 32, 18)
                drawCircle(40, 32, 18)
            }
            if translucent {
                fill(Color(red: 1, green: 0, blue: 0, alpha: 0.5))
                drawCircle(32, 32, 20)
            }
        }
    }

    /// A box of known size at the origin, seen from a known distance down +z.
    private final class Boxed: Sketch {
        var eyeDistance = 10.0
        var far = 100.0
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            background(.black)
            perspective(eye: Vector3(0, 0, eyeDistance), target: .zero, near: 0.1, far: far)
            fill(.white)
            drawBox(size: 2)
        }
    }

    private func scratch(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-exr-\(name)-\(UUID().uuidString).exr")
    }

    // MARK: The file

    @Test func theHeaderNamesWhatTheFrameCarries() throws {
        let url = scratch("header")
        defer { try? FileManager.default.removeItem(at: url) }
        OllinApp.exportEXR(Flat(), to: url.path)

        let file = try parse(url)
        #expect(file.version == 2)
        #expect(file.channels.map(\.name) == ["A", "B", "G", "R"])
        #expect(file.channels.allSatisfy { $0.type == 1 })       // half
        #expect(file.compression == 0)                           // none
        #expect(file.width == 64 && file.height == 64)
        #expect(file.attributes["lineOrder"]?.bytes == [0])      // the top row first
        #expect(file.attributes["screenWindowWidth"] != nil)
    }

    @Test func theSystemsOwnReaderOpensIt() throws {
        let url = scratch("system")
        defer { try? FileManager.default.removeItem(at: url) }
        OllinApp.exportEXR(Flat(), to: url.path)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 64 && image.height == 64)
        #expect(image.bitsPerComponent == 16)
        #expect(image.bitmapInfo.contains(.floatComponents))
    }

    @Test func theRecipeTravelsInTheComments() throws {
        let url = scratch("recipe")
        defer { try? FileManager.default.removeItem(at: url) }
        OllinApp.exportEXR(Flat(), to: url.path, frame: 3)

        let file = try parse(url)
        let comments = try #require(file.text("comments"))
        #expect(comments.contains("\"tool\":\"Ollin\""))
        #expect(comments.contains("\"frame\":3"))
    }

    // MARK: What the numbers mean

    @Test func theFileHoldsLinearLightWhereThePNGHoldsTheEncodedByte() throws {
        let url = scratch("linear")
        let png = url.deletingPathExtension().appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: png)
        }
        let ground = Color(white: 0.5)
        OllinApp.exportEXR(Flat(), to: url.path)
        OllinApp.export(Flat(), to: png.path)

        // The same pixel, two files: the EXR carries the light, the PNG the byte
        // a screen wants. 0.5 encoded is 0.2140 of the light.
        let file = try parse(url)
        #expect(abs(file.at("R", x: 2, y: 2) - Color.srgbToLinear(0.5)) < 0.002)
        #expect(abs(file.at("G", x: 2, y: 2) - Color.srgbToLinear(0.5)) < 0.002)
        #expect(file.at("A", x: 2, y: 2) == 1)
        #expect(ground.red == 0.5)

        let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try #require(image.dataProvider?.data as Data?)
        // BGRA, and the present pass dithers, so the byte may sit either side.
        let blue = Int(bytes[2 * image.bytesPerRow + 2 * 4])
        #expect(abs(blue - 128) <= 2, "the PNG byte was \(blue)")
    }

    @Test func lightAboveWhiteSurvivesTheFileAndClipsInThePNG() throws {
        let url = scratch("peak")
        let png = url.deletingPathExtension().appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: png)
        }
        let bright = Flat()
        bright.ground = .black
        bright.sums = true
        OllinApp.exportEXR(bright, to: url.path)
        let again = Flat()
        again.ground = .black
        again.sums = true
        OllinApp.export(again, to: png.path)

        // Where the two disks overlap, two whites were summed.
        let file = try parse(url)
        let overlap = file.at("R", x: 32, y: 32)
        #expect(overlap > 1.8 && overlap < 2.2, "the overlap read \(overlap)")
        // x 9 sits inside the left disk alone (the two overlap from x 22 on), so
        // one coat of white reads as exactly white.
        let single = file.at("R", x: 9, y: 32)
        #expect(single > 0.98 && single < 1.02, "one coat read \(single)")

        let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try #require(image.dataProvider?.data as Data?)
        let center = Int(bytes[32 * image.bytesPerRow + 32 * 4 + 2])
        let edge = Int(bytes[32 * image.bytesPerRow + 9 * 4 + 2])
        // One coat of white and two read as the same pixel in the PNG, within the
        // one level the dither moves a clipped white by, while the EXR above tells
        // them apart by a factor of two. That gap is the whole point of the file.
        #expect(center >= 254, "the PNG had somewhere left to go: \(center)")
        #expect(abs(center - edge) <= 1, "the PNG kept them apart: \(center) against \(edge)")
        #expect(overlap / single > 1.9, "the EXR did not keep them apart")
    }

    @Test func aSeeThroughCanvasKeepsItsCoverage() throws {
        let url = scratch("clear")
        defer { try? FileManager.default.removeItem(at: url) }
        let cut = Flat()
        cut.ground = .clear
        cut.translucent = true
        OllinApp.exportEXR(cut, to: url.path)

        let file = try parse(url)
        #expect(file.at("A", x: 1, y: 1) == 0, "the bare canvas should be empty")
        #expect(file.at("R", x: 1, y: 1) == 0)
        // Half-covered red: alpha a half, and the color premultiplied by it, which
        // is the convention this format reads by.
        let alpha = file.at("A", x: 32, y: 32)
        #expect(abs(alpha - 0.5) < 0.01, "the disk's alpha read \(alpha)")
        let red = file.at("R", x: 32, y: 32)
        #expect(abs(red - 0.5) < 0.01, "premultiplied red read \(red)")
        #expect(file.at("G", x: 32, y: 32) == 0)
    }

    // MARK: Depth

    @Test func aFlatFrameWritesNoDepthChannel() throws {
        let url = scratch("flat")
        defer { try? FileManager.default.removeItem(at: url) }
        OllinApp.exportEXR(Flat(), to: url.path)
        #expect(try parse(url).channels.map(\.name) == ["A", "B", "G", "R"])
    }

    @Test func theDepthChannelIsDistanceFromTheEye() throws {
        let url = scratch("depth")
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = Boxed()
        OllinApp.exportEXR(scene, to: url.path)

        let file = try parse(url)
        #expect(file.channels.map(\.name) == ["A", "B", "G", "R", "Z"])
        #expect(file.channels.last?.type == 2, "depth needs the range of a 32-bit float")
        // The box is two units across at the origin, so its front face stands one
        // unit toward an eye ten units away.
        let front = file.at("Z", x: 32, y: 32)
        #expect(abs(front - 9) < 0.05, "the front face read \(front)")
        // A corner of the canvas the box never reached keeps the cleared depth,
        // which is the camera's far plane exactly.
        #expect(file.at("Z", x: 0, y: 0) == 100)
        // And the face is nearer than the canvas edge, which is what a compositor
        // reads a Z channel for.
        #expect(front < file.at("Z", x: 0, y: 0))
    }

    @Test func aSupersampledExportStillWritesCanvasSizedDepth() throws {
        let url = scratch("scaled")
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = OllinApp.exportRenderScale
        OllinApp.exportRenderScale = 2
        defer { OllinApp.exportRenderScale = previous }
        OllinApp.exportEXR(Boxed(), to: url.path)

        let file = try parse(url)
        #expect(file.width == 64 && file.height == 64)
        #expect(file.samples["Z"]?.count == 64 * 64)
        // Each pixel took the nearest of the samples under it, so the front face
        // is still the front face.
        #expect(abs(file.at("Z", x: 32, y: 32) - 9) < 0.05)
        #expect(file.at("Z", x: 0, y: 0) == 100)
    }

    // MARK: A sequence

    @Test func aSequenceWritesOneLinearFilePerFrame() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-exr-sequence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        OllinApp.exportSequence(Flat(), to: directory.path, frames: 2, fps: 30, writesEXR: true)

        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(written == ["frame-00001.exr", "frame-00002.exr"])
        for name in written {
            let file = try parse(directory.appendingPathComponent(name))
            #expect(file.width == 64)
            #expect(abs(file.at("R", x: 2, y: 2) - Color.srgbToLinear(0.5)) < 0.002)
        }
    }
}
