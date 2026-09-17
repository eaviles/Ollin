import Foundation
import CoreGraphics

/// Writes an animated GIF a frame at a time, into an open file.
///
/// A frame is quantized, compared with the one before it, and coded into the
/// file the moment it arrives, so the writer holds a few frame-sized buffers
/// whatever the length: a loop of any number of frames costs the memory of
/// one. `OllinApp.exportGIF` and `--export-gif` run on it, and a sketch or an
/// extension can drive it with any `CGImage`, which is drawn into the writer's
/// own size and color space on the way in:
///
/// ```swift
/// let gif = try GIFWriter(path: "out.gif", width: 540, height: 540)
/// for image in images { try gif.append(image, delay: 0.04) }
/// try gif.finish()
/// ```
///
/// The format holds 256 colors a frame. `Palette.shared`, the default, chooses
/// one table from the first frame by median cut and keeps it for every frame
/// after, so a color never shifts between frames; colors that arrive later
/// join that table as they come, until the format's 256 are spent, after which
/// a frame that needs more gets a table of its own that the frames after it
/// share. `.perFrame` chooses a table for every frame from that frame alone.
///
/// A pixel that did not change since the frame before is left transparent
/// over it and the frame is cropped to what did, which is what keeps a still
/// background cheap. A see-through picture, one whose first frame has clear
/// pixels, keeps them as a hard cut instead, and every frame is written whole
/// so a pixel can clear again later. That choice is made once, from the first
/// frame.
///
/// A delay is stored in whole centiseconds, and players hold a frame for a
/// tenth of a second when the stored delay is under two.
public final class GIFWriter {

    /// How the 256 colors of a frame are chosen.
    public enum Palette: String, CaseIterable, Sendable {
        /// One table chosen from the first frame and kept, so a color never
        /// shifts between frames, with colors that arrive later joining it
        /// while the format's 256 last. The default.
        case shared
        /// A table chosen for every frame from that frame alone. Truer to a
        /// piece whose colors travel over its length, at a table's worth of
        /// bytes a frame; an area that changes slowly can shimmer as the table
        /// under it moves.
        case perFrame = "per-frame"
    }

    /// What stopped the file from being written.
    public struct WriteError: Error, CustomStringConvertible, Equatable, Sendable {
        public let problem: String
        public var description: String { problem }
    }

    public let path: String
    public let width: Int
    public let height: Int
    public let palette: Palette
    /// How many times the file plays: 0 forever, 1 once through, which is
    /// what the system's reader reports back for the file.
    public let loops: Int
    /// Frames written so far.
    public private(set) var frameCount = 0

    /// Colors a table holds beside the transparent index.
    static let maxColors = 255
    /// Entries in the current table, a power of two sized to its colors, so
    /// a picture of few colors codes in fewer bits; the last entry is the one
    /// kept for "leave the pixel as it is".
    private var tableSize = 256
    private var transparentIndex: Int { tableSize - 1 }
    /// The table's size as the format spells it, and the code width it asks of the coder.
    private var tableSizeCode: UInt8 { UInt8(tableSize.trailingZeroBitCount - 1) }

    private var handle: FileHandle
    private var isFinished = false
    /// Decided from the first frame: clear pixels are kept as a hard cut and
    /// every frame is written whole.
    private var isTransparent = false

    /// The frame as drawn, RGBA premultiplied, `width * height * 4` bytes.
    private let pixels: UnsafeMutablePointer<UInt8>
    private let context: CGContext
    /// One `UInt32` a pixel: `0x00RRGGBB` for an opaque pixel, `clearKey` for a
    /// see-through one. Two of them, this frame's and the one before.
    private var keys: UnsafeMutablePointer<UInt32>
    private var previousKeys: UnsafeMutablePointer<UInt32>
    private static let clearKey: UInt32 = 0x0100_0000
    /// The table index of every pixel in the rectangle being written.
    private let indices: UnsafeMutablePointer<UInt8>

