import CoreVideo
import Foundation
import IOSurface
import Ollin
import OllinSamplePhotos
import Testing
@testable import OllinVision

/// The rule that decides which leftover buffers may be freed, on its own: no
/// heap, no model, only what one look found against how many analyses ran.
@Suite struct LeftoverBooksTests {

    /// `count` buffers at addresses from `start`, each with a surface id of
    /// its own.
    private func buffers(_ count: Int, from start: UInt, surface: UInt32 = 0) -> [UInt: UInt32] {
        var found: [UInt: UInt32] = [:]
        for i in 0..<count {
            found[start + UInt(i) * 160] = surface + UInt32(start / 160) + UInt32(i)
        }
        return found
    }

    @Test func theFirstLookFreesNothing() {
        var books = LeftoverBooks()
        let free = books.settle(found: buffers(30, from: 1600), analyses: 30, complete: true)
        #expect(free.isEmpty)
        #expect(books.known.count == 30)
        #expect(books.known.values.allSatisfy { $0.mayFree })
        #expect(books.misses == 0)
    }

    @Test func theSecondAgreeingLookFreesWhatTheFirstFound() {
        var books = LeftoverBooks()
        let first = buffers(30, from: 1600)
        _ = books.settle(found: first, analyses: 30, complete: true)
        let second = first.merging(buffers(30, from: 160_000)) { a, _ in a }
        let free = books.settle(found: second, analyses: 30, complete: true)
        #expect(Set(free) == Set(first.keys))
        // What is left is the thirty new ones, each waiting its turn.
        #expect(books.known.count == 30)
        #expect(Set(books.known.keys).isDisjoint(with: first.keys))
        #expect(books.known.values.allSatisfy { $0.mayFree })
    }

    @Test func askingWhetherALookAddsUpChangesNothing() {
        var books = LeftoverBooks()
        let first = buffers(30, from: 1600)
        #expect(books.agrees(found: first, analyses: 30))
        #expect(!books.agrees(found: first, analyses: 29))
        #expect(books.known.isEmpty && books.misses == 0)
        _ = books.settle(found: first, analyses: 30, complete: true)
        // A look that sees only some of what is known does not add up: that is
        // how a look at part of the heap says it cannot tell.
        var part = first
        part.removeValue(forKey: 1600)
        #expect(!books.agrees(found: part, analyses: 0))
        #expect(books.agrees(found: first, analyses: 0))
        #expect(books.known.count == 30 && books.misses == 0)
    }

    @Test func oneBufferMoreThanTheAnalysesFreesNothing() {
        var books = LeftoverBooks()
        let first = buffers(31, from: 1600)
        #expect(books.settle(found: first, analyses: 30, complete: true).isEmpty)
        #expect(books.misses == 1)
        // None of the thirty-one can be told from the one nobody counted, so
        // none is ever offered, while the looks after it carry on.
        let second = first.merging(buffers(30, from: 160_000)) { a, _ in a }
        #expect(books.settle(found: second, analyses: 30, complete: true).isEmpty)
        #expect(books.misses == 0)
        let third = second.merging(buffers(30, from: 320_000)) { a, _ in a }
        let free = books.settle(found: third, analyses: 30, complete: true)
        #expect(Set(free) == Set(buffers(30, from: 160_000).keys))
        #expect(Set(free).isDisjoint(with: first.keys))
    }

    @Test func oneBufferFewerThanTheAnalysesFreesNothing() {
        var books = LeftoverBooks()
        #expect(books.settle(found: buffers(29, from: 1600), analyses: 30, complete: true).isEmpty)
        #expect(books.known.values.allSatisfy { !$0.mayFree })
        #expect(books.misses == 1)
    }

    @Test func aBufferGoneFreesNothing() {
        var books = LeftoverBooks()
        var first = buffers(30, from: 1600)
        _ = books.settle(found: first, analyses: 30, complete: true)
        // Somebody else let one go. Then somebody else has a hand on these.
        first.removeValue(forKey: 1600)
        let second = first.merging(buffers(30, from: 160_000)) { a, _ in a }
        #expect(books.settle(found: second, analyses: 30, complete: true).isEmpty)
        #expect(books.known.values.allSatisfy { !$0.mayFree })
    }

