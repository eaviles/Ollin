@testable import Ollin
import AppKit
import CoreGraphics
import Foundation
import Metal
import Testing

/// Two fingers on the trackpad: `pinchScale` and `turnAngle`, their hooks, a
/// take that repeats them, and the two controls that zoom with a pinch. The
/// trackpad's own events are made here the way the system makes them, so the
/// view's handler is what reads them.
@Suite
@MainActor
struct PinchAndTurnTests {

    /// Writes down what each hook saw and what every frame read.
    final class Fingers: Sketch {
        var pinchesSeen: [Double] = []
        var turnsSeen: [Double] = []
        var frames: [[Double]] = []

        override func fingersPinched() { pinchesSeen.append(pinchScale) }
        override func fingersTurned() { turnsSeen.append(turnAngle) }
        override func draw() { frames.append([pinchScale, turnAngle]) }
    }

    /// A trackpad gesture event: `hidType` 8 is a magnify (`value` the change
    /// of size), 5 a rotate (`value` in degrees, counterclockwise). The fields
    /// are the ones the system fills for a real trackpad.
    static func gesture(hidType: Int64, value: Double, at timestamp: Double) throws -> NSEvent {
        let cg = try #require(CGEvent(source: nil))
        cg.type = try #require(CGEventType(rawValue: 29))
        cg.timestamp = CGEventTimestamp(timestamp * 1e9)
        cg.setIntegerValueField(try #require(CGEventField(rawValue: 110)), value: hidType)
        let field: UInt32 = hidType == 8 ? 113 : 114
        cg.setDoubleValueField(try #require(CGEventField(rawValue: field)), value: value)
        cg.setIntegerValueField(try #require(CGEventField(rawValue: 132)), value: 2)
        return try #require(NSEvent(cgEvent: cg))
    }

    private func step(_ sketch: Sketch) {
        sketch.advance(time: Double(sketch.frameCount + 1) / 60, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
    }

    private func view(for sketch: Sketch) throws -> OllinMTKView {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: sketch)
        view.isPaused = true
        return view
    }

    // MARK: The trackpad's events

    /// A magnify event of 0.25 reads as a factor of 1.25: the hook sees it at
    /// once, the next frame reads it, and the frame after reads 1 again.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aMagnifyEventReadsAsItsFactor() throws {
        let sketch = Fingers()
        let canvas = try view(for: sketch)
        let event = try Self.gesture(hidType: 8, value: 0.25, at: 1)
        #expect(event.type == .magnify && event.magnification == 0.25)

        canvas.magnify(with: event)
        #expect(sketch.pinchesSeen == [1.25])
        step(sketch)
        #expect(sketch.frames.last == [1.25, 0])
        step(sketch)
        #expect(sketch.frames.last == [1, 0], "a still frame reads no pinch")
    }

    /// The trackpad says degrees counterclockwise; a sketch reads radians
    /// clockwise on its canvas, the way `rotate(_:)` turns, so a turn of the
    /// fingers turns a drawn shape with them.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRotateEventReadsAsAClockwiseTurnInRadians() throws {
        let sketch = Fingers()
        let canvas = try view(for: sketch)
        canvas.rotate(with: try Self.gesture(hidType: 5, value: 12.5, at: 1))
        #expect(sketch.turnsSeen == [-12.5 * .pi / 180])
        step(sketch)
        #expect(sketch.frames.last == [1, -12.5 * .pi / 180])
    }

    /// Inside the SwiftUI hosts an event can reach both the local monitor and
    /// the view; it counts once. The gesture's start and end, which move
    /// nothing, are not reported at all.
    @Test(.enabled(if: Snapshot.hasMetal))
    func oneEventIsCountedOnceAndAnEmptyOneNotAtAll() throws {
        let sketch = Fingers()
        let canvas = try view(for: sketch)
        let event = try Self.gesture(hidType: 8, value: 0.1, at: 2)
        canvas.reportGesture(event)      // the monitor
        canvas.magnify(with: event)      // then the responder chain
        #expect(sketch.pinchesSeen.count == 1)
        canvas.magnify(with: try Self.gesture(hidType: 8, value: 0.1, at: 3))
        #expect(sketch.pinchesSeen.count == 2, "a new event at a new time is a new pinch")
        canvas.magnify(with: try Self.gesture(hidType: 8, value: 0, at: 4))
        canvas.rotate(with: try Self.gesture(hidType: 5, value: 0, at: 4))
        #expect(sketch.pinchesSeen.count == 2 && sketch.turnsSeen.isEmpty)
    }

    // MARK: A frame's worth

    /// Every pinch between two frames is multiplied in and every turn added,
    /// while each hook sees its own event's value.
    @Test func aFrameMultipliesItsPinchesAndAddsItsTurns() {
        let sketch = Fingers()
        sketch.handlePinch(by: 1.1)
        sketch.handlePinch(by: 1.2)
        sketch.handleTurn(by: 0.1)
        sketch.handleTurn(by: -0.04)
        #expect(sketch.pinchesSeen == [1.1, 1.2])
        #expect(sketch.turnsSeen == [0.1, -0.04])
        step(sketch)
        let frame = sketch.frames[0]
        #expect(abs(frame[0] - 1.1 * 1.2) < 1e-12 && abs(frame[1] - 0.06) < 1e-12)
    }

    /// A factor at or below zero would turn a zoom inside out, so it is held
    /// just above zero; one that is not a number is dropped, never multiplied in.
    @Test func aFactorThatIsNoSizeIsHeldAndANaNIsDropped() {
        let sketch = Fingers()
        sketch.handlePinch(by: 0)
        sketch.handlePinch(by: -.infinity)
        sketch.handlePinch(by: .nan)
        sketch.handleTurn(by: .infinity)
        #expect(sketch.pinchesSeen == [0.01])
        #expect(sketch.turnsSeen.isEmpty)
        step(sketch)
        #expect(sketch.frames[0] == [0.01, 0])
    }

    // MARK: A take

    /// A take written while fingers pinched and turned plays them back on a
    /// fresh instance to the frame: every frame reads what the original read,
    /// and the hooks fire as often with the same values.
    @Test func aReplayedTakeRepeatsThePinchToTheFrame() {
        let live = Fingers()
        live.setCanvasSize(width: 200, height: 200)
        live.takeRecorder = TakeRecorder(sketch: live)
        for k in 0..<40 {
            switch k {
            case 4: live.handlePinch(by: 1.08)
            case 5: live.handlePinch(by: 1.05); live.handleTurn(by: 0.02)
            case 9: live.handleTurn(by: -0.31); live.handleTurn(by: 0.01)
            case 20: live.handlePinch(by: 0.8)
            default: break
            }
            step(live)
        }
        let take = live.takeRecorder!.take
        #expect(take.events.count == 6)

        let replay = Fingers()
        replay.setCanvasSize(width: 200, height: 200)
        take.install(on: replay)
        for _ in 0..<40 {
            replay.handlePinch(by: 3)        // live input is gated off during a replay
            step(replay)
        }
        #expect(replay.frames == live.frames)
        #expect(replay.pinchesSeen == live.pinchesSeen && replay.turnsSeen == live.turnsSeen)
        #expect(live.frames[4] == [1.08, 0] && live.frames[5] == [1.05, 0.02])
    }

    /// The take keeps the two kinds through the file.
    @Test func theEventsRoundTripThroughTheFile() throws {
        let events: [Take.Event] = [.pinch(scale: 1.25), .turn(angle: -0.5)]
        let data = try JSONEncoder().encode(events)
        #expect(try JSONDecoder().decode([Take.Event].self, from: data) == events)
    }

    // MARK: The controls that zoom with it

    /// `viewControl()` zooms by the pinch about the pointer, the way it zooms
    /// with the wheel: the content under the pointer stays under it.
    @Test func aPinchZoomsTheViewAboutThePointer() {
        let sketch = ViewControlTests.Probe()
        sketch.setCanvasSize(width: 400, height: 400)
        let pointer = Vector2(90, 310)
        sketch.setMouse(x: pointer.x, y: pointer.y)
        step(sketch)
        let under = sketch.mouseSeen
        sketch.handlePinch(by: 2)
        step(sketch)
        #expect(abs(sketch.viewZoom - 2) < 1e-12)
        #expect((sketch.mouseSeen - under).length < 1e-9, "\(sketch.mouseSeen) against \(under)")
        sketch.handlePinch(by: 0.5)
        step(sketch)
        #expect(abs(sketch.viewZoom - 1) < 1e-12)
    }

    /// The orbit camera dollies with a pinch: spreading the fingers to twice
    /// the distance brings the camera to half its distance.
    @Test func aPinchDolliesTheCamera() {
        let rig = CameraRig()
        rig.frame(target: .zero, radius: 10, elevation: 0.3, fieldOfView: .pi / 3)
        func input(pinch: Double) -> CameraInput {
            CameraInput(mouseX: 500, mouseY: 500, leftPressed: false, rightPressed: false,
                        modifiers: [], scrollDeltaY: 0, pinchScale: pinch)
        }
        rig.updateControl(input: input(pinch: 2), dt: 1.0 / 60, viewportHeight: 1000)
        for _ in 0..<600 { rig.updateControl(input: input(pinch: 1), dt: 1.0 / 60, viewportHeight: 1000) }
        #expect(abs(rig.radius - 5) < 1e-6, "radius \(rig.radius)")
    }
}