    private var histogram = Histogram()
    /// The nearest table entry for every six-bit bin, resolved on demand.
    private let lookup: UnsafeMutablePointer<UInt16>
    private var tableR: [Int32] = []
    private var tableG: [Int32] = []
    private var tableB: [Int32] = []
    /// Counts up on every table chosen; the first one is the file's global table.
    private var tableVersion = 0
    /// Where the global table sits in the file: after the header and the
    /// logical screen descriptor.
    private static let globalTableOffset: UInt64 = 13
    /// A color this close to an entry the table has is that entry.
    static let graftFloor = 8.0
    /// The RMS distance the current table achieves on the frame it was chosen
    /// from, which is what a later frame's distance is read against.
    private var trainingDistance = 0.0
    private let encoder = LZWEncoder()
    private var output: [UInt8] = []

    /// Opens `path` for writing, replacing whatever was there.
    public init(path: String, width: Int, height: Int,
                palette: Palette = .shared, loops: Int = 0) throws {
        guard width >= 1, height >= 1, width <= 65535, height <= 65535 else {
            throw WriteError(problem: "a GIF is at most 65535 pixels a side, not \(width)×\(height)")
        }
        self.path = path
        self.width = width
        self.height = height
        self.palette = palette
        self.loops = loops
        try? FileManager.default.removeItem(atPath: path)
        guard FileManager.default.createFile(atPath: path, contents: nil),
              let handle = FileHandle(forWritingAtPath: path) else {
            throw WriteError(problem: "cannot write \(path)")
        }
        self.handle = handle

        let count = width * height
        pixels = .allocate(capacity: count * 4)
        pixels.initialize(repeating: 0, count: count * 4)
        guard let context = CGContext(data: pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            pixels.deallocate()
            throw WriteError(problem: "cannot draw a \(width)×\(height) frame")
        }
        context.interpolationQuality = .high
        self.context = context
        keys = .allocate(capacity: count)
        keys.initialize(repeating: 0, count: count)
        previousKeys = .allocate(capacity: count)
        previousKeys.initialize(repeating: 0, count: count)
        indices = .allocate(capacity: count)
        indices.initialize(repeating: 0, count: count)
        lookup = .allocate(capacity: Histogram.bins)
        lookup.initialize(repeating: 0xFFFF, count: Histogram.bins)
        output.reserveCapacity(4096)
    }

    deinit {
        pixels.deallocate()
        keys.deallocate()
        previousKeys.deallocate()
        indices.deallocate()
        lookup.deallocate()
        if !isFinished { try? handle.close() }
    }

    /// The bytes the writer keeps between frames, which do not move with the
    /// frame count: the drawn frame, two key planes, the index plane, the
    /// histogram, the lookup, the coder's table and the last frame's output.
    var heldBytes: Int {
        let count = width * height
        return count * 4 + count * 4 * 2 + count
            + histogram.bytes + Histogram.bins * 2
            + encoder.bytes + output.capacity
    }

    // MARK: - Frames

    /// Adds `image` as the next frame, shown for `delay` seconds, drawn into the
    /// writer's size if it is another.
    public func append(_ image: CGImage, delay: Double) throws {
        guard !isFinished else { throw WriteError(problem: "\(path) is finished") }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(rect)
        context.draw(image, in: rect)

        if frameCount == 0 {
            isTransparent = Self.carriesAlpha(image) && hasClearPixel()
        }
        buildKeys()

        // What to write: the whole frame, or only what changed.
        var left = 0, top = 0, right = width, bottom = height   // half-open
        var diffs = false
        if frameCount > 0, !isTransparent {
            diffs = true
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                let row = y * width
                var x = 0
                while x < width {
                    if keys[row + x] != previousKeys[row + x] {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        maxY = y
                    }
                    x += 1
                }
            }
            if maxX < 0 {
                // Nothing moved: a one-pixel frame that changes nothing keeps the delay.
                left = 0; top = 0; right = 1; bottom = 1
                indices[0] = UInt8(transparentIndex)
                try writeFrame(left: left, top: top, width: 1, height: 1, delay: delay)
                swap(&keys, &previousKeys)
                frameCount += 1
                return
            }
            left = minX; top = minY; right = maxX + 1; bottom = maxY + 1
        }

