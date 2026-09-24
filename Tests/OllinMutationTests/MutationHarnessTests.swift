import Foundation
import Synchronization
import Testing
import OllinMutation

/// Whether this process runs under Thread Sanitizer, read off the loaded
/// images: the sanitizer's runtime is a dynamic library inserted at launch.
/// `Scripts/test.sh tsan` is the run that sets it.
var underThreadSanitizer: Bool {
    (0..<_dyld_image_count()).contains { index in
        String(cString: _dyld_get_image_name(index)).contains("libclang_rt.tsan")
    }
}

/// The harness's own tests: the generator repeats itself from a seed, every
/// kind of edit turns up in a run, a run tries what it says it tries and
/// counts what came back, and the one that matters most, a decoder that traps
/// takes the process down and leaves the dying case in the log.
@Suite struct MutationHarnessTests {

    @Test func theSameSeedGivesTheSameEdits() {
        var first = Mutator(seed: 5)
        var second = Mutator(seed: 5)
        var other = Mutator(seed: 6)
        let input = (0..<64).map { UInt8($0) }
        var same = true
        var differs = false
        for _ in 0..<500 {
            let a = first.mutate(input), b = second.mutate(input), c = other.mutate(input)
            if a != b { same = false }
            if a != c { differs = true }
        }
        #expect(same)
        #expect(differs)
    }

    @Test func everyKindOfEditAppearsInARun() {
        var mutator = Mutator(seed: 11)
        let input = [UInt8](repeating: 0x55, count: 64)
        for _ in 0..<600 { _ = mutator.mutate(input) }
        for edit in Mutator.Edit.allCases {
            #expect((mutator.editsApplied[edit] ?? 0) > 0, "\(edit) never applied")
        }
    }

    @Test func anEmptyInputStillGetsAnEdit() {
        var mutator = Mutator(seed: 2)
        for edit in Mutator.Edit.allCases {
            var bytes: [UInt8] = []
            mutator.apply(edit, to: &bytes)
            #expect(!bytes.isEmpty, "\(edit) left the empty input empty")
        }
    }

    @Test func theRunTriesTheSeedTheEmptyInputEveryTruncationAndTheCount() {
        let input: [UInt8] = Array(1...20)
        var seen: [[UInt8]] = []
        let report = MutationRun.run("selftest-cases", seeds: [input], count: 50, seed: 3, sweeps: false) { bytes in
            seen.append(bytes)
            return bytes.count >= 4
        }
        #expect(report.cases == 1 + 1 + 19 + 50)
        #expect(seen[0] == input)
        #expect(seen[1].isEmpty)
        #expect(seen[2] == [1])
        #expect(seen[20] == Array(1...19))
        #expect(report.seedsRefused.isEmpty)
        #expect(report.decoded + report.refused == report.cases)
        #expect(report.refused >= 4)
        // A run that completes takes its log with it.
        #expect(MutationLog.lastEntry(for: "selftest-cases") == nil)
        #expect(!FileManager.default.fileExists(atPath: MutationLog.url(for: "selftest-cases").path))
    }

    /// The field sweep writes every extreme at every width and byte order at
    /// every offset it can, between the truncations and the random edits.
    @Test func theSweepWritesEveryExtremeAtEveryField() {
        let input: [UInt8] = [10, 20, 30, 40, 50, 60]
        var seen: [[UInt8]] = []
        let report = MutationRun.run("selftest-sweep", seeds: [input], count: 0, seed: 3) { bytes in
            seen.append(bytes)
            return true
        }
        var expected = 0
        for offset in MutationRun.sweepOffsets(of: input.count) {
            for width in [1, 2, 4, 8] where offset + width <= input.count {
                expected += Mutator.extremes(width: width).count * (width == 1 ? 1 : 2)
            }
        }
        #expect(report.cases == 1 + 1 + 5 + expected)
        #expect(seen.contains([0xFF, 20, 30, 40, 50, 60]))
        #expect(seen.contains([10, 20, 0x80, 0x00, 50, 60]))
        #expect(seen.contains([10, 20, 0x00, 0x80, 50, 60]))
        #expect(seen.contains([10, 0x00, 0x00, 0xC0, 0x7F, 60]))   // a NaN, big-endian, at offset 1
        #expect(seen.allSatisfy { $0.count <= input.count })
        #expect(MutationRun.sweepOffsets(of: 1000) == Array(0..<128) + Array(968..<1000))
    }