    @Test func aNewBufferAtAnOldAddressIsNotTheOldOne() {
        var books = LeftoverBooks()
        let first = buffers(30, from: 1600)
        _ = books.settle(found: first, analyses: 30, complete: true)
        // The same thirty addresses, every one now a different buffer.
        let reused = buffers(30, from: 1600, surface: 9000)
        #expect(books.settle(found: reused, analyses: 30, complete: true).isEmpty)
        #expect(books.misses == 1)
        #expect(books.known.values.allSatisfy { !$0.mayFree })
    }

    @Test func anIncompleteLookFreesNothing() {
        var books = LeftoverBooks()
        let first = buffers(30, from: 1600)
        _ = books.settle(found: first, analyses: 30, complete: true)
        let second = first.merging(buffers(30, from: 160_000)) { a, _ in a }
        #expect(books.settle(found: second, analyses: 30, complete: false).isEmpty)
        #expect(books.misses == 1)
    }

    @Test func aBufferKeptIsNeverOfferedAgain() throws {
        var books = LeftoverBooks()
        let first = buffers(30, from: 1600)
        _ = books.settle(found: first, analyses: 30, complete: true)
        let second = first.merging(buffers(30, from: 160_000)) { a, _ in a }
        let free = books.settle(found: second, analyses: 30, complete: true)
        let kept = try #require(free.first)
        books.keep(kept, surface: first[kept]!)
        var third = buffers(30, from: 160_000).merging(buffers(30, from: 320_000)) { a, _ in a }
        third[kept] = first[kept]!
        let later = books.settle(found: third, analyses: 30, complete: true)
        #expect(!later.contains(kept))
        #expect(later.count == 30)
    }

    @Test func aSystemThatLeavesNoneIsARunOfMissesThatMetNone() {
        var books = LeftoverBooks()
        for _ in 0..<BodyPose3DLeftovers.patience {
            #expect(books.settle(found: [:], analyses: 30, complete: true).isEmpty)
        }
        #expect(books.misses == BodyPose3DLeftovers.patience)
        #expect(!books.missesMetLeftovers)
    }

    @Test func buffersThatDoNotAddUpAreARunOfMissesThatMetSome() {
        var books = LeftoverBooks()
        var found: [UInt: UInt32] = [:]
        for look in 0..<BodyPose3DLeftovers.patience {
            found.merge(buffers(12, from: UInt(1600 + look * 160_000))) { a, _ in a }
            #expect(books.settle(found: found, analyses: 30, complete: true).isEmpty)
        }
        #expect(books.misses == BodyPose3DLeftovers.patience)
        #expect(books.missesMetLeftovers)
    }
}

#if os(macOS)

/// The sweep against the real heap. These share the process's one ledger and
/// its switch, so they run one at a time. They count leftovers alive, never
/// the process's footprint: other suites run in the same process.
@Suite(.serialized) struct BodyPose3DLeftoverTests {

    private static let ledger = BodyPose3DLeftovers.shared

    /// Whether the walk can run here at all. It stands down where the
    /// allocator is another kind than the one it was proven on.
    private static let walks: ConditionTrait = .enabled("the heap walk stands down on this system's allocator") {
        ledger.census() != nil
    }

    /// The model over a blank frame, made once: `nil` where it has no compute
    /// device.
    private static let blank = Task<Body3D??, Never> {
        try? await BodyTracker3D.detect(in: Image(width: 128, height: 128, color: .white))
    }

    private static let modelRuns: ConditionTrait = .enabled("the 3D body model has no compute device here") {
        await blank.value != nil
    }