        if frameCount == 0 || palette == .perFrame {
            install(colorsOfFrame())
            if palette == .shared { trainingDistance = distanceOverFrame() }
        }
        let mapped = mapIndices(left: left, top: top, right: right, bottom: bottom, diffs: diffs)
        if palette == .shared, frameCount > 0, leavesTheTable(mapped) {
            // The picture left the table it was given. The colors it is
            // missing join the global table while the format has room for
            // them; past that, this frame and the frames after it carry a
            // table of their own.
            let colors = colorsOfFrame()
            let grafted = tableVersion == 1 ? try graft(colors) : false
            if !grafted { install(colors) }
            trainingDistance = distanceOverFrame()
            mapIndices(left: left, top: top, right: right, bottom: bottom, diffs: diffs)
        }
        try writeFrame(left: left, top: top, width: right - left, height: bottom - top, delay: delay)
        swap(&keys, &previousKeys)
        frameCount += 1
    }

    /// Writes the trailer and closes the file.
    public func finish() throws {
        guard !isFinished else { return }
        if frameCount == 0 { try writeHeader() }
        try write([0x3B])
        try handle.close()
        isFinished = true
    }

    /// When a frame has left its shared table, read two ways from the pixels
    /// it mapped. Over the whole frame, the error energy spread across every
    /// pixel: a whole picture drifting off its table (a fade in) counts here,
    /// and a strip of new colors uncovered behind a moving shape does not,
    /// since it is a few pixels' worth. Over the moved pixels alone, the RMS
    /// distance against a higher bar and a minimum count: a thin thing of a
    /// new color that arrives late and stays (a pale tree growing over dark
    /// soil) is almost no energy over the frame and the whole picture where
    /// it is, while the uncovered strip sits at about twice the training
    /// error and under the bar. Both bars scale with the training error, so
    /// a picture the table already fits poorly (a field of noise) is allowed
    /// the same again before a change counts.
    static let frameFloor = 8.0
    static let frameFactor = 2.0
    static let movedFloor = 12.0
    static let movedFactor = 3.0
    /// Enough moved pixels to be a thing rather than a flicker of antialiasing;
    /// a table sized to its colors costs a few hundred bytes, so the bar is low.
    static let movedMinimum = 8

    /// What `mapIndices` measured: the pixels it mapped and their summed
    /// squared distance from the table.
    struct Mapped {
        var count = 0
        var squares: UInt64 = 0
    }

    private func leavesTheTable(_ mapped: Mapped) -> Bool {
        guard mapped.count > 0 else { return false }
        let overFrame = (Double(mapped.squares) / Double(width * height)).squareRoot()
        if overFrame > max(Self.frameFloor, Self.frameFactor * trainingDistance) { return true }
        guard mapped.count >= Self.movedMinimum else { return false }
        let overMoved = (Double(mapped.squares) / Double(mapped.count)).squareRoot()
        return overMoved > max(Self.movedFloor, Self.movedFactor * trainingDistance)
    }

    private static func carriesAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private func hasClearPixel() -> Bool {
        let count = width * height
        var i = 3
        while i < count * 4 {
            if pixels[i] < 128 { return true }
            i += 4
        }
        return false
    }

    /// Reads the drawn frame into keys: the color of an opaque pixel with the
    /// premultiplication undone, or the clear key under half coverage.
    private func buildKeys() {
        let count = width * height
        for i in 0..<count {
            let p = i * 4
            let a = Int(pixels[p + 3])
            if isTransparent && a < 128 {
                keys[i] = Self.clearKey
                continue
            }
            var r = Int(pixels[p]), g = Int(pixels[p + 1]), b = Int(pixels[p + 2])
            if a < 255 && a > 0 {
                r = min(255, (r * 255 + a / 2) / a)
                g = min(255, (g * 255 + a / 2) / a)
                b = min(255, (b * 255 + a / 2) / a)
            }
            keys[i] = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
        }
    }

    // MARK: - The table

    /// The colors of the frame in `keys`, by median cut.
    private func colorsOfFrame() -> [Histogram.Entry] {
        histogram.reset()
        let count = width * height
        for i in 0..<count {
            let k = keys[i]
            if k == Self.clearKey { continue }
            histogram.add(r: Int(k >> 16 & 0xFF), g: Int(k >> 8 & 0xFF), b: Int(k & 0xFF))
        }
        return histogram.medianCut(maxColors: Self.maxColors)
    }

    /// Makes `colors` the current table, sized to them plus the transparent
    /// entry; the format's floor is four.
    private func install(_ colors: [Histogram.Entry]) {
        tableR = colors.map { Int32($0.r) }
        tableG = colors.map { Int32($0.g) }
        tableB = colors.map { Int32($0.b) }
        tableSize = 4
        while tableSize < colors.count + 1 { tableSize *= 2 }
        lookup.update(repeating: 0xFFFF, count: Histogram.bins)
        tableVersion += 1
    }

    /// Adds what `colors` has that the global table lacks, on disk as well,
    /// and says whether they all fit in the format's 256. Entries the frames
    /// already written point at are never touched: a color that fits a free
    /// entry is written into it, and more colors than the table has room for
    /// grow it to the next size that holds them by copying the file so far
    /// behind a wider head, a pass at constant memory that happens at most
    /// once per doubling. A frame already written keeps its narrower codes
    /// and its own transparent index, both of which stay valid under the
    /// wider table.
    private func graft(_ colors: [Histogram.Entry]) throws -> Bool {
        var fresh: [Histogram.Entry] = []
        let floor = Int32(Self.graftFloor * Self.graftFloor)
        for color in colors {
            let r = Int32(color.r), g = Int32(color.g), b = Int32(color.b)
            var nearest = Int32.max
            for i in 0..<tableR.count {
                let dr = tableR[i] - r, dg = tableG[i] - g, db = tableB[i] - b
                nearest = min(nearest, dr * dr + dg * dg + db * db)
            }
            for other in fresh {
                let dr = Int32(other.r) - r, dg = Int32(other.g) - g, db = Int32(other.b) - b
                nearest = min(nearest, dr * dr + dg * dg + db * db)
            }
            if nearest > floor { fresh.append(color) }
        }
        guard !fresh.isEmpty else { return true }
        guard tableR.count + fresh.count <= Self.maxColors else { return false }
        if tableR.count + fresh.count <= tableSize - 1 {
            var bytes: [UInt8] = []
            for color in fresh { bytes += [color.r, color.g, color.b] }
            do {
                try handle.seek(toOffset: Self.globalTableOffset + UInt64(3 * tableR.count))
                try handle.write(contentsOf: Data(bytes))
                try handle.seekToEnd()
            } catch {
                throw WriteError(problem: "cannot write \(path): \(error.localizedDescription)")
            }
            tableR += fresh.map { Int32($0.r) }
            tableG += fresh.map { Int32($0.g) }
            tableB += fresh.map { Int32($0.b) }
        } else {
            try grow(adding: fresh)
        }
        lookup.update(repeating: 0xFFFF, count: Histogram.bins)
        return true
    }

    /// Rewrites the file so far behind a global table wide enough for the
    /// old entries and `fresh` after them.
    private func grow(adding fresh: [Histogram.Entry]) throws {
        let oldTableBytes = 3 * tableSize
        let temp = path + ".growing"
        try? FileManager.default.removeItem(atPath: temp)
        do {
            try handle.synchronize()
            guard FileManager.default.createFile(atPath: temp, contents: nil),
                  let out = FileHandle(forWritingAtPath: temp),
                  let input = FileHandle(forReadingAtPath: path),
                  var head = try input.read(upToCount: Int(Self.globalTableOffset)).map(Array.init),
                  head.count == Int(Self.globalTableOffset) else {
                throw WriteError(problem: "cannot grow the table of \(path)")
            }
            tableR += fresh.map { Int32($0.r) }
            tableG += fresh.map { Int32($0.g) }
            tableB += fresh.map { Int32($0.b) }
            while tableSize < tableR.count + 1 { tableSize *= 2 }
            head[10] = 0x80 | 0x70 | tableSizeCode
            appendTable(to: &head)
            try out.write(contentsOf: Data(head))
            try input.seek(toOffset: Self.globalTableOffset + UInt64(oldTableBytes))
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                try out.write(contentsOf: chunk)
            }
            try input.close()
            try out.close()
            try handle.close()
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: temp))
            guard let reopened = FileHandle(forWritingAtPath: path) else {
                throw WriteError(problem: "cannot reopen \(path)")
            }
            try reopened.seekToEnd()
            handle = reopened
        } catch let error as WriteError {
            throw error
        } catch {
            throw WriteError(problem: "cannot grow the table of \(path): \(error.localizedDescription)")
        }
    }

    /// The index of the table entry nearest the bin a color falls in.
    @inline(__always)
    private func index(r: Int, g: Int, b: Int) -> Int {
        let bin = (r >> 2) << 12 | (g >> 2) << 6 | (b >> 2)
        let known = lookup[bin]
        if known != 0xFFFF { return Int(known) }
        let cr = Int32((r >> 2) << 2 | 2), cg = Int32((g >> 2) << 2 | 2), cb = Int32((b >> 2) << 2 | 2)
        var best = 0
        var bestDistance = Int32.max
        for i in 0..<tableR.count {
            let dr = tableR[i] - cr, dg = tableG[i] - cg, db = tableB[i] - cb
            let d = dr * dr + dg * dg + db * db
            if d < bestDistance { bestDistance = d; best = i }
        }
        lookup[bin] = UInt16(best)
        return best
    }

    /// Fills `indices` for the rectangle, row by row from its top left, and
    /// reports the pixels it mapped with their squared distance from the
    /// table; a pixel left alone is exact and is not counted.
    @discardableResult
    private func mapIndices(left: Int, top: Int, right: Int, bottom: Int, diffs: Bool) -> Mapped {
        var mapped = Mapped()
        var o = 0
        for y in top..<bottom {
            let row = y * width
            for x in left..<right {
                let i = row + x
                let k = keys[i]
                if k == Self.clearKey || (diffs && k == previousKeys[i]) {
                    indices[o] = UInt8(transparentIndex)
                } else {
                    let r = Int(k >> 16 & 0xFF), g = Int(k >> 8 & 0xFF), b = Int(k & 0xFF)
                    let e = index(r: r, g: g, b: b)
                    indices[o] = UInt8(e)
                    let dr = tableR[e] - Int32(r), dg = tableG[e] - Int32(g), db = tableB[e] - Int32(b)
                    mapped.squares += UInt64(dr * dr + dg * dg + db * db)
                    mapped.count += 1
                }
                o += 1
            }
        }
        return mapped
    }

    /// The RMS distance of the whole frame from the current table, on the same
    /// footing as `mapIndices` reports it.
    private func distanceOverFrame() -> Double {
        var sum: UInt64 = 0
        let count = width * height
        for i in 0..<count {
            let k = keys[i]
            if k == Self.clearKey { continue }
            let r = Int(k >> 16 & 0xFF), g = Int(k >> 8 & 0xFF), b = Int(k & 0xFF)
            let e = index(r: r, g: g, b: b)
            let dr = tableR[e] - Int32(r), dg = tableG[e] - Int32(g), db = tableB[e] - Int32(b)
            sum += UInt64(dr * dr + dg * dg + db * db)
        }
        return (Double(sum) / Double(count)).squareRoot()
    }

    // MARK: - The file

    private func write(_ bytes: [UInt8]) throws {
        do {
            try handle.write(contentsOf: Data(bytes))
        } catch {
            throw WriteError(problem: "cannot write \(path): \(error.localizedDescription)")
        }
    }

    private func appendTable(to out: inout [UInt8]) {
        for i in 0..<tableSize {
            if i < tableR.count {
                out.append(UInt8(tableR[i])); out.append(UInt8(tableG[i])); out.append(UInt8(tableB[i]))
            } else {
                out.append(0); out.append(0); out.append(0)
            }
        }
    }

    private func writeHeader() throws {
        var out: [UInt8] = Array("GIF89a".utf8)
        out.append(UInt8(width & 0xFF)); out.append(UInt8(width >> 8))
        out.append(UInt8(height & 0xFF)); out.append(UInt8(height >> 8))
        out.append(0x80 | 0x70 | tableSizeCode)   // a global table, 8 bits a channel
        out.append(0)           // background index
        out.append(0)           // pixel aspect ratio: square
        appendTable(to: &out)
        // The loop block counts the plays after the first, so a file that
        // plays once has none, and forever is its zero.
        if loops != 1 {
            let repeats = loops == 0 ? 0 : min(65535, max(0, loops - 1))
            out += [0x21, 0xFF, 0x0B]
            out += Array("NETSCAPE2.0".utf8)
            out += [0x03, 0x01, UInt8(repeats & 0xFF), UInt8((repeats >> 8) & 0xFF), 0x00]
        }
        try write(out)
    }

    private func writeFrame(left: Int, top: Int, width w: Int, height h: Int, delay: Double) throws {
        if frameCount == 0 { try writeHeader() }
        output.removeAll(keepingCapacity: true)
        // The graphic control extension: how this frame leaves, and its delay.
        let disposal: UInt8 = isTransparent ? 2 : 1      // restore the ground, or leave it
        let centiseconds = min(65535, max(0, Int((delay * 100).rounded())))
        output += [0x21, 0xF9, 0x04, disposal << 2 | 1,
                   UInt8(centiseconds & 0xFF), UInt8(centiseconds >> 8),
                   UInt8(transparentIndex), 0x00]
        // The image descriptor, with its own table when the global one is not it.
        let local = tableVersion > 1
        output += [0x2C,
                   UInt8(left & 0xFF), UInt8(left >> 8), UInt8(top & 0xFF), UInt8(top >> 8),
                   UInt8(w & 0xFF), UInt8(w >> 8), UInt8(h & 0xFF), UInt8(h >> 8),
                   local ? 0x80 | tableSizeCode : 0x00]
        if local { appendTable(to: &output) }
        let minCodeSize = tableSize.trailingZeroBitCount            // the LZW minimum code size
        output.append(UInt8(minCodeSize))
        encoder.encode(indices, count: w * h, minCodeSize: minCodeSize, into: &output)
        try write(output)
    }
}

