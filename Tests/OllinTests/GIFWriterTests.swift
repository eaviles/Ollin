import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Ollin

/// The GIF writer of Ollin's own. A frame goes into the file as it arrives,
/// and the file has to be as good as the one the system writer lays down for
/// the same frames: it decodes through ImageIO frame for frame within that
/// writer's tolerance, it is no larger, and it carries the frame-to-frame
/// diffing the format is built on. Every law here is pure, no device.
@Suite
struct GIFWriterTests {

    // MARK: Fixtures

    static let side = 160

    /// A frame built pixel by pixel, as the image a writer takes and the
    /// straight RGBA bytes it stands for. Opaque frames carry no alpha channel,
    /// the way a drawn frame arrives from the renderer.
    static func frame(side: Int = side, alpha: Bool = false,
                      _ pixel: (Int, Int) -> (r: Int, g: Int, b: Int, a: Int)) -> (image: CGImage, rgba: [UInt8]) {
        var straight = [UInt8](repeating: 0, count: side * side * 4)
        var stored = straight
        for y in 0..<side {
            for x in 0..<side {
                let p = pixel(x, y)
                let i = (y * side + x) * 4
                straight[i] = UInt8(p.r); straight[i + 1] = UInt8(p.g); straight[i + 2] = UInt8(p.b)
                straight[i + 3] = UInt8(alpha ? p.a : 255)
                let a = alpha ? p.a : 255
                stored[i] = UInt8(p.r * a / 255); stored[i + 1] = UInt8(p.g * a / 255)
                stored[i + 2] = UInt8(p.b * a / 255); stored[i + 3] = UInt8(a)
            }
        }
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: info.rawValue)!
        stored.withUnsafeBytes { context.data!.copyMemory(from: $0.baseAddress!, byteCount: side * side * 4) }
        return (context.makeImage()!, straight)
    }

    /// A two-axis gradient with a white disc crossing it over `n` frames, at a
    /// brightness: the probe the system writer was measured on.
    static func gradientAndDot(_ k: Int, of n: Int, brightness: Double = 1) -> (image: CGImage, rgba: [UInt8]) {
        let s = Double(side)
        let cx = s * (0.2 + 0.6 * Double(k) / Double(max(1, n - 1))), cy = s / 2
        return frame { x, y in
            let d = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)).squareRoot()
            if d < 20 { return (Int(255 * brightness), Int(255 * brightness), Int(255 * brightness), 255) }
            return (Int(Double(x) / (s - 1) * 255 * brightness), Int(Double(y) / (s - 1) * 255 * brightness),
                    Int(128 * brightness), 255)
        }
    }

    /// A flat ground with three antialiased rings and a disc crossing it: a
    /// piece with the color structure of a drawn one, a few colors and the
    /// ramps between them.
    static func groundAndRings(_ k: Int, of n: Int) -> (image: CGImage, rgba: [UInt8]) {
        let s = Double(side)
        let cx = s * (0.2 + 0.6 * Double(k) / Double(max(1, n - 1))), cy = s * 0.5
        func mix(_ a: (Int, Int, Int), _ b: (Int, Int, Int), _ t: Double) -> (r: Int, g: Int, b: Int, a: Int) {
            (Int(Double(a.0) + (Double(b.0) - Double(a.0)) * t), Int(Double(a.1) + (Double(b.1) - Double(a.1)) * t),
             Int(Double(a.2) + (Double(b.2) - Double(a.2)) * t), 255)
        }
        return frame { x, y in
            let ground = (26, 46, 66), ink = (240, 232, 210), accent = (230, 90, 60)
            let d = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)).squareRoot()
            if d < 14 { return mix(ground, accent, min(1, max(0, 14.5 - d))) }
            var color = ground
            for radius in [30.0, 52.0, 74.0] {
                let r = ((Double(x) - s / 2) * (Double(x) - s / 2) + (Double(y) - s / 2) * (Double(y) - s / 2)).squareRoot()
                let edge = abs(r - radius) - 2.5
                if edge < 1 { let t = min(1, max(0, 1 - edge)); return mix(color, ink, t) }
            }
            color = ground
            return (color.0, color.1, color.2, 255)
        }
    }

    /// The same frames through the system writer, with the same loop and delay.
    static func systemGIF(_ images: [CGImage], to path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                          images.count, nil)!
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.04,
                                                           kCGImagePropertyGIFUnclampedDelayTime: 0.04]] as CFDictionary
        for image in images { CGImageDestinationAddImage(destination, image, properties) }
        CGImageDestinationFinalize(destination)
    }

    /// Every frame of a file as ImageIO composes it, straight RGBA at the
    /// file's own size.
    static func decode(_ path: String) throws -> (frames: [[UInt8]], width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        var frames: [[UInt8]] = []
        var width = 0, height = 0
        for k in 0..<CGImageSourceGetCount(source) {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, k, nil))
            width = image.width; height = image.height
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                            count: width * height * 4)
            frames.append(Array(bytes))
        }
        return (frames, width, height)
    }

    /// Mean absolute difference over the three color channels of the opaque
    /// pixels, in levels of 255.
    static func meanError(_ source: [UInt8], _ decoded: [UInt8]) -> Double {
        var sum = 0, n = 0
        for i in stride(from: 0, to: source.count, by: 4) where source[i + 3] == 255 {
            for c in 0..<3 { sum += abs(Int(source[i + c]) - Int(decoded[i + c])) }
            n += 3
        }
        return n == 0 ? 0 : Double(sum) / Double(n)
    }

    static func size(_ path: String) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    }

    /// What the bytes say: the blocks a decoder walks.
    struct Walk {
        struct Frame {
            var left: Int, top: Int, width: Int, height: Int
            var hasLocalTable: Bool
            var minCodeSize: Int = 0
            var isTransparent: Bool, transparentIndex: Int
            var disposal: Int, delay: Int
            var dataBytes: Int
        }
        var header: String
        var hasGlobalTable: Bool
        var globalTableSize: Int
        var globalTable: [(r: UInt8, g: UInt8, b: UInt8)] = []
        var loops: Int?
        var frames: [Frame] = []
        var hasTrailer = false
    }

    static func walk(_ path: String) throws -> Walk {
        let data = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
        func u16(_ i: Int) -> Int { Int(data[i]) | Int(data[i + 1]) << 8 }
        var walk = Walk(header: String(decoding: data[0..<6], as: UTF8.self), hasGlobalTable: false,
                        globalTableSize: 0, loops: nil)
        var p = 6
        let packed = data[p + 4]
        walk.hasGlobalTable = packed & 0x80 != 0
        walk.globalTableSize = walk.hasGlobalTable ? 2 << Int(packed & 7) : 0
        p += 7
        if walk.hasGlobalTable {
            for i in 0..<walk.globalTableSize { walk.globalTable.append((data[p + 3 * i], data[p + 3 * i + 1], data[p + 3 * i + 2])) }
            p += 3 * walk.globalTableSize
        }
        var pending: (transparent: Bool, index: Int, disposal: Int, delay: Int) = (false, 0, 0, 0)
        while p < data.count {
            switch data[p] {
            case 0x3B:
                walk.hasTrailer = true
                p = data.count
            case 0x21 where data[p + 1] == 0xF9:
                let flags = data[p + 3]
                pending = (flags & 1 != 0, Int(data[p + 6]), Int(flags >> 2 & 7), u16(p + 4))
                p += 8
            case 0x21:
                p += 2
                var body: [UInt8] = []
                while data[p] != 0 { body += data[(p + 1)...(p + Int(data[p]))]; p += 1 + Int(data[p]) }
                p += 1
                if body.starts(with: Array("NETSCAPE2.0".utf8)), body.count >= 14 {
                    walk.loops = Int(body[12]) | Int(body[13]) << 8
                }
            case 0x2C:
                let flags = data[p + 9]
                var frame = Walk.Frame(left: u16(p + 1), top: u16(p + 3), width: u16(p + 5), height: u16(p + 7),
                                       hasLocalTable: flags & 0x80 != 0,
                                       isTransparent: pending.transparent, transparentIndex: pending.index,
                                       disposal: pending.disposal, delay: pending.delay, dataBytes: 0)
                p += 10
                if frame.hasLocalTable { p += 3 * (2 << Int(flags & 7)) }
                frame.minCodeSize = Int(data[p]); p += 1
                while data[p] != 0 { frame.dataBytes += Int(data[p]); p += 1 + Int(data[p]) }
                p += 1
                walk.frames.append(frame)
            default:
                Issue.record("unknown block \(data[p]) at \(p)")
                p = data.count
            }
        }
        return walk
    }

    static func temp(_ name: String) -> String {
        NSTemporaryDirectory() + "ollin-gifwriter-\(name)-\(UUID().uuidString).gif"
    }

    // MARK: Against the system writer

    /// The probe piece through both writers: ours decodes as close to the
    /// source as the system's does, frame for frame, at the same size.
    @Test func theFileDecodesFrameForFrameWithinTheSystemWritersTolerance() throws {
        let n = 12
        let frames = (0..<n).map { Self.gradientAndDot($0, of: n) }
        let ours = Self.temp("ours"), theirs = Self.temp("theirs")
        defer { try? FileManager.default.removeItem(atPath: ours); try? FileManager.default.removeItem(atPath: theirs) }
        let writer = try GIFWriter(path: ours, width: Self.side, height: Self.side)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()
        Self.systemGIF(frames.map(\.image), to: theirs)

        let mine = try Self.decode(ours), system = try Self.decode(theirs)
        #expect(mine.frames.count == n && system.frames.count == n)
        #expect(mine.width == Self.side && mine.height == Self.side)
        for k in 0..<n {
            let a = Self.meanError(frames[k].rgba, mine.frames[k])
            let b = Self.meanError(frames[k].rgba, system.frames[k])
            #expect(a <= b * 1.25 + 0.25, "frame \(k): ours \(a) against the system's \(b)")
        }
    }

    /// A piece like a drawn one, a flat ground with antialiased rings and a
    /// disc crossing it, makes a file no larger than the system writer's.
    /// The coder is byte for byte the system's on the same index image (the
    /// system's own first frame re-coded lands on its exact byte count), and
    /// the frames after the first are cropped and diffed the same way, so
    /// what is left to differ is how the table tiles the colors.
    @Test func theFileIsNoLargerThanTheSystemWriters() throws {
        let n = 12
        let frames = (0..<n).map { Self.groundAndRings($0, of: n) }
        let ours = Self.temp("ours-size"), theirs = Self.temp("theirs-size")
        defer { try? FileManager.default.removeItem(atPath: ours); try? FileManager.default.removeItem(atPath: theirs) }
        let writer = try GIFWriter(path: ours, width: Self.side, height: Self.side)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()
        Self.systemGIF(frames.map(\.image), to: theirs)
        #expect(Self.size(ours) <= Self.size(theirs), "ours \(Self.size(ours)) B, the system's \(Self.size(theirs)) B")
        // A picture of few colors gets a table sized to them and codes as
        // narrow as the table allows, the transparent entry its last.
        let walk = try Self.walk(ours)
        #expect(walk.globalTableSize <= 128 && walk.globalTableSize >= 32, "\(walk.globalTableSize) entries")
        let width = walk.globalTableSize.trailingZeroBitCount
        #expect(walk.frames.allSatisfy { $0.minCodeSize == width && $0.transparentIndex == walk.globalTableSize - 1 })
        print("GIF sizes: ours \(Self.size(ours)) B against the system's \(Self.size(theirs)) B, table \(walk.globalTableSize)")
        let mine = try Self.decode(ours), system = try Self.decode(theirs)
        for k in 0..<n {
            let a = Self.meanError(frames[k].rgba, mine.frames[k])
            let b = Self.meanError(frames[k].rgba, system.frames[k])
            #expect(a <= b * 1.25 + 0.25, "frame \(k): ours \(a) against the system's \(b)")
        }
    }

    /// The gradient probe is the hard case for a table: every pixel its own
    /// color. There the first frame's tiling is the system's plus five
    /// percent, at a lower error (2.56 against 2.63 levels), and every frame
    /// after it is within a few bytes of the system's.
    @Test func aFullGamutPlaneIsWithinFivePercentOfTheSystemWriters() throws {
        let n = 12
        let frames = (0..<n).map { Self.gradientAndDot($0, of: n) }
        let ours = Self.temp("ours-plane"), theirs = Self.temp("theirs-plane")
        defer { try? FileManager.default.removeItem(atPath: ours); try? FileManager.default.removeItem(atPath: theirs) }
        let writer = try GIFWriter(path: ours, width: Self.side, height: Self.side)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()
        Self.systemGIF(frames.map(\.image), to: theirs)
        #expect(Double(Self.size(ours)) <= Double(Self.size(theirs)) * 1.05,
                "ours \(Self.size(ours)) B, the system's \(Self.size(theirs)) B")
        let walk = try Self.walk(ours), reference = try Self.walk(theirs)
        for (a, b) in zip(walk.frames.dropFirst(), reference.frames.dropFirst()) {
            #expect(a.width == b.width && a.height == b.height && a.left == b.left && a.top == b.top)
            #expect(abs(a.dataBytes - b.dataBytes) <= 24, "\(a.dataBytes) against \(b.dataBytes)")
        }
    }

    // MARK: The bytes

    /// A still background is left alone: after the first frame every frame is
    /// cropped to where the disc moved, transparent over the rest, with one
    /// global table and no local one, looping forever.
    @Test func aStillBackgroundIsLeftAlone() throws {
        let n = 8
        let path = Self.temp("diff")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try GIFWriter(path: path, width: Self.side, height: Self.side)
        for k in 0..<n { try writer.append(Self.gradientAndDot(k, of: n).image, delay: 0.04) }
        try writer.finish()

        let walk = try Self.walk(path)
        #expect(walk.header == "GIF89a")
        #expect(walk.hasGlobalTable)
        #expect(walk.loops == 0)
        #expect(walk.hasTrailer)
        #expect(walk.frames.count == n)
        let first = try #require(walk.frames.first)
        #expect(first.width == Self.side && first.height == Self.side && first.left == 0 && first.top == 0)
        for frame in walk.frames.dropFirst() {
            #expect(frame.width <= 60 && frame.height <= 45, "\(frame.width)×\(frame.height)")
            #expect(frame.top > 40)
        }
        for frame in walk.frames {
            #expect(frame.isTransparent && frame.transparentIndex == 255)   // 255 colors fill the table
            #expect(frame.disposal == 1)
            #expect(frame.delay == 4)
            #expect(!frame.hasLocalTable)
        }
    }

    /// A frame that changes nothing is one transparent pixel holding the delay.
    @Test func aFrameThatChangesNothingCostsAlmostNothing() throws {
        let path = Self.temp("still")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let still = Self.gradientAndDot(0, of: 1).image
        let writer = try GIFWriter(path: path, width: Self.side, height: Self.side)
        try writer.append(still, delay: 0.04)
        let afterOne = Self.size(path)
        try writer.append(still, delay: 0.04)
        try writer.append(still, delay: 0.04)
        try writer.finish()
        #expect(Self.size(path) - afterOne < 60)
        let walk = try Self.walk(path)
        #expect(walk.frames.count == 3)
        for frame in walk.frames.dropFirst() { #expect(frame.width == 1 && frame.height == 1) }
        let decoded = try Self.decode(path)
        #expect(decoded.frames.count == 3)
        #expect(decoded.frames[2] == decoded.frames[0])
    }

    /// Colors on a coarse grid, one at random per pixel: the table holds them
    /// all exactly and the coder clears its dictionary many times a frame, so
    /// the decode is byte for byte the source.
    @Test func randomColorsDecodeExactly() throws {
        let path = Self.temp("noise")
        defer { try? FileManager.default.removeItem(atPath: path) }
        var generator = SeededGenerator(seed: 7)
        let levels = [0, 51, 102, 153, 204, 255]
        let frames = (0..<3).map { _ in
            Self.frame { _, _ in
                (levels.randomElement(using: &generator)!, levels.randomElement(using: &generator)!,
                 levels.randomElement(using: &generator)!, 255)
            }
        }
        let writer = try GIFWriter(path: path, width: Self.side, height: Self.side)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()
        let decoded = try Self.decode(path)
        #expect(decoded.frames.count == 3)
        for k in 0..<3 { #expect(decoded.frames[k] == frames[k].rgba, "frame \(k)") }
    }

    /// A piece that fades in from black leaves the table its first frame
    /// chose: the shared table is replaced when a frame's colors are past
    /// it, so the file stays as close to the source as the system's, which
    /// saw every frame before choosing.
    @Test func aSharedTableIsReplacedWhenThePictureLeavesIt() throws {
        let n = 12
        let frames = (0..<n).map { Self.gradientAndDot($0, of: n, brightness: Double($0) / Double(n - 1)) }
        let ours = Self.temp("fade"), theirs = Self.temp("fade-system")
        defer { try? FileManager.default.removeItem(atPath: ours); try? FileManager.default.removeItem(atPath: theirs) }
        let writer = try GIFWriter(path: ours, width: Self.side, height: Self.side, palette: .shared)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()
        Self.systemGIF(frames.map(\.image), to: theirs)

        let walk = try Self.walk(ours)
        #expect(!walk.frames[0].hasLocalTable)
        #expect(walk.frames.contains { $0.hasLocalTable })
        let mine = try Self.decode(ours), system = try Self.decode(theirs)
        for k in 0..<n {
            let a = Self.meanError(frames[k].rgba, mine.frames[k])
            let b = Self.meanError(frames[k].rgba, system.frames[k])
            #expect(a <= b * 1.5 + 0.5, "frame \(k): ours \(a) against the system's \(b)")
        }
    }

    /// A thin thing of a new color that arrives late and stays, a pale stem
    /// growing over dark ground, is almost no energy over the frame but the
    /// whole picture where it is: its color joins the global table in place
    /// when it appears, no frame pays for a table of its own, and the stem
    /// keeps its color from then on.
    @Test func aThinNewColorThatStaysJoinsTheTable() throws {
        let n = 12
        func garden(_ k: Int) -> (image: CGImage, rgba: [UInt8]) {
            Self.frame { x, y in
                // Dark soil below, a dusk sky above, a few green tufts always there.
                let tuft = (y > 120 && y < 150 && (x / 12) % 3 == 0 && (x % 12) < 3) ? (70, 140, 60) : nil
                let ground: (Int, Int, Int) = y >= 140 ? (18, 24, 14) : (10, 14, 20)
                // From the third frame a cream stem climbs from the ground, two pixels wide.
                let height = k < 3 ? 0 : (k - 2) * 9
                if x >= 79 && x <= 80 && y >= 140 - height && y < 140 { return (236, 220, 180, 255) }
                if let tuft { return (tuft.0, tuft.1, tuft.2, 255) }
                return (ground.0, ground.1, ground.2, 255)
            }
        }
        let frames = (0..<n).map(garden)
        let path = Self.temp("garden")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try GIFWriter(path: path, width: Self.side, height: Self.side, palette: .shared)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()

        let decoded = try Self.decode(path)
        let last = decoded.frames[n - 1]
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * Self.side + x) * 4
            return (Int(last[i]), Int(last[i + 1]), Int(last[i + 2]))
        }
        let stem = at(80, 100)
        #expect(abs(stem.0 - 236) < 10 && abs(stem.1 - 220) < 10 && abs(stem.2 - 180) < 10, "stem reads \(stem)")
        let walk = try Self.walk(path)
        #expect(walk.frames.allSatisfy { !$0.hasLocalTable })
        #expect(walk.globalTableSize == 8)       // three colors filled a table of four; the stem grew it once
        #expect(walk.globalTable.contains { abs(Int($0.r) - 236) < 10 && abs(Int($0.g) - 220) < 10 && abs(Int($0.b) - 180) < 10 })
    }

    /// More new colors than the table has free entries grow it to the full
    /// 256 in place: the frames already written keep their narrow codes and
    /// decode as they did, the new ones get their colors, and still no frame
    /// carries a table of its own.
    @Test func moreNewColorsThanFitGrowTheTable() throws {
        let n = 8
        func piece(_ k: Int) -> (image: CGImage, rgba: [UInt8]) {
            Self.frame { x, y in
                let ground: (Int, Int, Int) = y >= 100 ? (18, 24, 14) : (10, 14, 20)
                let stripe = (x / 20) % 2 == 0 ? (60, 70, 90) : nil
                // From the third frame a square of many colors sits in the sky.
                if k >= 2, x >= 40, x < 100, y >= 20, y < 80 {
                    return (120 + (x - 40) * 2, 60 + (y - 20) * 3, 200, 255)
                }
                if let stripe, y < 100 { return (stripe.0, stripe.1, stripe.2, 255) }
                return (ground.0, ground.1, ground.2, 255)
            }
        }
        let frames = (0..<n).map(piece)
        let path = Self.temp("grow")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try GIFWriter(path: path, width: Self.side, height: Self.side, palette: .shared)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()

        let walk = try Self.walk(path)
        #expect(walk.globalTableSize == 256)
        #expect(walk.frames.allSatisfy { !$0.hasLocalTable })
        #expect(walk.frames[0].minCodeSize == 2 && walk.frames[0].transparentIndex == 3)
        #expect(walk.frames[n - 1].minCodeSize == 8 && walk.frames[n - 1].transparentIndex == 255)
        let decoded = try Self.decode(path)
        #expect(Self.meanError(frames[0].rgba, decoded.frames[0]) == 0)
        #expect(Self.meanError(frames[1].rgba, decoded.frames[1]) == 0)
        for k in 2..<n {
            #expect(Self.meanError(frames[k].rgba, decoded.frames[k]) < 1.5, "frame \(k)")
        }
    }

    /// A table a frame: every frame after the first carries its own, and the
    /// fade decodes within the system's tolerance.
    @Test func aTableAFrameFollowsAPieceWhoseColorsTravel() throws {
        let n = 12
        let frames = (0..<n).map { Self.gradientAndDot($0, of: n, brightness: Double($0) / Double(n - 1)) }
        let ours = Self.temp("per-frame"), theirs = Self.temp("per-frame-system")
        defer { try? FileManager.default.removeItem(atPath: ours); try? FileManager.default.removeItem(atPath: theirs) }
        let writer = try GIFWriter(path: ours, width: Self.side, height: Self.side, palette: .perFrame)
        for frame in frames { try writer.append(frame.image, delay: 0.04) }
        try writer.finish()
        Self.systemGIF(frames.map(\.image), to: theirs)

        let walk = try Self.walk(ours)
        #expect(!walk.frames[0].hasLocalTable)
        for frame in walk.frames.dropFirst() { #expect(frame.hasLocalTable) }
        let mine = try Self.decode(ours), system = try Self.decode(theirs)
        for k in 0..<n {
            let a = Self.meanError(frames[k].rgba, mine.frames[k])
            let b = Self.meanError(frames[k].rgba, system.frames[k])
            #expect(a <= b * 1.25 + 0.25, "frame \(k): ours \(a) against the system's \(b)")
        }
    }

    /// A see-through picture keeps a hard cut, and every frame is written
    /// whole with the ground restored under it, so a pixel can clear again.
    @Test func aSeeThroughPictureKeepsAHardCut() throws {
        let path = Self.temp("clear")
        defer { try? FileManager.default.removeItem(atPath: path) }
        func disc(at cx: Int) -> (image: CGImage, rgba: [UInt8]) {
            Self.frame(alpha: true) { x, y in
                let d = ((x - cx) * (x - cx) + (y - 80) * (y - 80))
                return d < 40 * 40 ? (250, 40, 40, 255) : (0, 0, 0, 0)
            }
        }
        let writer = try GIFWriter(path: path, width: Self.side, height: Self.side)
        try writer.append(disc(at: 60).image, delay: 0.1)
        try writer.append(disc(at: 100).image, delay: 0.1)
        try writer.finish()

        let decoded = try Self.decode(path)
        func alpha(_ frame: [UInt8], _ x: Int, _ y: Int) -> Int { Int(frame[(y * Self.side + x) * 4 + 3]) }
        #expect(alpha(decoded.frames[0], 4, 4) == 0 && alpha(decoded.frames[0], 60, 80) == 255)
        #expect(alpha(decoded.frames[1], 4, 4) == 0 && alpha(decoded.frames[1], 100, 80) == 255)
        // Where the first disc was and the second is not, the ground shows again.
        #expect(alpha(decoded.frames[1], 30, 80) == 0)
        let walk = try Self.walk(path)
        for frame in walk.frames {
            #expect(frame.width == Self.side && frame.height == Self.side)
            #expect(frame.disposal == 2 && frame.isTransparent)
        }
    }

    // MARK: The surface

    /// A delay is whole centiseconds; once through writes no loop block, and
    /// a count of plays is stored as the repeats after the first, which is
    /// what the system's reader turns back into the count.
    @Test func aDelayIsWholeCentisecondsAndTheLoopIsWhatWasAsked() throws {
        let once = Self.temp("once"), thrice = Self.temp("thrice")
        defer { try? FileManager.default.removeItem(atPath: once); try? FileManager.default.removeItem(atPath: thrice) }
        let still = Self.gradientAndDot(0, of: 1).image
        let a = try GIFWriter(path: once, width: Self.side, height: Self.side, loops: 1)
        try a.append(still, delay: 0.1)
        try a.finish()
        let b = try GIFWriter(path: thrice, width: Self.side, height: Self.side, loops: 3)
        try b.append(still, delay: 0.125)
        try b.finish()

        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: once) as CFURL, nil))
        let frame = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let frameGIF = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(frameGIF?[kCGImagePropertyGIFDelayTime] as? Double == 0.1)
        #expect(try Self.walk(once).loops == nil)
        let other = try Self.walk(thrice)
        #expect(other.loops == 2)
        #expect(other.frames.first?.delay == 13)
        let looped = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: thrice) as CFURL, nil))
        let properties = CGImageSourceCopyProperties(looped, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gif?[kCGImagePropertyGIFLoopCount] as? Int == 3)
    }

    /// An image of another size is drawn into the writer's, which is what
    /// `--gif-width` is.
    @Test func anImageOfAnotherSizeIsDrawnIntoTheWriters() throws {
        let path = Self.temp("scaled")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try GIFWriter(path: path, width: 80, height: 80)
        try writer.append(Self.gradientAndDot(0, of: 1).image, delay: 0.04)
        try writer.finish()
        let decoded = try Self.decode(path)
        #expect(decoded.width == 80 && decoded.height == 80)
        // The disc is at the middle left of the source and lands there scaled.
        let i = (40 * 80 + 16) * 4
        #expect(decoded.frames[0][i] > 240 && decoded.frames[0][i + 1] > 240)
    }

    @Test func aFinishedWriterTakesNoMoreFrames() throws {
        let path = Self.temp("finished")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try GIFWriter(path: path, width: 8, height: 8)
        try writer.finish()
        #expect(throws: GIFWriter.WriteError.self) {
            try writer.append(Self.gradientAndDot(0, of: 1).image, delay: 0.04)
        }
        #expect(throws: GIFWriter.WriteError.self) {
            try GIFWriter(path: path, width: 0, height: 8)
        }
    }

    @Test func theFlagSpellsBothTables() {
        #expect(GIFWriter.Palette(rawValue: "shared") == .shared)
        #expect(GIFWriter.Palette(rawValue: "per-frame") == .perFrame)
        #expect(GIFWriter.Palette(rawValue: "perFrame") == nil)
    }
}

/// A small deterministic generator for the fixtures.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
