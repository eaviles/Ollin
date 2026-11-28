@testable import Ollin
import AppKit
import Foundation
import Metal
import MetalKit
import QuartzCore
import Testing

/// Small facts about a run's life, each of which went wrong once: a setup
/// asked for twice running twice, a replay's title outliving the replay, what
/// says a take is recording, a shader whose pipeline will not build being
/// asked of the device on every frame, a frame drawn again reading the
/// reflection history its lost attempt left, and a drive started inside
/// another drive ending the outer one's mode.
@Suite(.serialized)
@MainActor
struct RunLifecycleTests {

    // MARK: A live runner in a window nobody sees, turned by hand

    final class Tally {
        var setups = 0, draws = 0
    }

    final class Probe: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        var tally = Tally()
        override func setup() { tally.setups += 1 }
        override func draw() {
            tally.draws += 1
            background(.black)
        }
    }

    @MainActor
    struct Rig {
        let tally: Tally
        let view: OllinMTKView
        let runner: SketchRunner
        let window: NSWindow

        func probe() -> Probe {
            let probe = Probe()
            probe.tally = tally
            return probe
        }

        /// Wait for room in the frame ring, then run one refresh: a refresh
        /// the ring has no room for is dropped, and a count read after it
        /// would mean nothing. The probe comes before the clock.
        func refresh(_ location: SourceLocation = #_sourceLocation) {
            let deadline = CACurrentMediaTime() + 10
            while !runner.canStartFrame {
                if CACurrentMediaTime() > deadline { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
            }
            #expect(runner.canStartFrame, "the frame ring never emptied", sourceLocation: location)
            runner.draw(in: view)
        }

        func putAway() {
            runner.holdLoop(.closed)
            view.delegate = nil
            window.contentView = nil
        }
    }

    private static let hostTitle = "The host's own title"

    private func makeRig(_ sketch: Sketch? = nil, replaying frames: Int? = nil) throws -> Rig {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let tally = Tally()
        let first: Sketch
        if let sketch {
            first = sketch
        } else {
            let probe = Probe()
            probe.tally = tally
            first = probe
        }
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: first)
        view.drawableSize = CGSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: first, view: view, device: device)
        view.delegate = runner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.title = Self.hostTitle
        if let frames {
            Take(version: Take.currentVersion, sketchType: "Probe", seed: 7,
                 canvas: [64, 64], initialParams: [:],
                 frames: (0..<frames).map {
                     Take.Frame(time: Double($0) / 60, deltaTime: 1.0 / 60, frameRate: 60)
                 },
                 events: [], changes: []).install(on: first)
        }
        let rig = Rig(tally: tally, view: view, runner: runner, window: window)
        rig.refresh()
        return rig
    }

    // MARK: A setup asked for twice

    /// A file a sketch loads in `setup()` changes, so the host asks for
    /// `setup()` again; before the next frame the run also starts over (a new
    /// seed, a saved edit). The fresh `setup()` is the one that was asked
    /// for, so it runs once, in either order.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: ["rerun, then restart", "restart, then rerun",
                                                       "rerun, then reload", "reload, then rerun"])
    func aSetupAskedForAgainBesideAFreshOneRunsOnce(_ order: String) throws {
        let rig = try makeRig()
        defer { rig.putAway() }
        #expect(rig.tally.setups == 1)

        switch order {
        case "rerun, then restart":
            rig.runner.rerunSetup()
            rig.runner.restart(variation: 3)
        case "restart, then rerun":
            rig.runner.restart(variation: 3)
            rig.runner.rerunSetup()
        case "rerun, then reload":
            rig.runner.rerunSetup()
            rig.runner.reload(to: rig.probe())
        default:
            rig.runner.reload(to: rig.probe())
            rig.runner.rerunSetup()
        }
        for _ in 0..<4 { rig.refresh() }
        #expect(rig.tally.setups == 2, "\(order): setup() ran \(rig.tally.setups - 1) times for one fresh run")

        // A rerun asked for on its own still runs, once.
        rig.runner.rerunSetup()
        for _ in 0..<3 { rig.refresh() }
        #expect(rig.tally.setups == 3)
    }

    final class Counting: Sketch {
        nonisolated(unsafe) static var setups = 0
        override var canvasSize: CanvasSize { .square(64) }
        override func setup() { Counting.setups += 1 }
        override func draw() { background(.black) }
    }

    /// The same when the fresh `setup()` is the one a replay's backward jump
    /// runs: the jump starts the take over on a new instance and re-simulates
    /// without returning to the frame loop, and that first `setup()` answers
    /// a pending rerun like any other.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSetupAskedForAgainBesideAReplaysJumpBackRunsOnce() throws {
        Counting.setups = 0
        let rig = try makeRig(Counting(), replaying: 40)
        defer { rig.putAway() }
        for _ in 0..<10 { rig.refresh() }
        #expect(Counting.setups == 1)

        rig.runner.rerunSetup()
        rig.runner.handleTransportKey(character: nil, code: .leftArrow, shift: false)
        for _ in 0..<4 { rig.refresh() }
        #expect(rig.runner.isReplaying)
        #expect(Counting.setups == 2, "setup() ran \(Counting.setups - 1) times for one jump back")
    }

    // MARK: A replay's title

    /// While a take plays back, the window's title carries its position and
    /// state. When the replay ends without playing out (the run starts over
    /// on a new seed, or the sketch is swapped for an edited one), the title
    /// goes back to what the window said before.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: ["restart", "reload"])
    func aReplaysTitleLeavesWithTheReplay(_ ending: String) throws {
        let rig = try makeRig(replaying: 40)
        defer { rig.putAway() }
        for _ in 0..<3 { rig.refresh() }
        #expect(rig.window.title.contains("replay"), "a replay says so in the title: \(rig.window.title)")
        #expect(rig.window.title.hasSuffix("playing"))

        rig.runner.handleTransportKey(character: " ", code: nil, shift: false)
        #expect(rig.window.title.hasSuffix("paused"), "space pauses, and the title says so: \(rig.window.title)")

        if ending == "restart" {
            rig.runner.restart(variation: 2)
        } else {
            rig.runner.reload(to: rig.probe())
        }
        #expect(!rig.runner.isReplaying)
        for _ in 0..<3 { rig.refresh() }
        #expect(rig.window.title == Self.hostTitle,
                "after a \(ending) ended the replay the title still reads \"\(rig.window.title)\"")
    }

    /// A replay that starts over from its end (space at the end) is still a
    /// replay, so it keeps the title, and the window's own comes back once.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aReplayThatStartsOverKeepsItsTitle() throws {
        let rig = try makeRig(replaying: 6)
        defer { rig.putAway() }
        for _ in 0..<8 { rig.refresh() }
        #expect(rig.window.title.contains("end"), "the take played out: \(rig.window.title)")
        rig.runner.handleTransportKey(character: " ", code: nil, shift: false)
        #expect(rig.runner.isReplaying)
        #expect(rig.window.title.contains("replay"), "starting over is still a replay: \(rig.window.title)")
        rig.runner.restart(variation: 1)
        #expect(rig.window.title == Self.hostTitle)
    }

    // MARK: A shader whose pipeline will not build

    final class ShaderLayer: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        let shader = Shader("float4 shade(float2 uv, ShaderInfo info) { return float4(uv, 0.5, 1.0); }")
        var paints = false
        override func draw() {
            background(.black)
            if paints {
                fill(shader)
                drawRect(8, 8, 48, 48)
            } else {
                drawImage(generate(shader).image, 0, 0)
            }
        }
    }

    /// A shader that compiles and whose pipeline the device refuses is a
    /// failure like any other: asked once, remembered, and reported on every
    /// frame until the shaders are dropped to compile again. Asking the
    /// device again on every frame is what a failed compile is cached to
    /// avoid.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [false, true])
    func aPipelineThatWillNotBuildIsAskedForOnce(paints: Bool) throws {
        let sketch = ShaderLayer()
        sketch.paints = paints
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: sketch)
        view.drawableSize = CGSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        view.delegate = runner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let rig = Rig(tally: Tally(), view: view, runner: runner, window: window)
        defer { rig.putAway() }

        let renderer = runner.renderer
        renderer.plantedUserPipelineFailure = true
        for _ in 0..<5 { rig.refresh() }
        #expect(renderer.userPipelineBuilds == 1,
                "the device was asked \(renderer.userPipelineBuilds) times in five frames for a pipeline it refused")
        #expect(renderer.userShaderErrors.count == 1, "the refusal is the shader's error")

        // Dropping the shaders to compile again asks once more, and a
        // pipeline that builds is kept.
        renderer.plantedUserPipelineFailure = false
        runner.invalidateUserShaders()
        let before = renderer.userPipelineBuilds
        for _ in 0..<4 { rig.refresh() }
        #expect(renderer.userPipelineBuilds == before + 1)
        #expect(renderer.userShaderErrors.isEmpty)
    }

    // MARK: A frame drawn again, and the reflection history

    final class Mirror: Sketch {
        override var canvasSize: CanvasSize { .square(96) }
        override func draw() {
            let scene = makeRenderTarget()
            withTarget(scene) {
                background(Color(hex: 0x06080d))
                camera(.orbiting(target: Vector3(0, 0.7, 0), radius: 10, azimuth: 0.5, elevation: 0.4,
                                 fieldOfView: .pi / 4, near: 2, far: 24))
                ambientLight(Color(white: 0.3))
                directionalLight(.white, direction: Vector3(-0.35, -1, -0.2), intensity: 0.95)
                withState {
                    fill(Color(white: 0.05)); translate(0, -0.05, 0)
                    drawBox(width: 40, height: 0.1, depth: 40)
                }
                withState {
                    translate(0, 1.0, 0)
                    fill(Color(hue: 0.02, saturation: 0.75, brightness: 1.0))
                    drawSphere(radius: 1.0)
                }
            }
            drawImage(scene.combined(with: scene.depth,
                                     .screenSpaceReflections(amount: 0.9, roughness: 0.15,
                                                             fresnel: 0.8)).image, 0, 0)
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// A frame that holds a reflection pass builds on the frame before (the
    /// pass keeps a history), so when the GPU throws one away the export
    /// stops and names the frame rather than draw it again over a history the
    /// lost attempt may have half written. That is why the list of histories
    /// a redraw forgets has no entry for the reflection pass: a frame that
    /// holds one is never drawn again.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLostFrameWithAReflectionPassStopsTheExport() throws {
        let clean = pixels(of: try OllinApp.image(of: Mirror()))
        // The mirror is there to be lost: the floor shows the sphere.
        #expect(clean.contains { $0 > 60 })

        OllinApp.plantedDiscards = [0]
        defer { OllinApp.plantedDiscards = [] }
        var thrown: ExportError?
        do { _ = try OllinApp.image(of: Mirror()) } catch let error as ExportError { thrown = error }
        let error = try #require(thrown, "a lost frame with a reflection pass was drawn again")
        #expect(error.kind == .unrendered)
        #expect(error.problem.contains("frame 0 did not come back from the GPU"))
    }

    // MARK: What says a take is recording

    /// A runner says when it is recording a take, and stops saying so by
    /// itself whenever the take ends: when it is finished, when a replay
    /// takes over, and when the sketch is swapped for another.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRunnerSaysWhenATakeIsRecording() throws {
        let rig = try makeRig()
        defer { rig.putAway() }
        #expect(!rig.runner.isRecordingTake)

        rig.runner.beginTake()
        #expect(rig.runner.isRecordingTake)
        for _ in 0..<3 { rig.refresh() }
        // A seed restart starts the take over, still recording.
        rig.runner.restart(variation: 5)
        #expect(rig.runner.isRecordingTake)
        for _ in 0..<3 { rig.refresh() }
        let take = try #require(rig.runner.finishTake())
        #expect(take.frameCount >= 1)
        #expect(!rig.runner.isRecordingTake)

        rig.runner.beginTake()
        #expect(rig.runner.isRecordingTake)
        rig.runner.reload(to: rig.probe())
        #expect(!rig.runner.isRecordingTake, "a swap ends the take")

        rig.runner.beginTake()
        for _ in 0..<2 { rig.refresh() }
        rig.runner.replay(take)
        #expect(!rig.runner.isRecordingTake, "a replay ends the take")
        #expect(rig.runner.isReplaying)
    }

    // MARK: The camera rig asked for twice in a frame

    final class Orbit: Sketch {
        override var canvasSize: CanvasSize { .square(32) }
        var asks = 1
        var eyes: [Vector3] = []
        override func draw() {
            background(.black)
            // Once on the canvas, and again wherever else the same view is
            // wanted (inside a layer, for a second pass).
            for _ in 0..<asks { cameraShowcase(.turntable(period: 4), radius: 6) }
            if let eye = activeCamera?.eye { eyes.append(eye) }
            drawBox(width: 1, height: 1, depth: 1)
        }
    }

    /// The rig moves once a frame, however many times the frame asks it for
    /// its camera: a sketch that sets the same view on the canvas and inside
    /// a layer must not orbit at twice the speed for it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theCameraRigMovesOnceAFrameHoweverOftenItIsAsked() throws {
        let once = Orbit(), twice = Orbit()
        twice.asks = 2
        _ = try OllinApp.image(of: once, frame: 30)
        _ = try OllinApp.image(of: twice, frame: 30)
        let a = try #require(once.eyes.last), b = try #require(twice.eyes.last)
        #expect(once.eyes.count == 31 && twice.eyes.count == 31)
        let apart = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) + (a.z - b.z) * (a.z - b.z)).squareRoot()
        #expect(apart < 1e-9, "asked twice a frame, the camera ended \(apart) away from where one ask leaves it")
        // And it does move: the control.
        let first = try #require(once.eyes.first)
        #expect(abs(first.x - a.x) + abs(first.z - a.z) > 0.1)
    }

    // MARK: A drive inside a drive

    final class Inner: Sketch {
        override var canvasSize: CanvasSize { .square(16) }
        override func draw() { background(.white) }
    }

    final class Outer: Sketch {
        override var canvasSize: CanvasSize { .square(16) }
        var modes: [Bool] = []
        override func setup() throws {
            // A sketch that renders another sketch for a picture of its own.
            _ = try OllinApp.image(of: Inner())
        }
        override func draw() {
            modes.append(OllinApp.isRenderingHeadless)
            background(.black)
        }
    }

    /// A sketch may render another sketch while it is itself being exported.
    /// The inner render ending must leave the outer one's mode as it found
    /// it: everything that keeps an export silent and repeatable reads it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDriveInsideADriveLeavesTheOuterOnesMode() throws {
        let outer = Outer()
        _ = try OllinApp.image(of: outer, frame: 2)
        #expect(outer.modes == [true, true, true], "the outer export read its mode as \(outer.modes)")
        #expect(!OllinApp.isRenderingHeadless, "and the mode ends with the outermost drive")
    }
}