// MARK: - Median cut

extension GIFWriter {
    /// The colors of a frame binned at six bits a channel, with the exact sums
    /// under each bin, so a box's color is the mean of the pixels in it.
    struct Histogram {
        static let bins = 1 << 18
        private(set) var count = [UInt32](repeating: 0, count: bins)
        private(set) var sum = [UInt64](repeating: 0, count: bins * 3)

        var bytes: Int { Self.bins * 4 + Self.bins * 3 * 8 }

        mutating func reset() {
            count.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            sum.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        }

        @inline(__always)
        mutating func add(r: Int, g: Int, b: Int) {
            let bin = (r >> 2) << 12 | (g >> 2) << 6 | (b >> 2)
            count[bin] &+= 1
            sum[bin * 3] &+= UInt64(r)
            sum[bin * 3 + 1] &+= UInt64(g)
            sum[bin * 3 + 2] &+= UInt64(b)
        }

        struct Entry { var r: UInt8; var g: UInt8; var b: UInt8 }

        private struct Box {
            var lo: Int, hi: Int      // a half-open range into the bin list
            var pixels: UInt64
            var minR = 63, maxR = 0, minG = 63, maxG = 0, minB = 63, maxB = 0
            /// How far the box's bins sit from its mean, RMS in levels.
            var spread = 0.0
            var canSplit: Bool { hi - lo > 1 && spread >= Histogram.splitFloor }
            var priority: UInt64 {
                pixels * UInt64((maxR - minR + 1) * (maxG - minG + 1) * (maxB - minB + 1))
            }
        }

