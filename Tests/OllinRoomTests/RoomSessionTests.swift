import Foundation
import Ollin
import Testing
@testable import OllinRoom

// Two whole rooms, in one process, over a transport that lives in memory. No
// socket is opened, so these run anywhere and answer on the next line.

@Suite struct RoomSessionTests {

    private func pair(
        seats: (Int?, Int?) = (nil, nil),
        clocks: (TestClock, TestClock) = (TestClock(), TestClock())
    ) -> (bus: MemoryRoomBus, a: RoomSession, b: RoomSession) {
        let bus = MemoryRoomBus()
        let a = RoomSession(transport: MemoryRoomTransport(name: "a-mac", bus: bus), clock: clocks.0.reader)
        let b = RoomSession(transport: MemoryRoomTransport(name: "b-mac", bus: bus), clock: clocks.1.reader)
        a.start(seat: seats.0, sketchName: "LeftHalf")
        b.start(seat: seats.1, sketchName: "RightHalf")
        return (bus, a, b)
    }

    // MARK: Who is here

    @Test func twoRoomsFindEachOtherAndSayWhatTheyAreRunning() {
        let (_, a, b) = pair()
        #expect(a.peers == ["b-mac"])
        #expect(b.peers == ["a-mac"])
        #expect(a.everyone == ["a-mac", "b-mac"])
        #expect(a.members["b-mac"]?.sketchName == "RightHalf")
        #expect(b.members["a-mac"]?.sketchName == "LeftHalf")
    }

    @Test func arrivalsAndDeparturesAreReportedOnce() {
        let (bus, a, _) = pair()
        #expect(a.drainJoined() == ["b-mac"])
        #expect(a.drainJoined().isEmpty)
        bus.leave("b-mac")
        #expect(a.drainLeft() == ["b-mac"])
        #expect(a.drainLeft().isEmpty)
        #expect(a.peers.isEmpty)
    }

    @Test func aRoomAloneIsStillARoom() {
        let bus = MemoryRoomBus()
        let only = RoomSession(transport: MemoryRoomTransport(name: "solo", bus: bus))
        only.start(seat: nil, sketchName: "Alone")
        #expect(only.peers.isEmpty)
        #expect(only.everyone == ["solo"])
        #expect(only.seat == 0)
        #expect(only.seatCount == 1)
        #expect(only.ownsClock)
        #expect(only.time >= 0)
    }

    // MARK: Seats

    @Test func seatsFollowTheNamesWhenNobodyAsksForOne() {
        let (_, a, b) = pair()
        #expect(a.seat == 0)
        #expect(b.seat == 1)
        #expect(a.seatCount == 2)
        #expect(b.seatCount == 2)
    }

    @Test func aMachineThatAsksForASeatKeepsIt() {
        let (_, a, b) = pair(seats: (2, 0))
        #expect(a.seat == 2)
        #expect(b.seat == 0)
        // Three seats, because somebody is sitting in the third.
        #expect(a.seatCount == 3)
        #expect(b.seatCount == 3)
    }

    // MARK: Values

    @Test func aValueSentOnOneMachineArrivesOnTheOther() throws {
        let (_, a, b) = pair()
        a.send("beat", .number(120), reliable: true, to: [])
        let message = try #require(b.message("beat"))
        #expect(message.number == 120)
        #expect(message.sender == "a-mac")
        // It went out, so it did not come back to the machine that sent it.
        #expect(a.message("beat") == nil)
    }

    @Test func everythingThatArrivedDrainsInOrderAndOnlyOnce() {
        let (_, a, b) = pair()
        for step in 1...5 { a.send("step", .int(step), reliable: true, to: []) }
        #expect(b.messages().compactMap(\.int) == [1, 2, 3, 4, 5])
        #expect(b.messages().isEmpty)
        // The latest is still there after the drain.
        #expect(b.message("step")?.int == 5)
    }

    @Test func aSketchThatNeverDrainsDoesNotGrowWithoutBound() {
        let (_, a, b) = pair()
        for step in 0..<4200 { a.send("flood", .int(step), reliable: false, to: []) }
        let drained = b.messages()
        #expect(drained.count == 4096)
        // The oldest went, the newest stayed.
        #expect(drained.last?.int == 4199)
    }

    @Test func aMessageThatIsNotOneOfOursIsIgnored() {
        // `a` is bound rather than discarded: a session that goes out of scope
        // leaves the room, which is what a live reload relies on.
        let (_, a, b) = pair()
        b.receive(Data([1, 2, 3]), from: "a-mac")
        b.receive(Data(), from: "a-mac")
        #expect(b.messages().isEmpty)
        #expect(b.peers == ["a-mac"])
        #expect(a.peers == ["b-mac"])
    }

