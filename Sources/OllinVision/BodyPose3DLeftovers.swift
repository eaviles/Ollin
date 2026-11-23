import CoreVideo
import Foundation
import IOSurface
import os
internal import COllinHeapWalk

/// What the sweep knows about the leftover buffers between two looks at the
/// heap, and the rule that decides which of them may be freed. Kept apart from
/// the heap so the rule can be tested on its own.
///
/// The rule is the count of analyses. Every analysis leaves exactly one
/// leftover, so a look agrees when it finds exactly as many new ones as there
/// were analyses since the last look, and nothing it knew has gone. A buffer
/// may be freed only when it was new at a look that agreed and is still there,
/// the same buffer, at the next look that agrees. Anything else frees nothing:
/// a buffer more or fewer than the analyses account for means something else
/// is making or dropping buffers of this shape, and then none of them can be
/// told from one somebody owns.
struct LeftoverBooks: Sendable {

    struct Entry: Sendable, Equatable {
        /// The id of the buffer's surface. An address is used again once its
        /// block is returned and an id is not, so the pair is what "the same
        /// buffer as last time" means.
        var surface: UInt32
        /// Whether the next look that agrees may free it.
        var mayFree: Bool
    }

    /// Every leftover-shaped buffer the last look found and left in place, by
    /// address.
    private(set) var known: [UInt: Entry] = [:]

    /// Looks in a row that did not agree with the count of analyses.
    private(set) var misses = 0

    /// Whether any look of the current run of misses found a buffer of the
    /// leftovers' shape at all. A run that found none is a system with no
    /// leak; a run that found some is a leak that looks different.
    private(set) var missesMetLeftovers = false

    /// Whether a look's findings add up: nothing known has gone, and exactly
    /// as many new buffers are there as analyses ran. Changes nothing.
    func agrees(found: [UInt: UInt32], analyses: Int) -> Bool {
        var stayed = 0
        for (address, surface) in found where known[address]?.surface == surface {
            stayed += 1
        }
        return known.count == stayed && found.count - stayed == analyses
    }

    /// Settles one look. `found` is every leftover-shaped buffer with two
    /// owners, by address, with its surface's id; `analyses` is how many
    /// analyses ran since the last look; `complete` is whether the look saw
    /// the whole heap. Returns the addresses that may be freed now and forgets
    /// them; call `keep` for any the caller leaves in place after all.
    mutating func settle(found: [UInt: UInt32], analyses: Int, complete: Bool) -> [UInt] {
        let agrees = complete && self.agrees(found: found, analyses: analyses)

        var next: [UInt: Entry] = [:]
        var free: [UInt] = []
        for (address, surface) in found {
            if let before = known[address], before.surface == surface {
                if agrees, before.mayFree {
                    free.append(address)
                } else {
                    // Seen before and not freed now: it had its chance, or
                    // this look cast doubt on all of them.
                    next[address] = Entry(surface: surface, mayFree: false)
                }
            } else {
                next[address] = Entry(surface: surface, mayFree: agrees)
            }
        }
        known = next
        if agrees {
            misses = 0
            missesMetLeftovers = false
        } else {
            misses += 1
            if !found.isEmpty { missesMetLeftovers = true }
        }
        return free
    }

    /// A buffer `settle` offered that was left in place after all: it stays
    /// known and is never offered again.
    mutating func keep(_ address: UInt, surface: UInt32) {
        known[address] = Entry(surface: surface, mayFree: false)
    }
}