        /// A box whose colors all sit within this many levels of its mean is
        /// one color: an antialiased ramp does not need an entry per shade,
        /// and the entries it would have taken code in fewer bits.
        static let splitFloor = 3.0
        /// Two entries this close are one. A median split parts a dominant
        /// bin from its dithered neighbors first and isolates a neighbor
        /// later, which the split floor cannot see; a flat sky then flips
        /// between two entries a level apart and the coder pays for every
        /// flip.
        static let mergeFloor = 6.0

        /// Up to `maxColors` colors: the populated bins are split along their
        /// widest axis at the median pixel, the box with the most pixels over
        /// the widest spread first, and each box lands on the mean of its pixels.
        func medianCut(maxColors: Int) -> [Entry] {
            var bins: [Int32] = []
            for i in 0..<Self.bins where count[i] > 0 { bins.append(Int32(i)) }
            guard !bins.isEmpty else { return [Entry(r: 0, g: 0, b: 0)] }

            func measure(_ lo: Int, _ hi: Int) -> Box {
                var box = Box(lo: lo, hi: hi, pixels: 0)
                var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumSquares = 0.0
                for j in lo..<hi {
                    let bin = Int(bins[j])
                    let r = bin >> 12 & 63, g = bin >> 6 & 63, b = bin & 63
                    let n = count[bin]
                    box.pixels += UInt64(n)
                    if r < box.minR { box.minR = r }; if r > box.maxR { box.maxR = r }
                    if g < box.minG { box.minG = g }; if g > box.maxG { box.maxG = g }
                    if b < box.minB { box.minB = b }; if b > box.maxB { box.maxB = b }
                    let weight = Double(n)
                    sumR += weight * Double(r); sumG += weight * Double(g); sumB += weight * Double(b)
                    sumSquares += weight * Double(r * r + g * g + b * b)
                }
                let n = Double(box.pixels)
                let variance = max(0, sumSquares / n - (sumR * sumR + sumG * sumG + sumB * sumB) / (n * n))
                box.spread = 4 * variance.squareRoot()          // a bin is four levels wide
                return box
            }

            var boxes = [measure(0, bins.count)]
            while boxes.count < maxColors {
                var pick = -1
                var best: UInt64 = 0
                for (i, box) in boxes.enumerated() where box.canSplit && box.priority > best {
                    best = box.priority; pick = i
                }
                guard pick >= 0 else { break }
                let box = boxes[pick]
                let spreadR = box.maxR - box.minR, spreadG = box.maxG - box.minG, spreadB = box.maxB - box.minB
                let shift: Int
                if spreadG >= spreadR && spreadG >= spreadB { shift = 6 }
                else if spreadR >= spreadB { shift = 12 }
                else { shift = 0 }
                bins[box.lo..<box.hi].sort { (Int($0) >> shift) & 63 < (Int($1) >> shift) & 63 }
                var acc: UInt64 = 0
                var split = box.lo + 1
                for j in box.lo..<box.hi {
                    acc += UInt64(count[Int(bins[j])])
                    if acc * 2 >= box.pixels { split = j + 1; break }
                }
                split = min(max(split, box.lo + 1), box.hi - 1)
                boxes[pick] = measure(box.lo, split)
                boxes.append(measure(split, box.hi))
            }

            var means = boxes.map { box -> (r: Double, g: Double, b: Double, n: Double) in
                var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, n: UInt64 = 0
                for j in box.lo..<box.hi {
                    let bin = Int(bins[j])
                    r += sum[bin * 3]; g += sum[bin * 3 + 1]; b += sum[bin * 3 + 2]
                    n += UInt64(count[bin])
                }
                return (Double(r) / Double(n), Double(g) / Double(n), Double(b) / Double(n), Double(n))
            }
            // Entries within the merge floor of each other become one, at
            // the mean of their pixels, until no two are that close.
            var merged = true
            while merged {
                merged = false
                outer: for i in 0..<means.count {
                    for j in (i + 1)..<means.count {
                        let a = means[i], b = means[j]
                        let d = (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)
                        if d <= Self.mergeFloor * Self.mergeFloor {
                            let n = a.n + b.n
                            means[i] = ((a.r * a.n + b.r * b.n) / n, (a.g * a.n + b.g * b.n) / n,
                                        (a.b * a.n + b.b * b.n) / n, n)
                            means.remove(at: j)
                            merged = true
                            break outer
                        }
                    }
                }
            }
            return means.map { Entry(r: UInt8($0.r.rounded()), g: UInt8($0.g.rounded()), b: UInt8($0.b.rounded())) }
        }
    }
}

