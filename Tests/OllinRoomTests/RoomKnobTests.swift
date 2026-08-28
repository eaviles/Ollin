import Foundation
import Ollin
import Testing
@testable import OllinRoom

// The knob half of a room: one machine's `@Param` driving the same knob
// everywhere else, and a key from another machine driving one knob. Both run
// over the in-memory transport, so no socket is opened here either.

/// A sketch wearing a few knobs of different kinds.
private final class RoomProbeSketch: Sketch {
    enum Look: String, CaseIterable, ParamOption { case dawn, dusk, noir }

    @Param(0.1...4.0) var speed = 1.4
    @Param(1...12) var layers = 6
    @Param var trails = true
    @Param var look = Look.dusk
    @Param var accent = Color.purple
}

@MainActor @Suite struct RoomKnobTests {

    private func pair(on bus: MemoryRoomBus = MemoryRoomBus()) -> (a: Room, b: Room, sketchA: Sketch, sketchB: Sketch) {
        let a = Room(transport: MemoryRoomTransport(name: "a-mac", bus: bus))
        let b = Room(transport: MemoryRoomTransport(name: "b-mac", bus: bus))
        let sketchA = RoomProbeSketch()
        let sketchB = RoomProbeSketch()
        a.setup(sketchA)
        b.setup(sketchB)
        return (a, b, sketchA, sketchB)
    }

    // MARK: Shared knobs

    @Test func aSharedKnobDrivesTheSameKnobOnTheOtherMachine() throws {
        let (a, b, sketchA, sketchB) = pair()
        let left = try #require(sketchA as? RoomProbeSketch)
        let right = try #require(sketchB as? RoomProbeSketch)
        a.share("speed")

        left.speed = 3.0
        a.beforeDraw(sketchA)      // the value goes out here
        b.beforeDraw(sketchB)      // and lands here, between frames
        #expect(right.speed == 3.0)
    }

    @Test func everyKindOfKnobTravels() throws {
        let (a, b, sketchA, sketchB) = pair()
        let left = try #require(sketchA as? RoomProbeSketch)
        let right = try #require(sketchB as? RoomProbeSketch)
        a.shareAll()

        left.speed = 2.5
        left.layers = 11
        left.trails = false
        left.look = .noir
        left.accent = Color(red: 0.1, green: 0.9, blue: 0.4, alpha: 1)
        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)