/// Finds and frees the pixel buffers the system's 3D body pose request leaves
/// behind.
///
/// Each analysis by that request leaves one pixel buffer that nothing refers
/// to afterwards: 48 by 2736, one 16-bit float component, about a third of a
/// megabyte, with two owners that never let go. At a camera's thirty analyses
/// a second that is a gigabyte every minute and a half. Nothing the caller
/// holds leads to those buffers, so they are found where they sit: every
/// `interval` analyses the heap is looked at for pixel buffers with exactly
/// two owners, and `LeftoverBooks` decides which of the ones of that shape may
/// be freed.
///
/// It frees only what matches what was measured, checked while it runs and
/// never by the system's version: the shape and format, a surface made
/// through Core Video, exactly two owners at two looks in a row, one more
/// leftover for each analysis and none gone. Where any of that differs it
/// frees nothing, and after `patience` looks in a row that disagree it stops
/// looking for the rest of the run.
///
/// A look holds the allocator's lock and takes no memory inside it. What
/// makes a found buffer safe to look at afterwards is the third owner the look
/// takes under that lock, an atomic step that succeeds only on a buffer with
/// two owners at that instant, so a buffer some other thread is about to drop
/// is either held first or never touched.
///
/// There are two kinds of look, because the allocator's listing visits every
/// block in the heap and so costs more the more a process holds: milliseconds
/// in a small sketch, and more with every minute a tracker runs, since the
/// request leaves small objects behind as well. A whole look uses that
/// listing, and remembers which stretches of the heap the leftovers sat in.
/// A quick look reads only those stretches, where the next leftovers land
/// too, and costs the same however large the heap. Every sweep tries the quick
/// look; when its findings do not add up (a leftover landed in a stretch not
/// yet remembered) they are let go untouched and a whole look runs instead, no
/// more often than `wholeLookShare` of the time allows. A whole look also
/// runs every `auditGap` or so, so what the quick looks cannot see is checked.
///
/// macOS only: the walk was proven on the Mac's allocator. Elsewhere nothing
/// is learned and the sweep never runs.
final class BodyPose3DLeftovers: @unchecked Sendable {

    /// The one ledger every analysis in the process is counted through.
    static let shared = BodyPose3DLeftovers()

    /// How many analyses pass between two looks at the heap.
    static let interval = 30

    /// How many twice-owned pixel buffers one look has room for. A look that
    /// meets more than this does not agree, and frees nothing.
    static let room = 8192

    /// How many looks in a row may disagree with the count of analyses before
    /// the sweep stops for the rest of the run.
    static let patience = 8

    /// How many stretches of the heap a quick look remembers. Past this, new
    /// ones are not remembered and a leftover that lands in one waits for a
    /// whole look.
    static let regionRoom = 256

    /// The largest stretch a quick look reads, in bytes. A larger one is not
    /// remembered.
    static let regionLimit = 1 << 18

    /// How long quick looks may go on before a whole look checks the rest of
    /// the heap, in seconds, and the most of the time those checks may hold
    /// the allocator: a whole look grows slower as the heap grows, so the
    /// checks grow rarer with it.
    static let auditGap = 60.0
    static let auditShare = 0.0001

    /// The most of the time whole looks may hold the allocator: after one
    /// that held it for a time `t`, the next waits at least `t` divided by
    /// this, and never less than `shortestWholeLookGap`.
    static let wholeLookShare = 0.003

    /// The least time between two whole looks, in seconds.
    static let shortestWholeLookGap = 1.0

    /// Whether a whole look waits its turn, by the two limits above. The tests
    /// turn the wait off, so a sweep that needs a whole look takes it at once,
    /// however fast the machine runs the analyses between two sweeps.
    nonisolated(unsafe) static var wholeLooksWait = true

    /// Why the sweep stands down on a system that leaves nothing behind.
    static let nothingLeftBehind = "no buffers are left behind on this system"

    /// Why it stands down where buffers of the leftovers' shape are there and
    /// do not add up.
    static let doNotAddUp = "the buffers the 3D body pose request leaves behind do not add up as they were measured"

    /// The leftovers' shape: the pose network's 57 maps of 48 by 48, stacked.
    static let width = 48
    static let height = 2736

    /// What the sweep has done so far.
    struct Tally: Sendable, Equatable {
        /// Looks that were settled, of either kind.
        var looks = 0
        /// Of those, how many were whole looks.
        var wholeLooks = 0
        /// Looks that agreed with the count of analyses.
        var agreed = 0
        /// Quick looks whose findings did not add up and were let go.
        var quickMisses = 0
        /// Sweeps that wanted a whole look and had to wait for the next one's turn.
        var waits = 0
        /// Buffers freed.
        var freed = 0
        /// Leftover-shaped buffers known and in place after the last look.
        var alive = 0
        /// The longest the allocator stayed locked for one look, in seconds.
        var longestPause = 0.0
        /// Every look's pause, added up, in seconds.
        var totalPause = 0.0
        /// The longest a quick look held it, and all of them added up.
        var longestQuickPause = 0.0
        var totalQuickPause = 0.0
        /// Quick looks taken, settled or not.
        var quickLooks = 0
        /// The longest one whole sweep took, look and frees, in seconds.
        var longestSweep = 0.0
        /// Why the sweep stopped for the rest of the run, or `nil` while it runs.
        var stoodDown: String?
    }

