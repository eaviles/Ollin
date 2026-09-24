import Foundation
import COllinAllocationWatch

// A seeded mutation harness for the decoders that read bytes a sketch did not
// write: a datagram off the network, a frame off a cable, a file somebody hands
// over. The invariant every decoder is held to is small and total: whatever the
// bytes, the call returns a value, returns `nil`, or throws. A trap (an index
// out of range, an overflow, a narrowing that does not fit, a force unwrap) is
// the failure, because a stranger's packet must never end a show.
//
// A trap ends the test process, so the harness cannot catch it the way a test
// catches a wrong answer. Instead it writes the case it is about to try to a
// small log before every call, and removes the log when the run completes. A
// run that dies leaves the log behind, naming the run, its seed, the case
// number, and the bytes themselves in hex, which is everything needed to put
// the dying input straight into a test.
//
// A reader of a file owes one thing more: a count the bytes declare is checked
// against the bytes that remain before anything is set aside for it, so a
// forty-byte file that says it holds four billion entries is refused rather
// than answered with a gigabyte. That is invisible to the trap check, since a
// block reserved and never touched costs nothing a test can see, so a run can
// also watch the largest single block the decoding thread asks for and hold it
// to a bound on the input's size (`AllocationWatch`, `AllocationBound`).
//
// A regular target kept under `Tests/` (a test target may depend on a library
// target, never on another test target), with nothing but Foundation and the
// allocation watch's small C hook in it.

// MARK: - The generator

