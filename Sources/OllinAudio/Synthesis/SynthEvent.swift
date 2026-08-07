import Synchronization

/// Something a sketch asked for, on its way to the render thread.
///
/// Trivially copyable on purpose: it travels through a ring of preallocated
/// slots, and anything that needed allocating or reference counting could not
/// be written there.
struct SynthEvent {
    enum Kind: UInt8 { case noteOn, noteOff, allNotesOff, changeVoice }

    var kind: Kind = .noteOn
    var pitch: Double = 60
    var velocity: Double = 0.8
    /// How long to hold the note, in samples. Zero means hold it until a
    /// matching `noteOff` arrives.
    var durationSamples: Int = 0
    /// The voice to switch to, read only by `changeVoice`.
    var voice: Voice = Voice()
    /// The same length in seconds, which is what an offline render needs: it
    /// may run at a different rate from the hardware the note was asked on.
    var durationSeconds: Double = 0
}

/// A one-writer, one-reader queue of events between the sketch and the render
/// thread.
///
/// The render thread has a hard deadline (a few milliseconds), and missing it is
/// an audible click rather than a dropped frame. That rules out doing anything
/// there that could wait: no allocating, no locks. So a note does not reach the
/// voices directly. It is written into a slot that already exists, and the
/// render thread reads whatever has arrived when it next wakes up. The two ends
/// only ever agree through two counters, and each end writes just one of them.
///
/// The buffer is raw memory rather than an array because both ends touch it at
/// once, and an array is one value with one owner.
final class EventRing: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<SynthEvent>
    private let capacity: Int
    /// Where the sketch will write next. Only the sketch side moves it.
    private let writeIndex = Atomic<Int>(0)
    /// Where the render thread will read next. Only the render thread moves it.
    private let readIndex = Atomic<Int>(0)

    init(capacity: Int = 256) {
        self.capacity = capacity
        self.buffer = .allocate(capacity: capacity)
        self.buffer.initialize(repeating: SynthEvent(), count: capacity)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    /// Adds an event. Called from the sketch.
    ///
    /// Returns false if the render thread has not kept up, which means the
    /// sketch is asking for notes faster than they can be started. Dropping the
    /// event is the right answer there: waiting would stall `draw()`.
    @discardableResult
    func push(_ event: SynthEvent) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let next = (write + 1) % capacity
        guard next != readIndex.load(ordering: .acquiring) else { return false }
        buffer[write] = event
        // The event has to be visible before the count that publishes it.
        writeIndex.store(next, ordering: .releasing)
        return true
    }

    /// Takes the next event, or nil. Called from the render thread only.
    func pop() -> SynthEvent? {
        let read = readIndex.load(ordering: .relaxed)
        guard read != writeIndex.load(ordering: .acquiring) else { return nil }
        let event = buffer[read]
        readIndex.store((read + 1) % capacity, ordering: .releasing)
        return event
    }
}