    /// The learned look of a pixel buffer and the memory a walk writes into,
    /// set aside once so no walk takes any.
    private struct Heap {
        var mark: ollin_heap_mark
        let scratch: UnsafeMutablePointer<UInt>
        /// Beside each address in `scratch`, the stretch of heap it sits in.
        let around: UnsafeMutablePointer<ollin_heap_region>
        /// The stretches a leftover has sat in before, for the quick look.
        let regions: UnsafeMutablePointer<ollin_heap_region>
        /// Where a quick look copies a stretch to read it.
        let copy: UnsafeMutableRawPointer
    }

    private struct State: @unchecked Sendable {
        var inFlight = 0
        /// Analyses since the last look that was settled.
        var analyses = 0
        /// Analyses since the last sweep, settled or not.
        var sinceSweep = 0
        var books = LeftoverBooks()
        var tally = Tally()
        var heap: Heap?
        var triedLearning = false
        var remembered: Set<UInt> = []
        var regionCount = 0
        /// When the last whole look ended and how long it held the allocator.
        var lastWholeLook: UInt64 = 0
        var lastWholePause = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let on = OSAllocatedUnfairLock(initialState: true)
    private let reports: Bool

    init() {
        reports = ProcessInfo.processInfo.environment["OLLIN_POSE3D_LEFTOVERS_REPORT"] != nil
    }

    /// Whether leftovers are freed. Off, analyses are still counted, so
    /// turning it back on picks up where the count stands.
    var isOn: Bool {
        get { on.withLock { $0 } }
        set { on.withLock { $0 = newValue } }
    }

    /// What the sweep has done so far.
    var tally: Tally { state.withLock { $0.tally } }

    /// Runs one analysis by the 3D body pose request and counts it. Every
    /// perform of that request in the module goes through here: the count is
    /// what the sweep's rule rests on.
    static func counted<T>(_ analysis: () async throws -> T) async rethrows -> T {
        #if os(macOS)
        shared.began()
        defer { shared.ended() }
        #endif
        return try await analysis()
    }

    func began() {
        state.withLock { $0.inFlight += 1 }
    }

    /// Counts the analysis and, every `interval` of them, looks at the heap.
    /// A look waits for a moment when no analysis is under way: a buffer one
    /// is still working with must not be met half-made.
    func ended() {
        let isOn = isOn
        state.withLockUnchecked { state in
            state.inFlight -= 1
            state.analyses += 1
            state.sinceSweep += 1
            guard isOn, state.sinceSweep >= Self.interval, state.inFlight == 0 else { return }
            sweep(&state)
        }
    }

    /// One sweep now, whatever the count stands at. The tests' way in. With
    /// `whole`, the sweep is a whole look: no quick look first, and no wait
    /// for its turn.
    func sweepNow(whole: Bool = false) {
        state.withLockUnchecked { sweep(&$0, whole: whole) }
    }

    /// How many leftover-shaped buffers with two owners are alive right now,
    /// or `nil` where the walk cannot run. Looks without freeing or keeping
    /// books, under the ledger's lock so it never meets a sweep halfway.
    func census() -> Int? {
        state.withLockUnchecked { state in
            guard var heap = learned(&state) else { return nil }
            var report = ollin_heap_walk_report()
            ollin_heap_walk(&heap.mark, heap.scratch, nil, Self.room, &report)
            var count = 0
            for i in 0..<Int(report.held) {
                if Self.leftoverSurface(at: heap.scratch[i]) != nil { count += 1 }
                ollin_heap_release(heap.scratch[i], 1)
            }
            return report.status == 0 ? count : nil
        }
    }

    /// Forgets everything known and starts the books again, as a new process
    /// would. For the tests, which share one process.
    func startOver() {
        state.withLockUnchecked { state in
            state.books = LeftoverBooks()
            state.tally = Tally()
            state.analyses = 0
            state.sinceSweep = 0
            state.remembered = []
            state.regionCount = 0
            state.lastWholeLook = 0
            state.lastWholePause = 0
        }
    }