/// A seeded source of the edits a stranger's packet might carry. The same seed
/// gives the same sequence of edits on every machine and every run, which is
/// what makes a failure repeatable from its seed and case number alone.
package struct Mutator {

    /// What one edit does to a byte string.
    package enum Edit: CaseIterable, Sendable, Hashable {
        /// Cuts the bytes short at a random length.
        case truncate
        /// Flips one bit.
        case flipBit
        /// Replaces one byte with a random one.
        case flipByte
        /// Copies a random range over another part of the bytes.
        case splice
        /// Inserts a short random run.
        case insert
        /// Removes a short run.
        case delete
        /// Writes a field of 1, 2, 4, or 8 bytes at a random offset to one of
        /// the values a length or a number is most often wrong at: zero, one,
        /// all ones, the sign bit alone, the sign bit clear, and for the wide
        /// fields the float and double patterns for NaN, the infinities, a
        /// negative zero, a denormal, and a number too large for an `Int`.
        case extreme
        /// Swaps two bytes.
        case swap
        /// Repeats a run of the bytes in place, so a count field's items
        /// outnumber what the count says, or a list overruns its frame.
        case repeatRun
        /// Writes a number as text, at one of the values a text reader is most
        /// often wrong at (`1e300`, `nan`, `inf`, a number one past what an
        /// `Int` holds, twenty nines), over a run of digits already in the
        /// bytes when there is one, and at a random offset otherwise. This is
        /// the edit for the protocols that carry numbers as words: a serial
        /// line, an MQTT payload, a JSON value, an HTTP head.
        case decimal
    }

    /// The numbers `Edit.decimal` writes, as text.
    package static let decimals: [String] = [
        "1e300", "-1e300", "1e400", "-1e400", "1e-400", "nan", "NaN", "inf", "-inf", "infinity",
        "9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809",
        "18446744073709551615", "18446744073709551616", "99999999999999999999", "-0", "0x7fffffffffffffff",
        "4294967296", "2147483648", "65536", "0.1e1", "1.", ".5", "1e", "-", "+", "1_000", "١٢٣",
    ]

    /// The numbers the number sweep writes over each number in a text input:
    /// the values a count, an index, an offset, or a size is most often wrong
    /// at (negative, zero, the edges of a byte and a 16-bit field, where a
    /// format's own ceiling most often sits, one past a 31- and 32-bit field, one past what
    /// a `Double` counts exactly, the ends of an `Int`, and a number far past
    /// them), plus a fraction where a whole number was meant, and the text a
    /// reader of floating point accepts for the infinities.
    package static let numberSpellings: [String] = [
        "-1", "0", "1", "255", "256", "65535", "65536", "2147483648", "4294967296", "-2147483649", "9007199254740993",
        "9223372036854775807", "-9223372036854775808", "99999999999999999999", "1e300", "-1e300", "1e999",
        "0.5", "nan", "inf",
    ]

    /// The seed this generator was made with.
    package let seed: UInt64

    /// How many times each edit has been applied, so a test can check that
    /// every kind of edit appears in a run.
    package private(set) var editsApplied: [Edit: Int] = [:]

    private var state: UInt64

    package init(seed: UInt64) {
        self.seed = seed
        state = seed
    }

    /// The next 64 random bits (SplitMix64: one add and three shifts, which is
    /// all a mutation source needs, and it never depends on the platform).
    package mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in `0..<bound`; `0` when the bound is not positive.
    package mutating func below(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(next() % UInt64(bound))
    }

    /// One mutated copy of `bytes`: one to three edits stacked.
    package mutating func mutate(_ bytes: [UInt8]) -> [UInt8] {
        mutate(bytes, edits: 1 + below(3))
    }

    /// A mutated copy of `bytes` with `edits` edits stacked, each chosen at
    /// random from every kind.
    package mutating func mutate(_ bytes: [UInt8], edits: Int) -> [UInt8] {
        var out = bytes
        for _ in 0..<max(1, edits) {
            let kinds = Edit.allCases
            apply(kinds[below(kinds.count)], to: &out)
        }
        return out
    }

    /// Applies one edit of a chosen kind. An edit that has nothing to work on
    /// (a flip of an empty string) inserts instead, so a mutation always
    /// changes something.
    package mutating func apply(_ edit: Edit, to bytes: inout [UInt8]) {
        editsApplied[edit, default: 0] += 1
        let count = bytes.count
        switch edit {
        case .truncate:
            guard count > 0 else { insertRun(into: &bytes); return }
            bytes.removeSubrange(below(count)...)

        case .flipBit:
            guard count > 0 else { insertRun(into: &bytes); return }
            let index = below(count)
            bytes[index] ^= UInt8(1) << UInt8(below(8))

        case .flipByte:
            guard count > 0 else { insertRun(into: &bytes); return }
            bytes[below(count)] = UInt8(truncatingIfNeeded: next())

        case .splice:
            guard count > 1 else { insertRun(into: &bytes); return }
            let length = 1 + below(min(16, count - 1))
            let from = below(count - length + 1)
            let to = below(count - length + 1)
            let run = Array(bytes[from..<(from + length)])
            bytes.replaceSubrange(to..<(to + length), with: run)

        case .insert:
            insertRun(into: &bytes)

        case .delete:
            guard count > 0 else { insertRun(into: &bytes); return }
            let length = 1 + below(min(8, count))
            let at = below(count - length + 1)
            bytes.removeSubrange(at..<(at + length))

        case .extreme:
            let widths = [1, 2, 4, 8]
            let width = widths[below(widths.count)]
            guard count >= width else { insertRun(into: &bytes); return }
            let at = below(count - width + 1)
            let value = extremeValue(width: width)
            let littleEndian = below(2) == 0
            for step in 0..<width {
                let shift = UInt64(8 * (littleEndian ? step : width - 1 - step))
                bytes[at + step] = UInt8(truncatingIfNeeded: value >> shift)
            }

        case .swap:
            guard count > 1 else { insertRun(into: &bytes); return }
            let a = below(count), b = below(count)
            bytes.swapAt(a, b)

        case .repeatRun:
            guard count > 0 else { insertRun(into: &bytes); return }
            let length = 1 + below(min(16, count))
            let from = below(count - length + 1)
            let run = Array(bytes[from..<(from + length)])
            let times = 1 + below(4)
            var repeated: [UInt8] = []
            for _ in 0..<times { repeated.append(contentsOf: run) }
            bytes.insert(contentsOf: repeated, at: from + length)

        case .decimal:
            let text = Array(Self.decimals[below(Self.decimals.count)].utf8)
            let runs = digitRuns(in: bytes)
            if runs.isEmpty {
                bytes.insert(contentsOf: text, at: below(count + 1))
            } else {
                bytes.replaceSubrange(runs[below(runs.count)], with: text)
            }
        }
    }

    /// Every maximal run of the characters a number is written with, starting
    /// on a digit or a sign.
    private func digitRuns(in bytes: [UInt8]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        func isNumeric(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || byte == 46 || byte == 45 || byte == 43 || byte == 101 || byte == 69
        }
        for (index, byte) in bytes.enumerated() {
            let starts = (48...57).contains(byte) || byte == 45
            if let begun = start {
                if !isNumeric(byte) { runs.append(begun..<index); start = nil }
            } else if starts {
                start = index
            }
        }
        if let begun = start { runs.append(begun..<bytes.count) }
        return runs
    }

    private mutating func insertRun(into bytes: inout [UInt8]) {
        let length = 1 + below(8)
        let at = below(bytes.count + 1)
        var run: [UInt8] = []
        for _ in 0..<length { run.append(UInt8(truncatingIfNeeded: next())) }
        bytes.insert(contentsOf: run, at: at)
    }

    /// One of the values a field of `width` bytes is most often wrong at.
    private mutating func extremeValue(width: Int) -> UInt64 {
        let choices = Self.extremes(width: width)
        return choices[below(choices.count)]
    }

    /// The values a field of `width` bytes (1, 2, 4, or 8) is most often wrong
    /// at: zero, one, two, all ones and one short of it, the sign bit alone
    /// and its neighbors, the largest signed value, and for the wide fields
    /// the float and double bit patterns for NaN, the infinities, a negative
    /// zero, a denormal, the largest finite number, and numbers a narrowing
    /// to an `Int` or an `Int32` cannot hold.
    package static func extremes(width: Int) -> [UInt64] {
        let bits = UInt64(8 * width)
        let all: UInt64 = bits == 64 ? .max : (UInt64(1) << bits) - 1
        let sign: UInt64 = UInt64(1) << (bits - 1)
        var choices: [UInt64] = [0, 1, 2, all, all - 1, sign, sign - 1, sign + 1, 0x7F, 0x80]
        if width == 4 {
            let floats: [Float] = [.nan, .infinity, -.infinity, -0.0, .leastNonzeroMagnitude,
                                   .greatestFiniteMagnitude, 1e30, -1e30, 3.0e9, 2_147_483_648]
            choices.append(contentsOf: floats.map { UInt64($0.bitPattern) })
        }
        if width == 8 {
            let doubles: [Double] = [.nan, .infinity, -.infinity, -0.0, .leastNonzeroMagnitude,
                                     .greatestFiniteMagnitude, 1e300, -1e300, 9.3e18, -9.3e18,
                                     4_294_967_296, 1e18]
            choices.append(contentsOf: doubles.map { $0.bitPattern })
        }
        return choices
    }

    /// `bytes` with a field of `width` bytes at `offset` set to `value`, in the
    /// byte order asked for; unchanged when the field would not fit.
    package static func writing(_ value: UInt64, width: Int, at offset: Int, littleEndian: Bool,
                                into bytes: [UInt8]) -> [UInt8] {
        guard offset >= 0, width > 0, offset + width <= bytes.count else { return bytes }
        var out = bytes
        for step in 0..<width {
            let shift = UInt64(8 * (littleEndian ? step : width - 1 - step))
            out[offset + step] = UInt8(truncatingIfNeeded: value >> shift)
        }
        return out
    }
}

