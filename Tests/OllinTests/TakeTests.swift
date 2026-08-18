@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import Testing

/// Record and replay (`Take`): the claims worth pinning are determinism ones.
/// A recorded run replayed onto a fresh instance must walk the same state,
/// fire the same hooks, apply the same knob moves at the same frames, and
/// render the same pixels, while live input stays gated off; and the file
/// must round-trip and refuse a format it does not read.
@Suite
@MainActor
struct TakeTests {

    // MARK: The sketch under test

    /// Draws nothing; instead it writes down everything it can feel each
    /// frame, so two runs compare as plain values. It reads the clock, the
    /// pointer, pressure, scroll, keys, modifiers, a knob, and both random
    /// generators, and it counts every hook.
    private final class Performance: Sketch {
        @Param(0...10) var gain = 1.0
        var trace: [Double] = []
        var presses = 0, releases = 0, keyDowns = 0, keyUps = 0, wheels = 0

        override func setup() {
            trace.append(random())      // setup consumes randomness, on purpose
        }

        override func draw() {
            trace.append(contentsOf: [
                time, deltaTime, Double(frameCount),
                mouseX, mouseY, mouseIsPressed ? 1 : 0,
                rightMouseIsPressed ? 1 : 0, pressure, scrollDeltaY,
                keyIsPressed ? 1 : 0, modifiers.contains(.shift) ? 1 : 0,
                gain, random(), noise(time * 3.7, 0.5),
            ])
        }

        override func mousePressed() { presses += 1 }
        override func mouseReleased() { releases += 1 }
        override func keyPressed() { keyDowns += 1 }
        override func keyReleased() { keyUps += 1 }
        override func mouseWheel() { wheels += 1 }
    }

    /// Drive a run the way the live window does: an irregular clock, input
    /// arriving between frames, a knob moved mid-run. Returns the sketch,
    /// still wearing its recorder.
    private func recordPerformance(frames: Int = 60) -> Performance {
        let live = Performance()
        live.setCanvasSize(width: 400, height: 400)
        live.takeRecorder = TakeRecorder(sketch: live)
        live.setup()
        var t = 0.0
        for k in 0..<frames {
            let dt = 1.0 / 60 + Double(k % 7) * 0.0013   // a jittery real clock
            t += dt
            switch k {
            case 5:
                live.setMouse(x: 120, y: 80)
                live.handleMouseButton(pressed: true)
            case 6: live.setMouse(x: 141.5, y: 92.25)
            case 9: live.handleMouseButton(pressed: false)
            case 12: live.handleKey(character: "a", code: nil, pressed: true)
            case 14: live.handleKey(character: "a", code: nil, pressed: false)
            case 16: live.handleKey(character: nil, code: .upArrow, pressed: true)
            case 17: live.clearHeldKeys()
            case 20: live.handleScroll(deltaY: 3.5)
            case 25: live.setModifiers([.shift])
            case 30: live.setPressure(0.7, canVary: true)
            case 33: live.setRightMousePressed(true)
            case 35: live.setRightMousePressed(false)
            case 40: live.gain = 4.2
            default: break
            }
            live.advance(time: t, deltaTime: dt, frameRate: 1 / dt)
            live.performDraw()
        }
        return live
    }

    /// Replay `take` onto a fresh instance, driving it with a deliberately
    /// wrong clock: the player must override every value.
    private func replayPerformance(_ take: Take, frames: Int) -> Performance {
        let fresh = Performance()
        fresh.setCanvasSize(width: 400, height: 400)
        take.install(on: fresh)
        fresh.setup()
        for k in 0..<frames {
            fresh.advance(time: Double(k) * 99, deltaTime: 9.9, frameRate: 1)
            fresh.performDraw()
        }
        return fresh
    }

    // MARK: Determinism

    @Test func aRecordedRunReplaysExactly() {
        let live = recordPerformance()
        let take = live.takeRecorder!.take

        #expect(take.frameCount == 60)
        #expect(take.seed == live.variation)
        #expect(!take.events.isEmpty)
        #expect(take.changes.contains { $0.name == "gain" })

        let replayed = replayPerformance(take, frames: 60)
        #expect(replayed.trace == live.trace)
        #expect(replayed.presses == live.presses)
        #expect(replayed.releases == live.releases)
        #expect(replayed.keyDowns == live.keyDowns)
        #expect(replayed.keyUps == live.keyUps)
        #expect(replayed.wheels == live.wheels)
    }

    @Test func theKnobMoveLandsOnItsFrame() {
        let live = recordPerformance()
        let take = live.takeRecorder!.take
        let change = take.changes.first { $0.name == "gain" }
        // Moved before the k == 40 advance, so it applies ahead of that frame.
        #expect(change?.frame == 40)
        #expect(change?.value == .number(4.2))

        // At frame 40 the replay still reads the starting value; one frame on,
        // the recorded move has landed.
        let before = replayPerformance(take, frames: 40)
        #expect(before.gain == 1.0)
        let after = replayPerformance(take, frames: 41)
        #expect(after.gain == 4.2)
    }

