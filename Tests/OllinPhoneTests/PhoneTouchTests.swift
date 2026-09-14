import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises the phone as a control surface over staged wire samples (GPU-free,
/// CI-safe): the fingers on the glass, the landings found from their numbers,
/// and the round trip that carries every field. The numbers are chosen so each
/// expectation has one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) @MainActor struct PhoneTouchTests {

    private func point(_ id: UInt32, _ x: Float, _ y: Float,
                       force: Float? = nil, radius: Float = 0.05,
                       age: Float = 0) -> PhoneTouchPoint {
        PhoneTouchPoint(id: id, position: SIMD2(x, y), hasForce: force != nil,
                        force: force ?? 0, radius: radius, age: age)
    }

    private func decoded(_ message: PhoneMessage) -> PhoneMessage? {
        let frame = PhoneWire.encode(message)
        guard let header = PhoneHeader.parse(frame) else { return nil }
        return PhoneWire.decode(header: header,
                                payload: frame.dropFirst(PhoneWire.headerByteCount))
    }

    // MARK: The wire

    @Test func theWireCarriesEveryFingerBack() {
        let staged = PhoneTouchSample(timestamp: 12.5, touches: [
            point(7, -0.5, 0.25, force: 0.4, radius: 0.08, age: 1.5),
            point(8, 1, -1, radius: 0.02, age: 0.25),
        ])
        let frame = PhoneWire.encode(.touch(staged))
        #expect(PhoneHeader.parse(frame)?.kind == .touch)
        guard case .touch(let read)? = decoded(.touch(staged)) else {
            return #expect(Bool(false), "the frame did not decode as a touch")
        }
        #expect(read == staged)
    }

    @Test func theLastFingerLeavingIsARealReading() {
        // An empty list is not an empty message: it is the release, and a decoder
        // that refused it would leave the Mac holding a finger that is gone.
        guard case .touch(let read)? = decoded(.touch(PhoneTouchSample(timestamp: 3, touches: [])))
        else { return #expect(Bool(false), "an empty set did not decode") }
        #expect(read.touches.isEmpty)
        #expect(read.timestamp == 3)
    }

    @Test func aScreenThatCannotWeighAPressSaysNothingRatherThanZero() {
        // hasForce is what separates "pressed with no weight" from "this glass
        // cannot tell", which is most iPhones.
        let staged = PhoneTouchSample(timestamp: 1, touches: [point(1, 0, 0)])
        guard case .touch(let read)? = decoded(.touch(staged)) else {
            return #expect(Bool(false), "the frame did not decode as a touch")
        }
        #expect(read.touches[0].hasForce == false)
        #expect(PhoneTouch(read.touches[0]).force == nil)
        #expect(PhoneTouch(point(1, 0, 0, force: 0)).force == 0)
    }

    @Test func aShortTouchPayloadIsSkippedRatherThanRead() {
        // A truncated frame must read as a skipped message, never as a finger
        // somewhere random.
        let frame = PhoneWire.encode(.touch(PhoneTouchSample(timestamp: 1,
                                                            touches: [point(1, 0.5, 0.5)])))
        let payload = frame.dropFirst(PhoneWire.headerByteCount).dropLast(4)
        let header = PhoneHeader(kind: .touch, payloadLength: payload.count)
        #expect(PhoneWire.decode(header: header, payload: payload) == nil)
    }

    // MARK: What is down

    @Test func theFingersOnTheGlassAreTheLatestReading() {
        let touches = PhoneTouches()
        touches.feel([PhoneTouch(id: 1, position: Vector2(-0.5, 0)),
                      PhoneTouch(id: 2, position: Vector2(0.5, 0))], at: 1)
        #expect(touches.down.map(\.id) == [1, 2])
        #expect(touches.isTouching)
        #expect(touches.touch(id: 2)?.position == Vector2(0.5, 0))

        // One finger lifts; the other keeps its number, so a drag it started is
        // still being followed.
        touches.feel([PhoneTouch(id: 2, position: Vector2(0.6, 0.1))], at: 1.2)
        #expect(touches.down.map(\.id) == [2])
        #expect(touches.touch(id: 1) == nil)
        #expect(touches.touch(id: 2)?.position == Vector2(0.6, 0.1))

        touches.feel([], at: 1.4)
        #expect(touches.down.isEmpty)
        #expect(!touches.isTouching)
    }

    // MARK: What just happened

    @Test func aNumberNotSeenBeforeIsALanding() {
        // The whole of how a tap is found. A finger that moves keeps its number
        // and must not tap again, or a drag would fire a pad on every frame.
        let touches = PhoneTouches()
        touches.feel([PhoneTouch(id: 4, position: Vector2(-0.25, 0.5))], at: 2)
        touches.feel([PhoneTouch(id: 4, position: Vector2(-0.2, 0.5))], at: 2.1)
        touches.feel([PhoneTouch(id: 4, position: Vector2(-0.1, 0.5)),
                      PhoneTouch(id: 5, position: Vector2(0.75, -0.5))], at: 2.2)

        let taps = touches.taps()
        #expect(taps.map(\.id) == [4, 5])
        #expect(taps[0].position == Vector2(-0.25, 0.5))   // where it landed, not where it is
        #expect(taps[0].time == 2)
        #expect(taps[1].time == 2.2)
        #expect(touches.tapCount == 2)
    }

    @Test func aTapBetweenTwoDrawsIsStillThereToFind() {
        // The reason the landings are kept rather than read off the latest
        // reading: a finger that lands and leaves between two frames is gone
        // from `down` by the time a sketch looks.
        let touches = PhoneTouches()
        touches.feel([PhoneTouch(id: 9, position: Vector2(0, 0.8))], at: 5)
        touches.feel([], at: 5.05)
        #expect(touches.down.isEmpty)
        let taps = touches.taps()
        #expect(taps.count == 1)
        #expect(taps[0].id == 9)
        #expect(taps[0].position == Vector2(0, 0.8))
    }

    @Test func tapsDrainOnceAndTheCountDoesNot() {
        let touches = PhoneTouches()
        touches.feel([PhoneTouch(id: 1, position: .zero)], at: 1)
        #expect(touches.taps().count == 1)
        #expect(touches.taps().isEmpty)           // drained
        #expect(touches.tapCount == 1)            // the count is not draining
        touches.feel([], at: 1.1)
        touches.feel([PhoneTouch(id: 2, position: .zero)], at: 1.2)
        #expect(touches.tapCount == 2)
        #expect(touches.taps().count == 1)
    }

    @Test func aFingerLandingAgainUnderTheSameNumberIsNotASecondTap() {
        // The phone never reuses a number, and this pins what the Mac does if it
        // ever did: the number is what identity means here.
        let touches = PhoneTouches()
        touches.feel([PhoneTouch(id: 3, position: .zero)], at: 1)
        touches.feel([PhoneTouch(id: 3, position: Vector2(0.1, 0))], at: 1.1)
        #expect(touches.tapCount == 1)
    }

    @Test func theCableComingOutLetsEveryFingerGo() {
        // The phone sends only on a change, so a finger that was down when the
        // cable came out would stay down for the rest of the run: on an
        // instrument, a note that never ends. The counts are kept, since
        // nothing about them stopped being true.
        let touches = PhoneTouches()
        touches.feel([PhoneTouch(id: 1, position: .zero)], at: 1)
        #expect(touches.isTouching)
        touches.releaseAll()
        #expect(!touches.isTouching)
        #expect(touches.down.isEmpty)
        #expect(touches.tapCount == 1)
        #expect(touches.taps().count == 1)
        // The same finger's number landing again after a reconnect is a landing,
        // because the surface let it go.
        touches.feel([PhoneTouch(id: 1, position: .zero)], at: 2)
        #expect(touches.tapCount == 2)
    }

    @Test func theSurfaceForgetsEverythingOnReset() {
        let touches = PhoneTouches()
        touches.feel([PhoneTouch(id: 1, position: .zero)], at: 1)
        #expect(touches.isReporting)
        touches.reset()
        #expect(touches.down.isEmpty)
        #expect(touches.taps().isEmpty)
        #expect(touches.tapCount == 0)
        #expect(!touches.isReporting)
        #expect(touches.timeSinceTap == .greatestFiniteMagnitude)
    }

    @Test func theClockCarriesForwardBetweenReadings() {
        // The phone sends only on a change, so a hand resting still sends
        // nothing: a fade read off the last landing has to keep running.
        let touches = PhoneTouches()
        #expect(touches.timeSinceTap == .greatestFiniteMagnitude)
        touches.feel([PhoneTouch(id: 1, position: .zero)], at: 10)
        #expect(touches.timeSinceTap >= 0)
        #expect(touches.timeSinceTap < 0.5)
        touches.feel([], at: 12)
        #expect(touches.timeSinceTap >= 2)        // two seconds on the phone's clock
    }

    // MARK: Onto the canvas

    @Test func aFingerLandsWhereTheRectanglePutsIt() {
        // The middle of the glass is the middle of the rectangle, and up on the
        // phone is up on the canvas, which the y flip is for.
        let rect = Rectangle(x: 100, y: 200, width: 400, height: 300)
        #expect(PhoneTouch(id: 1, position: .zero).point(in: rect) == Vector2(300, 350))
        #expect(PhoneTouch(id: 2, position: Vector2(-1, 1)).point(in: rect) == Vector2(100, 200))
        #expect(PhoneTouch(id: 3, position: Vector2(1, -1)).point(in: rect) == Vector2(500, 500))
        #expect(PhoneTap(id: 4, position: Vector2(1, 1)).point(in: rect) == Vector2(500, 200))
    }

    // MARK: The air

    @Test func theAirReadingRoundTrips() {
        let staged = PhoneAirSample(timestamp: 8.25, pressure: 101.32, altitude: -3.75)
        #expect(PhoneHeader.parse(PhoneWire.encode(.air(staged)))?.kind == .air)
        guard case .air(let read)? = decoded(.air(staged)) else {
            return #expect(Bool(false), "the frame did not decode as air")
        }
        #expect(read == staged)
        // Going down is a real reading: the altitude is relative to where the
        // phone started, so below it is negative.
        #expect(read.altitude < 0)
    }

    @Test func aShortAirPayloadIsSkippedRatherThanRead() {
        let frame = PhoneWire.encode(.air(PhoneAirSample(timestamp: 1, pressure: 100, altitude: 0)))
        let payload = frame.dropFirst(PhoneWire.headerByteCount).dropLast(2)
        let header = PhoneHeader(kind: .air, payloadLength: payload.count)
        #expect(PhoneWire.decode(header: header, payload: payload) == nil)
    }

    @Test func theAirReadsInBothUnits() {
        let air = PhoneAir(PhoneAirSample(timestamp: 1, pressure: 101.3, altitude: 0.5))
        #expect(abs(air.pressure - 101.3) < 1e-5)
        #expect(abs(air.hectopascals - 1013) < 1e-4)
        #expect(abs(air.altitude - 0.5) < 1e-6)
    }

    // MARK: The kinds themselves

    @Test func theTwoNewKindsKeepTheirNumbers() {
        // Both ends of the cable read a kind by its raw value, so a number that
        // moved would make an installed app and a fresh Mac disagree in silence.
        #expect(PhoneMessageKind.touch.rawValue == 16)
        #expect(PhoneMessageKind.air.rawValue == 17)
        #expect(PhoneMessage.touch(PhoneTouchSample(timestamp: 0, touches: [])).kind == .touch)
        #expect(PhoneMessage.air(PhoneAirSample(timestamp: 0, pressure: 0, altitude: 0)).kind == .air)
    }
}