// MARK: - The log

/// The file a run writes before every case and removes when it completes, so
/// a trap leaves behind the one line that reproduces it.
package struct MutationLog {

    /// The folder the logs live in, under the temporary directory.
    package static var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ollin-mutation", isDirectory: true)
    }

    /// Where the log for a run of this name is written.
    package static func url(for name: String) -> URL {
        directory.appendingPathComponent(name + ".log")
    }

    /// One case as the log spells it, and as the log is read back.
    package struct Entry: Equatable, Sendable {
        package var name: String
        package var seed: UInt64
        package var index: Int
        package var bytes: [UInt8]

        package init(name: String, seed: UInt64, index: Int, bytes: [UInt8]) {
            self.name = name
            self.seed = seed
            self.index = index
            self.bytes = bytes
        }

        package var line: String {
            "\(name) seed=\(seed) case=\(index) count=\(bytes.count) bytes=\(MutationLog.hex(bytes))\n"
        }

        /// Reads a line the log wrote, or `nil` for anything else.
        package init?(line: String) {
            let fields = line.split(separator: " ")
            guard fields.count == 5,
                  fields[1].hasPrefix("seed="), let seed = UInt64(fields[1].dropFirst(5)),
                  fields[2].hasPrefix("case="), let index = Int(fields[2].dropFirst(5)),
                  fields[4].hasPrefix("bytes=") else { return nil }
            guard let bytes = MutationLog.bytes(fromHex: String(fields[4].dropFirst(6).trimmingCharacters(in: .newlines))) else {
                return nil
            }
            self.init(name: String(fields[0]), seed: seed, index: index, bytes: bytes)
        }
    }

    private let descriptor: Int32
    package let url: URL

    /// Opens (and empties) the log for `name`; `nil` when the file cannot be
    /// made, in which case the run goes on without one.
    package init?(name: String) {
        let url = Self.url(for: name)
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else { return nil }
        self.descriptor = descriptor
        self.url = url
    }

    /// Writes the case about to be tried, over whatever was there. Two system
    /// calls and no buffering, so the line is in the kernel's hands before the
    /// decoder runs and survives the process dying under it.
    package func note(_ entry: Entry) {
        let line = Array(entry.line.utf8)
        line.withUnsafeBytes { raw in
            _ = pwrite(descriptor, raw.baseAddress, raw.count, 0)
        }
        _ = ftruncate(descriptor, off_t(line.count))
    }

    /// The run completed: close and remove the log, so a log that exists
    /// always means a run that died.
    package func finish() {
        _ = close(descriptor)
        try? FileManager.default.removeItem(at: url)
    }

    /// The last case a run of this name noted, or `nil` when it completed (or
    /// never ran).
    package static func lastEntry(for name: String) -> Entry? {
        guard let text = try? String(contentsOf: url(for: name), encoding: .utf8) else { return nil }
        return Entry(line: text)
    }

    package static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    package static func bytes(fromHex text: String) -> [UInt8]? {
        let digits = Array(text.utf8)
        guard digits.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case 48...57: return digit - 48
        case 97...102: return digit - 87
        case 65...70: return digit - 55
        default: return nil
        }
    }
}