    // MARK: The sweep

    /// The learned heap, learning it on first use. `nil` once learning has
    /// failed: the sweep has then stood down and says why.
    private func learned(_ state: inout State) -> Heap? {
        if let heap = state.heap { return heap }
        guard !state.triedLearning else { return nil }
        state.triedLearning = true
        let scratch = UnsafeMutablePointer<UInt>.allocate(capacity: Self.room)
        var mark = ollin_heap_mark()
        guard ollin_heap_mark_learn(&mark, scratch, Self.room) != 0 else {
            scratch.deallocate()
            standDown(&state, "memory on this system is not laid out as it was where the cleanup was proven")
            return nil
        }
        let heap = Heap(mark: mark, scratch: scratch,
                        around: .allocate(capacity: Self.room),
                        regions: .allocate(capacity: Self.regionRoom),
                        copy: .allocate(byteCount: Self.regionLimit, alignment: 16))
        // Touched once now, so no page of it is first handed over mid-look.
        heap.copy.initializeMemory(as: UInt8.self, repeating: 0, count: Self.regionLimit)
        state.heap = heap
        return heap
    }

    private func sweep(_ state: inout State, whole: Bool = false) {
        guard state.tally.stoodDown == nil, var heap = learned(&state) else { return }
        let begun = DispatchTime.now().uptimeNanoseconds
        state.sinceSweep = 0

        // The quick look first: only the stretches a leftover has sat in
        // before. Every so often it is skipped, so a whole look checks the rest.
        let sinceWhole = Double(begun - state.lastWholeLook) / 1e9
        let auditGap = max(Self.auditGap, state.lastWholePause / Self.auditShare)
        if !whole, state.regionCount > 0, sinceWhole < auditGap {
            var report = ollin_heap_walk_report()
            ollin_heap_probe(&heap.mark, heap.regions, state.regionCount, heap.copy, Self.regionLimit,
                             heap.scratch, Self.room, &report)
            let found = leftovers(held: Int(report.held), heap)
            let pause = Double(report.nanoseconds) / 1e9
            state.tally.quickLooks += 1
            state.tally.longestQuickPause = max(state.tally.longestQuickPause, pause)
            state.tally.totalQuickPause += pause
            if report.dropped == 0, state.books.agrees(found: found, analyses: state.analyses) {
                settle(&state, found: found, complete: true, heap: heap, begun: begun)
                return
            }
            // It does not add up from here, which says only that a leftover
            // sits somewhere not yet remembered. Nothing is concluded from it.
            for address in found.keys { ollin_heap_release(address, 1) }
            state.tally.quickMisses += 1
        }

        // The whole look, when its turn has come.
        let gap = max(Self.shortestWholeLookGap, state.lastWholePause / Self.wholeLookShare)
        guard whole || !Self.wholeLooksWait || state.lastWholeLook == 0 || sinceWhole >= gap else {
            state.tally.waits += 1
            return
        }
        var report = ollin_heap_walk_report()
        ollin_heap_walk(&heap.mark, heap.scratch, heap.around, Self.room, &report)
        // Each leftover's stretch of heap is remembered for the quick looks.
        for i in 0..<Int(report.held) where state.regionCount < Self.regionRoom {
            let region = heap.around[i]
            guard region.size > 0, region.size <= Self.regionLimit,
                  !state.remembered.contains(region.base),
                  Self.leftoverSurface(at: heap.scratch[i]) != nil else { continue }
            state.remembered.insert(region.base)
            heap.regions[state.regionCount] = region
            state.regionCount += 1
        }
        let found = leftovers(held: Int(report.held), heap)
        let pause = Double(report.nanoseconds) / 1e9
        state.lastWholePause = pause
        state.tally.wholeLooks += 1
        state.tally.longestPause = max(state.tally.longestPause, pause)
        state.tally.totalPause += pause
        settle(&state, found: found, complete: report.status == 0 && report.dropped == 0,
               heap: heap, begun: begun)
        state.lastWholeLook = DispatchTime.now().uptimeNanoseconds
    }

