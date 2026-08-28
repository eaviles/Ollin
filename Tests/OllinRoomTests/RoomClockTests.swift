import Foundation
import Testing
@testable import OllinRoom

// The clock is arithmetic over numbers, so none of this needs a network.

@Suite struct RoomClockTests {

    @Test func anAnswerSaysHowFarApartTheTwoClocksAre() throws {
        // The question left at 10, the answer came back at 10.2, and the owner
        // said it was 100 when it wrote the answer. So the owner wrote it about
        // 0.1 s ago, and the owner's clock now reads about 100.1 while this one
        // reads 10.2: a difference of 89.9.
        let sample = try #require(RoomClock.sample(sentAt: 10, receivedAt: 10.2, ownerTime: 100))
        #expect(abs(sample.roundTrip - 0.2) < 1e-9)
        #expect(abs(sample.offset - 89.9) < 1e-9)
        #expect(abs(sample.error - 0.1) < 1e-9)
    }

    @Test func anAnswerFromBeforeTheQuestionIsRefused() {
        #expect(RoomClock.sample(sentAt: 10, receivedAt: 9, ownerTime: 100) == nil)
        #expect(RoomClock.sample(sentAt: 10, receivedAt: 11, ownerTime: .nan) == nil)
        #expect(RoomClock.sample(sentAt: 10, receivedAt: .infinity, ownerTime: 100) == nil)
    }

    @Test func theFastestAnswerIsTheOneBelieved() {
        var clock = RoomClock()
        clock.add(RoomClockSample(roundTrip: 0.40, offset: 5.0))
        clock.add(RoomClockSample(roundTrip: 0.02, offset: 7.0))
        clock.add(RoomClockSample(roundTrip: 0.30, offset: 6.0))
        // A slow answer is a delayed one, so the quickest round trip is the
        // honest sample, not the average of the three.
        #expect(clock.offset == 7.0)
        #expect(clock.error == 0.01)
    }

    @Test func theWindowKeepsOnlyTheRecentAnswers() {
        var clock = RoomClock()
        // A very fast answer, long ago, followed by a full window of slow ones.
        clock.add(RoomClockSample(roundTrip: 0.001, offset: 99))
        for step in 0..<RoomClock.sampleLimit {
            clock.add(RoomClockSample(roundTrip: 0.2 + Double(step) * 0.01, offset: 4))
        }
        #expect(clock.samples.count == RoomClock.sampleLimit)
        #expect(clock.offset == 4)
    }

    @Test func theOffsetSurvivesAChangeOfOwner() {
        var clock = RoomClock()
        clock.add(RoomClockSample(roundTrip: 0.02, offset: 12))
        #expect(clock.offset == 12)
        clock.reset()
        // The answers are forgotten, because they came from a clock that left.
        // The offset they produced stays, or room time would jump back to this
        // machine's own clock until the new owner answers.
        #expect(clock.samples.isEmpty)
        #expect(clock.offset == 12)
        #expect(clock.error == nil)
    }

    @Test func everyMachinePicksTheSameClockOwner() {
        let names = ["studio-mac-b2", "gallery-mac-a1", "desk-mac-c3"]
        #expect(RoomClock.owner(among: names) == "desk-mac-c3")
        #expect(RoomClock.owner(among: names.reversed()) == "desk-mac-c3")
        #expect(RoomClock.owner(among: ["only"]) == "only")
        #expect(RoomClock.owner(among: []) == nil)
    }
}