    /// Whether this process runs in a virtual machine, which a CI runner is.
    /// The request leaves no buffer behind on the runner (macOS 26, no Neural
    /// Engine: 132 analyses on 2026-11-21 and none of the shape, while a
    /// planted one was counted), so there the two tests that run the model
    /// take either answer. Whether the system's version or the machine decides
    /// is not known, so on a real Mac they still ask for the leftovers, and a
    /// Mac that leaves none fails them, which is news worth having.
    private static let inVirtualMachine: Bool = {
        var present: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &present, &size, nil, 0) == 0 && present != 0
    }()

    /// A pixel buffer made the way a leftover is: its shape, its format, a
    /// surface from Core Video.
    private func plant() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        CVPixelBufferCreate(nil, BodyPose3DLeftovers.width, BodyPose3DLeftovers.height,
                            kCVPixelFormatType_OneComponent16Half, attributes, &buffer)
        return try #require(buffer)
    }

    private func surface(of buffer: CVPixelBuffer) throws -> IOSurfaceRef {
        try #require(CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue())
    }

    @Test(walks) func aSurfaceTellsWhetherItsBufferIsAlive() throws {
        // The witness the tests below lean on, checked both ways: in use while
        // its buffer lives, not in use once the buffer is gone.
        var buffer: CVPixelBuffer? = try plant()
        let witness = try surface(of: buffer!)
        #expect(IOSurfaceIsInUse(witness))
        buffer = nil
        #expect(!IOSurfaceIsInUse(witness))
    }

    @Test(walks) func onlyABufferWithTwoOwnersIsCounted() throws {
        let ledger = Self.ledger
        let before = try #require(ledger.census())
        // One owner: this test.
        let buffer = try plant()
        #expect(ledger.census() == before)
        // Two: counted.
        let second = Unmanaged.passRetained(buffer)
        #expect(ledger.census() == before + 1)
        // Three: not a leftover.
        let third = Unmanaged.passRetained(buffer)
        #expect(ledger.census() == before)
        third.release()
        second.release()
        #expect(ledger.census() == before)
        // And every count the walk took, it gave back.
        #expect(IOSurfaceIsInUse(try surface(of: buffer)))
        #expect(CVPixelBufferGetWidth(buffer) == BodyPose3DLeftovers.width)
    }

    @Test(walks) func aBufferNoAnalysisMadeIsRefused() throws {
        let ledger = Self.ledger
        let wasOn = ledger.isOn
        defer {
            ledger.isOn = wasOn
            ledger.startOver()
        }
        ledger.isOn = true
        ledger.startOver()
        ledger.sweepNow(whole: true)   // whatever is in the heap already is on the books

        // A leftover in every way the walk can see: the shape, the format, the
        // maker, two owners that hold on. Only no analysis made it.
        let buffer = try plant()
        let second = Unmanaged.passRetained(buffer)
        defer { second.release() }
        let witness = try surface(of: buffer)
        let opening = ledger.tally
        for _ in 0..<4 {
            ledger.sweepNow(whole: true)
            #expect(IOSurfaceIsInUse(witness))
        }
        let tally = ledger.tally
        #expect(tally.freed == opening.freed)
        // Each of the four was a look at the whole heap, the buffer in it: a
        // sweep that waits its turn would prove nothing here.
        #expect(tally.wholeLooks == opening.wholeLooks + 4, "\(tally)")
        #expect(tally.alive >= 1)
        #expect(CVPixelBufferGetHeight(buffer) == BodyPose3DLeftovers.height)
    }

    @Test(walks) func whereNothingIsLeftBehindTheSweepStandsDown() throws {
        defer { BodyPose3DLeftovers.wholeLooksWait = true }
        BodyPose3DLeftovers.wholeLooksWait = false
        // A ledger of its own, so no other suite's analyses are counted in,
        // and analyses that leave nothing, as the request's do on a system
        // without the leak.
        let ledger = BodyPose3DLeftovers()
        let (interval, patience) = (BodyPose3DLeftovers.interval, BodyPose3DLeftovers.patience)

        // On a system with the leak, earlier tests' leftovers are alive in
        // this process. They go on the books first, accounted for.
        ledger.isOn = false
        let aliveBefore = try #require(ledger.census())
        for _ in 0..<aliveBefore { ledger.began(); ledger.ended() }
        ledger.isOn = true
        ledger.sweepNow(whole: true)

        // With those in the heap a run of looks that find no new one is a
        // leak that does not add up, which is said out loud at the last of
        // them: that case stops well short. On a clean heap it runs out.
        let looks = aliveBefore == 0 ? patience : patience / 2
        for look in 1...looks {
            #expect(ledger.tally.stoodDown == nil)
            for _ in 0..<interval { ledger.began(); ledger.ended() }
            #expect(ledger.tally.wholeLooks == look + 1, "\(ledger.tally)")
        }
        let tally = ledger.tally
        #expect(tally.freed == 0)
        #expect(tally.agreed <= 1)   // the opening look, and none after it
        guard aliveBefore == 0, try #require(ledger.census()) == 0 else {
            #expect(tally.alive >= aliveBefore)
            return
        }
        // Nothing of the shape anywhere: the reason nobody is told.
        #expect(tally.stoodDown == BodyPose3DLeftovers.nothingLeftBehind)
        // Stood down, it never looks again.
        for _ in 0..<(2 * interval) { ledger.began(); ledger.ended() }
        #expect(ledger.tally.looks == tally.looks)
    }

    @Test(walks, modelRuns) @MainActor
    func withTheSwitchOffEveryAnalysisLeavesOne() async throws {
        let ledger = Self.ledger
        let wasOn = ledger.isOn
        defer { ledger.isOn = wasOn; ledger.startOver() }
        ledger.isOn = false

        let source = FrameSourceTests.ManualFrameSource()
        let tracker = BodyTracker3D(source)
        let frame = FrameBox(SamplePhoto.reaching.load().currentCGImage())
        let analyzer = SourceAnalyzers.analyzer(for: source)
        await analyzer.analyzeNow(frame)   // the model's own first-run buffers come and go here
        #expect(tracker.body != nil)

        let before = try #require(ledger.census())
        let analyses = 12
        for _ in 0..<analyses { await analyzer.analyzeNow(frame) }
        let after = try #require(ledger.census())
        let left = after - before
        if Self.inVirtualMachine, left == 0 { return }   // this system leaves none
        // At least: another suite may run the model in this process too.
        #expect(left >= analyses)
    }

    @Test(walks, modelRuns) @MainActor
    func withTheSwitchOnTheLeftoversAreFreed() async throws {
        let ledger = Self.ledger
        let wasOn = ledger.isOn
        defer {
            ledger.isOn = wasOn
            BodyPose3DLeftovers.wholeLooksWait = true
            ledger.startOver()
        }
        // Every sweep takes a whole look when it needs one, so the count of
        // looks does not hang on how fast this machine runs the model.
        BodyPose3DLeftovers.wholeLooksWait = false

        let source = FrameSourceTests.ManualFrameSource()
        let tracker = BodyTracker3D(source)
        let frame = FrameBox(SamplePhoto.reaching.load().currentCGImage())
        let analyzer = SourceAnalyzers.analyzer(for: source)
        ledger.isOn = false
        await analyzer.analyzeNow(frame)
        let first = try #require(tracker.body)

        // Start from the heap as it stands: what earlier tests left is on the
        // books and stays there.
        ledger.startOver()
        ledger.sweepNow(whole: true)
        ledger.isOn = true
        let before = try #require(ledger.census())

        let interval = BodyPose3DLeftovers.interval
        for _ in 0..<(4 * interval) { await analyzer.analyzeNow(frame) }

        let after = try #require(ledger.census())
        let tally = ledger.tally
        #expect(tally.stoodDown == nil)
        if Self.inVirtualMachine, after == before, tally.freed == 0 {
            // This system leaves none. Then every sweep looked at the whole
            // heap with the model's own memory in it, found nothing of the
            // shape, and freed nothing; four looks are short of standing down.
            #expect(tally.wholeLooks >= 5, "\(tally)")
            #expect(tally.alive == 0, "\(tally)")
        } else {
            // Without the sweep there would be 4 intervals more. With it, the
            // last interval's are waiting their turn and the rest are gone.
            #expect(after - before < 2 * interval, "\(after - before) more leftovers alive; \(tally)")
            #expect(tally.freed >= interval, "\(tally)")
            // Once the first leftovers are freed, the next land where they
            // sat, and a look at those places alone settles the count.
            #expect(tally.looks > tally.wholeLooks, "no quick look settled; \(tally)")
        }

        // The pose that comes back is the pose from before anything was freed.
        let last = try #require(tracker.body)
        for joint in BodyJoint3D.allCases {
            #expect(first.position(joint) == last.position(joint))
        }
    }
}

#endif
