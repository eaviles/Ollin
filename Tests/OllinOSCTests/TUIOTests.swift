import Foundation
import Testing
import Ollin
@testable import OllinOSC

/// The TUIO decoder over the OSC receiver: what a tracker's frame does to the
/// surface a sketch reads. Most of it runs with no socket at all, by handing the
/// receiver the messages a tracker would send; the last test sends a real
/// datagram over loopback. No GPU, so these run in CI too.
@Suite
struct TUIOTests {

    // MARK: Building a tracker's messages

    func set(_ id: Int, _ x: Double, _ y: Double,
             velocity: Vector2 = .zero, acceleration: Double = 0) -> OSCMessage {
        OSCMessage("/tuio/2Dcur", .string("set"), .int(Int32(id)),
                   .float(Float(x)), .float(Float(y)),
                   .float(Float(velocity.x)), .float(Float(velocity.y)),
                   .float(Float(acceleration)))
    }

    func alive(_ ids: [Int]) -> OSCMessage {
        OSCMessage("/tuio/2Dcur", arguments: [.string("alive")] + ids.map { .int(Int32($0)) })
    }

    func fseq(_ frame: Int) -> OSCMessage {
        OSCMessage("/tuio/2Dcur", .string("fseq"), .int(Int32(frame)))
    }

    func send(_ surface: TUIOReceiver, _ messages: [OSCMessage]) {
        messages.forEach(surface.receive)
    }

    // MARK: The frame

    @Test func aFrameOfTouchesArrives() {
        let surface = TUIOReceiver()
        send(surface, [set(7, 0.25, 0.75, velocity: Vector2(0.1, -0.2), acceleration: 0.03),
                       set(3, 0.5, 0.5),
                       alive([7, 3]),
                       fseq(1)])

        // Ordered by session id, so one frame draws the same way twice.
        #expect(surface.cursors.map(\.id) == [3, 7])
        let touch = surface.cursors[1]
        #expect(abs(touch.point.x - 0.25) < 1e-6)
        #expect(abs(touch.point.y - 0.75) < 1e-6)
        #expect(abs(touch.velocity.y + 0.2) < 1e-6)
        #expect(abs(touch.acceleration - 0.03) < 1e-6)
        #expect(surface.framesReceived == 1)
    }

