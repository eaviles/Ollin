// RoomClock: how the machines in a room agree on what time it is.
//
// Every machine starts its own clock when its sketch starts, so two machines
// running the same piece are out of step by the difference between their start
// times, which is exactly the thing an audience sees. One peer owns the clock
// (the one whose name sorts first, so every peer picks the same one with no
// election), and the others ask it what time it is a few times a second.
//
// The estimate is the standard one for a request and its answer: the answer was
// written about half a round trip ago, so the owner's time now is the time it
// reported plus half the round trip, and half the round trip is also the honest
// error bar. Of several answers the fastest one is the most trustworthy, because
// a slow answer is a delayed one, so the lowest round trip in the recent window
// is the sample kept.
//
// All of it is arithmetic over numbers, so the tests need no network.

import Foundation

/// One answer from the clock owner, and what it says about the difference
/// between the two clocks.
public struct RoomClockSample: Sendable, Equatable {
    /// How long the question and its answer took, in seconds.
    public let roundTrip: Double
    /// Seconds to add to this machine's own clock to read the owner's.
    public let offset: Double

    public init(roundTrip: Double, offset: Double) {
        self.roundTrip = roundTrip
        self.offset = offset
    }

    /// Half the round trip: how far the estimate can be wrong.
    public var error: Double { roundTrip / 2 }
}

/// Keeps the recent answers and reports the offset the room should use.
struct RoomClock {

    /// How many answers to keep. Eight at a few per second is a window of a few
    /// seconds, long enough to catch a quiet moment on a busy network.
    static let sampleLimit = 8

    private(set) var samples: [RoomClockSample] = []

    /// Seconds to add to this machine's own clock to read the room's.
    ///
    /// It is held through a reset on purpose. When the clock owner leaves, the
    /// answers from the old owner are forgotten, but the offset they produced
    /// stays in force until the new owner answers, so room time keeps running
    /// instead of jumping back to this machine's own clock for a second.
    private(set) var offset: Double = 0

    /// How far the offset can be wrong, or `nil` when no answer has arrived from
    /// the owner in force.
    var error: Double? { best?.error }

    /// The fastest of the kept answers.
    var best: RoomClockSample? {
        samples.min { $0.roundTrip < $1.roundTrip }
    }

    /// Records one answer, dropping the oldest when the window is full.
    mutating func add(_ sample: RoomClockSample) {
        samples.append(sample)
        if samples.count > RoomClock.sampleLimit {
            samples.removeFirst(samples.count - RoomClock.sampleLimit)
        }
        if let best { offset = best.offset }
    }

    /// Forgets every answer, and keeps the offset they produced. Used when the
    /// clock owner changes, because the old answers came from a different clock.
    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    /// Works out one answer. `sentAt` and `receivedAt` are read from this
    /// machine's own clock; `ownerTime` is what the owner reported.
    static func sample(sentAt: Double, receivedAt: Double, ownerTime: Double) -> RoomClockSample? {
        let roundTrip = receivedAt - sentAt
        guard roundTrip >= 0, roundTrip.isFinite, ownerTime.isFinite else { return nil }
        return RoomClockSample(roundTrip: roundTrip, offset: ownerTime + roundTrip / 2 - receivedAt)
    }

    /// Which peer owns the clock: the name that sorts first, so every machine in
    /// the room picks the same one without asking.
    static func owner(among names: [String]) -> String? {
        names.min()
    }
}