    @Test func aSeedThatDoesNotDecodeIsNamedByItsPosition() {
        let report = MutationRun.run("selftest-refused", seeds: [[9, 9, 9], [1], [9, 9]], count: 5, seed: 3) { bytes in
            bytes.first == 9
        }
        #expect(report.seedsRefused == [1])
    }

    @Test func aThrowIsCountedAndTheRunGoesOn() {
        struct Refusal: Error {}
        let report = MutationRun.run("selftest-throws", seeds: [[1, 2, 3, 4]], count: 20, seed: 3) { bytes in
            if bytes.count == 4 { return true }
            throw Refusal()
        }
        #expect(report.threw > 0)
        #expect(report.decoded > 0)
        #expect(report.threw + report.decoded + report.refused == report.cases)
    }

    @Test func aLogLineReadsBackAsItWasWritten() throws {
        let entry = MutationLog.Entry(name: "osc-packet", seed: 42, index: 17, bytes: [0, 1, 0xAB, 0xFF])
        let back = try #require(MutationLog.Entry(line: entry.line))
        #expect(back == entry)
        #expect(entry.line == "osc-packet seed=42 case=17 count=4 bytes=0001abff\n")
        #expect(MutationLog.Entry(line: "not a log line") == nil)
        #expect(MutationLog.bytes(fromHex: "abc") == nil)
        #expect(MutationLog.bytes(fromHex: "zz") == nil)
    }

    @Test func theTruncationSpreadCoversTheHeadAndTheTail() {
        #expect(MutationRun.truncationLengths(of: 0).isEmpty)
        #expect(MutationRun.truncationLengths(of: 1).isEmpty)
        #expect(MutationRun.truncationLengths(of: 4) == [1, 2, 3])
        let long = MutationRun.truncationLengths(of: 5000)
        #expect(long.count <= 288)
        #expect(long.first == 1)
        #expect(long.last == 4999)
        #expect(long.contains(4968))
        #expect(long == long.sorted())
        #expect(long.allSatisfy { $0 >= 1 && $0 < 5000 })
    }

