import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises the wand over staged wire samples (GPU-free, CI-safe): the frame the
/// hold's quarter turn stands upright, the direction a sketch points with, the
/// button the person presses, and the round trip that carries all of it. The
/// numbers are chosen so each expectation has one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) struct PhoneWandTests {

    /// A phone standing at `origin` with its camera axes square to the world: x
    /// right, y up, looking along -z. The identity basis is what makes the quarter
    /// turns readable by hand.
    private func sample(origin: SIMD3<Float> = SIMD3(0, 1.25, 0),
                        turns: UInt8 = 0,
                        pressed: Bool = false,
                        pressCount: UInt32 = 0,
                        touch: SIMD2<Float>? = nil,
                        tracked: Bool = true,
                        scale: Float = 1) -> PhoneWandSample {
        let transform = simd_float4x4(SIMD4<Float>(scale, 0, 0, 0),
                                      SIMD4<Float>(0, scale, 0, 0),
                                      SIMD4<Float>(0, 0, scale, 0),
                                      SIMD4<Float>(origin, 1))
        return PhoneWandSample(tracked: tracked, timestamp: 7, transform: transform,
                               quarterTurnsCW: turns, pressed: pressed,
                               pressCount: pressCount, hasTouch: touch != nil,
                               touch: touch ?? .zero)
    }

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool {
        abs(a - b) <= eps
    }

    // MARK: The wire

    @Test func theWireCarriesEveryFieldBack() {
        let staged = sample(origin: SIMD3(0.5, 1.4, -2), turns: 3, pressed: true,
                            pressCount: 41, touch: SIMD2(-0.25, 0.75))
        let frame = PhoneWire.encode(.wand(staged))
        let header = PhoneHeader.parse(frame)
        #expect(header?.kind == .wand)
        let payload = frame.dropFirst(PhoneWire.headerByteCount)
        guard let header, case .wand(let read)? = PhoneWire.decode(header: header, payload: payload)
        else { return #expect(Bool(false), "the frame did not decode as a wand") }
        #expect(read == staged)
    }

    @Test func aWandWithNoThumbOnItRoundTrips() {
        // The touch is carried as a flag beside the point, so nothing touching has
        // to survive the trip as nothing rather than as the middle of the pad.
        let staged = sample(pressCount: 3)
        let frame = PhoneWire.encode(.wand(staged))
        guard let header = PhoneHeader.parse(frame),
              case .wand(let read)? = PhoneWire.decode(
                header: header, payload: frame.dropFirst(PhoneWire.headerByteCount))
        else { return #expect(Bool(false), "the frame did not decode as a wand") }
        #expect(!read.hasTouch)
        #expect(PhoneWand(read).touch == nil)
    }

    @Test func aShortPayloadIsSkippedRatherThanRead() {
        // A truncated frame must read as a skipped message, never as a pose that
        // would point a sketch somewhere random.
        let frame = PhoneWire.encode(.wand(sample()))
        let payload = frame.dropFirst(PhoneWire.headerByteCount).dropLast(4)
        let header = PhoneHeader(kind: .wand, payloadLength: payload.count)
        #expect(PhoneWire.decode(header: header, payload: payload) == nil)
    }

    // MARK: The hold

    @Test func theQuarterTurnStandsTheAxesUprightAndMovesNothingElse() {
        // A picture turned a quarter clockwise puts its old top at its new right,
        // so the old y axis becomes the new x. The place, and the way the phone
        // looks, are the same in every hold.
        let camera = simd_float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0),
                                   SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(1, 2, 3, 1))
        let expected: [UInt8: (x: SIMD3<Float>, y: SIMD3<Float>)] = [
            0: (SIMD3(1, 0, 0), SIMD3(0, 1, 0)),
            1: (SIMD3(0, 1, 0), SIMD3(-1, 0, 0)),
            2: (SIMD3(-1, 0, 0), SIMD3(0, -1, 0)),
            3: (SIMD3(0, -1, 0), SIMD3(1, 0, 0)),
        ]
        for (turns, axes) in expected {
            let held = PhoneWire.wandFrame(fromCamera: camera, quarterTurnsCW: turns)
            #expect(SIMD3(held.columns.0.x, held.columns.0.y, held.columns.0.z) == axes.x,
                    "x axis after \(turns) turns")
            #expect(SIMD3(held.columns.1.x, held.columns.1.y, held.columns.1.z) == axes.y,
                    "y axis after \(turns) turns")
            #expect(held.columns.2 == camera.columns.2, "the z axis never turns")
            #expect(held.columns.3 == camera.columns.3, "the place never moves")
        }
        // A count past a full turn wraps rather than falling through to no turn.
        #expect(PhoneWire.wandFrame(fromCamera: camera, quarterTurnsCW: 5)
                == PhoneWire.wandFrame(fromCamera: camera, quarterTurnsCW: 1))
    }

    @Test func aWrongHoldTipsTheDrawingWithoutMissingTheAim() {
        // This is why the turn is safe to get wrong once: it moves what is up, and
        // it never moves what the phone is pointed at. A picture standing on its
        // side is the symptom; a beam landing somewhere else is not.
        let straight = PhoneWand(sample(turns: 0))
        let turned = PhoneWand(sample(turns: 1))
        #expect(close(straight.pointing.distance(to: turned.pointing), 0))
        #expect(straight.position == turned.position)
        #expect(straight.up != turned.up)
        #expect(turned.up == Vector3(-1, 0, 0))
        #expect(turned.across == Vector3(0, 1, 0))
    }

    // MARK: Where it points

    @Test func theWandPointsOutOfTheBackOfThePhone() {
        // ARKit's camera looks along -z, and so does Ollin's own camera, so the
        // pointing direction is the third column turned around.
        let wand = PhoneWand(sample(origin: SIMD3(0, 1.25, 0)))
        #expect(wand.pointing == Vector3(0, 0, -1))
        #expect(wand.up == Vector3(0, 1, 0))
        #expect(wand.across == Vector3(1, 0, 0))
        #expect(wand.position == Vector3(0, 1.25, 0))
        #expect(wand.point(at: 2) == Vector3(0, 1.25, -2))
        #expect(wand.ray.origin == wand.position)
        #expect(wand.ray.direction == wand.pointing)
    }

    @Test func theBeamFindsWhatItIsPointedAt() {
        // The one thing a sketch actually asks the wand: is the person pointing at
        // this? A ball a meter and a half down the beam is hit; the same ball put
        // behind the phone is not.
        let wand = PhoneWand(sample(origin: SIMD3(0, 1.25, 0)))
        let hit = wand.ray.hit(sphereAt: Vector3(0, 1.25, -1.5), radius: 0.13)
        #expect(hit != nil)
        #expect(close(hit ?? 0, 1.37, 1e-9))
        #expect(wand.ray.hit(sphereAt: Vector3(0, 1.25, 1.5), radius: 0.13) == nil)
    }

    @Test func aScaledPoseStillGivesDirectionsOfLengthOne() {
        // ARKit's camera pose carries no scale, but a direction that is not a unit
        // vector would quietly multiply every distance a hit reports.
        let wand = PhoneWand(sample(origin: SIMD3(0, 1, 0), scale: 3))
        #expect(close(wand.pointing.length, 1))
        #expect(close(wand.up.length, 1))
        #expect(wand.position == Vector3(0, 1, 0))
    }

    @Test func aPoseWithNoBasisFallsBackToTheWorldAxes() {
        // A pose that has collapsed must not divide by zero and hand a sketch a
        // direction full of NaN, which would take the whole picture with it.
        let broken = simd_float4x4(SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0),
                                   SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(1, 2, 3, 1))
        let wand = PhoneWand(PhoneWandSample(tracked: false, timestamp: 1, transform: broken))
        #expect(wand.pointing == Vector3(0, 0, -1))
        #expect(wand.up == Vector3(0, 1, 0))
        #expect(wand.position == Vector3(1, 2, 3))
    }

    // MARK: The button

    @Test func thePressCountRisesApartFromWhetherAFingerIsDown() {
        // A tap that lands and leaves between two frames arrives as a raised count
        // with nothing pressed. A sketch that only read `isPressed` would miss it,
        // which is the whole reason the count is carried.
        let landed = PhoneWand(sample(pressed: true, pressCount: 8))
        let gone = PhoneWand(sample(pressed: false, pressCount: 9))
        #expect(landed.isPressed)
        #expect(landed.pressCount == 8)
        #expect(!gone.isPressed)
        #expect(gone.pressCount == 9)
        #expect(gone.pressCount > landed.pressCount)
    }

    @Test func theThumbIsReportedInTheSamePlaceItSits() {
        // -1 to 1 across and up, the middle at zero, so a sketch can use it as a
        // rate in either direction with no remapping.
        let wand = PhoneWand(sample(pressed: true, pressCount: 1, touch: SIMD2(-1, 0.5)))
        #expect(wand.touch == Vector2(-1, 0.5))
        #expect(PhoneWand(sample(pressed: true, pressCount: 1)).touch == nil)
    }

    @Test func anUntrackedWandStillCarriesItsButton() {
        // Tracking comes and goes as the room is recognized; the thumb does not.
        // A sketch can keep taking presses while the pose is worth nothing.
        let wand = PhoneWand(sample(pressed: true, pressCount: 2, tracked: false))
        #expect(!wand.isTracked)
        #expect(wand.isPressed)
        #expect(wand.pressCount == 2)
    }
}