        #expect(right.speed == 2.5)
        #expect(right.layers == 11)
        #expect(right.trails == false)
        #expect(right.look == .noir)
        #expect(right.accent.green == 0.9)
    }

    @Test func aKnobNobodySharesStaysHome() throws {
        let (a, b, sketchA, sketchB) = pair()
        let left = try #require(sketchA as? RoomProbeSketch)
        let right = try #require(sketchB as? RoomProbeSketch)
        a.share("speed")

        left.speed = 2.0
        left.layers = 12
        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)
        #expect(right.speed == 2.0)
        #expect(right.layers == 6)
    }

    @Test func aKnobThatDidNotMoveIsNotSentAgain() throws {
        let (a, b, sketchA, sketchB) = pair()
        let left = try #require(sketchA as? RoomProbeSketch)
        let right = try #require(sketchB as? RoomProbeSketch)
        a.share("speed")

        left.speed = 2.0
        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)
        #expect(right.speed == 2.0)

        // The follower turns its own copy. Nothing new goes out from A, so the
        // follower's value stands until A's own knob moves again.
        right.speed = 0.5
        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)
        #expect(right.speed == 0.5)

        left.speed = 1.0
        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)
        #expect(right.speed == 1.0)
    }

    @Test func twoMachinesSharingOneKnobDoNotSendItBackAndForth() throws {
        // Both machines share the same knob, which is allowed: whoever is
        // standing next to a machine can turn it. What arrives is remembered as
        // if this machine had turned it, so nothing is echoed back.
        let (a, b, sketchA, sketchB) = pair()
        let left = try #require(sketchA as? RoomProbeSketch)
        let right = try #require(sketchB as? RoomProbeSketch)
        a.share("speed")
        b.share("speed")

        left.speed = 2.0
        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)
        #expect(right.speed == 2.0)

        // Several quiet frames: nothing changes, so nothing travels.
        for _ in 0..<5 {
            a.beforeDraw(sketchA)
            b.beforeDraw(sketchB)
        }
        #expect(left.speed == 2.0)
        #expect(right.speed == 2.0)
    }

    @Test func twoPeopleTurningOneKnobAtOnceEndUpLookingAtTheSameValue() throws {
        // The hard case: both machines turn the knob before either has heard the
        // other, so both send. Without a time on the message each would take the
        // other's value and stop, leaving the two machines showing different
        // numbers for good. The later turn has to win on both.
        let bus = MemoryRoomBus()
        let (a, b, sketchA, sketchB) = pair(on: bus)
        let left = try #require(sketchA as? RoomProbeSketch)
        let right = try #require(sketchB as? RoomProbeSketch)
        a.share("speed")
        b.share("speed")

        bus.hold()
        left.speed = 2.0
        right.speed = 0.5
        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)
        #expect(left.speed != right.speed)   // neither has heard the other yet
        bus.flush()

        a.beforeDraw(sketchA)
        b.beforeDraw(sketchB)
        #expect(left.speed == right.speed)
        #expect(left.speed == 2.0 || left.speed == 0.5)

        // And it stays settled: nothing more travels on the quiet frames after.
        for _ in 0..<3 {
            a.beforeDraw(sketchA)
            b.beforeDraw(sketchB)
        }
        #expect(left.speed == right.speed)
    }

    @Test func aMachineThatJoinsLateIsGivenTheKnobsAsTheyStand() throws {
        let bus = MemoryRoomBus()
        let first = Room(transport: MemoryRoomTransport(name: "a-mac", bus: bus))
        let sketchA = RoomProbeSketch()
        first.setup(sketchA)
        first.share("speed")

        sketchA.speed = 3.5
        first.beforeDraw(sketchA)     // said to an empty room

        // A second machine opens the piece a minute into the run.
        let late = Room(transport: MemoryRoomTransport(name: "b-mac", bus: bus))
        let sketchB = RoomProbeSketch()
        late.setup(sketchB)
        #expect(sketchB.speed == 1.4)  // its own default, for now

        first.beforeDraw(sketchA)      // the arrival sends the knobs again
        late.beforeDraw(sketchB)
        #expect(sketchB.speed == 3.5)
    }

    // MARK: Bound keys

    @Test func aBoundKnobFollowsWhatAnotherMachineSends() throws {
        let (a, b, sketchA, sketchB) = pair()
        let right = try #require(sketchB as? RoomProbeSketch)
        _ = sketchA

        b.bind("dial", to: right.$speed)        // 0...1 into the knob's own range
        a.send("dial", 0.5)
        #expect(abs(right.speed - (0.1 + 0.5 * 3.9)) < 1e-9)

        b.bind("dial", to: right.$speed, from: 0...127)
        a.send("dial", 127.0)
        #expect(abs(right.speed - 4.0) < 1e-9)

        b.unbind("dial")
        a.send("dial", 0.0)
        #expect(abs(right.speed - 4.0) < 1e-9)
    }

    // MARK: The room around them

    @Test func aRoomKnowsWhoElseIsThereAndWhatTheyRun() {
        let (a, b, _, _) = pair()
        #expect(a.peers == ["b-mac"])
        #expect(a.everyone == ["a-mac", "b-mac"])
        #expect(!a.isAlone)
        #expect(a.sketchName(of: "b-mac") == "RoomProbeSketch")
        #expect(a.sketchName(of: "nobody") == nil)
        #expect(a.seat == 0 && b.seat == 1)
        #expect(a.seatCount == 2)
        #expect(a.ownsClock && !b.ownsClock)
        #expect(a.problem == nil)
    }

    @Test func valuesOfEveryKindReadBackOnTheOtherMachine() {
        let (a, b, _, _) = pair()
        a.send("number", 2.5)
        a.send("count", 7)
        a.send("word", "hola")
        a.send("on", true)
        a.send("at", Vector2(3, 4))
        a.send("ink", Color.red)
        a.send("raw", Data([1, 2, 3]))

        #expect(b.number("number") == 2.5)
        #expect(b.integer("count") == 7)
        #expect(b.text("word") == "hola")
        #expect(b.flag("on") == true)
        #expect(b.point("at") == Vector2(3, 4))
        #expect(b.color("ink") == Color.red)
        #expect(b.bytes("raw") == Data([1, 2, 3]))

        // Nothing arrived under this key, so the fallback stands.
        #expect(b.number("missing", default: 9) == 9)
        #expect(b.text("missing", default: "none") == "none")
        #expect(b.flag("missing", default: true) == true)
        #expect(b.integer("missing", default: 3) == 3)
        #expect(b.point("missing", default: Vector2(1, 1)) == Vector2(1, 1))
        #expect(b.color("missing", default: .black) == .black)
    }
}