// MARK: - LZW

extension GIFWriter {
    /// The variable-width LZW coder the format specifies: codes from nine to
    /// twelve bits, a clear code when the table fills, packed least significant
    /// bit first into blocks of at most 255 bytes.
    final class LZWEncoder {
        private static let hashSize = 1 << 13
        private static let maxCodes = 1 << 12
        private let hashKeys: UnsafeMutablePointer<Int32>
        private let hashCodes: UnsafeMutablePointer<UInt16>

        var bytes: Int { Self.hashSize * 6 }

        init() {
            hashKeys = .allocate(capacity: Self.hashSize)
            hashKeys.initialize(repeating: -1, count: Self.hashSize)
            hashCodes = .allocate(capacity: Self.hashSize)
            hashCodes.initialize(repeating: 0, count: Self.hashSize)
        }

        deinit {
            hashKeys.deallocate()
            hashCodes.deallocate()
        }

        /// Codes `count` indices from `indices` into sub-blocks appended to `out`,
        /// ending with the block terminator. `minCodeSize` is the width of an
        /// index, two to eight bits.
        func encode(_ indices: UnsafePointer<UInt8>, count: Int, minCodeSize: Int, into out: inout [UInt8]) {
            let clear = 1 << minCodeSize
            let end = clear + 1
            var free = end + 1
            var codeSize = minCodeSize + 1

            var bits: UInt32 = 0
            var bitCount = 0
            var blockStart = out.count       // where the current block's length byte sits
            out.append(0)
            var blockLength = 0

            @inline(__always) func emitByte(_ byte: UInt8) {
                out.append(byte)
                blockLength += 1
                if blockLength == 255 {
                    out[blockStart] = 255
                    blockStart = out.count
                    out.append(0)
                    blockLength = 0
                }
            }
            @inline(__always) func emit(_ code: Int) {
                bits |= UInt32(code) << UInt32(bitCount)
                bitCount += codeSize
                while bitCount >= 8 {
                    emitByte(UInt8(bits & 0xFF))
                    bits >>= 8
                    bitCount -= 8
                }
            }
            func resetTable() {
                hashKeys.update(repeating: -1, count: Self.hashSize)
            }

            resetTable()
            emit(clear)
            guard count > 0 else {
                emit(end)
                if bitCount > 0 { emitByte(UInt8(bits & 0xFF)) }
                if blockLength > 0 { out[blockStart] = UInt8(blockLength) } else { out.removeLast() }
                out.append(0)
                return
            }

            var prefix = Int(indices[0])
            var i = 1
            while i < count {
                let c = Int(indices[i])
                i += 1
                let key = Int32(prefix << 8 | c)
                // Open addressing over a table the entries never fill past half.
                var slot = Int((UInt32(bitPattern: key) &* 2_654_435_761) >> 19)
                var found = -1
                while true {
                    let k = hashKeys[slot]
                    if k == key { found = Int(hashCodes[slot]); break }
                    if k == -1 { break }
                    slot = (slot + 1) & (Self.hashSize - 1)
                }
                if found >= 0 { prefix = found; continue }
                emit(prefix)
                if free < Self.maxCodes {
                    if free == 1 << codeSize { codeSize += 1 }
                    hashKeys[slot] = key
                    hashCodes[slot] = UInt16(free)
                    free += 1
                } else {
                    emit(clear)
                    resetTable()
                    free = end + 1
                    codeSize = minCodeSize + 1
                }
                prefix = c
            }
            emit(prefix)
            if free == 1 << codeSize && codeSize < 12 { codeSize += 1 }
            emit(end)
            if bitCount > 0 { emitByte(UInt8(bits & 0xFF)) }
            if blockLength > 0 { out[blockStart] = UInt8(blockLength) } else { out.removeLast() }
            out.append(0)
        }
    }
}