    /// Asks each buffer a look came back holding what it is. The ones of the
    /// leftovers' shape are returned, still held, by address with their
    /// surface's id; every other is let go as it was found.
    private func leftovers(held: Int, _ heap: Heap) -> [UInt: UInt32] {
        var found: [UInt: UInt32] = [:]
        for i in 0..<held {
            let address = heap.scratch[i]
            if let surface = Self.leftoverSurface(at: address) {
                found[address] = surface
            } else {
                ollin_heap_release(address, 1)
            }
        }
        return found
    }

    /// Puts one look's findings through the books, frees what they offer, and
    /// lets go of the rest.
    private func settle(_ state: inout State, found: [UInt: UInt32], complete: Bool,
                        heap: Heap, begun: UInt64) {
        var heap = heap
        let offered = Set(state.books.settle(found: found, analyses: state.analyses, complete: complete))
        var freed = 0
        for (address, surface) in found {
            // Three owners: the two that never let go, and the look's. Any
            // other count means somebody else has taken or dropped one since,
            // and then it is not a leftover.
            if offered.contains(address), ollin_heap_owner_count(address, &heap.mark) == 3 {
                ollin_heap_release(address, 3)
                freed += 1
            } else {
                if offered.contains(address) { state.books.keep(address, surface: surface) }
                ollin_heap_release(address, 1)
            }
        }

        state.analyses = 0
        state.tally.looks += 1
        if state.books.misses == 0 { state.tally.agreed += 1 }
        state.tally.freed += freed
        state.tally.alive = state.books.known.count
        state.tally.longestSweep = max(state.tally.longestSweep,
                                       Double(DispatchTime.now().uptimeNanoseconds - begun) / 1e9)

        if state.books.misses >= Self.patience {
            // Nothing of the shape in sight is a system with no leak, and
            // there is nothing to say. Buffers of the shape that do not add
            // up is a leak this cleanup does not know.
            standDown(&state, state.books.missesMetLeftovers ? Self.doNotAddUp : nil)
        }
        if reports, state.tally.looks % 10 == 0 || state.tally.stoodDown != nil {
            let tally = state.tally
            Self.note(String(format: "3D pose leftovers: %d looks (%d whole), %d agreed, %d freed, %d in place; quick: %d taken, %d let go, longest pause %.2f ms, mean %.2f ms; whole: longest pause %.2f ms, mean %.2f ms, %d waited; longest sweep %.2f ms",
                             tally.looks, tally.wholeLooks, tally.agreed, tally.freed, tally.alive,
                             tally.quickLooks, tally.quickMisses, tally.longestQuickPause * 1000,
                             tally.totalQuickPause * 1000 / Double(max(1, tally.quickLooks)),
                             tally.longestPause * 1000,
                             tally.totalPause * 1000 / Double(max(1, tally.wholeLooks)),
                             tally.waits, tally.longestSweep * 1000))
        }
    }

    /// Stops the sweep for the rest of the run. With a reason, the developer
    /// is told once; without one (no leak here) nothing is said.
    private func standDown(_ state: inout State, _ reason: String?) {
        state.tally.stoodDown = reason ?? Self.nothingLeftBehind
        guard let reason else { return }
        Self.note("BodyTracker3D's cleanup is off for this run: \(reason), so nothing is freed and memory may grow while the tracker runs.")
    }

    private static func note(_ line: String) {
        FileHandle.standardError.write(Data("OllinVision: \(line)\n".utf8))
    }

    /// The id of the surface behind the pixel buffer at `address` when the
    /// buffer has the leftovers' shape, format, and maker, and `nil` for any
    /// other buffer. Called only on a buffer the walk holds, so it is alive.
    private static func leftoverSurface(at address: UInt) -> UInt32? {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return nil }
        let buffer = Unmanaged<CVPixelBuffer>.fromOpaque(pointer).takeUnretainedValue()
        guard CVPixelBufferGetWidth(buffer) == width,
              CVPixelBufferGetHeight(buffer) == height,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent16Half,
              let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue(),
              IOSurfaceCopyValue(surface, kIOSurfaceName) as? String == "CoreVideo" else { return nil }
        return IOSurfaceGetID(surface)
    }
}