// MARK: - The run

/// Runs a decoder over mutations of the inputs it is meant to read, and
/// reports what came back. The decoder closure answers `true` when it decoded
/// something, `false` when it refused (a `nil`), and throws when it throws;
/// the harness never judges which, only that the call came back at all.
package enum MutationRun {

    /// What a run found.
    package struct Report: CustomStringConvertible, Sendable {
        package var name: String
        package var seed: UInt64
        /// How many inputs were tried, the unmutated seeds included.
        package var cases = 0
        package var decoded = 0
        package var refused = 0
        package var threw = 0
        /// The positions of the seed inputs that did not decode as given. A
        /// seed that never decodes tests nothing, so a test asserts this is
        /// empty.
        package var seedsRefused: [Int] = []
        /// The largest single block the decoding thread asked for in any one
        /// case, in bytes, when the run watched its allocations; 0 otherwise.
        package var largestAllocation = 0
        /// The cases that asked for more than the run's bound allowed, the
        /// first sixteen of them, and how many there were in all. A test
        /// asserts `oversizedCount` is zero.
        package var oversized: [Oversized] = []
        package var oversizedCount = 0

        package var description: String {
            "\(name) (seed \(seed)): \(cases) cases, \(decoded) decoded, \(refused) refused, \(threw) threw"
            + (seedsRefused.isEmpty ? "" : ", seeds refused at \(seedsRefused)")
            + (largestAllocation == 0 ? "" : ", largest block \(largestAllocation) bytes")
            + (oversizedCount == 0 ? "" : ", \(oversizedCount) over the bound, first at \(oversized[0])")
        }
    }

    /// One case that asked for more than its bound.
    package struct Oversized: CustomStringConvertible, Sendable {
        /// The case number, as the log would name it.
        package var index: Int
        /// The input it was given.
        package var bytes: [UInt8]
        /// The largest single block it asked for.
        package var allocated: Int
        /// What the bound allowed for an input of its size.
        package var limit: Int

        package var description: String {
            "case \(index) (\(bytes.count) bytes) asked for \(allocated) bytes against \(limit)"
        }
    }

    /// The cases tried for each seed input, in order: the seed itself, the
    /// empty input, every truncation (all of them for a short input, a spread
    /// of them for a long one), the field sweep (every value in
    /// `Mutator.extremes` written at every width and byte order at every
    /// offset in the first 128 bytes and the last 32, which is where a
    /// header's and a trailer's fields live), then `count` random mutations of
    /// one to three stacked edits. One generator runs through the whole list,
    /// so a case number identifies its bytes for a given seed and set of
    /// inputs. `sweeps` turns the field sweep off for an input too large to
    /// afford it.
    ///
    /// `allocations` watches the largest single block the decoding thread asks
    /// for in each case and records every case that asks for more than the
    /// bound allows for an input of its size (`Report.oversized`). A block past
    /// `AllocationWatch.ceiling` is not recorded but stops the process, since a
    /// decoder that asked for it may be about to touch it, and the log holds
    /// the case as it would for a trap.
    package static func run(
        _ name: String,
        seeds: [[UInt8]],
        count: Int = 400,
        seed: UInt64 = 1,
        sweeps: Bool = true,
        numberSweep: Bool = false,
        allocations: AllocationBound? = nil,
        decode: ([UInt8]) throws -> Bool
    ) -> Report {
        var report = Report(name: name, seed: seed)
        var mutator = Mutator(seed: seed)
        let log = MutationLog(name: name)
        var index = 0

        func attempt(_ bytes: [UInt8]) -> Bool? {
            let entry = MutationLog.Entry(name: name, seed: seed, index: index, bytes: bytes)
            log?.note(entry)
            index += 1
            report.cases += 1
            let watch = allocations == nil ? nil : AllocationWatch.begin(naming: entry.line)
            defer {
                if let watch, let allocations {
                    let largest = AllocationWatch.end(watch)
                    report.largestAllocation = max(report.largestAllocation, largest)
                    let limit = allocations.limit(forInputOf: bytes.count)
                    if largest > limit {
                        report.oversizedCount += 1
                        if report.oversized.count < 16 {
                            report.oversized.append(Oversized(index: entry.index, bytes: bytes,
                                                              allocated: largest, limit: limit))
                        }
                    }
                }
            }
            do {
                let decoded = try decode(bytes)
                if decoded { report.decoded += 1 } else { report.refused += 1 }
                return decoded
            } catch {
                report.threw += 1
                return nil
            }
        }

        for (position, input) in seeds.enumerated() {
            if attempt(input) != true { report.seedsRefused.append(position) }
            _ = attempt([])
            for length in truncationLengths(of: input.count) {
                _ = attempt(Array(input.prefix(length)))
            }
            if sweeps {
                for offset in sweepOffsets(of: input.count) {
                    for width in [1, 2, 4, 8] where offset + width <= input.count {
                        for value in Mutator.extremes(width: width) {
                            for littleEndian in width == 1 ? [true] : [true, false] {
                                _ = attempt(Mutator.writing(value, width: width, at: offset,
                                                            littleEndian: littleEndian, into: input))
                            }
                        }
                    }
                }
            }
            if numberSweep {
                for variant in numberSweepVariants(of: input) { _ = attempt(variant) }
            }
            for _ in 0..<max(0, count) {
                _ = attempt(mutator.mutate(input))
            }
        }

        log?.finish()
        return report
    }

    /// The number sweep, the field sweep's twin for a format that writes its
    /// numbers as text (JSON, a line of an OBJ, a `.cube` entry, an SVG path):
    /// every number in the input replaced, one at a time, by each spelling in
    /// `Mutator.numberSpellings`, which are the values a count, an index, or a
    /// size is most often wrong at. A number is a run that starts on a digit,
    /// or on a sign or a point directly before one, and runs on through
    /// digits, points, and an exponent.
    package static func numberSweepVariants(of input: [UInt8]) -> [[UInt8]] {
        var variants: [[UInt8]] = []
        for range in numberRuns(in: input) {
            for spelling in Mutator.numberSpellings {
                var out = input
                out.replaceSubrange(range, with: Array(spelling.utf8))
                if out != input { variants.append(out) }
            }
        }
        return variants
    }

    /// Where the numbers written as text sit in `bytes`.
    package static func numberRuns(in bytes: [UInt8]) -> [Range<Int>] {
        func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
        var runs: [Range<Int>] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let signed = (byte == 45 || byte == 43 || byte == 46) && index + 1 < bytes.count && isDigit(bytes[index + 1])
            // A digit glued to a letter before it is part of a name (`x2`, `TEXCOORD_0`), not a number.
            let gluedToName = index > 0 && (bytes[index - 1] == 95 || (65...90).contains(bytes[index - 1])
                                            || (97...122).contains(bytes[index - 1]))
            guard isDigit(byte) || signed, !gluedToName else { index += 1; continue }
            var end = index + 1
            while end < bytes.count {
                let next = bytes[end]
                if isDigit(next) || next == 46 {
                    end += 1
                } else if next == 101 || next == 69, end + 1 < bytes.count,
                          isDigit(bytes[end + 1]) || ((bytes[end + 1] == 45 || bytes[end + 1] == 43)
                                                     && end + 2 < bytes.count && isDigit(bytes[end + 2])) {
                    end += 2
                } else {
                    break
                }
            }
            runs.append(index..<end)
            index = end
        }
        return runs
    }

    /// The offsets the field sweep writes at: the first 128 bytes and the
    /// last 32, in order, each once.
    package static func sweepOffsets(of count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var offsets = Set(0..<min(count, 128))
        for offset in max(0, count - 32)..<count { offsets.insert(offset) }
        return offsets.sorted()
    }

    /// Every length short of the whole for an input up to 512 bytes; past that
    /// 256 lengths spread evenly plus the last 32, so a long frame still has
    /// its header and its tail cut at every byte that matters.
    package static func truncationLengths(of count: Int) -> [Int] {
        guard count > 1 else { return [] }
        if count <= 512 { return Array(1..<count) }
        var lengths = Set<Int>()
        for step in 0..<256 { lengths.insert(1 + step * (count - 1) / 256) }
        for length in max(1, count - 32)..<count { lengths.insert(length) }
        return lengths.sorted()
    }
}