    /// The deciding test: a decoder that reads past its input ends the process,
    /// the harness cannot catch that, and the log it wrote before the call is
    /// what is left. It runs the unsafe decoder in a child process and reads
    /// the child's log from here. The seed decodes (eight bytes), so the first
    /// case that dies is the second one, the empty input.
    @Test(.enabled(if: !underThreadSanitizer, "the child an exit test spawns does not come up under Thread Sanitizer: its exit is reported within a few milliseconds, before a sanitized process could have loaded, and the log its body would have written is absent"))
    func anUnsafeDecoderGoesRedAndTheLogNamesTheDyingCase() async throws {
        try? FileManager.default.removeItem(at: MutationLog.url(for: "selftest-unsafe"))
        await #expect(processExitsWith: .failure) {
            _ = MutationRun.run("selftest-unsafe", seeds: [[1, 2, 3, 4, 5, 6, 7, 8]], count: 200, seed: 7) { bytes in
                _ = bytes[4]
                return true
            }
        }
        let entry = try #require(MutationLog.lastEntry(for: "selftest-unsafe"))
        #expect(entry.name == "selftest-unsafe")
        #expect(entry.seed == 7)
        #expect(entry.index == 1)
        #expect(entry.bytes.isEmpty)
        #expect(entry.bytes.count < 5)
        try? FileManager.default.removeItem(at: MutationLog.url(for: "selftest-unsafe"))
    }

    // MARK: The allocation watch

    /// The watch counts the blocks its own thread asks for and no other
    /// thread's: two plain threads, one watching while the other allocates
    /// far more at the same moment.
    @Test(.enabled(if: AllocationWatch.isAvailable, "the allocator does not report to the watch in this process"))
    func theWatchSeesItsOwnThreadAndNoOther() async {
        // Two plain threads (never pool workers) take turns through one
        // flag: 1 once the watch is on, 2 once the other thread's block is
        // freed.
        let step = Atomic<Int>(0)
        let largest: Int = await withCheckedContinuation { done in
            Thread.detachNewThread {
                while step.load(ordering: .acquiring) < 1 { Thread.sleep(forTimeInterval: 0.001) }
                let block = malloc(64 << 20)
                memset(block, 1, 4096)
                free(block)
                step.store(2, ordering: .releasing)
            }
            Thread.detachNewThread {
                guard let slot = AllocationWatch.begin(naming: "selftest-threads") else { done.resume(returning: -1); return }
                step.store(1, ordering: .releasing)
                while step.load(ordering: .acquiring) < 2 { Thread.sleep(forTimeInterval: 0.001) }
                let own = malloc(3 << 20)
                free(own)
                done.resume(returning: AllocationWatch.end(slot))
            }
        }
        #expect(largest >= 3 << 20)
        #expect(largest < 64 << 20)
    }

    /// The declared-size case, and the one this watch exists for: a format of
    /// a three-byte count and that many sixteen-byte entries. The reader that
    /// checks the count against the bytes that remain before it sets anything
    /// aside stays inside the bound on every case; its twin, which reserves
    /// what the count says first, asks for up to 256 MB for a file of a few
    /// bytes and is named by the cases that did it.
    @Test(.enabled(if: AllocationWatch.isAvailable, "the allocator does not report to the watch in this process"))
    func aCountReservedBeforeItIsCheckedGoesRed() throws {
        func read(_ bytes: [UInt8], checksFirst: Bool) -> Bool {
            guard bytes.count >= 3 else { return false }
            let count = Int(bytes[0]) << 16 | Int(bytes[1]) << 8 | Int(bytes[2])
            var entries: [SIMD4<Float>] = []
            if checksFirst {
                guard count <= (bytes.count - 3) / 16 else { return false }
                entries.reserveCapacity(count)
            } else {
                entries.reserveCapacity(count)
                guard count <= (bytes.count - 3) / 16 else { return false }
            }
            for entry in 0..<count {
                let at = 3 + entry * 16
                entries.append(SIMD4(Float(bytes[at]), Float(bytes[at + 4]), Float(bytes[at + 8]), Float(bytes[at + 12])))
            }
            return entries.count == count
        }
        let seed: [UInt8] = [0, 0, 2] + [UInt8](repeating: 7, count: 32)
        let bound = AllocationBound(perInputByte: 4)
        let checked = MutationRun.run("selftest-count-checked", seeds: [seed], count: 300, seed: 5, allocations: bound) {
            read($0, checksFirst: true)
        }
        #expect(checked.oversizedCount == 0, "\(checked)")
        #expect(checked.seedsRefused.isEmpty)
        #expect(checked.largestAllocation > 0)

        let reserved = MutationRun.run("selftest-count-reserved", seeds: [seed], count: 300, seed: 5, allocations: bound) {
            read($0, checksFirst: false)
        }
        #expect(reserved.oversizedCount > 0, "\(reserved)")
        let first = try #require(reserved.oversized.first)
        #expect(first.allocated > first.limit)
        #expect(first.bytes.count < 64)
        // The count the case carries is what it reserved for.
        let declared = Int(first.bytes[0]) << 16 | Int(first.bytes[1]) << 8 | Int(first.bytes[2])
        #expect(first.allocated >= declared * 16)
        #expect(reserved.largestAllocation <= AllocationWatch.ceiling)
    }

    /// A block past the ceiling does not wait to be recorded: the process
    /// stops before the decoder can fill it, and the log holds the case as it
    /// would for a trap. The seed decodes; the sweep's all-ones count at the
    /// head is the first case that asks for two gigabytes.
    @Test(.enabled(if: AllocationWatch.isAvailable && !underThreadSanitizer, "the watch or the exit test is not available in this process"))
    func aBlockPastTheCeilingStopsTheProcessAndTheLogNamesTheCase() async throws {
        try? FileManager.default.removeItem(at: MutationLog.url(for: "selftest-ceiling"))
        await #expect(processExitsWith: .failure) {
            _ = MutationRun.run("selftest-ceiling", seeds: [[0, 1, 9, 9]], count: 10, seed: 7,
                                allocations: AllocationBound(perInputByte: 1)) { bytes in
                guard let first = bytes.first else { return false }
                let block = malloc(Int(first) << 23)
                free(block)
                return true
            }
        }
        let entry = try #require(MutationLog.lastEntry(for: "selftest-ceiling"))
        #expect(entry.name == "selftest-ceiling")
        #expect(Int(entry.bytes[0]) << 23 > AllocationWatch.ceiling)
        try? FileManager.default.removeItem(at: MutationLog.url(for: "selftest-ceiling"))
    }
}