    @Test func aRoomNobodyHoldsOnToLeaves() {
        let bus = MemoryRoomBus()
        let stayer = RoomSession(transport: MemoryRoomTransport(name: "a-mac", bus: bus))
        stayer.start(seat: nil, sketchName: "A")
        do {
            let passing = RoomSession(transport: MemoryRoomTransport(name: "b-mac", bus: bus))
            passing.start(seat: nil, sketchName: "B")
            #expect(stayer.peers == ["b-mac"])
        }
        // A live reload builds a fresh sketch and drops the old room. It has to
        // leave rather than sit there as a member nobody is drawing.
        #expect(stayer.peers.isEmpty)
    }

    @Test func aRoomThatStoppedSendsNothing() {
        let (_, a, b) = pair()
        a.stop()
        a.send("beat", .number(1), reliable: true, to: [])
        #expect(b.message("beat") == nil)
        #expect(a.peers.isEmpty)
    }

    // MARK: The clock

    @Test func aMachineThatJoinsLateAdoptsTheRoomsTime() {
        let bus = MemoryRoomBus()
        let early = TestClock()
        let late = TestClock()
        let a = RoomSession(transport: MemoryRoomTransport(name: "a-mac", bus: bus), clock: early.reader)
        a.start(seat: nil, sketchName: "A")
        // A has been running for five minutes when B opens the same room.
        early.advance(300)
        let b = RoomSession(transport: MemoryRoomTransport(name: "b-mac", bus: bus), clock: late.reader)
        b.start(seat: nil, sketchName: "B")

        #expect(a.ownsClock)
        #expect(!b.ownsClock)
        // Before it asks, B knows only its own clock, which started just now.
        #expect(b.time < 1)
        b.pumpClock()
        #expect(abs(b.time - a.time) < 0.01)
        #expect((b.clockError ?? 1) < 0.01)
        #expect(a.clockError == 0)
    }

    @Test func timeStaysInStepWhileBothMachinesRun() {
        let bus = MemoryRoomBus()
        let early = TestClock()
        let late = TestClock()
        let a = RoomSession(transport: MemoryRoomTransport(name: "a-mac", bus: bus), clock: early.reader)
        a.start(seat: nil, sketchName: "A")
        early.advance(42.5)
        let b = RoomSession(transport: MemoryRoomTransport(name: "b-mac", bus: bus), clock: late.reader)
        b.start(seat: nil, sketchName: "B")
        b.pumpClock()

        for _ in 0..<10 {
            early.advance(1.0 / 60)
            late.advance(1.0 / 60)
            #expect(abs(b.time - a.time) < 0.01)
        }
    }

    @Test func theAnswerAllowsForTheTimeItSpentOnTheWire() {
        let bus = MemoryRoomBus()
        let early = TestClock()
        let late = TestClock()
        let a = RoomSession(transport: MemoryRoomTransport(name: "a-mac", bus: bus), clock: early.reader)
        a.start(seat: nil, sketchName: "A")
        early.advance(100)
        let b = RoomSession(transport: MemoryRoomTransport(name: "b-mac", bus: bus), clock: late.reader)
        b.start(seat: nil, sketchName: "B")

        // Every delivery now costs 20 ms on both clocks, so the question and its
        // answer take 40 ms in all. Without the half-round-trip allowance B would
        // read 20 ms behind A.
        bus.beforeDelivery.withLock {
            $0 = { early.advance(0.02); late.advance(0.02) }
        }
        b.pumpClock()
        #expect(abs(b.time - a.time) < 0.005)
    }

    @Test func theRoomKeepsItsTimeWhenTheClockOwnerLeaves() {
        let bus = MemoryRoomBus()
        let early = TestClock()
        let late = TestClock()
        let a = RoomSession(transport: MemoryRoomTransport(name: "a-mac", bus: bus), clock: early.reader)
        a.start(seat: nil, sketchName: "A")
        early.advance(600)
        let b = RoomSession(transport: MemoryRoomTransport(name: "b-mac", bus: bus), clock: late.reader)
        b.start(seat: nil, sketchName: "B")
        b.pumpClock()
        let before = b.time

        a.stop()
        #expect(b.peers.isEmpty)
        #expect(b.ownsClock)
        // B now owns the clock, and the room's ten minutes did not disappear
        // with the machine that was keeping them.
        #expect(abs(b.time - before) < 0.01)
        #expect(b.clockError == 0)
    }
}