// MARK: - The allocation watch

/// How large a single block a decoder may ask for while it reads an input of a
/// given size: a floor any input may use, plus so many bytes for every byte
/// of input. A reader that sets aside what a count field declares before it
/// checks the count against the bytes that remain asks for far more than
/// either, which is the case this bound is for.
package struct AllocationBound: Sendable {
    /// The most any input may ask for in one block, whatever its size.
    package var floor: Int
    /// How many bytes one byte of input may grow into: 1 for a reader that
    /// copies, more for text read into numbers or a compressed stream opened.
    package var perInputByte: Int

    package init(floor: Int = 16 << 20, perInputByte: Int) {
        self.floor = floor
        self.perInputByte = perInputByte
    }

    /// The largest block allowed while reading `count` bytes.
    package func limit(forInputOf count: Int) -> Int {
        floor + perInputByte * count
    }
}

/// The largest single block one thread asks the system allocator for over a
/// stretch of its work.
///
/// It listens through the allocator's own logging hook, the one the system's
/// stack logging installs: every allocation in the process reports its size
/// there, the hook keeps the largest one made by each thread being watched,
/// and ignores the rest. The hook is installed once and never removed, and it
/// is written in C (`COllinAllocationWatch`) because it runs inside the
/// allocator, where it must not allocate, and generic Swift in a debug build
/// does. Where the allocator does not report (a sanitizer that brings its
/// own), `isAvailable` is false and nothing is watched.
package enum AllocationWatch {

    /// A block larger than this, asked for on a watched thread, stops the
    /// process before the caller can touch it: it writes the case it was
    /// given to standard error and aborts. A gigabyte is past anything a
    /// reader here should ask for, and on a machine with eight gigabytes a
    /// few such blocks filled at once would take the machine down with the
    /// test.
    package static var ceiling: Int { Int(ollin_allocation_watch_ceiling()) }

    /// Whether the allocator reports to the watch in this process, proved by
    /// watching a probe block of a size nothing else asks for.
    package static let isAvailable: Bool = {
        guard let slot = begin(naming: "probe") else { return false }
        let probe = malloc(7_777_777)
        free(probe)
        return end(slot) >= 7_777_777
    }()

    /// Starts watching the calling thread, and returns the slot to hand to
    /// `end(_:)`; `nil` when the watch is not available or every slot is
    /// taken. `note` is what a block past the ceiling writes before the
    /// process stops, so it names the case.
    package static func begin(naming note: String) -> Int? {
        let bytes = Array(note.utf8)
        let slot = bytes.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { ollin_allocation_watch_begin($0.baseAddress, $0.count) }
        }
        return slot < 0 ? nil : Int(slot)
    }

    /// Stops watching and returns the largest single block the thread asked
    /// for since `begin`, in bytes.
    package static func end(_ slot: Int) -> Int {
        Int(clamping: ollin_allocation_watch_end(Int32(slot)))
    }
}