    @Test func liveInputIsGatedDuringReplay() {
        let live = recordPerformance(frames: 10)
        let take = live.takeRecorder!.take
        let fresh = Performance()
        fresh.setCanvasSize(width: 400, height: 400)
        take.install(on: fresh)
        fresh.setup()
        fresh.setMouse(x: 999, y: 999)          // a live pointer during replay
        fresh.handleMouseButton(pressed: true)
        #expect(fresh.mouseX == 0)
        #expect(fresh.mouseIsPressed == false)
        #expect(fresh.presses == 0)
    }

    @Test func aReplayKeepsAdvancingPastTheEnd() {
        let live = recordPerformance(frames: 10)
        let take = live.takeRecorder!.take
        let fresh = Performance()
        fresh.setCanvasSize(width: 400, height: 400)
        take.install(on: fresh)
        fresh.setup()
        var lastTime = -Double.infinity
        for _ in 0..<15 {
            fresh.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
            #expect(fresh.time > lastTime)
            lastTime = fresh.time
        }
        #expect(fresh.frameCount == 15)
    }

    @Test func aSeedOverrideKeepsTheGesturesAndMovesTheWorld() {
        let live = recordPerformance()
        let take = live.takeRecorder!.take
        let fresh = Performance()
        fresh.setCanvasSize(width: 400, height: 400)
        take.install(on: fresh)
        fresh.seed(take.seed &+ 1)              // the --seed override, after install
        fresh.setup()
        for k in 0..<60 {
            fresh.advance(time: Double(k), deltaTime: 9.9, frameRate: 1)
            fresh.performDraw()
        }
        // The gestures still replay (the pointer trace matches) while the
        // random samples walk a different world.
        #expect(fresh.mouseX == live.mouseX)
        #expect(fresh.presses == live.presses)
        #expect(fresh.trace != live.trace)
    }

    // MARK: The file

    @Test func theFileRoundTripsAndRefusesAForeignVersion() throws {
        let live = recordPerformance(frames: 20)
        let take = live.takeRecorder!.take
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-take-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try take.write(to: url)
        let loaded = try Take.load(from: url)
        #expect(loaded == take)

        var foreign = take
        foreign.version = Take.currentVersion + 1
        try foreign.write(to: url)
        #expect(throws: TakeError.self) { try Take.load(from: url) }
    }

    // MARK: Pixels

    /// Draws from the pointer, the clock, and the seed, so a replayed frame
    /// only matches when all three came back exactly.
    private final class Painter: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func setup() { noClear() }
        override func draw() {
            if frameCount == 1 { background(.white) }
            fill(Color(red: random(), green: 0.4, blue: 0.6))
            noStroke()
            drawCircle(mouseX + random(-20, 20), mouseY + random(-20, 20),
                       6 + 4 * sin(time * 3))
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aReplayedRunRendersTheRecordedPixels() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let live = Painter()
        let renderer = try MetalRenderer(device: device,
                                         pixelFormat: live.colorOutput.drawablePixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device),
                                         encoding: live.colorOutput.presentEncoding)
        let viewport = SIMD2<Float>(200, 200)

        // The original: a live-shaped drive (jittery clock, a moving pointer),
        // rendered every frame because `noClear` accumulates.
        live.setCanvasSize(width: 200, height: 200)
        live.takeRecorder = TakeRecorder(sketch: live)
        live.setup()
        var t = 0.0
        var original: CGImage?
        for k in 0..<30 {
            let dt = 1.0 / 60 + Double(k % 5) * 0.002
            t += dt
            live.setMouse(x: 40 + Double(k) * 4, y: 100 + 30 * sin(Double(k) * 0.4))
            live.advance(time: t, deltaTime: dt, frameRate: 1 / dt)
            live.performDraw()
            original = renderer.accumulatedImage(of: live.drawer, viewport: viewport,
                                                 width: 200, height: 200)
        }
        let take = live.takeRecorder!.take

        // The replay, through the same accumulating drive.
        let fresh = Painter()
        fresh.setCanvasSize(width: 200, height: 200)
        take.install(on: fresh)
        let replayRenderer = try MetalRenderer(device: device,
                                               pixelFormat: fresh.colorOutput.drawablePixelFormat,
                                               sampleCount: ollinPreferredSampleCount(device),
                                               encoding: fresh.colorOutput.presentEncoding)
        fresh.setup()
        var replayed: CGImage?
        for k in 0..<30 {
            fresh.advance(time: Double(k), deltaTime: 9.9, frameRate: 1)
            fresh.performDraw()
            replayed = replayRenderer.accumulatedImage(of: fresh.drawer, viewport: viewport,
                                                       width: 200, height: 200)
        }

        let originalImage = try #require(original)
        let replayedImage = try #require(replayed)
        let originalBytes = try #require(originalImage.dataProvider?.data as Data?)
        let replayedBytes = try #require(replayedImage.dataProvider?.data as Data?)
        #expect(originalBytes == replayedBytes,
                "a replayed run should render byte-identically to the run it recorded")
    }
}