    @Test func nothingIsSeenUntilTheFrameNumber() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.1, 0.1), alive([1]), fseq(1)])

        // Half of the next frame has arrived: the surface still reads the last
        // whole one, so a sketch never draws a torn frame.
        send(surface, [set(1, 0.9, 0.9), set(2, 0.5, 0.5), alive([1, 2])])
        #expect(surface.cursors.count == 1)
        #expect(abs(surface.cursors[0].point.x - 0.1) < 1e-6)

        send(surface, [fseq(2)])
        #expect(surface.cursors.count == 2)
        #expect(abs(surface.cursors[0].point.x - 0.9) < 1e-6)
    }

    @Test func aTouchThatIsNoLongerAliveLeaves() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.2, 0.2), set(2, 0.8, 0.8), alive([1, 2]), fseq(1)])
        #expect(surface.cursors.count == 2)

        // The tracker sends no "remove": the finger is simply missing from the
        // alive list, and that is what takes it off the surface.
        send(surface, [alive([2]), fseq(2)])
        #expect(surface.cursors.map(\.id) == [2])

        send(surface, [alive([]), fseq(3)])
        #expect(surface.cursors.isEmpty)
        // A tracker with nothing on it is still a tracker that is there.
        #expect(surface.framesReceived == 3)
    }

    @Test func aSetForSomethingNotAliveIsNotInvented() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.2, 0.2), set(9, 0.4, 0.4), alive([1]), fseq(1)])
        #expect(surface.cursors.map(\.id) == [1])
    }

    // MARK: Datagrams out of order

    @Test func aLateFrameIsThrownAway() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.5, 0.5), alive([1]), fseq(10)])

        // A datagram that overtook another on the way carries an older frame
        // number. Taking it would drag the touch back to where it was.
        send(surface, [set(1, 0.1, 0.1), alive([1]), fseq(9)])
        #expect(abs(surface.cursors[0].point.x - 0.5) < 1e-6)

        send(surface, [set(1, 0.2, 0.2), alive([1]), fseq(11)])
        #expect(abs(surface.cursors[0].point.x - 0.2) < 1e-6)
    }

    @Test func aTrackerThatStartsOverIsTaken() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.5, 0.5), alive([1]), fseq(5000)])
        // Far below the last number is a tracker whose count began again, not a
        // datagram that arrived late.
        send(surface, [set(1, 0.1, 0.1), alive([1]), fseq(3)])
        #expect(abs(surface.cursors[0].point.x - 0.1) < 1e-6)
    }

    @Test func aTrackerWithNoFrameNumberCommitsOnTheNextFrame() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.3, 0.3), alive([1])])
        #expect(surface.cursors.isEmpty)

        // The next frame opening is what closes this one, so such a tracker
        // reads one frame late rather than not at all.
        send(surface, [set(1, 0.4, 0.4), alive([1])])
        #expect(abs(surface.cursors[0].point.x - 0.3) < 1e-6)
        send(surface, [set(1, 0.5, 0.5), alive([1])])
        #expect(abs(surface.cursors[0].point.x - 0.4) < 1e-6)
    }

    // MARK: The other two profiles

    @Test func piecesCarryTheirSymbolAndTurn() {
        let surface = TUIOReceiver()
        surface.receive(OSCMessage("/tuio/2Dobj", .string("set"), .int(4), .int(17),
                                   .float(0.5), .float(0.25), .float(1.5),
                                   .float(0), .float(0), .float(0.2), .float(0), .float(0)))
        surface.receive(OSCMessage("/tuio/2Dobj", arguments: [.string("alive"), .int(4)]))
        surface.receive(OSCMessage("/tuio/2Dobj", .string("fseq"), .int(1)))

        let piece = try! #require(surface.objects.first)
        #expect(piece.id == 4)
        #expect(piece.symbol == 17)
        #expect(abs(piece.angle - 1.5) < 1e-6)
        #expect(abs(piece.angularVelocity - 0.2) < 1e-6)
        // Each profile keeps its own picture, so pieces and touches never mix.
        #expect(surface.cursors.isEmpty)
    }

    @Test func shapesCarryTheirSizeAndArea() {
        let surface = TUIOReceiver()
        surface.receive(OSCMessage("/tuio/2Dblb", .string("set"), .int(2),
                                   .float(0.5), .float(0.5), .float(0),
                                   .float(0.2), .float(0.1), .float(0.016),
                                   .float(0), .float(0), .float(0), .float(0), .float(0)))
        surface.receive(OSCMessage("/tuio/2Dblb", arguments: [.string("alive"), .int(2)]))
        surface.receive(OSCMessage("/tuio/2Dblb", .string("fseq"), .int(1)))

        let shape = try! #require(surface.blobs.first)
        #expect(abs(shape.size.x - 0.2) < 1e-6)
        #expect(abs(shape.size.y - 0.1) < 1e-6)
        #expect(abs(shape.area - 0.016) < 1e-6)

        let canvas = Rectangle(x: 0, y: 0, width: 1000, height: 500)
        let box = shape.bounds(in: canvas)
        // A float32 on the wire, so the tolerance is the wire's, not a double's.
        #expect(abs(box.width - 200) < 1e-3)
        #expect(abs(box.height - 50) < 1e-3)
        #expect(abs(box.center.x - 500) < 1e-3)
    }

    // MARK: Onto the canvas

    @Test func theSurfaceLandsOnTheCanvasWithNothingFlipped() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0, 0), set(2, 1, 1), set(3, 0.25, 0.5),
                       alive([1, 2, 3]), fseq(1)])

        // TUIO measures from the top left and so does the canvas, so a touch at
        // the surface's origin belongs at the canvas's own.
        let canvas = Rectangle(x: 0, y: 0, width: 800, height: 600)
        #expect(surface.cursors[0].position(in: canvas) == Vector2(0, 0))
        #expect(surface.cursors[1].position(in: canvas) == Vector2(800, 600))
        #expect(surface.cursors[2].position(in: canvas) == Vector2(200, 300))
    }

    // MARK: What is not a frame

    @Test func aTrackerNamesItselfWithoutDisturbingTheSurface() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.5, 0.5), alive([1]), fseq(1)])
        #expect(surface.sourceName == nil)

        surface.receive(OSCMessage("/tuio/2Dcur", .string("source"), .string("tracker@10.0.0.2")))
        #expect(surface.sourceName == "tracker@10.0.0.2")
        #expect(surface.cursors.count == 1)
    }

    @Test func messagesThatAreNotTUIOAreIgnored() {
        let surface = TUIOReceiver()
        send(surface, [set(1, 0.5, 0.5), alive([1]), fseq(1)])

        surface.receive(OSCMessage("/level", 0.5))
        surface.receive(OSCMessage("/tuio2/frm", .int(1)))
        // A profile Ollin does not read leaves the ones it does alone.
        surface.receive(OSCMessage("/tuio/3Dcur", arguments: [.string("alive")]))
        #expect(surface.cursors.count == 1)
        #expect(surface.framesReceived == 1)
    }

    @Test func aBundleIsTakenInOrder() {
        let surface = TUIOReceiver()
        let frame = OSCBundle(.immediate, messages: [set(5, 0.6, 0.4), alive([5]), fseq(1)])
        surface.receive(.bundle(frame))
        #expect(surface.cursors.map(\.id) == [5])
        #expect(abs(surface.cursors[0].point.y - 0.4) < 1e-6)
    }

    // MARK: Over the wire

    struct Timeout: Error {}

    /// Polls `probe` until it answers or the timeout elapses. The probe comes
    /// before the clock is read: a starved task can wake past its own deadline
    /// having never looked.
    func waitFor<T>(timeout: Double = 3.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test func aTrackerReachesTheSurfaceOverUDP() async throws {
        let surface = TUIOReceiver(port: 0)
        try surface.start()
        defer { surface.stop() }
        let port = try await waitFor { surface.boundPort }
        let sender = OSCSender(host: "127.0.0.1", port: port)
        defer { sender.close() }

        var frame = 0
        let touch = try await waitFor { () -> TUIOCursor? in
            frame += 1
            sender.send(OSCBundle(.immediate, messages: [
                set(21, 0.75, 0.25), alive([21]), fseq(frame),
            ]))
            return surface.cursors.first
        }
        #expect(touch.id == 21)
        #expect(abs(touch.point.x - 0.75) < 1e-6)
    }
}
