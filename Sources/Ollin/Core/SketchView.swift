import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import MetalKit
import QuartzCore
import simd
import COllinShaders

/// The sketch runner currently drawing, so a host menu command can reach the
/// running sketch without a per-scene reference (the camera-view snaps in
/// `OllinCameraCommands`). Set each frame by the drawing runner; weak, so a closed
/// window's runner is released. The shipping hosts show one sketch window at a
/// time, so the most-recently-drawn runner is the right target.
@MainActor
enum OllinActiveSketch {
    static weak var runner: SketchRunner?
}

/// A display a running sketch is put on besides the one it draws in.
///
/// The runner owns the frame and asks each of these for somewhere to put it. The
/// windows themselves belong to the host, which is where the wall is built and
/// where AppKit lives.
@MainActor
protocol CanvasOutput: AnyObject {

    /// Where this display wants the frame put, with what it carries of the
    /// canvas worked out against its own size. Nil when it has no drawable free,
    /// which is a frame it sits out rather than one the wall waits for.
    func nextDisplay(canvas: Vector2) -> MetalRenderer.ExtraDisplay?

    /// How large this display wants the canvas drawn: its own size in pixels,
    /// and the part of the canvas it carries.
    func canvasDemand(canvas: Vector2) -> (size: CGSize, part: Rectangle)?

    /// Put this display's picture up, or take it away for the night. A wall goes
    /// black rather than showing the desktop, so it is the picture that is taken
    /// away and never the window.
    func setShowing(_ showing: Bool)
}

// MARK: - The continuous draw loop

/// Bridges an `MTKView`'s per-frame callback to a `Sketch`: it advances the
/// temporal state (`frameCount` / `time` / `deltaTime` / `frameRate`), runs the
/// user's `draw()`, and hands the recorded geometry to the renderer.
///
/// The MTKView is configured for continuous redraw (`isPaused = false`,
/// `enableSetNeedsDisplay = false`), so this fires every display refresh — no
/// `loop()` toggling needed to animate.
@MainActor
public final class SketchRunner: NSObject, MTKViewDelegate {

    /// The instance currently drawing. `package` so the session layer can
    /// reach the *current* sketch after swaps (its own `sketch` deliberately
    /// stays the first mount, which is what keeps the view from remounting).
    package private(set) var sketch: Sketch
    private let renderer: MetalRenderer
    private weak var view: MTKView?

    /// Whether the GPU has room for another frame: the question `draw(in:)`
    /// asks before it starts one, so a refresh it cannot take is dropped
    /// rather than waited on.
    var canStartFrame: Bool { renderer.canStartFrame }

    /// The built-in stats observer (overlay + inspector), kept here so it can be
    /// re-attached to each freshly reloaded sketch — extensions otherwise reset
    /// with the new instance. Set via `observeStats(into:)`; nil for headless runs.
    private var statsExtension: StatsExtension?

    /// Called after each frame with the renderer's current user-shader compile error
    /// (`nil` when every shader compiled). The live host shows it in the error
    /// overlay; a standalone run leaves it unset (the message also goes to stderr).
    /// Invoked on the main thread, deduped so it fires only when the error changes.
    public var onUserShaderError: (@MainActor (ShaderCompileError?) -> Void)?
    private var lastForwardedShaderError: String?

    private var didSetup = false
    private var didReload = false        // call reloaded() after the post-reload setup()
    private var pendingSetupRerun = false // re-run setup() in place (e.g. an asset changed)
    private var clockCarry: Double?      // seconds to continue `time` from across a reload
    private var elapsed: Double = 0      // the sketch clock: the sum of the frame steps so far
    private var lastTime: CFTimeInterval = 0
    private var smoothedFrameRate: Double = 0
    private var smoothedCPUMS: Double = 0
    /// The profiler's other three times, smoothed the same way, so a readout of
    /// the split doesn't flicker frame to frame.
    private var smoothedEncodeMS: Double = 0
    private var smoothedGPUMS: Double = 0
    private var smoothedWaitMS: Double = 0

    /// A camera-view snap requested from the host menu (`OllinCameraCommands`),
    /// applied at the top of the next frame so it rides the rig exactly like a
    /// `cameraView(_:)` call from `draw()`.
    private var pendingCameraView: CameraView?

    /// The orientation holder the axis widget reads, fed each frame by `publishOrientation`.
    private var cameraOrientation: CameraOrientationState?
    /// The sketch mouse position captured when a puck drag begins, so the widget's
    /// drag drives the camera orbit through the same input the canvas would.
    private var widgetDragBase: (x: Double, y: Double)?
    /// The last `cameraAxis()`/`groundGrid()` values pushed to the Camera-menu prefs,
    /// so the push fires only on a change. Reset on reload so a fresh sketch
    /// re-asserts its default (and the viewer's session override resets with it).
    private var lastAxisFlag: Bool?
    private var lastGridFlag: Bool?

    /// True while a camera snap or axis-widget drag has un-paused a `noLoop()`
    /// sketch so the glide can animate. The pause must be handed back once the
    /// camera settles: the sketch itself can't re-pause (its one-shot `noLoop()`
    /// already ran, and `setLooping` only reacts to changes), so without this a
    /// single ⌘-view press would leave a still sketch redrawing at full refresh
    /// forever. `cameraHoldoverPose` is the previous frame's resolved camera; two
    /// equal consecutive poses (with no pending snap or drag) mean settled.
    private var cameraHoldover = false
    private var cameraHoldoverPose: Camera3D?

    /// The longest step the sketch clock takes in one frame, however long the
    /// frame actually took. The clock is the sum of its steps rather than the
    /// wall clock, so anything that stops the frames for a while (a display
    /// asleep overnight, a window dragged, a stall) resumes where the piece
    /// left off instead of jumping forward by the whole gap. That jump is not
    /// cosmetic: `deltaTime` drives every integrator a sketch has, and one
    /// eight-hour step throws a physics world into the far distance.
    ///
    /// A quarter of a second is past any frame rate worth animating at, so a
    /// running sketch never meets the clamp; a sketch slower than four frames a
    /// second runs in slow motion, which beats the alternative.
    static let longestFrameStep: Double = 0.25

    /// The step the clock takes for a frame that measured `raw` seconds: the
    /// measurement, capped, and never negative (the clock a display link reads
    /// can step backwards across a system time change).
    static func clockStep(measuring raw: Double) -> Double {
        min(max(0, raw), longestFrameStep)
    }

    // MARK: Checkpointing

    /// How often this run writes its state down, or `nil` for a run that does
    /// not. Set by the host that owns the window: a sketch under the live host
    /// or the gallery never checkpoints, because restoring old state on every
    /// reload is the opposite of what iterating wants.
    private var checkpointInterval: Double?
    /// The clock reading the next save is due at.
    private var nextCheckpoint: Double = .infinity
    /// Whether the one restore this run gets has happened. `didSetup` goes false
    /// again on a reload or a seed restart, and neither should pull old state
    /// back in.
    private var didRestoreCheckpoint = false
    private var didLogFirstSave = false
    /// Whether this run's `--param` values have been applied. They are a launch
    /// instruction, not a standing one: they land once, on the first `setup()`,
    /// and a reload afterwards keeps whatever the inspector has since turned
    /// (which the host carries across the swap anyway).
    private var didApplyLaunchParams = false

    /// Apply the parameter values this run was started with, the first time only.
    private func applyLaunchParams() {
        guard !didApplyLaunchParams else { return }
        didApplyLaunchParams = true
        sketch.applyCommandLineParams()
    }

    /// Start the parts of an installation the runner owns. Called by the host
    /// that opened the window, once, before the first frame. Public so an app
    /// that puts a sketch in a `SketchView` (a phone, say) can turn the
    /// checkpoint on: the app owns the launch there, so nothing else reads
    /// what the sketch would declare in its `Installation`.
    public func beginInstallation(_ settings: Installation) {
        guard let interval = settings.checkpoint.interval else { return }
        checkpointInterval = interval
        // A watchdog stopping the piece, or Control-C in the terminal it was
        // started from, should not lose the minute since the last save.
        CheckpointSignals.catchStops {
            OllinActiveSketch.runner?.saveCheckpointNow()
        }
    }

    // MARK: Fitting the wall

    /// What this run is fitted with: the sketch's declaration with the saved
    /// calibration's corners in it. Nil at a desk, and in every host that owns
    /// its own window rather than giving it to the piece.
    private var projectionSettings: Installation.Projection?
    /// Whether this run is being fitted to what it is thrown onto at all, which
    /// is what tells the renderer to stop taking its shape from the drawable.
    var isFitted: Bool { projectionSettings != nil }
    /// The display size the placement was last worked out against, so a monitor
    /// changing rebuilds it and an ordinary frame does not.
    private var projectionSize: SIMD2<Int> = .zero

    /// Fit this run to what it is thrown onto, or stop fitting it. Called by the
    /// host that owns the window, and again by each drag of a calibration
    /// handle.
    func setProjection(_ projection: Installation.Projection?) {
        projectionSettings = projection
        projectionSize = .zero          // work it out again against the display
        if projection == nil {
            renderer.projection = nil
            (view as? OllinMTKView)?.projection = nil
        }
    }

    /// Work the declaration out against the display, when either has moved. The
    /// canvas keeps its own proportions inside the fitted picture, so this is
    /// also what tells the renderer to stop taking its shape from the drawable.
    private func refreshProjection(in view: MTKView) {
        guard let projectionSettings else { return }
        let size = SIMD2(Int(view.drawableSize.width.rounded()),
                         Int(view.drawableSize.height.rounded()))
        guard size.x > 0, size.y > 0, size != projectionSize else { return }
        projectionSize = size
        // Nothing to work out from a shape with no inside, which is what a hand
        // dragging one corner past another makes for a moment. The last good
        // placement stays up until the hand comes back: a picture that vanishes
        // mid-drag is a picture nobody can drag.
        guard let placement = ProjectionPlacement(projectionSettings,
                                                  canvas: Vector2(sketch.width, sketch.height),
                                                  output: Vector2(Double(size.x), Double(size.y)))
        else { return }
        renderer.projection = placement
        (view as? OllinMTKView)?.projection = placement
    }

    // MARK: The other displays

    /// The displays this run is put on besides the one it draws in. Empty for a
    /// piece on one screen, which is every run at a desk.
    private var otherDisplays: [any CanvasOutput] = []

    /// The device this run's frames are made on. A wall's own layers have to be
    /// on the same one, since a drawable can only take a frame from its own
    /// device.
    var metalDevice: MTLDevice { renderer.device }

    /// Put the piece on these displays as well as the one it draws in. Called by
    /// the host that owns the windows, and again when a display is plugged in or
    /// unplugged.
    func setOtherDisplays(_ displays: [any CanvasOutput]) {
        otherDisplays = displays
        if displays.isEmpty { renderer.wallDemand = nil }
    }

    /// How large the canvas has to be drawn to feed every display it goes on:
    /// the largest ask among them.
    ///
    /// A display carrying half the canvas across its own width asks for a canvas
    /// twice that wide, so a wall of four projectors asks for four times the
    /// canvas one of them would. The ask is capped at what a texture can be, and
    /// the cap is said out loud once, because a wall quietly drawn at half the
    /// resolution somebody paid for is the kind of thing nobody notices until
    /// the opening.
    private func wallDemand(canvas: Vector2, view: MTKView) -> CGSize? {
        guard !otherDisplays.isEmpty else { return nil }
        var width = 0.0, height = 0.0
        func ask(_ size: CGSize, _ part: Rectangle) {
            guard part.width > 0, part.height > 0 else { return }
            width = max(width, Double(size.width) / part.width)
            height = max(height, Double(size.height) / part.height)
        }
        ask(view.drawableSize, renderer.projection?.source ?? Installation.Projection.wholeCanvas)
        for display in otherDisplays {
            if let asked = display.canvasDemand(canvas: canvas) { ask(asked.size, asked.part) }
        }
        guard width > 0, height > 0 else { return nil }
        let cap = Double(SketchRunner.largestPicture)
        if width > cap || height > cap, !didLogWallCap {
            didLogWallCap = true
            ollinInstallationLog("the wall asks for \(Int(width))x\(Int(height)) of canvas; "
                                 + "drawing at \(SketchRunner.largestPicture) at most")
        }
        return CGSize(width: min(width, cap), height: min(height, cap))
    }

    /// The widest a canvas is drawn for a wall, whatever the wall asks for: what
    /// a Metal texture can be on this generation of hardware.
    static let largestPicture = 16384
    private var didLogWallCap = false

    /// Whether the piece is on screen at all. A schedule that shuts for the
    /// night takes the canvas away; nothing else ever does.
    private var isShowing = true

    /// Put the piece on screen, or take it away, as the schedule's part of the
    /// day changes. Called by the host that owns the window.
    ///
    /// Taking it away stops the frames as well as hiding them, and stopping the
    /// frames is what makes the night cost nothing: the clock is the sum of the
    /// frames the piece draws, so a piece that comes back in the morning comes
    /// back where it stopped rather than fourteen hours further on. A still
    /// sketch keeps its own pause across it, since a `noLoop()` piece must not
    /// start redrawing just because the day did.
    func setShowing(_ showing: Bool) {
        guard showing != isShowing else { return }
        isShowing = showing
        view?.isHidden = !showing
        view?.isPaused = showing ? !sketch.isLooping : true
        // Every other display of the wall goes down with it. They are fed from
        // this frame loop, so a night without frames would otherwise leave the
        // last one of the evening lit on all of them.
        for display in otherDisplays { display.setShowing(showing) }
        if showing { redrawOnce() }
    }

    /// Draw one frame now, outside the loop.
    ///
    /// A still piece draws once and stops, so a display that arrives after that
    /// frame has nothing to put up and would stay black for the rest of the run.
    /// A display gaining a size, or the morning arriving, asks for one here.
    func redrawOnce() {
        guard let view, didSetup else { return }
        DispatchQueue.main.async { [weak view] in
            guard let view, !view.isHidden else { return }
            view.draw()
        }
    }

    /// Write the run's state now. Quiet after the first one: a line a minute for
    /// a week buries everything else in the log.
    func saveCheckpointNow() {
        // Never before the run has read the state it is replacing. Saving is
        // asked for from outside the frame loop (a schedule closing for the
        // night, a quit, a stop signal), and any of those can arrive before the
        // first frame, which is where the restore happens. Writing then puts an
        // empty run over a piece that has been growing for three days.
        guard checkpointInterval != nil, didSetup else { return }
        do {
            try Checkpoint.write(sketch, time: elapsed)
            if !didLogFirstSave {
                didLogFirstSave = true
                let seconds = Int(checkpointInterval ?? 0)
                let path = Checkpoint.url(for: sketch)?.path ?? "?"
                ollinInstallationLog("saving state every \(seconds)s to \(path)")
            }
        } catch {
            ollinInstallationLog("could not save the state: \(error)")
        }
    }

    // MARK: Record and replay (the take transport, see `Take`)

    /// Where the recording writes, when this run records one.
    private var takeRecordURL: URL?
    /// The autosave cadence, in recorded frames: the gap doubles after each
    /// write (a growing take re-encodes whole, so a fixed short cadence would
    /// cost more the longer the run gets), capped at a minute of frames.
    private var takeAutosaveDue = 120
    private var takeAutosaveGap = 120

    /// Whether this runner is playing a recorded take back.
    public var isReplaying: Bool { sketch.takePlayer != nil }
    /// The transport's own pause, distinct from `noLoop()`.
    private var replayPaused = false
    /// A jump asked for by the transport keys: the `frameCount` to land on.
    private var pendingScrubTarget: Int?

    /// Start recording this run into a fresh take. The run restarts (same
    /// seed, fresh `setup()`) so the take begins at frame 0, which is what
    /// makes it replayable; parameter values stay put, and the take writes them
    /// down as its starting point. Pass a file to also write the take there,
    /// on a growing autosave cadence and at `finishTake()`.
    public func beginTake(writingTo url: URL? = nil) {
        sketch.takePlayer = nil
        isClockPaused = false      // a recording wants the live clock
        takeRecordURL = url
        restart(variation: sketch.variation)
        attachTakeRecorder()
        if let url { print("Ollin: recording a take to \(url.path)") }
    }

    /// Attach a fresh recorder to the current sketch, resetting the autosave
    /// cadence. The runner's half of `beginTake`, also used by the first-frame
    /// launch flag and by a seed restart mid-recording.
    private func attachTakeRecorder() {
        sketch.takeRecorder = TakeRecorder(sketch: sketch)
        takeAutosaveGap = 120
        takeAutosaveDue = 120
    }

    /// Stop recording and hand the take over, writing it to the recording
    /// destination when there is one. Quiet when nothing was recording.
    @discardableResult
    public func finishTake() -> Take? {
        guard let recorder = sketch.takeRecorder else { return nil }
        sketch.takeRecorder = nil
        let take = recorder.take
        if let url = takeRecordURL {
            do {
                try take.write(to: url)
                print("Ollin: take written, \(take.frameCount) frames, \(url.path)")
            } catch {
                FileHandle.standardError.write(
                    Data("Ollin: could not write the take: \(error)\n".utf8))
            }
        }
        return take
    }

    /// Play a recorded take back in this window: the sketch restarts under the
    /// take's seed and starting parameter values, live input hands over to the
    /// recording, and the keyboard becomes the transport (space pauses and
    /// resumes, the arrows step a frame, with shift they jump thirty, Home and
    /// End go to the ends, and space at the end starts over).
    public func replay(_ take: Take) {
        finishTake()
        isClockPaused = false      // a replay owns the whole transport
        take.install(on: sketch)
        replayPaused = false
        pendingScrubTarget = nil
        restartForTransport()
    }

    /// The `restart(variation:)` recipe without the reseed: a replay's install
    /// already seeded the sketch and restored its starting parameters.
    private func restartForTransport() {
        sketch.frameCount = 0
        renderer.resetAccumulation()
        didSetup = false
        clockCarry = nil
        sketch.loop()
        view?.isPaused = false
    }

    /// Back to frame 0 of the replay, on a fresh instance of the sketch.
    ///
    /// The original run began on a fresh instance, so a rewound one must too:
    /// state a sketch accumulates in its stored properties (a rate gate like
    /// `time >= nextNote`, a particle array) would otherwise carry the end of
    /// the first pass into the start of the second, and the re-simulation
    /// could never walk the recorded path. Reseeding and re-running `setup()`
    /// on the old instance was measured wrong exactly that way: the clock
    /// rewound while the gates stayed shut, and the whole second pass drew
    /// and sounded nothing.
    private func rewindReplay() {
        guard let player = sketch.takePlayer else { return }
        let take = player.take
        let fresh = type(of: sketch).init()
        reload(to: fresh)
        didReload = false          // a rewind is a fresh run, not a code swap
        take.install(on: fresh)
        restartForTransport()
    }

    /// Jump the replay to `frame` (a `frameCount` value, clamped to the take).
    /// A backward jump restarts from frame 0 and re-simulates forward, which
    /// determinism makes exact; the cost is the frames in between. The jump
    /// lands paused, so stepping inspects still frames.
    public func scrub(to frame: Int) {
        guard let player = sketch.takePlayer else { return }
        pendingScrubTarget = min(max(1, frame), player.take.frameCount)
        replayPaused = true
        view?.isPaused = false     // wake the loop for the one pass that lands it
    }

    /// The transport keys, fed by the view during a replay (live keys never
    /// reach a replayed sketch, so they are free to drive the transport).
    func handleTransportKey(character: Character?, code: KeyCode?, shift: Bool) {
        guard let player = sketch.takePlayer else { return }
        let step = shift ? SketchRunner.audibleScrubSpan : 1
        let lastFrame = player.take.frameCount
        switch (character, code) {
        case (" ", _):
            if sketch.frameCount >= lastFrame {
                rewindReplay()               // space at the end starts over
                replayPaused = false
            } else {
                replayPaused.toggle()
                view?.isPaused = replayPaused
            }
        case ("0", _):
            scrub(to: 1)
        case (_, .some(.leftArrow)):
            scrub(to: sketch.frameCount - step)
        case (_, .some(.rightArrow)):
            scrub(to: sketch.frameCount + step)
        case (_, .some(.home)):
            scrub(to: 1)
        case (_, .some(.end)):
            scrub(to: lastFrame)
        default:
            break
        }
        // A key pressed while the display link is held must speak right away;
        // the next frame pass (if one comes) repeats this harmlessly.
        updateReplayTitle(player)
    }

    /// How many re-simulated frames a scrub may voice. A short forward jump
    /// (the shift-arrow step) plays its notes, so a beat can be found by
    /// ear; anything longer, and every rewound jump, re-simulates quiet.
    static let audibleScrubSpan = 30

    /// Land a pending scrub: rewind when the target is behind, then re-simulate
    /// up to the frame before it. The normal frame path draws the target frame
    /// itself in the same pass, so the landed frame reaches the screen (and
    /// speaks: it is never muted, in either direction). The frames crossed on
    /// the way voice only on a short forward jump; a rewound jump replays from
    /// zero, and a long one compresses too much sound into one instant, so
    /// both pass unheard.
    private func performScrub(to target: Int) {
        guard sketch.takePlayer != nil else { return }
        let rewound = target <= sketch.frameCount
        let crossed = target - (rewound ? 0 : sketch.frameCount)
        if rewound { rewindReplay() }
        let muted = rewound || crossed > SketchRunner.audibleScrubSpan
            ? sketch.transportMutables() : []
        for instrument in muted { instrument.transportMuted = true }
        while sketch.frameCount < target - 1 { stepReplayFrame() }
        for instrument in muted { instrument.transportMuted = false }
    }

    /// One re-simulated frame with no present: advance (the player supplies
    /// the recorded clock and inputs), draw, and give a stateful GPU layer its
    /// step, mirroring the headless drive in `renderImage(of:)`. An
    /// accumulating or feedback frame must actually render for its persistent
    /// surface to evolve; anything else only needs its compute stepped.
    private func stepReplayFrame() {
        if !didSetup {
            sketch.setup()
            applyLaunchParams()
            didSetup = true
        }
        sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(sketch.width), Float(sketch.height))
        let w = Int(sketch.width.rounded()), h = Int(sketch.height.rounded())
        if sketch.drawer.accumulates {
            _ = renderer.accumulatedImage(of: sketch.drawer, viewport: viewport,
                                          width: w, height: h)
        } else if sketch.drawer.usesFeedback {
            _ = renderer.image(of: sketch.drawer, viewport: viewport, width: w, height: h)
        } else {
            renderer.stepCompute(sketch.drawer)
        }
    }

    /// The transport's end of frame: autosave a recording on its growing
    /// cadence, and hold a replay that reached its last frame (or a transport
    /// pause) by stopping the display link until a key wakes it.
    private func endTakeFrame(in view: MTKView) {
        if let recorder = sketch.takeRecorder, takeRecordURL != nil,
           recorder.take.frameCount >= takeAutosaveDue {
            takeAutosaveGap = min(takeAutosaveGap * 2, 3600)
            takeAutosaveDue = recorder.take.frameCount + takeAutosaveGap
            // A value copy, written off the main thread: the encode of a long
            // take is real work, and the frame loop must not pay it.
            let snapshot = recorder.take
            if let url = takeRecordURL {
                DispatchQueue.global(qos: .utility).async { try? snapshot.write(to: url) }
            }
        }
        if let player = sketch.takePlayer {
            if player.isPastEnd(sketch.frameCount) { replayPaused = true }
            if replayPaused, pendingScrubTarget == nil { view.isPaused = true }
            updateReplayTitle(player)
        }
    }

    /// The transport's face: during a replay the window title carries the
    /// position and the state, so a frame with nothing drawn on it can never
    /// read as a dead window.
    /// A window on glass carries no title, so a replay there says nothing.
    private func updateReplayTitle(_ player: TakePlayer) {
        #if os(macOS)
        guard let window = view?.window else { return }
        let total = max(player.take.frameCount, 1)
        let pct = min(100, Int((Double(sketch.frameCount) / Double(total) * 100).rounded()))
        let state = sketch.frameCount >= total ? "end, space starts over"
                  : replayPaused ? "paused" : "playing"
        window.title = "\(sketch.title) - replay \(pct)% | \(state)"
        #endif
    }

    // MARK: The clock transport (the parameter timeline's play, pause, and scrub)

    /// Whether the timeline transport is holding the clock still. Distinct from
    /// `noLoop()` (the sketch's own stillness, which the sketch may lift) and
    /// from a replay's pause (a take owns the whole transport while it plays).
    package private(set) var isClockPaused = false
    /// While the clock runs, wrap it inside this span of seconds when it passes
    /// the top end. The region lives on the transport, not in the automation
    /// file, so looping a stretch changes nothing about what the file holds.
    package var clockLoopRegion: ClosedRange<Double>?
    /// One deliberate pass under a held clock: the clock moves by this much and
    /// the frame advances with that step (never negative; a backward nudge
    /// places the clock and hands the frame a zero step).
    private var pendingClockNudge: Double?
    /// The frame length a transport step moves by. The exports' default cadence,
    /// so sixty steps walk one second whatever the display refreshes at.
    package static let clockStepRate: Double = 60

    /// The sketch clock as the transport reads it: where the next frame draws.
    package var clockTime: Double { elapsed }

    /// Hold the clock still, or let it run again. While held, the display link
    /// stops (no frames are drawn and thrown away, and an accumulating canvas
    /// keeps its ink); a scrub or a step wakes it for exactly one pass. Quiet
    /// during a replay, which owns the transport.
    package func setClockPaused(_ paused: Bool) {
        guard sketch.takePlayer == nil, paused != isClockPaused else { return }
        isClockPaused = paused
        if paused {
            view?.isPaused = true
        } else {
            // Resume from now: the held stretch must not arrive as one step.
            lastTime = CACurrentMediaTime()
            if sketch.isLooping { view?.isPaused = false }
        }
    }

    /// Place the clock at `target` seconds. Under a held clock this draws one
    /// frame there (a zero step, so nothing integrates across the jump); while
    /// playing, the next refresh simply reads the placed clock.
    package func scrubClock(to target: Double) {
        guard sketch.takePlayer == nil else { return }
        elapsed = max(0, target)
        if isClockPaused || !sketch.isLooping { runClockPass(nudge: 0) }
    }

    /// Step the clock by whole frames at ``clockStepRate``, holding it first
    /// the way a video editor's frame step does. A backward step places the
    /// clock and hands the frame a zero step.
    package func stepClock(byFrames frames: Int) {
        guard sketch.takePlayer == nil, frames != 0 else { return }
        if !isClockPaused { setClockPaused(true) }
        runClockPass(nudge: Double(frames) / SketchRunner.clockStepRate)
    }

    /// Draw one frame at the held clock, so an edit made while paused shows.
    package func refreshClockFrame() {
        guard sketch.takePlayer == nil, isClockPaused else { return }
        runClockPass(nudge: 0)
    }

    private func runClockPass(nudge: Double) {
        pendingClockNudge = nudge
        // A frame the interpolator held belongs to the run before the hold;
        // presenting it would eat this deliberate pass and show a stale frame.
        renderer.dropHeldFrame()
        view?.isPaused = false     // wake the loop for the one pass
    }

    /// The Camera menu's projection override starts every launch in perspective.
    /// Left persisted (the plain `@AppStorage` behavior), a stale orthographic
    /// toggle from an earlier session reads as broken rendering rather than a
    /// mode: parallel view rays flatten the environment backdrop to a single
    /// color and reroute every reflection, and nothing on the canvas names the
    /// menu that did it. Cleared once per process, before any frame applies it;
    /// within the session the toggle works normally.
    private static let orthographicOverrideCleared: Void =
        UserDefaults.standard.removeObject(forKey: OllinHUD.orthographicKey)

    public init(sketch: Sketch, view: MTKView, device: MTLDevice) {
        _ = Self.orthographicOverrideCleared
        self.sketch = sketch
        do {
            // The drawable is single-sample (the final present target); MSAA happens
            // in the renderer's float intermediate, so pass the MSAA count directly.
            self.renderer = try MetalRenderer(device: device,
                                              pixelFormat: view.colorPixelFormat,
                                              sampleCount: ollinPreferredSampleCount(device),
                                              encoding: sketch.colorOutput.presentEncoding)
        } catch {
            fatalError("Ollin: failed to initialize the Metal renderer: \(error)")
        }
        super.init()
        self.view = view
        wireLoopControl(sketch)
    }

    /// Route a sketch's `noLoop()`/`loop()` to pausing/resuming the view's
    /// display timer. Re-applied to each freshly reloaded sketch.
    private func wireLoopControl(_ sketch: Sketch) {
        sketch.loopStateDidChange = { [weak self] looping in
            self?.view?.isPaused = !looping
        }
    }

    /// Snap the running sketch's camera to a canonical inspection view, requested
    /// from a host menu command. Applied at the top of the next frame, so it rides
    /// the camera rig like a `cameraView(_:)` call from `draw()`; a sketch that
    /// doesn't use the rig (or is 2D) simply ignores it.
    func requestCameraView(_ view: CameraView) {
        pendingCameraView = view
        if !sketch.isLooping { cameraHoldover = true }   // hand the pause back once settled
        self.view?.isPaused = false   // a noLoop() sketch must still snap on demand
    }

    /// Restart the running sketch at a chosen variation seed, requested from a
    /// host's seed-navigation card. In place, on the same instance: the sketch
    /// reseeds now, the clock and any accumulated canvas reset, and `setup()`
    /// re-runs at the top of the next frame, while `@Param` parameter values stay
    /// put (same instance, so every host's parameter surface keeps working).
    /// A sketch whose `setup()` pins its own seed simply reproduces that one
    /// variation. **Call on the main thread.**
    public func restart(variation: Int) {
        // A seed restart is a new run: it deliberately ends a replay, and a
        // recording starts over on the new seed (a take that changed seed
        // mid-stream could never reproduce).
        sketch.takePlayer = nil
        let wasRecording = sketch.takeRecorder != nil
        sketch.takeRecorder = nil
        sketch.seed(variation)
        defer { if wasRecording { attachTakeRecorder() } }
        sketch.frameCount = 0
        renderer.resetAccumulation()   // a fresh variation starts on a clean canvas
        didSetup = false               // re-run setup() and restart the clock next frame
        clockCarry = nil
        // Restore the running state rather than just unpausing the view: a
        // still sketch's fresh `noLoop()` must be a *change* to fire the pause
        // again, or the restarted still image would redraw forever.
        sketch.loop()
        view?.isPaused = false
    }

    /// Drive the camera orbit from a drag on the axis widget's puck by feeding the
    /// sketch's mouse state the way the canvas would, so a rig-driven sketch
    /// (`cameraShowcase` / `cameraControl`) orbits exactly as if the scene were
    /// dragged. `translation` is the SwiftUI drag translation in points, scaled to
    /// canvas units so the feel matches dragging the scene. A hand-`camera()` or 2D
    /// sketch ignores it.
    func widgetOrbit(began: Bool, ended: Bool, translation: CGSize) {
        let viewWidth = Double(view?.bounds.width ?? 0)
        let scale = viewWidth > 0 ? Double(sketch.width) / viewWidth : 1
        if began {
            widgetDragBase = (sketch.mouseX, sketch.mouseY)
            sketch.setMouseButtonState(true)
        }
        if let base = widgetDragBase {
            sketch.setMouse(x: base.x + Double(translation.width) * scale,
                            y: base.y + Double(translation.height) * scale)
        }
        if ended {
            sketch.setMouseButtonState(false)
            widgetDragBase = nil
        }
        if !sketch.isLooping { cameraHoldover = true }   // hand the pause back once settled
        view?.isPaused = false
    }

    /// Swap in a freshly loaded sketch without tearing down the window or GPU
    /// resources — the heart of live reload. The new instance starts clean:
    /// `setup()` runs again and the clock resets on the next frame. **Call on the
    /// main thread**, since the draw callback runs there and reads `sketch`.
    /// - Parameters:
    ///   - newSketch: the freshly loaded instance, run from the next frame on.
    ///   - keepClock: when `true`, the new sketch keeps the old one's
    ///     `time`/`frameCount` advancing across the swap instead of resetting to
    ///     zero, so an animation's phase doesn't visibly jump on reload. Instance
    ///     state still resets (it's a fresh instance either way).
    public func reload(to newSketch: Sketch, keepClock: Bool = false) {
        // A reload ends the take on either side of the transport: an edited
        // sketch is a different run (its take is written out, so nothing is
        // lost), and a replay's recorded inputs belong to the code they drove.
        finishTake()
        // A frame held for the next refresh belongs to the sketch being
        // replaced, and the interpolator's history to the run that ends here.
        renderer.dropHeldFrame()
        // Size the fresh instance the way `updateCanvasSize` will keep asserting
        // it: a `.resizable` sketch's canvas follows the live view, so carry the
        // current size across the swap; otherwise honor the *new* sketch's
        // declared `canvasSize`, so an edited resolution takes effect on the
        // swap itself rather than waiting for the next drawable resize (which a
        // fixed-size window never delivers).
        if case .resizable = newSketch.windowMode {
            newSketch.setCanvasSize(width: sketch.width, height: sketch.height)
        } else {
            newSketch.setCanvasSize(width: Double(newSketch.canvasSize.width),
                                    height: Double(newSketch.canvasSize.height))
        }
        if keepClock {
            newSketch.frameCount = sketch.frameCount
            clockCarry = sketch.time      // continue `time` from here (see draw)
        } else {
            clockCarry = nil
        }
        // The drawable and the present pipeline were built for the running
        // sketch's `colorOutput` and can't be swapped under a live frame, so an
        // edited one is honored on the next launch. Said out loud, because
        // silently ignoring it looks like the setting doesn't work.
        if newSketch.colorOutput != sketch.colorOutput {
            print("Ollin: colorOutput changed to .\(newSketch.colorOutput.rawValue); "
                  + "relaunch to see it (the window's drawable is built once)")
        }
        wireLoopControl(newSketch)
        let recorder = sketch.sessionRecorder
        sketch = newSketch
        if let statsExtension { newSketch.extend(statsExtension) }   // re-attach stats observer
        if let recorder {
            // A running recording survives the swap: the recorder moves to the
            // fresh instance and, at its setup hook, picks up that sketch's
            // own instruments.
            newSketch.sessionRecorder = recorder
            newSketch.extend(recorder)
        }
        renderer.resetAccumulation()   // a reloaded sketch starts on a clean canvas
        didSetup = false            // re-run setup() next frame
        didReload = true            // ...then call reloaded() once
        lastAxisFlag = nil          // re-assert the fresh sketch's axis/grid defaults
        lastGridFlag = nil
        cameraHoldover = false      // any camera-snap holdover belonged to the old sketch
        cameraHoldoverPose = nil
        view?.isPaused = false      // a prior noLoop() must not freeze the reload
    }

    /// Start feeding per-frame stats into `stats` (for the overlay and the live
    /// inspector). Installs the built-in `StatsExtension` on the current sketch
    /// and remembers it, so `reload(to:)` can re-attach it to each swapped-in
    /// sketch. **Call on the main thread.**
    func observeStats(into stats: FrameStats) {
        let ext = StatsExtension(stats: stats)
        statsExtension = ext
        sketch.extend(ext)
    }

    /// Start feeding the camera orientation into `cameraState` for the axis widget. Set
    /// once when the view builds; the runner writes it each frame in `publishOrientation`.
    func observeOrientation(into cameraState: CameraOrientationState) {
        cameraOrientation = cameraState
    }

    /// Publish the current camera orientation (and the gate flags) to the axis
    /// widget's holder, after `draw()` set the frame's camera. Published on the main
    /// queue, never inline: mutating an observed value inside the render callback
    /// drives a re-entrant SwiftUI layout pass. Driving the widget from this data
    /// (rather than a `TimelineView`) is what keeps it from freezing when the window
    /// loses focus: SwiftUI pauses a free-running timeline there, but honors a data
    /// update, so the tripod keeps tracking the orbit in the background. Only runs
    /// the per-frame work while the widget is on screen, so a 2D sketch (or a 3D one
    /// not showing the axis) pays nothing.
    private func publishOrientation() {
        guard let cameraState = cameraOrientation else { return }
        let cam = sketch.activeCamera
        let is3D = cam != nil
        let axisVisible = sketch.showsCameraAxis
        let gridVisible = sketch.showsGroundGrid
        let showingAxis = is3D && UserDefaults.standard.bool(forKey: OllinHUD.showAxisKey)

        var rotation: simd_float3x3?
        if showingAxis, let cam {
            let v = cam.viewMatrix
            rotation = simd_float3x3(SIMD3(v.columns.0.x, v.columns.0.y, v.columns.0.z),
                                     SIMD3(v.columns.1.x, v.columns.1.y, v.columns.1.z),
                                     SIMD3(v.columns.2.x, v.columns.2.y, v.columns.2.z))
        }

        let gatesChanged = cameraState.is3D != is3D
            || cameraState.axisVisible != axisVisible
            || cameraState.gridVisible != gridVisible
        guard showingAxis || gatesChanged else { return }
        DispatchQueue.main.async {
            if let rotation { cameraState.orientation = rotation }
            cameraState.is3D = is3D
            cameraState.axisVisible = axisVisible
            cameraState.gridVisible = gridVisible
        }
    }

    /// Recompile the shader library from `source` and rebuild the pipelines for
    /// the *running* sketch — live shader reload. Throws (leaving the current
    /// shaders in place) if the source doesn't compile. **Call on the main
    /// thread.**
    public func reloadShaderLibrary(source: String) throws {
        try renderer.reloadLibrary(source: source)
    }

    /// Live shader reload from the framework's split `Shader*.metal` segments in
    /// `directory` (the repo source the user is editing), read and concatenated in
    /// the renderer's fixed order. Throws if a segment is missing or doesn't
    /// compile, leaving the current shaders in place. **Call on the main thread.**
    public func reloadShaderLibrary(fromDirectory directory: String) throws {
        guard let source = MetalRenderer.concatenatedShaderSource(fromDirectory: directory) else {
            throw MetalRenderer.RendererError.shaderLibrary
        }
        try renderer.reloadLibrary(source: source)
    }

    /// Re-run the current sketch's `setup()` on the next frame without swapping
    /// the instance or resetting the clock — for when a co-located asset changes
    /// and `setup()` is where it'd be (re)loaded. **Call on the main thread.**
    public func rerunSetup() {
        pendingSetupRerun = true
    }

    /// Drop the cached compiled user shaders so a `.metal` resource shader is re-read
    /// and recompiled on the next frame: the live-reload hook for a user's own shader
    /// file. The `Shader` value is unchanged (it holds the file path, not the source),
    /// so a property-initialized shader picks up the edit too. **Call on the main
    /// thread.** Forces one frame if the sketch paused itself with `noLoop()`, so a
    /// still sketch still updates.
    public func invalidateUserShaders() {
        renderer.invalidateUserShaderCaches()
        if view?.isPaused == true { view?.draw() }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateCanvasSize(from: view, drawableSize: size)
    }

    /// Retime the draw loop for the display the window now sits on. The rate is
    /// read once when the view is built, so a piece moved from a 60 Hz panel to
    /// a 120 Hz one (or onto a projector at 30) would otherwise keep asking for
    /// the old one for the rest of the run. Called by the installation host
    /// after the displays change.
    #if os(macOS)
    func displayChanged(to screen: NSScreen?) {
        guard let rate = (screen ?? NSScreen.main)?.maximumFramesPerSecond else { return }
        view?.preferredFramesPerSecond = rate
    }
    #endif

    /// One exponential smoothing step, at the factor the frame rate already
    /// uses. The first sample seeds the value, so a readout opens at the real
    /// number instead of climbing to it from zero.
    private func smooth(_ current: Double, _ sample: Double) -> Double {
        current == 0 ? sample : current + (sample - current) * 0.1
    }

    /// Where a capture asked for from the host menu goes: the sketch's own name
    /// and the frame number, in the directory the sketch was run from.
    private func defaultCaptureURL(for sketch: Sketch) -> URL {
        let name = "\(String(describing: type(of: sketch)))-frame-\(sketch.frameCount).gputrace"
        return URL(fileURLWithPath: name,
                   relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    public func draw(in view: MTKView) {
        // The drawing runner is the one a host menu command should reach.
        OllinActiveSketch.runner = self

        // Make sure the sketch knows its size before the first setup()/draw().
        if sketch.width == 0 || sketch.height == 0 {
            updateCanvasSize(from: view, drawableSize: view.drawableSize)
        }

        // A transport jump lands before the frame: re-simulate up to the frame
        // ahead of the target, and let this pass draw the target itself.
        if let target = pendingScrubTarget {
            pendingScrubTarget = nil
            performScrub(to: target)
        } else if replayPaused, sketch.takePlayer != nil {
            // The pause is enforced here, not only by stopping the display
            // link: a tick can already be queued when the pause lands (the
            // scrub pass re-simulates the take, so there is time for one),
            // and advancing in it would walk off the frame a single back
            // step just landed on.
            view.isPaused = true
            return
        } else if isClockPaused, sketch.takePlayer == nil, didSetup,
                  pendingClockNudge == nil, !pendingSetupRerun, pendingCameraView == nil {
            // The timeline transport's hold, enforced the same way: a queued
            // tick must not advance a clock the panel just placed, and an
            // accumulating canvas must not composite the held frame twice.
            // A reload's first frame, a setup rerun, and a camera snap still
            // pass (each runs one pass under a zero step and holds again).
            view.isPaused = true
            return
        }

        let now = CACurrentMediaTime()

        if !didSetup {
            // A launch that asked to record starts its take here, ahead of
            // `setup()`, so the take begins at the run's own frame 0.
            if let url = OllinApp.pendingTakeRecording {
                OllinApp.pendingTakeRecording = nil
                takeRecordURL = url
                attachTakeRecorder()
                print("Ollin: recording a take to \(url.path)")
            }
            // A run that keeps a checkpoint gets one restore, at its first
            // setup: the seed and the tuned parameters before `setup()` builds
            // anything from them, the state itself after.
            var restored: Checkpoint?
            if checkpointInterval != nil, !didRestoreCheckpoint {
                didRestoreCheckpoint = true
                restored = Checkpoint.load(for: sketch)
                restored?.applyBeforeSetup(to: sketch)
            }
            // Continue the clock across a keep-clock reload, or from where the
            // saved state left it; otherwise start at zero.
            elapsed = clockCarry ?? restored?.time ?? 0
            clockCarry = nil
            lastTime = now
            // Reflect where the cursor actually is before the first frame, so a
            // mouse-driven sketch isn't stuck reading (0, 0) — and rendering a
            // blank frame — until the pointer first moves over the window.
            #if os(macOS)
            (view as? OllinMTKView)?.seedPointer()
            #endif
            sketch.setup()
            restored?.applyAfterSetup(to: sketch)
            applyLaunchParams()
            nextCheckpoint = elapsed + (checkpointInterval ?? .infinity)
            didSetup = true
            if didReload {            // setup() just ran on a hot-swapped sketch
                didReload = false
                sketch.reloaded()
            }
        } else if pendingSetupRerun {
            pendingSetupRerun = false
            sketch.setup()            // in-place asset reload; clock keeps running
        }

        // A refresh the GPU has no room for is dropped whole, here, before the
        // sketch draws anything. Starting it instead would park this thread in
        // the frame ring until the GPU handed a slot back, and this thread is
        // the one the window's own controls run on: a frame heavy enough to
        // fall behind would take the mouse and the inspector down with the
        // frame rate. Dropped early, a heavy sketch gives slow frames and a
        // window that still answers. The clock is untouched (it is real time,
        // read at the top of the next refresh), and nothing is drawn and
        // thrown away, which is what an accumulating canvas needs.
        //
        // A take is the exception, playing or recording: a replay consumes one
        // recorded frame per refresh and a recording claims to hold every frame
        // it drew, so both want the wait rather than the gap.
        let carryingATake = sketch.takePlayer != nil || sketch.takeRecorder != nil

        // Frame interpolation shows two pictures for every one the sketch draws:
        // the made frame on the refresh that drew it, and the drawn frame here.
        // This refresh runs no sketch code at all, which is where the time for a
        // heavy scene comes from. The clock is untouched, so the next draw's step
        // spans both refreshes and the motion keeps its real-time speed.
        if renderer.hasHeldFrame {
            renderer.presentHeldFrame(sketch.drawer, in: view)
            return
        }
        // What the renderer cannot see about this refresh: a take wants every
        // frame it drew (and a replay consumes one per refresh), a still sketch
        // may never be asked to draw again, and every display of a wall wants
        // the same frame rather than one made picture each.
        renderer.hostAllowsInterpolation = !carryingATake && sketch.isLooping
            && otherDisplays.isEmpty && !isClockPaused

        // A transport pass is the other exception beside a take: it is one
        // deliberate frame (a scrub, a step), so it waits for the ring rather
        // than dropping, or the frame the panel just asked for never lands.
        guard renderer.canStartFrame || carryingATake || pendingClockNudge != nil else { return }

        // The clock is the sum of its own steps, each one capped (see
        // `longestFrameStep`), so a gap in the frames is a pause rather than a
        // jump: the piece resumes where it stopped.
        let step = max(0, now - lastTime)
        lastTime = now
        let measured = SketchRunner.clockStep(measuring: step)
        let dt: Double
        if let nudge = pendingClockNudge {
            // A transport scrub or step: the clock moves by exactly the nudge
            // (a scrub placed it already and nudges zero), and the frame
            // advances with that step, never a negative one.
            pendingClockNudge = nil
            elapsed = max(0, elapsed + nudge)
            dt = max(0, nudge)
        } else if isClockPaused, sketch.takePlayer == nil {
            // A pass allowed through under a held clock (a reload's first
            // frame, a setup rerun, a camera snap): time stands still.
            dt = 0
        } else {
            dt = measured
            elapsed += dt
            // The transport's loop region: past the top end, the clock comes
            // around to the bottom. Only a real span wraps, and only forward
            // play does; a scrub goes where it was sent.
            if let region = clockLoopRegion, region.upperBound > region.lowerBound,
               elapsed > region.upperBound {
                let span = region.upperBound - region.lowerBound
                elapsed = region.lowerBound
                    + (elapsed - region.lowerBound).truncatingRemainder(dividingBy: span)
            }
        }

        // Exponentially smoothed FPS so the number doesn't jitter frame to frame.
        // A capped step is a stall rather than a frame rate, so it never feeds
        // the readout: one overnight gap would otherwise pull the average to
        // zero and take a minute of frames to climb back.
        if step <= SketchRunner.longestFrameStep {
            let instantaneous = measured > 0 ? 1.0 / measured : 0
            if smoothedFrameRate == 0 {
                smoothedFrameRate = instantaneous
            } else {
                smoothedFrameRate += (instantaneous - smoothedFrameRate) * 0.1
            }
        }

        sketch.advance(time: elapsed, deltaTime: dt, frameRate: smoothedFrameRate)
        // A made frame sits in the middle of the gap between two drawn ones, and
        // that gap is this step (which already spans both refreshes while
        // interpolation runs, since the refresh between drew nothing).
        renderer.frameDelta = dt

        // Where this canvas is on the desk, read fresh each frame so a window
        // being dragged is current in the frames drawn during the drag. It is
        // the view's own rectangle rather than the window's, so a host with a
        // sidebar or a title bar reports the canvas and not the chrome.
        // A canvas on a phone or a tablet fills a screen it cannot be moved
        // around, so there is no placement to read and the sketch keeps none.
        #if os(macOS)
        sketch.setPlacement(canvas: SketchRunner.onScreen(view.convert(view.bounds, to: nil),
                                                          in: view.window),
                            screen: SketchRunner.desktopRect(view.window?.screen?.frame))
        #endif

        // A camera-view snap from the host menu: request it before the sketch's
        // draw() runs, so its cameraShowcase/cameraControl/cameraMove call applies
        // it this frame.
        if let view = pendingCameraView {
            pendingCameraView = nil
            sketch.cameraView(view)
        }

        // Projection (orthographic vs perspective) is a Camera-menu toggle; apply it
        // to the rig before draw() so a rig-driven camera flattens accordingly.
        sketch.cameraRig.isOrthographic = UserDefaults.standard.bool(forKey: OllinHUD.orthographicKey)

        // Time only the CPU tessellation (`performDraw`), not the render: the
        // renderer blocks on the triple-buffer semaphore (the vsync wait), which
        // would pin this to 1/fps and tell us nothing. CPU tessellation is the
        // documented first bottleneck, so it's the headroom number worth showing.
        let drawStart = CACurrentMediaTime()
        sketch.performDraw()
        let cpuMS = (CACurrentMediaTime() - drawStart) * 1000
        smoothedCPUMS = smooth(smoothedCPUMS, cpuMS)

        // Whatever the sketch said about itself this frame goes to the
        // accessibility layer. A sketch that says nothing pays one comparison.
        (view as? OllinMTKView)?.refreshDescription()

        // Bridge the sketch's cameraAxis()/groundGrid() flags to the Camera-menu
        // prefs, but only on a change, so the sketch sets the default and the menu
        // becomes the authority that can override it (a per-frame `cameraAxis()`
        // call no longer fights a viewer's toggle). The prefs reset on reload.
        if lastAxisFlag != sketch.showsCameraAxis {
            lastAxisFlag = sketch.showsCameraAxis
            UserDefaults.standard.set(sketch.showsCameraAxis, forKey: OllinHUD.showAxisKey)
        }
        if lastGridFlag != sketch.showsGroundGrid {
            lastGridFlag = sketch.showsGroundGrid
            UserDefaults.standard.set(sketch.showsGroundGrid, forKey: OllinHUD.showGridKey)
        }

        // Ground grid: a shader-drawn y=0 reference floor, injected after the sketch's
        // draw so it depth-composites with the scene (objects occlude it). Live-only:
        // the headless `image(of:)` drives the sketch on its own loop, so this never
        // reaches an export. The grid pattern, anti-aliasing, colored axes, and distance
        // fade are all computed in `ollin_grid_fragment` from the plane's world XZ, so
        // lines stay crisp and a constant ~1px at any zoom or grazing angle. The plane
        // follows the camera's look-at and is sized to cover the fade, so it reads as
        // infinite; the cell size snaps to a nice step for the current viewing distance.
        // Never inject onto an accumulation surface: `noClear()` composites every
        // frame's geometry into the persistent pile, so the chrome would burn
        // permanent grid lines into the artwork. And never into a frame that is
        // being handed out: a recorder or a shared feed reads the frame the window
        // shows, so while one is armed the grid leaves the window rather than
        // reaching the take.
        let frameAskers = sketch.renderedFrameAskers()
        if let cam = sketch.activeCamera, !sketch.drawer.accumulates, frameAskers.isEmpty,
           UserDefaults.standard.bool(forKey: OllinHUD.showGridKey) {
            let eye = cam.eye.simd3
            let eyeDist = max(Double(simd_distance(eye, cam.target.simd3)), 0.001)
            let fadeStart = eyeDist * 2.0, fadeEnd = eyeDist * 11.0
            let params = OllinGridParams(
                cameraPos: SIMD4<Float>(eye, 0),
                lineColor:  SIMD4<Float>(0.52, 0.52, 0.56, 0.20),   // faint minor lines
                majorColor: SIMD4<Float>(0.72, 0.72, 0.76, 0.52),   // brighter every-10th
                xAxisColor: SIMD4<Float>(0.80, 0.30, 0.32, 0.85),   // red X axis
                zAxisColor: SIMD4<Float>(0.30, 0.50, 0.85, 0.85),   // blue Z axis
                cellSize: 1.0,                                       // base division = 1 world unit; shader picks the LOD
                lineWidthPixels: 1.0,
                fadeStart: Float(fadeStart), fadeEnd: Float(fadeEnd))
            // The grid composites straight over the frame; reset blend in case the sketch
            // left a non-normal mode at the end of its draw.
            sketch.withState {
                sketch.blendMode(.normal)
                sketch.drawer.drawGroundGrid(params, center: cam.target, halfExtent: fadeEnd * 1.15)
            }
        }

        // How bright this frame is allowed to go, read fresh each frame: the
        // system grants and withdraws headroom as the display's brightness and
        // the surrounding content change, so a value fixed at launch would
        // either clip highlights or send more than the panel can show. A
        // standard or wide sketch stops at white whatever the screen reports.
        #if os(macOS)
        let headroom = view.window?.screen?
            .maximumExtendedDynamicRangeColorComponentValue ?? 1
        #else
        let headroom = view.window?.windowScene?.screen.currentEDRHeadroom ?? 1
        #endif
        renderer.presentCeiling = sketch.colorOutput.ceiling(displayHeadroom: Float(headroom))
        sketch.setDisplayHeadroom(Double(headroom))

        // A GPU frame capture, asked for by the sketch or by the host's menu
        // command, wraps exactly this one frame. The capture must bracket the
        // encode, so it opens here rather than around the whole draw.
        let capture = sketch.takeGPUCaptureRequest()
            ?? (UserDefaults.standard.bool(forKey: OllinHUD.captureFrameKey)
                ? defaultCaptureURL(for: sketch) : nil)
        if capture != nil {
            UserDefaults.standard.set(false, forKey: OllinHUD.captureFrameKey)
        }
        let capturing = capture.map { renderer.beginGPUCapture(to: $0) } ?? false

        refreshProjection(in: view)

        // The other displays of a wall: each hands over the drawable it wants
        // this frame in, and what it carries of the canvas. Asked for before the
        // render so all of them ride the one command buffer, which is what keeps
        // the beams of a wall on the same frame.
        var wall: [MetalRenderer.ExtraDisplay] = []
        if !otherDisplays.isEmpty {
            let canvas = Vector2(sketch.width, sketch.height)
            renderer.wallDemand = wallDemand(canvas: canvas, view: view)
            wall = otherDisplays.compactMap { $0.nextDisplay(canvas: canvas) }
        }

        // The frame hooks: whoever asked for this frame's pixels gets them once
        // the GPU has finished it, from the frame the window shows, brought to
        // the canvas size. Delivered on the main queue in frame order, a refresh
        // or so after `afterFrame`; nothing is drawn twice and nothing waits.
        var grab: MetalRenderer.FrameGrabRequest?
        if !frameAskers.isEmpty {
            let sketch = sketch
            grab = MetalRenderer.FrameGrabRequest(
                width: Int(sketch.width.rounded()), height: Int(sketch.height.rounded()),
                wantsImage: !frameAskers.image.isEmpty,
                wantsTexture: !frameAskers.texture.isEmpty,
                deliver: { image, texture in
                    sketch.runFrameRendered(image: image, texture: texture, to: frameAskers)
                })
        }

        renderer.render(sketch.drawer,
                        viewport: SIMD2<Float>(Float(sketch.width), Float(sketch.height)),
                        in: view, also: wall, grab: grab)

        if capturing, let capture { renderer.endGPUCapture(at: capture) }

        // A sketch that stops the loop inside the draw that just ran will not be
        // asked for another refresh, so the frame held behind a made one would
        // never be shown and a guessed picture would stand as the final still.
        // Hand it over now: it queues onto the next refresh either way.
        if !sketch.isLooping, renderer.hasHeldFrame {
            renderer.presentHeldFrame(sketch.drawer, in: view)
        }

        // The grid is host chrome for the live window only. It was appended after the
        // sketch's own draw, so pop it back off now that the on-screen render has
        // consumed it, and nothing that reads the drawer after the frame (a pick, a
        // later export of it) sees the debug grid as the sketch's own geometry.
        sketch.drawer.removeGridChrome()

        // Hand the frame's camera orientation to the axis widget (no-op if unused).
        publishOrientation()

        // Surface any user-shader compile error to the host (deduped) for the error
        // overlay. The draw callback runs on the main thread, so the handler does too.
        if let handler = onUserShaderError {
            let current = renderer.currentUserShaderError
            if current?.message != lastForwardedShaderError {
                lastForwardedShaderError = current?.message
                MainActor.assumeIsolated { handler(current) }
            }
        }

        // The profile the renderer just counted, with its three measured times
        // smoothed like the CPU one (`cpuDrawMS` is timed here, around the draw,
        // so the renderer never fills it in).
        var profile = renderer.profile
        smoothedEncodeMS = smooth(smoothedEncodeMS, profile.cpuEncodeMS)
        smoothedGPUMS = smooth(smoothedGPUMS, profile.gpuMS)
        smoothedWaitMS = smooth(smoothedWaitMS, profile.waitMS)
        profile.cpuDrawMS = smoothedCPUMS
        profile.cpuEncodeMS = smoothedEncodeMS
        profile.gpuMS = smoothedGPUMS
        profile.waitMS = smoothedWaitMS

        // Hand the frame's timing to any extensions (the stats observer, a
        // recorder). Counts are still valid here: the drawer clears next frame.
        sketch.runAfterFrame(FrameInfo(deltaTime: dt, frameRate: smoothedFrameRate,
                                       cpuDrawMS: smoothedCPUMS,
                                       vertexCount: sketch.drawer.vertices.count,
                                       sdfCount: sketch.drawer.sdfInstances.count,
                                       pointCount: sketch.drawer.points.count,
                                       particleCount: sketch.drawer.particleCount,
                                       profile: profile))

        // The cadence, measured on the sketch clock rather than the wall clock,
        // so a piece that was paused or asleep does not come back owing a pile
        // of saves.
        if elapsed >= nextCheckpoint, let interval = checkpointInterval {
            nextCheckpoint = elapsed + interval
            saveCheckpointNow()
        }

        // Hand the pause back to a `noLoop()` sketch once the camera work that
        // un-paused it has settled (see `cameraHoldover`). A 2D or hand-`camera()`
        // sketch has no rig-resolved camera, so it settles right away; a glide or
        // release momentum keeps the pose changing frame to frame and holds the
        // view running until it comes to rest.
        if cameraHoldover {
            if sketch.isLooping {
                cameraHoldover = false          // the sketch runs continuously anyway
                cameraHoldoverPose = nil
            } else if pendingCameraView == nil, widgetDragBase == nil {
                let pose = sketch.activeCamera
                let settled = pose == nil || (cameraHoldoverPose.map { poseSettled($0, pose!) } ?? false)
                cameraHoldoverPose = pose
                if settled {
                    cameraHoldover = false
                    cameraHoldoverPose = nil
                    view.isPaused = true
                }
            } else {
                cameraHoldoverPose = sketch.activeCamera
            }
        }

        endTakeFrame(in: view)
    }

    /// Whether two consecutive frames' camera poses are close enough to call the
    /// motion finished. The rig's easing converges asymptotically, so exact
    /// equality would keep a flicked `noLoop()` camera running long after the
    /// motion stopped being visible; the tolerance is relative to the viewing
    /// distance, far below a pixel.
    private func poseSettled(_ a: Camera3D, _ b: Camera3D) -> Bool {
        let tolerance = max((a.eye - a.target).length, 1e-3) * 1e-6
        return (a.eye - b.eye).length <= tolerance
            && (a.target - b.target).length <= tolerance
            && a.projection == b.projection
    }

    /// Resolve the sketch's logical canvas, in points. For `.auto`/`.fixed` that's
    /// `canvasSize` itself: the window is only a scaled preview of it, so the canvas
    /// stays stable across displays and matches what `--export` renders. For
    /// `.resizable` the canvas follows the window, so use the view's bounds (already
    /// in points). We deliberately don't derive points from
    /// `drawableSize / backingScale` — that scale is unreliable before the view
    /// joins a window (it reads 1 on a Retina display), which silently doubled the
    /// canvas and left mouse coordinates at half scale.
    #if os(macOS)
    /// A rectangle in AppKit's screen space as one a sketch can use: the origin
    /// moves to the top-left of the primary screen and y grows downward, which
    /// is how the canvas is measured. `nil` when there is no rectangle, or no
    /// screen to measure it against.
    static func desktopRect(_ rect: CGRect?) -> Rectangle? {
        // `screens.first` rather than `main`: the main screen is the one with
        // the key window, while the coordinate system is anchored on the
        // primary one, and on two displays those are different screens.
        guard let rect, let primary = NSScreen.screens.first else { return nil }
        return Rectangle(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                         width: rect.width, height: rect.height)
    }

    /// The same journey back: a rectangle in desk coordinates, as AppKit wants
    /// it, counting up from the bottom of the primary display. What a window is
    /// put on a display of a wall with.
    static func screenRect(_ rect: Rectangle) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: rect.x, y: primary.frame.maxY - (rect.y + rect.height),
                      width: rect.width, height: rect.height)
    }

    /// The same, for a rectangle in a view's own window: it goes out to the
    /// screen first. `nil` while the view has no window, which is every frame
    /// of a headless render.
    static func onScreen(_ rect: CGRect, in window: NSWindow?) -> Rectangle? {
        guard let window else { return nil }
        return desktopRect(window.convertToScreen(rect))
    }
    #endif

    private func updateCanvasSize(from view: MTKView, drawableSize _: CGSize) {
        if case .resizable = sketch.windowMode {
            let pts = view.bounds.size
            guard pts.width > 0, pts.height > 0 else { return }
            sketch.setCanvasSize(width: Double(pts.width), height: Double(pts.height))
        } else {
            sketch.setCanvasSize(width: Double(sketch.canvasSize.width),
                                 height: Double(sketch.canvasSize.height))
        }
    }
}

// MARK: - Shared MTKView configuration

#if os(macOS)

/// An `MTKView` that reports the cursor position to its `Sketch` as
/// `mouseX`/`mouseY`, in sketch coordinates (points, top-left origin). AppKit's
/// view space is y-up, so y is flipped. It also carries what the sketch said
/// about itself to the accessibility layer, which is what the tests reach in
/// for: the wiring is the whole feature there, so it is checked on a real view.
final class OllinMTKView: MTKView {
    weak var sketch: Sketch?

    /// How this run is fitted to what it is thrown onto, when it is. The
    /// pointer goes back through it, so a piece being calibrated still reads
    /// `mouseX` in its own canvas rather than in screen corners.
    var projection: ProjectionPlacement?

    /// Whether the view claims keyboard focus the moment it lands in a window
    /// (`KeyboardFocus.automatic`). The gallery turns this off so its example
    /// list keeps arrow-key navigation until the viewer clicks the canvas.
    var claimsKeyboardOnAttach = true
    /// Reports first-responder changes up to the SwiftUI layer, which shows the
    /// click-to-focus keyboard hint while the canvas doesn't hold the keys.
    var onKeyboardFocusChange: ((Bool) -> Void)?

    /// Whether this canvas stays out of the event path entirely: no hit, no
    /// first responder, so every key and click goes to whatever is behind it.
    ///
    /// A screen saver is the one host that turns this on, and it has to. The
    /// contract there is that any input ends the saver, and the program that
    /// ends it is the host, not this view. A canvas that answered a click would
    /// eat the click that was supposed to give the machine back.
    var ignoresInput = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        ignoresInput ? nil : super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.inVisibleRect` keeps the area sized to the view; `.mouseMoved`
        // delivers moves even when no button is held.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        reportPointer(event)
        if let dragger = shapeDragging, event.modifierFlags.contains(Self.shapeDragModifier),
           let point = canvasPoint(event.locationInWindow) {
            dragger.pointerHovered(at: point)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        if draggingShape {
            if let point = canvasPoint(event.locationInWindow) {
                shapeDragging?.dragMoved(to: point)
            }
            return
        }
        reportPointer(event)
        // While a pressure-event stream is live, drag events must stay quiet: a
        // pressure-sensing trackpad's drag events carry the legacy constant 1 in
        // `pressure`, and reporting it would flap the sketch's value between the
        // true press and 1.0 on alternating events. Devices that never send
        // pressure events (tablet points, plain mice) keep this path.
        if !pressureStreamLive { reportPressure(event) }
    }
    override func mouseDown(with event: NSEvent) {
        // A host that can edit the sketch's source takes the modified press,
        // and only if there is a shape under it; the sketch never sees that
        // one, so a drag that moves a circle can't also paint with it. It is
        // taken before the keys change hands: on the performance stage the
        // editor holds them, and a drag on the stage is no reason to take
        // them away.
        if let dragger = shapeDragging, event.modifierFlags.contains(Self.shapeDragModifier),
           let point = canvasPoint(event.locationInWindow), dragger.dragBegan(at: point) {
            draggingShape = true
            return
        }
        // A click reclaims keyboard focus (e.g. after a click on an inspector
        // control moved first responder away), so the canvas keeps the keys.
        window?.makeFirstResponder(self)
        // The hosting layer's gesture recognizers install their own deep-click
        // pressure configuration, which takes precedence over the view property
        // for the press that is starting: re-claim the drawing gesture for this
        // stream (one stage, smooth 0…1, no force-click firing mid-stroke).
        pressureStreamLive = false
        pressureConfiguration?.set()
        reportPointer(event)
        reportPressure(event)
        sketch?.handleMouseButton(pressed: true)
    }
    override func mouseUp(with event: NSEvent) {
        if draggingShape {
            draggingShape = false
            shapeDragging?.dragEnded()
            return
        }
        reportPointer(event)
        sketch?.setPressure(0, canVary: false)
        sketch?.handleMouseButton(pressed: false)
    }

    /// A pressure-sensing device keeps sending pressure while the press deepens
    /// without the pointer moving, so a still hand still swells the mark. Inside
    /// the SwiftUI hosts this never fires (see the monitor in
    /// `viewDidMoveToWindow`); it stays for plain AppKit embeddings.
    override func pressureChange(with event: NSEvent) {
        pressureStreamLive = true
        reportPressure(event)
    }

    /// Hand the sketch the press force, and whether this device can vary it at all.
    /// `associatedEventsMask` reports which other events this input could also send,
    /// so a pressure bit in it is what separates a trackpad reporting a real 0.4
    /// from a plain mouse reporting a flat 1.
    ///
    /// Only valid on mouse down/up/drag, tablet-point, and pressure events: reading
    /// `pressure` on anything else (a plain `mouseMoved`) raises.
    private func reportPressure(_ event: NSEvent) {
        // A pressure event is its own capability proof: only a device that can
        // vary sends them. It must also be the only path that trusts the value,
        // and `associatedEventsMask` must never be read here: on a pressure
        // event that access raises, and AppKit's dispatch swallows the raise,
        // silently abandoning the report (verified by hand).
        if event.type == .pressure {
            sketch?.setPressure(Double(event.pressure), canVary: true)
            return
        }
        // A mouse event from a pressure-sensing device (the mask's pressure
        // bit) carries the legacy constant 1 in `pressure`; the truth arrives
        // on the pressure-event stream, whose curve starts near zero. Seed
        // zero until that stream speaks, so a stroke never opens on a
        // one-frame full-force blip. A plain mouse keeps its honest flat 1.
        let canVary = event.associatedEventsMask.contains(.pressure)
        sketch?.setPressure(canVary ? 0 : Double(event.pressure), canVary: canVary)
    }

    // The secondary (right) button drives the camera-control pan (alongside a
    // modifier-drag). Report the pointer on a right-drag too, since AppKit sends
    // `rightMouseDragged` (not `mouseDragged`) while it's held.
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        reportPointer(event)
        sketch?.setRightMousePressed(true)
    }
    override func rightMouseDragged(with event: NSEvent) { reportPointer(event) }
    override func rightMouseUp(with event: NSEvent) {
        reportPointer(event)
        sketch?.setRightMousePressed(false)
    }

    override func scrollWheel(with event: NSEvent) {
        sketch?.handleScroll(deltaY: Double(event.scrollingDeltaY))
    }

    /// Modifier keys (shift / option / command / control) changed: map AppKit's
    /// flags onto Ollin's platform-neutral set.
    override func flagsChanged(with event: NSEvent) {
        sketch?.setModifiers(ModifierKeys(event.modifierFlags))
        // The dragger hears about the modifier through the monitor installed
        // in `viewDidMoveToWindow`, which sees the event whether or not this
        // view holds the keys; this override stands in only where no window
        // has installed one.
        if modifierMonitor == nil { armShapeDrag(for: event) }
    }

    /// Holding the modifier is what arms shape dragging: the sketch starts
    /// recording where each shape was written, so the next frame can say
    /// what the pointer is over. Letting go puts that cost away again.
    private func armShapeDrag(for event: NSEvent) {
        guard let dragger = shapeDragging else { return }
        let held = event.modifierFlags.contains(Self.shapeDragModifier)
        let pointer = window.flatMap { canvasPoint($0.mouseLocationOutsideOfEventStream) }
        dragger.modifierChanged(held: held, at: pointer)
    }

    // MARK: Files dropped on the canvas

    /// A drop of files from the Finder is taken as a copy when the pasteboard
    /// holds file URLs and the canvas answers input at all.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !ignoresInput, sketch != nil,
              Self.fileURLs(on: sender.draggingPasteboard) != nil else { return [] }
        return .copy
    }

    /// The files reach the sketch as paths, with the pointer at the drop point
    /// mapped the way a click is, so a projected run reads it in its own canvas.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let sketch, let urls = Self.fileURLs(on: sender.draggingPasteboard),
              let point = canvasPoint(sender.draggingLocation) else { return false }
        sketch.handleDroppedFiles(urls.map(\.path), at: point)
        return true
    }

    /// The file URLs a pasteboard carries, or nil when it carries none.
    static func fileURLs(on pasteboard: NSPasteboard) -> [URL]? {
        let read = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let read, !read.isEmpty else { return nil }
        return read
    }

    // MARK: Dragging a shape back into the source

    /// The modifier that hands a press to the host instead of the sketch.
    /// Command is free here: the camera rig's own modified drags are shift and
    /// option, and a sketch reading a modifier is reading a *held* key, not a
    /// press the canvas swallowed.
    static let shapeDragModifier = NSEvent.ModifierFlags.command

    /// Installed by a host that can edit the sketch's own source; `nil` in
    /// every other run, which is what keeps an ordinary window's clicks
    /// entirely the sketch's.
    weak var shapeDragging: (any ShapeDragging)?

    /// Whether the press being held belongs to the host's shape drag.
    private var draggingShape = false

    // MARK: Keyboard

    /// Required for the view to receive `keyDown`/`keyUp`.
    override var acceptsFirstResponder: Bool { !ignoresInput }

    /// Whether the current drag has a live pressure-event stream. Set by the
    /// first pressure event after a mouse down; while true, drag events stop
    /// reporting pressure (see `mouseDragged`).
    private var pressureStreamLive = false

    /// Pressure events reach the app but the SwiftUI hosting layer's gesture
    /// plumbing consumes them before responder dispatch, so `pressureChange`
    /// never fires inside the hosts (verified by hand: every event visible at
    /// the app level, none delivered to the view). A local monitor feeds them
    /// to the sketch instead; the `pressureChange` override stays for plain
    /// AppKit embeddings, where delivery works and the monitor double-reports
    /// the same value harmlessly.
    private var pressureMonitor: Any?

    /// A modifier change goes to whoever holds the keys, and on the
    /// performance stage that is the editor riding over the canvas, so the
    /// shape drag would never arm through `flagsChanged` there. This monitor
    /// sees every modifier change in the key window before it is dispatched,
    /// and hands it to the dragger when a host has installed one.
    private var modifierMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if pressureMonitor == nil {
            pressureMonitor = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] event in
                guard let self, event.window === self.window,
                      self.sketch?.mouseIsPressed == true else { return event }
                self.pressureStreamLive = true
                self.reportPressure(event)
                return event
            }
        }
        if modifierMonitor == nil {
            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow else { return event }
                self.armShapeDrag(for: event)
                return event
            }
        }
        // Take keyboard focus once we're in a window, so a sketch reacts to keys
        // without the user clicking the canvas first. A host whose window has its
        // own keyboard surface (the gallery's example list) opts out; there a
        // click claims the keys instead (see `mouseDown`).
        if claimsKeyboardOnAttach {
            window?.makeFirstResponder(self)
        }
    }

    /// Hand first-responder status back to the window before we leave it, so a
    /// torn-down canvas can't linger in the window's responder chain. Without this,
    /// switching sketches (the gallery rebuilds the canvas per example) frees a view
    /// that's still the window's first responder, and the next responder-chain walk
    /// — e.g. clicking another example in the sidebar — dereferences the freed view
    /// and crashes (EXC_BAD_ACCESS in `-[NSResponder nextResponder]`).
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        // The pressure monitor's teardown lives here (not deinit, which is
        // nonisolated and can't touch main-actor state); leaving the window
        // uninstalls it, and `viewDidMoveToWindow` reinstalls on re-attach.
        if newWindow == nil, let pressureMonitor {
            NSEvent.removeMonitor(pressureMonitor)
            self.pressureMonitor = nil
        }
        if newWindow == nil, let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
            self.modifierMonitor = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        // Auto-repeat fires keyDown over and over while held; the hook is
        // once-per-press, so ignore repeats (held-key response polls isKeyDown).
        guard !event.isARepeat else { return }
        dispatchKey(event, pressed: true)
    }

    /// `⌘]` and `⌘[` move the outlined shape among its neighbors, and with
    /// Shift all the way to the front or the back. Taken here, before the
    /// menus see the key, and only while a host that edits the source is
    /// installed and has a shape outlined; otherwise the key is left alone.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let dragger = shapeDragging, !event.isARepeat,
           event.modifierFlags.contains(Self.shapeDragModifier),
           let step = Self.reorderStep(for: event) {
            if dragger.reorderHovered(step) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// The reorder a bracket key asks for, or nil for any other key.
    static func reorderStep(for event: NSEvent) -> SourceReorderStep? {
        let shift = event.modifierFlags.contains(.shift)
        switch event.charactersIgnoringModifiers {
        case "]": return shift ? .toFront : .forward
        case "[": return shift ? .toBack : .backward
        case "}": return .toFront
        case "{": return .toBack
        default: return nil
        }
    }

    override func keyUp(with event: NSEvent) {
        dispatchKey(event, pressed: false)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onKeyboardFocusChange?(true) }
        return became
    }

    /// Drop held keys and modifiers when focus leaves; without a matching `keyUp` /
    /// `flagsChanged` a key or modifier held across a focus change would otherwise
    /// stay stuck down.
    override func resignFirstResponder() -> Bool {
        sketch?.clearHeldKeys()
        sketch?.setModifiers([])
        sketch?.setRightMousePressed(false)
        onKeyboardFocusChange?(false)
        return super.resignFirstResponder()
    }

    private func dispatchKey(_ event: NSEvent, pressed: Bool) {
        guard let sketch else { return }
        let (character, code) = Self.interpret(event)
        // During a replay the recorded events own the sketch's keyboard, so
        // the live keys are free to drive the transport instead.
        if let runner = delegate as? SketchRunner, runner.isReplaying {
            if pressed {
                runner.handleTransportKey(character: character, code: code,
                                          shift: event.modifierFlags.contains(.shift))
            }
            return
        }
        sketch.handleKey(character: character, code: code, pressed: pressed)
    }

    /// Resolve an AppKit key event to Ollin's model: a named `KeyCode` for keys
    /// with no useful character (arrows, the function row), otherwise the typed
    /// character. Exactly one of the two is non-`nil`.
    private static func interpret(_ event: NSEvent) -> (Character?, KeyCode?) {
        if let code = KeyCode(event: event) { return (nil, code) }
        if let character = event.charactersIgnoringModifiers?.first { return (character, nil) }
        return (nil, nil)
    }

    /// Seed `mouseX`/`mouseY` from the cursor's current location, so a
    /// mouse-driven sketch reflects where the pointer actually is on the first
    /// frame instead of reading (0, 0) until the first move. Uses the real
    /// cursor position even if it's currently outside the window; it
    /// self-corrects the instant the pointer moves over the canvas.
    func seedPointer() {
        guard let window else { return }
        report(windowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func reportPointer(_ event: NSEvent) {
        report(windowPoint: event.locationInWindow)
        reportStylus(event)
    }

    /// What a tablet says about the stylus beyond where it is.
    ///
    /// The tablet fields are only there on a tablet event, and reading one off
    /// any other event raises, so the subtype is checked first and nothing is
    /// touched under a plain mouse. A tablet's pointer motion arrives as an
    /// ordinary mouse event with the `tabletPoint` subtype; entering and
    /// leaving the tablet's range arrives on its own.
    private func reportStylus(_ event: NSEvent) {
        guard let sketch else { return }
        let mouseKind = event.type == .mouseMoved || event.type == .leftMouseDown
            || event.type == .leftMouseDragged || event.type == .leftMouseUp
        // A tablet rides the mouse stream with a subtype, and the subtype is
        // itself only readable on the kinds of event that have one.
        if mouseKind, event.subtype == .tabletProximity {
            tabletProximity(with: event)
            return
        }
        let tabletEvent = event.type == .tabletPoint
            || (mouseKind && event.subtype == .tabletPoint)
        guard tabletEvent else { return }
        let tilt = event.tilt
        sketch.setStylus(Stylus(tilt: Vector2(Double(tilt.x), Double(tilt.y)),
                                twist: Double(event.rotation) * .pi / 180,
                                isEraser: sketch.stylus.isEraser,
                                isNearby: true,
                                tiltIsAvailable: true))
    }

    /// The pen entering or leaving the tablet's range, which is also where the
    /// end being used is said: a stylus turned over arrives as a different
    /// pointing device entirely.
    override func tabletProximity(with event: NSEvent) {
        guard let sketch else { return }
        let entering = event.isEnteringProximity
        sketch.setStylus(Stylus(tilt: entering ? sketch.stylus.tilt : .zero,
                                twist: entering ? sketch.stylus.twist : 0,
                                isEraser: event.pointingDeviceType == .eraser,
                                isNearby: entering,
                                tiltIsAvailable: sketch.stylus.tiltIsAvailable))
    }

    /// The pen moving in range without a button held, which a tablet sends as
    /// its own kind of event rather than as a mouse move.
    override func tabletPoint(with event: NSEvent) {
        reportPointer(event)
    }

    /// Hand the sketch a window point in its own coordinates (see
    /// `canvasPoint(_:)` for the conversion).
    private func report(windowPoint: NSPoint) {
        guard let sketch, let point = canvasPoint(windowPoint) else { return }
        sketch.setMouse(x: point.x, y: point.y)
    }

    /// A point in window coordinates, in sketch space. The view's bounds are in
    /// points, but the logical canvas (`sketch.width`/`height`) may be larger
    /// (a 1080 canvas shown in an 810-pt preview window), so normalize by the
    /// bounds and rescale into canvas space. AppKit is y-up, so y is flipped to
    /// the sketch's top-left origin.
    func canvasPoint(_ windowPoint: NSPoint) -> Vector2? {
        guard let sketch else { return nil }
        let p = convert(windowPoint, from: nil)
        let bw = Double(bounds.width), bh = Double(bounds.height)
        // A fitted piece fills the display and puts its picture inside that
        // through a warp, so the pointer takes the same warp backwards. Without
        // it a piece being lined up on a wall reads a mouse somewhere else.
        if let projection, bw > 0, bh > 0 {
            let onCanvas = projection.canvasPoint(
                fromOutput: Vector2(Double(p.x) / bw, (bh - Double(p.y)) / bh))
            return Vector2(onCanvas.x * sketch.width, onCanvas.y * sketch.height)
        }
        let x = bw > 0 ? Double(p.x) / bw * sketch.width : Double(p.x)
        let y = bh > 0 ? (bh - Double(p.y)) / bh * sketch.height : bh - Double(p.y)
        return Vector2(x, y)
    }

    // MARK: - What the canvas says about itself

    /// The described parts, as accessibility elements. Kept and reused rather
    /// than rebuilt on every query: a screen reader follows an element by
    /// identity, so handing it a new object each time would drop its place.
    private var describedParts: [NSAccessibilityElement] = []
    /// The shape of the description these parts were built from, so a reworded
    /// part costs an update and a new part costs a rebuild.
    private var describedShape: String?

    /// Bring the accessibility elements in line with what the sketch has said.
    /// Cheap and safe to call every frame: a sketch that describes nothing
    /// leaves on the first line, and a sketch that only rewords a part writes
    /// the new words into the element it already has.
    func refreshDescription() {
        guard let sketch else { return }
        let description = sketch.accessibleDescription
        if description.isEmpty && describedShape == nil { return }

        let shape = description.isEmpty ? nil : description.shape
        if shape != describedShape {
            describedShape = shape
            describedParts = description.elements.map { _ in
                let part = NSAccessibilityElement()
                part.setAccessibilityRole(.image)
                part.setAccessibilityParent(self)
                return part
            }
            // The set of parts changed, so anything reading the window has to
            // ask again. Rewording a part posts nothing: it would interrupt.
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
        // Words and places are refreshed every time, so a part that moves or a
        // window that is resized still points at the right piece of canvas.
        let whole = Rectangle(x: 0, y: 0, width: sketch.width, height: sketch.height)
        for (part, element) in zip(describedParts, description.elements) {
            part.setAccessibilityLabel(element.spoken)
            part.setAccessibilityFrameInParentSpace(
                viewRect(of: element.region ?? whole,
                         canvasWidth: sketch.width, canvasHeight: sketch.height,
                         in: bounds, through: projection))
        }
    }

    override func isAccessibilityElement() -> Bool {
        guard let sketch, !sketch.accessibleDescription.isEmpty else {
            return super.isAccessibilityElement()
        }
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        guard let sketch, !sketch.accessibleDescription.isEmpty else {
            return super.accessibilityRole()
        }
        // A canvas with no named parts is one picture; a canvas with parts is a
        // group somebody can move through.
        return sketch.accessibleDescription.hasParts ? .group : .image
    }

    override func accessibilityLabel() -> String? {
        sketch?.accessibleDescription.summary ?? super.accessibilityLabel()
    }

    override func accessibilityChildren() -> [Any]? {
        guard let sketch, sketch.accessibleDescription.hasParts else {
            return super.accessibilityChildren()
        }
        refreshDescription()
        return describedParts
    }
}

/// Maps AppKit's modifier flags onto Ollin's platform-neutral `ModifierKeys`.
/// Lives on the AppKit side of the seam so `ModifierKeys` stays free of AppKit for
/// the eventual UIKit path.
private extension ModifierKeys {
    init(_ flags: NSEvent.ModifierFlags) {
        var mods: ModifierKeys = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.control) { mods.insert(.control) }
        self = mods
    }
}

/// Maps an AppKit key event to a named `KeyCode`, or `nil` for an ordinary
/// character key (which the view reports through `key` instead). Lives here, on
/// the AppKit side of the seam, so the `KeyCode` type itself stays free of
/// AppKit for the eventual UIKit path.
private extension KeyCode {
    init?(event: NSEvent) {
        if let special = event.specialKey {
            switch special {
            case .upArrow: self = .upArrow
            case .downArrow: self = .downArrow
            case .leftArrow: self = .leftArrow
            case .rightArrow: self = .rightArrow
            case .carriageReturn, .newline: self = .return
            case .enter: self = .enter
            case .tab: self = .tab
            case .delete: self = .delete            // the Backspace key
            case .deleteForward: self = .forwardDelete
            case .home: self = .home
            case .end: self = .end
            case .pageUp: self = .pageUp
            case .pageDown: self = .pageDown
            default:
                // The function row (F1…F35) sits in a contiguous block, so derive
                // its number rather than enumerate every case.
                let first = NSEvent.SpecialKey.f1.rawValue
                let last = NSEvent.SpecialKey.f35.rawValue
                guard (first...last).contains(special.rawValue) else { return nil }
                self = .function(special.rawValue - first + 1)
            }
            return
        }
        // Escape isn't an NSEvent.SpecialKey; catch it by its hardware key code.
        if event.keyCode == 53 { self = .escape; return }
        return nil
    }
}

#endif

/// The standard display format: 8-bit BGRA, **sRGB-encoded**, so the GPU blends
/// and resolves MSAA in linear light (the shaders output linear color and the
/// target encodes on store). What a sketch presents into unless it declares a
/// deeper `colorOutput`, in which case `ColorOutput.drawablePixelFormat` names
/// the float drawable instead. Shared by the live view and the off-screen export
/// paths so their pixels match.
let ollinColorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

/// MSAA sample count for the triangle path — 8× where the device supports it (it
/// sharpens thin strokes, polygon/curve outlines, and tessellated text), else
/// the universally-supported 4×. The SDF path is analytically anti-aliased and
/// doesn't depend on this. It's the sample count of the renderer's float
/// intermediate, not of the drawable (which is single-sample — see below).
func ollinPreferredSampleCount(_ device: MTLDevice) -> Int {
    device.supportsTextureSampleCount(8) ? 8 : 4
}

/// When a hosted sketch takes keyboard focus.
public enum KeyboardFocus: Sendable {
    /// The canvas claims the keyboard as soon as it appears, so a sketch reacts
    /// to keys without a click first. The default, right for a window that *is*
    /// the sketch (standalone runs, the live host).
    case automatic
    /// The canvas never takes the keyboard on its own; clicking the sketch
    /// claims it. For hosts whose window has another keyboard surface (the
    /// gallery's example list keeps its arrow-key navigation this way).
    case onClick
}

/// Whether the canvas currently holds keyboard focus: the first-responder
/// signal the click-to-focus hint reads.
@Observable @MainActor
private final class CanvasKeyFocus {
    var isFocused = false
}

/// The setup a canvas view takes on either window system, so the two sides of
/// the seam cannot drift apart. The drawable's format and color space follow
/// what the sketch asked to carry out (see `ColorOutput`). A `.standard` sketch
/// takes the 8-bit sRGB drawable and leaves the color space nil; the wider
/// outputs present into a float drawable, which has no encoding of its own, so
/// the space has to be stated. `extended` additionally asks the system for
/// brightness above SDR white, which is what makes the compositor grant this
/// layer headroom.
@MainActor
func configureOllinCanvas(_ view: MTKView, sketch: Sketch) {
    let output = sketch.colorOutput
    view.colorPixelFormat = output.drawablePixelFormat
    if let space = output.displayColorSpace {
        // The view carries the property on one platform and the layer does on
        // the other; both land on the same layer.
        #if os(macOS)
        view.colorspace = space
        #else
        (view.layer as? CAMetalLayer)?.colorspace = space
        #endif
    }
    if let layer = view.layer as? CAMetalLayer {
        layer.wantsExtendedDynamicRangeContent = output.wantsExtendedDynamicRange
    }
    // The drawable is the present target: single-sample. MSAA is done in the
    // renderer's float intermediate, then resolved before the present pass.
    view.sampleCount = 1
    view.isPaused = false                    // run continuously...
    view.enableSetNeedsDisplay = false       // ...driven by the display timer
}

#if os(macOS)

@MainActor
func makeOllinMTKView(device: MTLDevice, size: CGSize, sketch: Sketch) -> OllinMTKView {
    let view = OllinMTKView(frame: CGRect(origin: .zero, size: size), device: device)
    view.sketch = sketch
    configureOllinCanvas(view, sketch: sketch)
    // Files dropped on the canvas reach the sketch as paths.
    view.registerForDraggedTypes([.fileURL])
    // Ask a Force Touch trackpad for the drawing gesture rather than the default
    // one: a single stage over the full 0...1 range, so a press reads as a smooth
    // amount instead of arming the force-click that fires look-up mid-stroke.
    view.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
    view.preferredFramesPerSecond = NSScreen.main?.maximumFramesPerSecond ?? 60
    return view
}

#endif

// MARK: - SwiftUI host

/// A SwiftUI view that hosts a running `Sketch`. Handy if you want to embed a
/// sketch in a SwiftUI app; standalone `swift run` sketches use `OllinApp.run`
/// (via `Sketch.main()`) instead.
///
/// ```swift
/// SketchView(HelloCircle())
///     .frame(width: 1080, height: 1080)
/// ```
///
/// Pass `onRunner` to receive the `SketchRunner` once the view is created — for
/// hosts that need to drive it (live reload via `reload(to:)`, toggle
/// `loop()`/`noLoop()`). Plain embedders can ignore it.
///
/// Pass `stats` to share the live `FrameStats` with another view (the live
/// host's inspector does this so its readout and the overlay are one source of
/// truth). Left nil, the view owns its own — enough for the on-canvas overlay.
public struct SketchView: View {
    private let sketch: Sketch
    private let injectedStats: FrameStats?
    private let showsInspectorPanel: Bool
    private let keyboardFocus: KeyboardFocus
    private let showsKeyboardHint: Bool
    private let onRunner: (@MainActor (SketchRunner) -> Void)?
    /// A host that turns a modified drag on the canvas into an edit of the
    /// sketch's own file (see `draggingShapes(with:)`).
    private var shapeDragging: (any ShapeDragging)?

    /// Whether the canvas holds the keys right now, driving the hint.
    @State private var keyFocus = CanvasKeyFocus()

    /// Owned stats for standalone/gallery hosts that don't inject their own.
    @State private var ownedStats = FrameStats()
    /// The floating "Show FPS" inspector panel, summoned by the menu toggle.
    /// A detached panel belongs to a desk with windows on it, so the phone and
    /// the tablet keep the on-canvas overlay and nothing else.
    #if os(macOS)
    @State private var statsPanel = StatsPanelController()
    #endif
    /// The shared toggle the "Show FPS" command flips.
    @AppStorage(OllinHUD.showStatsKey) private var showStats = false

    /// The live camera orientation feeding the axis widget. Its observed gate flags
    /// (`is3D` / `axisVisible`) decide whether the widget mounts, so a 2D sketch
    /// never creates it.
    @State private var cameraState = CameraOrientationState()
    /// The shared toggle the "Show Axis" command flips, OR-ed with the sketch's own
    /// `cameraAxis(_:)` flag.
    @AppStorage(OllinHUD.showAxisKey) private var showAxis = false

    /// - Parameters:
    ///   - sketch: the sketch this view runs, advances, and draws.
    ///   - stats: the frame counters a host owns and reads; with none, the view
    ///     keeps a set of its own.
    ///   - showsInspectorPanel: whether this view honors the "Show Inspector"
    ///     toggle by summoning the detached inspector panel. A host with its own
    ///     inspector surface (the live host's sidebar, the gallery's) passes
    ///     `false` so the panel doesn't duplicate it; standalone runs leave it on.
    ///   - keyboardFocus: when the canvas takes the keyboard. `.automatic`
    ///     claims it on appear (the default); `.onClick` only when clicked, so
    ///     the host window's own keyboard surface keeps working.
    ///   - showsKeyboardHint: under `.onClick`, whether to float the
    ///     "Click the sketch to use the keyboard" prompt while the canvas is
    ///     unfocused. Pass `true` only for sketches that actually read keys.
    ///   - onRunner: handed the `SketchRunner` once it exists, so a host can
    ///     reload the sketch, record a take, or read the clock.
    public init(_ sketch: Sketch,
                stats: FrameStats? = nil,
                showsInspectorPanel: Bool = true,
                keyboardFocus: KeyboardFocus = .automatic,
                showsKeyboardHint: Bool = false,
                onRunner: (@MainActor (SketchRunner) -> Void)? = nil) {
        self.sketch = sketch
        self.injectedStats = stats
        self.showsInspectorPanel = showsInspectorPanel
        self.keyboardFocus = keyboardFocus
        self.showsKeyboardHint = showsKeyboardHint
        self.onRunner = onRunner
    }

    private var stats: FrameStats { injectedStats ?? ownedStats }

    /// Hand modified drags on the canvas to `handler`, which moves the shape
    /// under the pointer by editing the file the sketch was written in. Only a
    /// host that owns that file installs one; every other window leaves every
    /// click to the sketch.
    package func draggingShapes(with handler: any ShapeDragging) -> SketchView {
        var copy = self
        copy.shapeDragging = handler
        return copy
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            MetalCanvas(sketch: sketch, stats: stats, cameraState: cameraState,
                        keyboardFocus: keyboardFocus, keyFocus: keyFocus,
                        shapeDragging: shapeDragging, onRunner: onRunner)
            // Mounted only for a 3D frame the sketch or the menu asked to annotate,
            // so a 2D sketch never builds the widget or its animation timeline. The
            // widget is its own size, so it intercepts clicks only over itself.
            if cameraState.is3D && showAxis {
                AxisWidget(cameraState: cameraState)
                    .padding(.bottom, 26)
                    .transition(.opacity)
            }
            // The click-to-focus prompt: only for keyboard-reading sketches in an
            // `.onClick` host, only while the canvas doesn't hold the keys. It
            // never intercepts the click; the canvas claims focus on mouse-down.
            if showsKeyboardHint && keyboardFocus == .onClick && !keyFocus.isFocused {
                KeyboardFocusHint()
                    // Clear the axis widget when both are on screen.
                    .padding(.bottom, cameraState.is3D && showAxis ? 118 : 18)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: cameraState.is3D)
        .animation(.easeOut(duration: 0.2), value: keyFocus.isFocused)
        .onAppear { syncPanel() }
        .onChange(of: showStats) { _, _ in syncPanel() }
        #if os(macOS)
        .onDisappear { statsPanel.close() }
        #endif
    }

    /// Reflect the "Show FPS" toggle onto the floating panel. A no-op for hosts
    /// that opt out (the live host), which have their own inspector.
    private func syncPanel() {
        #if os(macOS)
        guard showsInspectorPanel else { return }
        statsPanel.sync(visible: showStats, sketch: sketch, stats: stats)
        #endif
    }
}

/// The one name for the two SwiftUI bridges, so the canvas below is written
/// once. This is the AppKit/UIKit seam itself.
#if os(macOS)
private typealias CanvasRepresentable = NSViewRepresentable
#else
private typealias CanvasRepresentable = UIViewRepresentable
#endif

/// The `MTKView`-backed half of `SketchView`: it builds the renderer + runner and
/// drives the per-frame loop. Kept private so the public surface is the SwiftUI
/// `View` above (which layers the overlay on top).
private struct MetalCanvas: CanvasRepresentable {
    let sketch: Sketch
    let stats: FrameStats
    let cameraState: CameraOrientationState
    let keyboardFocus: KeyboardFocus
    let keyFocus: CanvasKeyFocus
    let shapeDragging: (any ShapeDragging)?
    let onRunner: (@MainActor (SketchRunner) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Build the canvas and the runner that drives it. The two window systems
    /// name their entry points differently and share this body, so a change to
    /// how a canvas starts reaches both.
    private func makeCanvas(_ context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        // Initial size only; SwiftUI resizes the view to its frame on layout.
        let view = makeOllinMTKView(device: device, size: sketch.canvasSize.cgSize, sketch: sketch)
        // Keyboard focus and source-editing drags are both desk work: a touch
        // canvas has no first responder to claim and no editor behind it.
        #if os(macOS)
        view.claimsKeyboardOnAttach = (keyboardFocus == .automatic)
        view.onKeyboardFocusChange = { [weak keyFocus] focused in
            keyFocus?.isFocused = focused
        }
        view.shapeDragging = shapeDragging
        #endif
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.observeStats(into: stats)
        runner.observeOrientation(into: cameraState)
        view.delegate = runner
        context.coordinator.runner = runner   // retain the runner
        onRunner?(runner)
        return view
    }

    private func updateCanvas(_ view: MTKView) {
        // A host can install its editor after the view exists (the live host
        // mounts the canvas on the first successful compile).
        #if os(macOS)
        (view as? OllinMTKView)?.shapeDragging = shapeDragging
        #endif
    }

    /// Stop the old view's loop when SwiftUI removes it — notably when the gallery
    /// swaps one example for another (the detail pane is keyed by example `id`, so
    /// each switch dismantles the previous `MetalCanvas`). Pausing the display
    /// timer and dropping the delegate keeps an abandoned view from ticking after
    /// it leaves the hierarchy, and releases the runner (and its renderer).
    private static func dismantleCanvas(_ view: MTKView, _ coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.runner = nil
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView { makeCanvas(context) }

    func updateNSView(_ nsView: MTKView, context: Context) { updateCanvas(nsView) }

    static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
        dismantleCanvas(nsView, coordinator)
    }
    #else
    func makeUIView(context: Context) -> MTKView { makeCanvas(context) }

    func updateUIView(_ uiView: MTKView, context: Context) { updateCanvas(uiView) }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        dismantleCanvas(uiView, coordinator)
    }
    #endif

    final class Coordinator {
        var runner: SketchRunner?
    }
}

/// The click-to-focus prompt: a small glass capsule floated over the bottom of
/// the canvas telling the viewer the sketch wants their keyboard. Transient
/// chrome in the reload-toast idiom; it clears the moment the canvas takes
/// focus, and it never intercepts the click itself.
private struct KeyboardFocusHint: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            SwiftUI.Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Click the sketch to use the keyboard")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        // The reload toast's lift, gentler in light mode where the dark-tuned
        // radius reads as a smudge.
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 16, y: 7)
    }
}

// MARK: - Standalone app boot (for `swift run`-ing a sketch)

/// Boots a minimal AppKit app that runs a single sketch in a window. This is
/// the path each `Examples/` target uses (via `Sketch.main()`), and it works
/// from the terminal with `swift run` — no Xcode or app bundle required.
///
/// Main-actor isolated: it owns `NSApplication`/`NSWindow`/`MTKView`, all of
/// which are main-actor types.
@MainActor
public enum OllinApp {

    /// The instance handed to `run`, read back by `OllinSketchApp` once SwiftUI
    /// instantiates it. (SwiftUI builds the `App` itself, so the sketch is passed
    /// out-of-band rather than through an initializer.)
    fileprivate static var standaloneSketch: Sketch?

    /// Where `--record-take` asked this run's take to be written. The runner
    /// picks it up ahead of its first frame (the recorder must attach before
    /// `setup()`, and only the runner knows when that is) and clears it, so a
    /// host's later windows never inherit the flag.
    static var pendingTakeRecording: URL?

    /// Read the windowed take flags (`--replay <file>`, `--record-take <file>`)
    /// against the sketch about to open. A replay installs on the sketch now,
    /// before its window exists, so `setup()` already runs under the take's
    /// seed and parameters; a recording is left for the runner to start (see
    /// `pendingTakeRecording`). Called by the hosts that own a window; the
    /// headless export surface reads `--replay` on its own in
    /// `handleCommandLine`.
    public static func configureTransport(_ args: [String], for sketch: Sketch) {
        if let i = args.firstIndex(of: "--replay"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            do {
                let take = try Take.load(from: url)
                let type = String(describing: type(of: sketch))
                if take.sketchType != type {
                    FileHandle.standardError.write(Data(
                        "Ollin: this take was recorded from \(take.sketchType); replaying it onto \(type)\n".utf8))
                }
                take.install(on: sketch)
                print("Ollin: replaying \(take.frameCount) frames from \(url.path) (space pauses, arrows step, Home/End jump)")
            } catch {
                FileHandle.standardError.write(Data("Ollin: could not read the take: \(error)\n".utf8))
                exit(1)
            }
        }
        if let i = args.firstIndex(of: "--record-take"), i + 1 < args.count {
            guard sketch.takePlayer == nil else {
                FileHandle.standardError.write(Data(
                    "Ollin: --record-take is ignored during a replay\n".utf8))
                return
            }
            pendingTakeRecording = URL(fileURLWithPath: args[i + 1])
        }
        installAutomation(args, on: sketch)
    }

    /// Read `--automation <file>` and hand the parameter curves in it to the sketch
    /// about to run. Called before `setup()`, so a sketch that also writes
    /// tracks in code replaces the file's track for any parameter it names itself.
    /// The standalone window and every export path go through here; under the
    /// live-reload host a sketch carries its tracks in `setup()` instead, which
    /// is what survives each swap.
    static func installAutomation(_ args: [String], on sketch: Sketch) {
        guard let i = args.firstIndex(of: "--automation"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        do {
            sketch.automation = try Automation.load(from: url)
        } catch {
            FileHandle.standardError.write(Data("Ollin: could not read the automation: \(error)\n".utf8))
            exit(1)
        }
    }

    /// True while a headless driver (the frame grab, the sequence/video/GIF/SVG
    /// exporters, the benchmark loop) is driving the sketch clock: fixed
    /// timestep, no window, no runloop servicing between frames. Sources that
    /// normally follow a real clock (a playing video) read this to switch to a
    /// deterministic pull that follows the sketch clock instead.
    ///
    /// Every headless drive sets it, drives, and clears it synchronously on one
    /// thread, and the readers are the nonisolated live sources, so it is
    /// `nonisolated(unsafe)` for the same reason `isVectorExporting` below is.
    /// That is what lets a source that only consults this flag (`DataFeed.start`,
    /// `PushFeed.start`) stay off the main actor: an isolated read here would
    /// make every such call a hop, and a hop waits behind whatever the main
    /// actor is already doing.
    package nonisolated(unsafe) static var isRenderingHeadless = false

    /// True for the *whole* of a vector-export drive (`recordVectorFrame`),
    /// setup and warmup frames included, not just the recorded frame. Vector
    /// export replaces GPU emission per draw call, so a `Batch` recorded any
    /// time during the run must capture vector commands rather than geometry;
    /// `Drawer.makeBatch` reads this to pick the representation. The drive is
    /// synchronous on one thread (set, drive, clear), and the nonisolated
    /// `Drawer` reads it mid-drive, hence `nonisolated(unsafe)`.
    package nonisolated(unsafe) static var isVectorExporting = false

    /// Boot a window running `sketch` and start the app; does not return. Hosts
    /// the sketch in a `SketchView` inside a SwiftUI `App` (`OllinSketchApp`) —
    /// the same lifecycle the live host and gallery use. This is the
    /// `swift run Example-X` path, reached via `Sketch.main()`.
    #if os(macOS)
    public static func run(_ sketch: Sketch) {
        // A piece asked to get itself back up becomes its own supervisor here,
        // and never reaches the line below: it starts the piece as a child
        // process instead and starts another whenever one ends badly. Before
        // the window rather than after, so the process that owns the window is
        // the one that can be replaced.
        Supervisor.superviseIfAsked(Installation.resolved(for: sketch))
        configureTransport(CommandLine.arguments, for: sketch)
        standaloneSketch = sketch
        OllinSketchApp.main()
    }
    #endif

    // A window is measured against a desk it can be moved around. On a phone or
    // a tablet the canvas takes the screen it is given, so the three sizes below
    // have nothing to answer and stay here.
    #if os(macOS)

    /// The window size for `sketch`, resolved from its `windowMode`. `.auto` and
    /// `.resizable` open at the screen-fit size (`.resizable` can then be dragged
    /// from there); `.fixed(f)` is an explicit fraction of `canvasSize`.
    public static func windowSize(for sketch: Sketch) -> CGSize {
        switch sketch.windowMode {
        case .auto, .resizable:
            return windowSize(fitting: sketch.canvasSize.cgSize)
        case .fixed(let fraction):
            let canvas = sketch.canvasSize.cgSize
            return CGSize(width: canvas.width * fraction, height: canvas.height * fraction)
        }
    }

    /// The auto-fit window size for an `export` resolution: 1:1 when the screen has
    /// room, otherwise the largest clean fraction (¾, ½, …) that fits within ~90%
    /// of the main screen, and an exact shrink-to-fit if even those are too big, so
    /// it always fits. A 1080² sketch opens at 1080 on a large display and 810 on a
    /// 14"/16" laptop. Falls back to ¾ when no screen is readable (e.g. headless).
    public static func windowSize(fitting export: CGSize) -> CGSize {
        guard let available = NSScreen.main?.visibleFrame.size else {
            return CGSize(width: export.width * 0.75, height: export.height * 0.75)
        }
        let maxWidth = available.width * 0.9, maxHeight = available.height * 0.9
        func fits(_ f: Double) -> Bool {
            export.width * f <= maxWidth && export.height * f <= maxHeight
        }
        // Largest clean fraction that fits (1:1 when there's room, a comfortable
        // step down otherwise); if none fit, an exact shrink so it always fits.
        let fraction = [1.0, 0.75, 0.5, 0.375, 0.25].first(where: fits)
            ?? min(maxWidth / export.width, maxHeight / export.height)
        return CGSize(width: export.width * fraction, height: export.height * fraction)
    }

    /// The window size for a default (un-overridden) sketch — `Sketch.defaultSize`
    /// fitted to the screen. Hosts with their own chrome (the gallery, the live
    /// host) size their sketch pane to this.
    public static var defaultWindowSize: CGSize { windowSize(fitting: Sketch.defaultSize.cgSize) }

    #endif

    /// Render one frame of `sketch` off-screen and return it as a `CGImage` — no
    /// window, no display loop. Drives the sketch headlessly: `setup()`, then
    /// `draw()` advanced to `frame` at `fps` (so an animated or stateful sketch
    /// renders the right moment). Same pipeline, MSAA, and blending as the live
    /// view and `--export`, so the pixels match.
    ///
    /// This is the headless frame-grab: `export` is this plus a PNG write, and
    /// snapshot tests compare its result against a committed reference. Returns
    /// `nil` if there's no Metal device or the render fails (a library-friendly
    /// soft failure, unlike `export`'s hard exit).
    ///
    /// `quality` is the **automatic** render-quality fallback for features the sketch left at
    /// `.default`: it defaults to `.detail` (best quality; export has no frame-rate pressure),
    /// the `--render-quality` flag overrides it, and a feature the sketch dialed explicitly is
    /// always honored regardless.
    /// The offline path-traced render mode for the export paths (the `--path-traced`
    /// flag sets it; a host may set it directly before `image(of:)` / `export`).
    /// nil (the default) keeps every export on the raster pipeline. Stills and the
    /// sequence/video exports honor it; the contact sheets and the vector exports
    /// stay raster (a sheet of tiles at minutes per tile helps nobody).
    public static var pathTracedExport: PathTracing?

    /// How many samples across a canvas pixel an export renders: 1 (the default)
    /// draws the frame at canvas size, 2 draws it twice as wide and twice as tall
    /// and averages each 2x2 block back into one pixel, and so on up to 4. The
    /// exported picture keeps its canvas size; what changes is how finely it was
    /// sampled. It is the quality-over-speed dial for a frame off the clock: the
    /// work grows with the square of the number, so the live window never uses it.
    ///
    /// `--render-scale N` sets it for every raster export. What it sharpens is the
    /// tessellated fill, text, and fine dense detail; the analytic shapes and the
    /// stroked paths carry their own coverage and are already crisp at 1. The
    /// picture-side chain (motion blur, the lens flare, the frame filters, the
    /// tone map) runs at canvas size either way, so a blur stays the width the
    /// sketch asked for.
    public static var exportRenderScale = 1

    /// How many times each exported frame is drawn before it is written, with
    /// the clock held: `--settle N`. The first draw advances the sketch's clock
    /// as always; the next N−1 draw the same moment again (`time` unchanged,
    /// `deltaTime` zero, `frameCount` counting on), and the last one is what
    /// lands in the file. A picture that converges over frames, an
    /// `Accumulator`'s running mean or a `LineSpray` through a moving camera,
    /// settles for every written frame instead of only the first, at N times
    /// the cost. 1 (the default) draws each frame once. A `noClear` pile keeps
    /// adding through the held draws, so it brightens N times faster there.
    public static var exportSettle = 1

    /// The renderer a headless render draws through. A failure is said out loud, since the
    /// usual cause is a shader that stopped compiling and the export would otherwise die
    /// with a "no Metal device" that hides the compiler's message.
    static func headlessRenderer(for sketch: Sketch, device: MTLDevice) -> MetalRenderer? {
        do {
            return try MetalRenderer(device: device,
                                     pixelFormat: sketch.colorOutput.drawablePixelFormat,
                                     sampleCount: ollinPreferredSampleCount(device),
                                     encoding: sketch.colorOutput.presentEncoding)
        } catch {
            print("Ollin: the renderer failed to start: \(error)")
            return nil
        }
    }

    public static func image(of sketch: Sketch, frame: Int = 0, fps: Double = 60,
                             quality: RenderQuality = .detail) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = headlessRenderer(for: sketch, device: device) else {
            return nil
        }
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        renderer.automaticQuality = quality
        renderer.pathTracing = pathTracedExport
        renderer.renderScale = exportRenderScale
        return renderImage(of: sketch, frame: frame, fps: fps, renderer: renderer)
    }

    /// The one-frame headless drive behind `image(of:)`, against a caller-owned
    /// renderer: the contact sheet reuses one renderer (and its compiled
    /// pipelines) across every tile instead of rebuilding per seed. The caller
    /// owns `isRenderingHeadless` and the renderer's quality fallback.
    static func renderImage(of sketch: Sketch, frame: Int, fps: Double,
                            renderer: MetalRenderer) -> CGImage? {
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.runSetup()
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        let width = size.width, height = size.height
        // In accumulation mode (`noClear`) each frame piles onto the persistent
        // surface, so render every frame into it — the captured frame N is the
        // built-up canvas, not a fresh draw of frame N alone.
        var accumulated: CGImage?
        var fedBack: CGImage?
        let target = max(0, frame)
        // The captured frame is drawn `exportSettle` times with the clock held
        // (the same `time`, no `deltaTime`, the frame count moving on so the
        // renderer steps its persistent layers), and the last draw is the one
        // returned: a running mean settles before the still is taken.
        let settle = max(1, exportSettle)
        for k in 0...target {                        // advance so frame N is correct
            let draws = k == target ? settle : 1
            for pass in 0..<draws {
                sketch.advance(time: Double(k) / fps, deltaTime: pass == 0 ? 1 / fps : 0, frameRate: fps)
                sketch.performDraw()
                if sketch.drawer.accumulates {
                    accumulated = renderer.accumulatedImage(of: sketch.drawer, viewport: viewport,
                                                            width: width, height: height)
                } else if sketch.drawer.usesFeedback || pass > 0 {
                    // Feedback state lives in render-pass-filled ping-pong textures, so
                    // (like accumulation) every intermediate frame must render (which also
                    // steps compute) for the layer to evolve; only the last frame is kept.
                    // A settle draw always renders, since rendering is what steps the
                    // layer it is there to settle.
                    fedBack = renderer.image(of: sketch.drawer, viewport: viewport,
                                             width: width, height: height)
                } else if k < target {
                    // A stateful compute sim must run on the GPU every frame to evolve;
                    // the intermediate frames we don't capture still need their steps
                    // executed (only the final frame is rendered + read back below).
                    renderer.stepCompute(sketch.drawer)
                }
            }
        }
        if sketch.drawer.accumulates { return accumulated }
        if sketch.drawer.usesFeedback || settle > 1 { return fedBack }
        return renderer.image(of: sketch.drawer, viewport: viewport, width: width, height: height)
    }

    /// Render one frame of `sketch` off-screen and write it as a still, with no
    /// window. Drives the sketch headlessly: `setup()`, then `draw()` advanced to
    /// `frame` at `fps` (so animated/stateful sketches export the right moment).
    /// The headless frame-grab (`image(of:)`) plus an image write, and the basis
    /// for PNG sequences → video.
    ///
    /// The file name picks the format. A `.heic` (or `.heif`) path writes HEIC,
    /// which is the one that can keep brightness above white: an `extended`
    /// sketch's highlights ride along in an ISO gain map. Everything else writes
    /// a PNG, which stops at white.
    public static func export(_ sketch: Sketch, to path: String, frame: Int = 0, fps: Double = 60,
                              quality: RenderQuality = .detail) {
        guard let cgImage = image(of: sketch, frame: frame, fps: fps, quality: quality) else {
            fatalError("Ollin: failed to render the frame for export (no Metal device?)")
        }
        let recipe = ExportMetadata.capture(from: sketch, frame: frame, fps: fps).recipe
        let size = "\(cgImage.width)×\(cgImage.height)"
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "heic", "heif":
            guard let still = exportHEIC(cgImage, to: path, recipe: recipe) else {
                fatalError("Ollin: failed to write \(path)")
            }
            // Say whether the highlights made it, since that is the whole reason
            // to choose this format and it depends on what the frame drew.
            let carried = still.keepsHighlights
                ? String(format: ", highlights to %.2fx white in a gain map", still.peak)
                : ", nothing above white to keep"
            print("Ollin: exported frame \(frame) → \(path) (\(size)\(carried))")
        default:
            guard writePNG(cgImage, to: path, recipe: recipe) else {
                fatalError("Ollin: failed to write \(path)")
            }
            print("Ollin: exported frame \(frame) → \(path) (\(size))")
        }
    }

    /// Render a deterministic PNG sequence of `sketch` into `directory` — no
    /// window. Drives the sketch headlessly at a **fixed timestep**
    /// (`deltaTime = 1/fps`, `time = frame/fps`), decoupled from wall-clock, so
    /// every frame renders the exact moment it should no matter how long it takes
    /// — a ten-minute render still assembles into a smooth `fps` video. Frames are
    /// written as `frame_00001.png`, `frame_00002.png`, … (zero-padded from
    /// `startFrame`), ready for `ffmpeg`. One sketch instance and renderer are
    /// reused across the run, so stateful sketches evolve frame to frame.
    ///
    /// `skipSeconds` runs the sketch (clock + `draw()`) for that long *before*
    /// capturing, without writing — so a stateful sketch settles into motion
    /// first; the captured clock then continues from `skipSeconds` onward, and
    /// the written frames still number from `startFrame`.
    ///
    /// For a *reproducible* sequence, seed the sketch (`seed(…)` in `setup()`);
    /// unseeded, it's internally consistent within a run but differs between runs.
    public static func exportSequence(_ sketch: Sketch, to directory: String,
                                      frames: Int, fps: Double = 60,
                                      startFrame: Int = 1, skipSeconds: Double = 0,
                                      quality: RenderQuality = .detail,
                                      slowMotion: SlowMotion? = nil,
                                      writesEXR: Bool = false) {
        guard frames > 0 else { return }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Ollin: failed to create \(directory): \(error)")
        }

        let size = sketch.canvasSize
        let motion = (slowMotion?.isActive ?? false) ? slowMotion : nil
        // The clock the sketch is driven at, which is the rate these numbered
        // frames belong to: assemble them at `fps` and the motion plays slow.
        let clock = motion?.clockRate(playingAt: fps) ?? fps
        let skipFrames = max(0, Int((skipSeconds * clock).rounded()))
        let skipNote = skipFrames > 0 ? String(format: " (after %gs warmup)", skipSeconds) : ""
        let kind = writesEXR ? " as linear EXR" : ""
        print("Ollin: exporting \(frames) frames\(kind) at \(Int(fps)) fps\(skipNote) → \(directory) (\(size.width)×\(size.height))")
        if let motion { print(motion.note(written: frames, fps: fps)) }

        let elapsed = renderFrames(sketch, frames: frames, fps: fps, skipSeconds: skipSeconds,
                                   quality: quality, slowMotion: motion,
                                   capturesLinear: writesEXR) { frame, index in
            // Captured per frame (cheap: the git lookup is cached) so each
            // file's recipe names the sketch-clock frame it shows.
            var meta = ExportMetadata.capture(from: sketch, frame: skipFrames + index, fps: clock)
            meta.slowMotion = motion
            let recipe = meta.recipe
            let name = String(format: writesEXR ? "frame-%05d.exr" : "frame-%05d.png",
                              startFrame + index)
            let path = (directory as NSString).appendingPathComponent(name)
            if writesEXR {
                // A made frame is built by the interpolator after the present, so
                // it has no linear canvas behind it; the flag parsing refuses that
                // pairing, and this is the backstop.
                guard let linear = frame.linear, writeEXR(linear, to: path, recipe: recipe) != nil else {
                    fatalError("Ollin: failed to write \(path)")
                }
            } else {
                guard let cgImage = frame.image, writePNG(cgImage, to: path, recipe: recipe) else {
                    fatalError("Ollin: failed to write \(path)")
                }
            }
        }

        print(String(format: "Ollin: exported %d frames in %.1fs → %@", frames, elapsed, directory))
        if writesEXR {
            // No assembly line here: these are linear frames for a compositor,
            // not something to hand a video encoder as they are.
            print("Each file holds the frame in linear light, before the tone map.")
            return
        }
        print("Assemble with ffmpeg (or use --export-video / --export-gif directly):")
        print("  ffmpeg -framerate \(Int(fps)) -start_number \(startFrame) \\")
        print("    -i \(directory)/frame-%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 \\")
        print("    \(directory)/out.mp4")
    }

    /// Drive `sketch` headlessly at a **fixed timestep** (`time = frame/fps`,
    /// `deltaTime = 1/fps` — never wall-clock) and hand each rendered frame to
    /// `write` with its 0-based index. The shared engine behind the
    /// PNG-sequence, video, and GIF exports: one sketch instance and renderer
    /// are reused across the run (stateful sketches evolve frame to frame),
    /// `skipSeconds` runs the sketch that long *before* capturing (the captured
    /// clock continues from there), and a single rewriting progress line shows
    /// pct done · render throughput. Returns the elapsed wall-clock seconds.
    /// One frame on its way out of the headless drive.
    ///
    /// Most consumers want `image`: a PNG, a GIF frame, a video frame drawn
    /// through Core Graphics. The HDR video writer takes `pixels` instead,
    /// because its frames are PQ code values, which no `CGImage` color space
    /// names, so the bytes themselves are the only honest form. Both describe
    /// the same read-back, and both are valid only while the callback runs.
    @MainActor
    struct RenderedFrame {
        let renderer: MetalRenderer
        let buffer: MTLBuffer
        let bytesPerRow: Int
        let width: Int
        let height: Int
        /// The canvas showed through (`background(.clear)`), so the present
        /// kept its coverage as alpha and the image is tagged premultiplied.
        let transparent: Bool

        /// The frame as an image, in whatever space the sketch's `colorOutput`
        /// presents into.
        var image: CGImage? {
            renderer.displayImage(from: buffer, width: width, height: height,
                                  transparent: transparent)
        }

        /// The presented bytes themselves, `bytesPerRow * height` of them.
        var pixels: UnsafeRawPointer { UnsafeRawPointer(buffer.contents()) }

        /// The same frame one step earlier, in linear light with its depth,
        /// which the EXR sequence writes. Nil unless the render was asked to
        /// keep it (`capturesLinear`).
        var linear: MetalRenderer.LinearFrame? { renderer.lastLinearFrame }
    }

    @discardableResult
    static func renderFrames(_ sketch: Sketch, frames: Int, fps: Double,
                             skipSeconds: Double, quality: RenderQuality = .detail,
                             encoding: PresentEncoding? = nil,
                             slowMotion: SlowMotion? = nil,
                             capturesLinear: Bool = false,
                             write: (RenderedFrame, Int) -> Void) -> Double {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        let renderer: MetalRenderer
        do {
            // A frame leaves at whatever depth the sketch asked to carry, and
            // `encoding` may be overridden by the caller: the HDR video export
            // drives the same loop but wants PQ-encoded frames rather than the
            // linear Display P3 the screen and the still export take.
            renderer = try MetalRenderer(device: device,
                                         pixelFormat: sketch.colorOutput.drawablePixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device),
                                         encoding: encoding ?? sketch.colorOutput.presentEncoding)
        } catch {
            fatalError("Ollin: failed to initialize the Metal renderer: \(error)")
        }
        renderer.automaticQuality = quality   // the fallback for features the sketch left at .default
        renderer.pathTracing = pathTracedExport
        renderer.renderScale = exportRenderScale
        renderer.pathTraceReportsProgress = false   // the loop below prints its own line
        renderer.capturesLinearFrame = capturesLinear
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }

        let size = sketch.canvasSize
        let width = size.width, height = size.height
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.runSetup()

        // Slow motion parts the two rates an export usually shares. The file
        // still plays at `fps`; the sketch's own clock runs at `clock`. The
        // drawn form steps that clock finer and draws every written frame, so
        // `drawnFrames` and `frames` agree; the made form leaves the clock alone
        // and fills the gaps afterward, so it draws fewer than it writes.
        let motion = (slowMotion?.isActive ?? false) ? slowMotion : nil
        let clock = motion?.clockRate(playingAt: fps) ?? fps
        let drawnFrames = motion?.drawnFrames(forWritten: frames) ?? frames
        // Made frames are built from the picture and depth each render leaves
        // behind, so the render has to be told to keep them.
        renderer.exportMadeFrames = motion?.source == .made
        defer { renderer.endExportMadeFrames() }

        let skipFrames = max(0, Int((skipSeconds * clock).rounded()))
        let wallStart = CACurrentMediaTime()
        var written = 0                                   // 0-based index handed to `write`
        for k in 0..<(skipFrames + drawnFrames) {
            sketch.advance(time: Double(k) / clock, deltaTime: 1 / clock, frameRate: clock)
            sketch.performDraw()                          // run every frame so state settles

            // Whether the interpolator can work on this sketch at all is only
            // knowable once it has drawn, so it is asked at the first frame,
            // before a single file has been written.
            if k == 0, motion?.source == .made,
               let refusal = renderer.madeFrameRefusal(sketch.drawer) {
                fflush(stdout)          // so the refusal reads after the header
                FileHandle.standardError.write(Data(
                    "Ollin: \(refusal).\nDrop --made-frames and every frame is drawn instead, which costs more time and is never worse.\n".utf8))
                exit(1)
            }

            // In accumulation mode (`noClear`) the persistent pile must build every
            // frame — including warmup — so render into it always; otherwise warmup
            // frames skip the render entirely.
            let accumulates = sketch.drawer.accumulates
            var rendered: (buffer: MTLBuffer, bytesPerRow: Int)?
            if accumulates || k >= skipFrames {
                rendered = accumulates
                    ? renderer.accumulatedFrame(of: sketch.drawer, viewport: viewport, width: width, height: height)
                    : renderer.renderedFrame(of: sketch.drawer, viewport: viewport, width: width, height: height)
                // A written frame settles: the same moment drawn again `exportSettle`
                // times with the clock held (no `deltaTime`, the frame count moving
                // on so the renderer steps its persistent layers), and the last
                // draw is the one written. Warmup frames are drawn once.
                if k >= skipFrames {
                    for _ in 1..<max(1, exportSettle) {
                        sketch.advance(time: Double(k) / clock, deltaTime: 0, frameRate: clock)
                        sketch.performDraw()
                        rendered = accumulates
                            ? renderer.accumulatedFrame(of: sketch.drawer, viewport: viewport, width: width, height: height)
                            : renderer.renderedFrame(of: sketch.drawer, viewport: viewport, width: width, height: height)
                    }
                }
            } else {
                // Non-accumulating warmup frame: not captured, but a stateful compute
                // sim still needs its steps run on the GPU so the field evolves into
                // the first captured frame.
                renderer.stepCompute(sketch.drawer)
            }

            if k < skipFrames {                           // warmup: built the pile, don't write
                FileHandle.standardError.write(Data(
                    String(format: "\r  warming up %d/%d    ", k + 1, skipFrames).utf8))
                continue
            }

            guard let rendered else {
                fatalError("Ollin: failed to render frame \(k)")
            }
            let done = k - skipFrames + 1                  // 1-based count of drawn frames
            // The made frame goes first: it belongs between the frame just drawn
            // and the one before it, and it is built from the pair the render
            // left behind. Nothing comes back for the first frame of a run,
            // which has nothing before it to sit between.
            if motion?.source == .made {
                if let made = renderer.exportMadeFrame(sketch.drawer, deltaTime: 1 / clock,
                                                       width: width, height: height),
                   written < frames {
                    write(RenderedFrame(renderer: renderer, buffer: made.buffer,
                                        bytesPerRow: made.bytesPerRow,
                                        width: width, height: height,
                                        transparent: sketch.drawer.hasTransparentBackground), written)
                    written += 1
                }
            }
            if written < frames {
                write(RenderedFrame(renderer: renderer, buffer: rendered.buffer,
                                    bytesPerRow: rendered.bytesPerRow,
                                    width: width, height: height,
                                    transparent: sketch.drawer.hasTransparentBackground), written)
                written += 1
            }

            // A single rewriting progress line: pct done · render throughput.
            // It counts what the sketch draws, which is what the time is going
            // into; under made-frame slow motion the file holds more than that.
            let elapsed = CACurrentMediaTime() - wallStart
            let renderFPS = elapsed > 0 ? Double(done) / elapsed : 0
            let line = String(format: "\r  rendering %d/%d (%d%%) · %.0f fps    ",
                              done, drawnFrames, done * 100 / drawnFrames, renderFPS)
            FileHandle.standardError.write(Data(line.utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
        // A gap that could not be filled leaves the file short, and a short file
        // that says nothing is the worst way to find out.
        if motion?.source == .made, written < frames {
            FileHandle.standardError.write(Data(
                "Ollin: the interpolator stopped making frames, so the file holds \(written) of the \(frames) asked for\n".utf8))
        }
        return CACurrentMediaTime() - wallStart
    }

    /// Run `sketch`'s draw loop headlessly for `frames` frames — no window, no
    /// GPU, no vsync — timing only the CPU cost of `setup()` + per-frame
    /// `performDraw()` (the tessellation that builds `drawer.vertices`). Prints
    /// ms/frame, vertices/frame, and the implied CPU-bound FPS ceiling, so a
    /// rendering-performance change can be measured deterministically.
    static func benchmark(_ sketch: Sketch, frames: Int = 600, fps: Double = 60, gpu: Bool = false,
                          quality: RenderQuality = .default) {
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        let n = max(1, frames)
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.runSetup()
        // One warm-up frame so first-time buffer growth doesn't skew the average.
        sketch.advance(time: 0, deltaTime: 1 / fps, frameRate: fps)
        sketch.performDraw()

        // Optional GPU timing. Three numbers, because they answer different questions:
        //   • CPU draw   : the per-frame `performDraw()` tessellation cost alone.
        //   • GPU        : the *pure* per-frame GPU cost from command-buffer timestamps
        //                  (vsync- and readback-independent, the real live render cost),
        //                  the same measurement the `.defocus`/shadow benchmarks report.
        //   • end-to-end : CPU + GPU + a full read-back, run fully serially; conservative
        //                  (the live path triple-buffers, so live ≈ max(CPU, GPU)).
        // The live frame rate is bounded by max(CPU, GPU), printed as the estimate.
        if gpu {
            guard let device = MTLCreateSystemDefaultDevice() else {
                fatalError("Ollin requires a Metal-capable GPU.")
            }
            // Built for the sketch's own `colorOutput`, so the number measures
            // what this sketch actually renders rather than the standard path's
            // cost with the sketch's name on it.
            guard let renderer = try? MetalRenderer(device: device,
                                                    pixelFormat: sketch.colorOutput.drawablePixelFormat,
                                                    sampleCount: ollinPreferredSampleCount(device),
                                                    encoding: sketch.colorOutput.presentEncoding) else {
                fatalError("Ollin: failed to initialize the Metal renderer.")
            }
            // The tier the numbers describe, so a `--render-quality` on the command line
            // reaches the benchmark as well: a tier that trades quality for frame rate is
            // measurable here rather than only settable elsewhere.
            renderer.automaticQuality = quality
            let w = size.width, h = size.height
            let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
            // Warm up: render several real frames so first-time buffer growth is paid and
            // any stateful layer (feedback, a sim field) settles into its steady-state cost.
            for k in 0..<8 {
                sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
                sketch.performDraw()
                _ = renderer.image(of: sketch.drawer, viewport: viewport, width: w, height: h)
            }

            // CPU draw cost and the end-to-end (serial CPU + GPU + readback) cost, one loop.
            let start = CACurrentMediaTime()
            var cpuTotal = 0.0
            for k in 1...n {
                sketch.advance(time: Double(n + k) / fps, deltaTime: 1 / fps, frameRate: fps)
                let drawStart = CACurrentMediaTime()
                sketch.performDraw()
                cpuTotal += CACurrentMediaTime() - drawStart
                _ = renderer.image(of: sketch.drawer, viewport: viewport, width: w, height: h)
            }
            let endToEnd = (CACurrentMediaTime() - start) / Double(n) * 1000
            let cpuMs = cpuTotal / Double(n) * 1000
            // Pure per-frame GPU cost on the last drawn frame (vsync- and readback-free).
            let gpuMs = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                          width: w, height: h, iterations: max(8, n / 4))
            let liveMs = max(cpuMs, gpuMs)
            print(String(format: "Ollin bench: %d frames @ %d×%d · CPU %.2f ms · GPU %.2f ms · end-to-end %.2f ms",
                         n, w, h, cpuMs, gpuMs, endToEnd))
            print(String(format: "  → live ~%.0f fps (bound by %@) · end-to-end ~%.0f fps",
                         liveMs > 0 ? 1000 / liveMs : 0, cpuMs >= gpuMs ? "CPU" : "GPU",
                         endToEnd > 0 ? 1000 / endToEnd : 0))
            return
        }

        let start = CACurrentMediaTime()
        var vertexTotal = 0
        var instanceTotal = 0
        for k in 1...n {
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            vertexTotal += sketch.drawer.vertices.count
            instanceTotal += sketch.drawer.sdfInstances.count
        }
        let elapsed = CACurrentMediaTime() - start
        let msPerFrame = elapsed / Double(n) * 1000
        let ceiling = msPerFrame > 0 ? 1000 / msPerFrame : 0
        print(String(format: "Ollin bench: %d frames · %.0f verts + %.0f sdf/frame · %.3f ms/frame (CPU) · ~%.0f fps CPU ceiling",
                     n, Double(vertexTotal) / Double(n), Double(instanceTotal) / Double(n), msPerFrame, ceiling))
    }

}

#if os(macOS)

public extension Sketch {
    /// Entry point that lets a single sketch file be `@main` with no
    /// boilerplate:
    ///
    /// ```swift
    /// @main
    /// final class HelloCircle: Sketch {
    ///     override func draw() { /* ... */ }
    /// }
    /// ```
    ///
    /// `@main` invokes this inherited `main()` with `Self` bound to the
    /// concrete subclass, so `Self()` builds *that* sketch (which is why
    /// `Sketch.init()` is `required`) and `OllinApp.run` boots it. Each
    /// `Examples/` target uses this.
    @MainActor
    static func main() {
        // `swift run Example-X --export <path> [--frame N]` writes a PNG and
        // exits (no window); otherwise the sketch runs in a window as usual.
        if OllinApp.handleCommandLine(makeSketch: { Self() }) { return }
        OllinApp.run(Self())
    }
}

#endif

public extension OllinApp {
    /// Handle the shared headless command-line surface (the export flags
    /// `--export`, `--export-sequence`, `--export-video`, `--export-gif`,
    /// `--export-loop`, `--export-spatial`, `--export-svg`, `--export-pdf`,
    /// `--export-gcode`, `--export-web`,
    /// `--export-usdz`, `--export-grid`, `--export-sweep`,
    /// `--export-separations` with their options, `--seed` on any of them,
    /// `--param name=value` to set a declared parameter on any of them (and on the
    /// windowed path, which reaches here first),
    /// `--replay` to drive any of them from a recorded take, plus `--bench`)
    /// against a sketch supplied on demand.
    ///
    /// Returns `true` when a headless flag was recognized (the work ran, or a
    /// usage message was printed), meaning the caller should exit rather than
    /// open a window; `false` when the arguments ask for no headless work.
    /// `makeSketch` is called only when a flag matches, so a host may pass an
    /// expensive factory at no cost to the windowed path: OllinLive hands in a
    /// closure that compiles a loose sketch file, which is how any watched
    /// sketch gains the same export surface as a standalone `@main` sketch.
    /// `Sketch.main()` routes every `@main` sketch through here.
    @MainActor
    @discardableResult
    static func handleCommandLine(_ args: [String] = CommandLine.arguments,
                                  makeSketch: () -> Sketch) -> Bool {
        // `--capture-source` beside any export flag ties the files to the source
        // that drew them: the commit is recorded in the recipe and added to
        // every written name, and an uncommitted tree is written into the
        // repository first, so the exact code stays recoverable. Resolved here,
        // before the export branches read their paths.
        var args = args
        if args.contains("--capture-source"),
           args.contains(where: { $0.hasPrefix("--export") }) {
            let source = CaptureSource.resolve(note: ProcessInfo.processInfo.processName)
            CaptureSource.current = source
            if let source {
                args = CaptureSource.stamped(args, with: source.id)
                if source.isCapture {
                    print("Ollin: source captured as \(source.id), uncommitted work included."
                          + " Read it with: git show \(source.id)")
                } else {
                    print("Ollin: source is commit \(source.id).")
                }
            } else {
                FileHandle.standardError.write(Data(
                    "Ollin: --capture-source needs a git repository; the files keep their given names.\n".utf8))
            }
        }
        // `--param <name>=<value>` sets a declared parameter for this run, repeatable.
        // Read here rather than inside an export branch, so the windowed path
        // picks it up too (`handleCommandLine` runs before any window opens).
        readParamOverrides(args)
        // `--cues <file>` names a saved cue sheet and `--cue <name>` the look to
        // start at, applied after `setup()` the way `--param` is.
        readCueFlags(args)
        // `--render-quality <performance|default|detail>` sets the render-quality fallback for
        // the export paths, applied to any feature the sketch left at `.default` (an explicit
        // sketch dial still wins). Defaults to `.detail`: exported art is full quality unless
        // asked otherwise. (Distinct from `--quality`, the video *encoding* quality.)
        let renderQuality: RenderQuality = {
            guard let i = args.firstIndex(of: "--render-quality"), i + 1 < args.count,
                  let q = RenderQuality(name: args[i + 1]) else { return .detail }
            return q
        }()
        // `--render-scale N` draws each exported frame N times across the canvas and
        // averages it back down (see `exportRenderScale`). Pre-parsed like the
        // quality, so it applies to whichever export flag follows.
        if let i = args.firstIndex(of: "--render-scale"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            exportRenderScale = max(1, n)
        }
        // `--settle N` draws each exported frame N times with the clock held and
        // writes the last (see `exportSettle`). Pre-parsed like the render scale,
        // so it applies to whichever export flag follows.
        if let i = args.firstIndex(of: "--settle") {
            guard i + 1 < args.count, let n = Int(args[i + 1]), n >= 1 else {
                FileHandle.standardError.write(Data(
                    "usage: --settle N, N the number of draws per written frame (1 draws each frame once)\n".utf8))
                exit(1)
            }
            // A take carries one frame of input per drawn frame, so drawing a
            // frame several times would read through it several times too fast,
            // and a recording would write the held draws down as frames.
            if args.contains("--replay") || args.contains("--record-take") {
                FileHandle.standardError.write(Data(
                    "--settle cannot replay or record a take: a take carries one frame of input per drawn frame, and a held clock draws each frame several times\n".utf8))
                exit(1)
            }
            // The interpolator builds a frame from the motion between two drawn
            // ones, and a held clock leaves none between the settle draws.
            if args.contains("--made-frames") {
                FileHandle.standardError.write(Data(
                    "--settle cannot use --made-frames: a made frame is built from the motion between two drawn frames, and a held clock has none\n".utf8))
                exit(1)
            }
            exportSettle = n
        }
        // `--slow-motion N` writes a file that plays N times slower than the
        // sketch ran: the clock steps N times finer, the file keeps its `--fps`,
        // and `--seconds` still counts seconds of the sketch's own time (see
        // `SlowMotion`). Pre-parsed like the render scale, so it applies to
        // whichever export flag follows.
        let slowMotion: SlowMotion? = {
            let made = args.contains("--made-frames")
            guard let i = args.firstIndex(of: "--slow-motion") else {
                // `--made-frames` on its own is the half-speed it can do.
                return made ? .made(2) : nil
            }
            guard i + 1 < args.count, let factor = Double(args[i + 1]), factor.isFinite, factor > 1 else {
                FileHandle.standardError.write(Data(
                    "usage: --slow-motion N [--made-frames], N a number above 1 (2 is half speed, 4 is quarter speed)\n".utf8))
                exit(1)
            }
            // A take holds one recorded frame of input per drawn frame, so a
            // finer clock would run through it several times too fast. Say so
            // rather than writing a video whose gestures are wrong.
            if args.contains("--replay"), !made {
                FileHandle.standardError.write(Data(
                    "--slow-motion cannot replay a take: a take carries one frame of input per drawn frame, and a finer clock has nothing to read between them\n".utf8))
                exit(1)
            }
            // The platform makes one frame per gap and offers no way to ask for
            // a moment other than the middle, so half speed is what it can do.
            if made, factor != 2 {
                FileHandle.standardError.write(Data(
                    "--made-frames fills one frame per gap, so it does half speed: pass --slow-motion 2, or drop --made-frames and every frame is drawn\n".utf8))
                exit(1)
            }
            // A still has nothing to slow down, and the vector and spatial
            // exports take their own path, so say so rather than doing nothing.
            let takesIt = ["--export-sequence", "--export-video", "--export-gif", "--export-loop"]
            if !takesIt.contains(where: args.contains) {
                FileHandle.standardError.write(Data(
                    "note: --slow-motion applies to \(takesIt.joined(separator: ", ")); nothing here reads it\n".utf8))
            }
            return made ? .made(factor) : .drawn(factor)
        }()
        // `--path-traced [N]` switches the still/sequence/video exports to the
        // offline path tracer (see `PathTracing`), N samples per pixel; bare, the
        // count comes from the render-quality tier. Pre-parsed like the quality so
        // it applies to whichever export flag follows.
        if let i = args.firstIndex(of: "--path-traced") {
            let n = i + 1 < args.count ? Int(args[i + 1]) : nil
            // `--pt-depth N` caps the path length (the default 8 suits almost
            // everything; shorter renders faster, longer only helps mirror halls).
            let depth: Int? = args.firstIndex(of: "--pt-depth").flatMap { j in
                j + 1 < args.count ? Int(args[j + 1]) : nil
            }
            // `--denoise` filters the grain out of the finished render. It takes
            // its strength from the trace's own measured variance, so it smooths a
            // thin render hard and a nearly converged one only a little. Off unless
            // asked for: the plain flag renders the estimate the tracer arrived at.
            pathTracedExport = PathTracing(
                samplesPerPixel: n ?? PathTracing.tierSamples(for: renderQuality),
                maxDepth: depth ?? 8,
                denoise: args.contains("--denoise"))
        }
        // `--seed N` reseeds the sketch before its `setup()` on every export
        // path, so a variation found in the inspector or on a contact sheet
        // re-renders exactly (a sketch that pins its own seed in `setup()`
        // still wins, as anywhere). For `--export-grid` it is the first seed
        // of the sheet.
        let seedOverride: Int? = {
            guard let i = args.firstIndex(of: "--seed"), i + 1 < args.count else { return nil }
            return Int(args[i + 1])
        }()
        // `--replay <file>` beside any export flag re-renders a recorded take:
        // the fresh sketch gets the recording's seed, starting parameters, clock,
        // and inputs, so the export is the recorded run frame for frame (see
        // `Take`). `--seed N` beside it re-seeds on purpose, playing the same
        // gestures onto a different variation. The video-shaped exports
        // default their length to the take's when none is given.
        let replayTake: Take? = {
            guard let i = args.firstIndex(of: "--replay"), i + 1 < args.count else { return nil }
            do {
                return try Take.load(from: URL(fileURLWithPath: args[i + 1]))
            } catch {
                FileHandle.standardError.write(Data("Ollin: could not read the take: \(error)\n".utf8))
                exit(1)
            }
        }()
        func make() -> Sketch {
            let sketch = makeSketch()
            if let replayTake { replayTake.install(on: sketch) }
            if let seedOverride { sketch.seed(seedOverride) }
            // `--automation <file>` drives the declared parameters from written-down
            // curves; the exports read the clock at a fixed step, so the render
            // is the automation exactly.
            installAutomation(args, on: sketch)
            return sketch
        }
        // `--export-sequence <dir> (--frames N | --seconds S) [--fps F] [--start N]`
        // renders a deterministic numbered PNG sequence and exits.
        if let i = args.firstIndex(of: "--export-sequence"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let dir = args[i + 1]
            let fps = value("--fps").flatMap(Double.init) ?? 60
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                // `--seconds` counts the sketch's own time under slow motion too,
                // so covering it takes the factor's worth of extra frames.
                frames = Int((seconds * fps * (slowMotion?.factor ?? 1)).rounded())
            }
            // Replaying with no length given renders the whole take.
            if frames <= 0, let replayTake { frames = replayTake.frameCount }
            let start = value("--start").flatMap(Int.init) ?? 1
            let skip = value("--skip").flatMap(Double.init) ?? 0
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-sequence <dir> (--frames N | --seconds S) [--fps F] [--skip S] [--start N] [--slow-motion N] [--exr]\n".utf8))
                return true
            }
            // `--exr` writes each frame in linear light instead of as a PNG (see
            // `--export-exr`). A made frame is built by the interpolator after the
            // present pass, so there is no linear canvas behind it to write.
            let writesEXR = args.contains("--exr")
            if writesEXR, slowMotion?.source == .made {
                FileHandle.standardError.write(Data(
                    "--exr cannot use --made-frames: a made frame is built from two presented frames, and a linear frame is what comes before the present\n".utf8))
                exit(1)
            }
            OllinApp.exportSequence(make(), to: dir, frames: frames, fps: fps,
                                    startFrame: start, skipSeconds: skip, quality: renderQuality,
                                    slowMotion: slowMotion, writesEXR: writesEXR)
            return true
        }
        // `--export-loop <path> [--fps F] [--skip S] [--gif-width PX] [--codec C]
        // [--bitrate MBPS] [--quality 0..1]` renders exactly one period of a
        // sketch that declares `loopDuration`, as a seamlessly looping GIF or
        // video (picked by the file extension), and exits.
        if let i = args.firstIndex(of: "--export-loop"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let path = args[i + 1]
            let isGIF = path.lowercased().hasSuffix(".gif")
            let fps = value("--fps").flatMap(Double.init) ?? (isGIF ? 25 : 60)
            let skip = value("--skip").flatMap(Double.init) ?? 0
            let sketch = make()
            guard let duration = sketch.loopDuration, duration > 0 else {
                FileHandle.standardError.write(Data("""
                    --export-loop renders one period of a sketch that declares its loop:
                        override var loopDuration: Double? { 6 }   // seconds per lap
                    usage: --export-loop <path.gif|.mp4|.mov> [--fps F] [--skip S] [--gif-width PX] [--codec C] [--bitrate MBPS] [--quality 0..1]

                    """.utf8))
                return true
            }
            // GIF stores whole-centisecond frame delays, so exportGIF quantizes
            // the rate; compute the lap against the rate that will actually
            // play, or the frame count drifts off one period.
            let loopFPS = isGIF ? 100 / Double(max(2, Int((100 / fps).rounded()))) : fps
            // One lap either way: slow motion covers the same period with the
            // factor's worth of extra frames, so the loop still closes.
            let exact = duration * loopFPS * (slowMotion?.factor ?? 1)
            let frames = max(1, Int(exact.rounded()))
            if abs(exact - exact.rounded()) > 1e-6 {
                FileHandle.standardError.write(Data(
                    "note: a \(duration)s loop at \(loopFPS) fps is not a whole number of frames; the loop won't close exactly (pick an fps that divides the loop).\n".utf8))
            }
            if isGIF {
                let width = value("--gif-width").flatMap(Int.init)
                OllinApp.exportGIF(sketch, to: path, frames: frames, fps: loopFPS,
                                   width: width, skipSeconds: skip, renderQuality: renderQuality,
                                   slowMotion: slowMotion)
            } else {
                var codec = VideoCodec.h264
                if let name = value("--codec") {
                    guard let parsed = VideoCodec(flag: name) else {
                        FileHandle.standardError.write(Data(
                            "unknown codec '\(name)': expected one of \(VideoCodec.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                        return true
                    }
                    codec = parsed
                }
                let bitrate = value("--bitrate").flatMap(Double.init).map { Int($0 * 1_000_000) }
                let quality = value("--quality").flatMap(Double.init)
                OllinApp.exportVideo(sketch, to: path, frames: frames, fps: fps,
                                     codec: codec, bitsPerSecond: bitrate, encodeQuality: quality,
                                     renderQuality: renderQuality, skipSeconds: skip,
                                     slowMotion: slowMotion)
            }
            return true
        }
        // `--export-video <path> (--frames N | --seconds S) [--fps F] [--skip S]
        // [--codec h264|hevc|hevcWithAlpha|proRes422|proRes4444] [--bitrate MBPS] [--quality 0..1]`
        // encodes a video (.mp4/.mov) and exits.
        if let i = args.firstIndex(of: "--export-video"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let fps = value("--fps").flatMap(Double.init) ?? 60
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                // `--seconds` counts the sketch's own time under slow motion too.
                frames = Int((seconds * fps * (slowMotion?.factor ?? 1)).rounded())
            }
            // Replaying with no length given renders the whole take.
            if frames <= 0, let replayTake { frames = replayTake.frameCount }
            let skip = value("--skip").flatMap(Double.init) ?? 0
            var codec = VideoCodec.h264
            if let name = value("--codec") {
                guard let parsed = VideoCodec(flag: name) else {
                    FileHandle.standardError.write(Data(
                        "unknown codec '\(name)': expected one of \(VideoCodec.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                    return true
                }
                codec = parsed
            }
            let bitrate = value("--bitrate").flatMap(Double.init).map { Int($0 * 1_000_000) }
            let quality = value("--quality").flatMap(Double.init)
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-video <path> (--frames N | --seconds S) [--fps F] [--skip S] [--codec C] [--bitrate MBPS] [--quality 0..1] [--slow-motion N]\n".utf8))
                return true
            }
            OllinApp.exportVideo(make(), to: args[i + 1], frames: frames, fps: fps,
                                 codec: codec, bitsPerSecond: bitrate, encodeQuality: quality,
                                 renderQuality: renderQuality, skipSeconds: skip,
                                 slowMotion: slowMotion)
            return true
        }
        // `--export-web <path> [--frames N | --seconds S] [--fps F] [--skip S] [--inline]
        // [--no-controls] [--max-page-size MB]` records what the sketch draws over
        // a duration and writes a page that plays it back in a browser, then
        // exits. With no length given, a sketch that declares `loopDuration`
        // records one lap, which the page wraps without a seam. `--inline`
        // writes the fragment (the canvas plus one script block) for a page of
        // your own instead of a whole file. A page past 25 MB is refused with
        // what made it heavy; `--max-page-size` raises the limit, and `0` lifts it.
        if let i = args.firstIndex(of: "--export-web"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let fps = value("--fps").flatMap(Double.init) ?? 30
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                frames = Int((seconds * fps).rounded())
            }
            if frames <= 0, let replayTake { frames = replayTake.frameCount }
            let skip = value("--skip").flatMap(Double.init) ?? 0
            let form: WebPageForm = args.contains("--inline") ? .inline : .standalone
            // `--no-controls` leaves the parameters at their recorded values:
            // no probe, no panel, no handle onto them.
            let controls = !args.contains("--no-controls")
            var maxBytes: Int? = OllinApp.maxWebPageBytes
            if let megabytes = value("--max-page-size").flatMap(Double.init) {
                maxBytes = megabytes > 0 ? Int(megabytes * 1024 * 1024) : nil
            }
            let sketch = make()
            if frames <= 0, let lap = sketch.loopDuration, lap > 0 {
                frames = Int((lap * fps).rounded())
            }
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-web <path> (--frames N | --seconds S, or a sketch that declares loopDuration) [--fps F] [--skip S] [--inline] [--no-controls] [--max-page-size MB]\n".utf8))
                return true
            }
            // The probe records fresh sketches made the way this one was (the
            // seed, a replayed take, and the automation applied), so a control
            // is measured against the same run. The export runs to completion
            // here, so the factory never outlives the call.
            withoutActuallyEscaping(makeSketch) { factory in
                OllinApp.exportWeb(sketch, to: args[i + 1], frames: frames, fps: fps, skipSeconds: skip, form: form,
                                   controls: controls, maxBytes: maxBytes, remake: {
                    let fresh = factory()
                    if let replayTake { replayTake.install(on: fresh) }
                    if let seedOverride { fresh.seed(seedOverride) }
                    installAutomation(args, on: fresh)
                    return fresh
                })
            }
            return true
        }
        // `--export-spatial <path.mov> (--frames N | --seconds S) [--fps F] [--skip S]
        // [--interocular X] [--convergence D] [--meters-per-unit U] [--bitrate MBPS]
        // [--quality 0..1]` writes stereo spatial video and exits.
        if let i = args.firstIndex(of: "--export-spatial"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let fps = value("--fps").flatMap(Double.init) ?? 30
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                frames = Int((seconds * fps).rounded())
            }
            // Replaying with no length given renders the whole take.
            if frames <= 0, let replayTake { frames = replayTake.frameCount }
            let skip = value("--skip").flatMap(Double.init) ?? 0
            let bitrate = value("--bitrate").flatMap(Double.init).map { Int($0 * 1_000_000) }
            let quality = value("--quality").flatMap(Double.init)
            let metersPerUnit = value("--meters-per-unit").flatMap(Double.init) ?? 1
            // Either number given on the command line overrides what the sketch
            // declares; neither given leaves the sketch's own declaration alone.
            let interocular = value("--interocular").flatMap(Double.init)
            let convergence = value("--convergence").flatMap(Double.init)
            let stereo = (interocular == nil && convergence == nil)
                ? nil : StereoGeometry(interocular: interocular, convergence: convergence)
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-spatial <path.mov> (--frames N | --seconds S) [--fps F] [--skip S] [--interocular X] [--convergence D] [--meters-per-unit U] [--bitrate MBPS] [--quality 0..1]\n".utf8))
                return true
            }
            OllinApp.exportSpatialVideo(make(), to: args[i + 1], frames: frames, fps: fps,
                                        stereo: stereo, metersPerUnit: metersPerUnit,
                                        bitsPerSecond: bitrate, quality: quality,
                                        renderQuality: renderQuality, skipSeconds: skip)
            return true
        }
        // `--export-gif <path> (--frames N | --seconds S) [--fps F] [--skip S]
        // [--gif-width PX]` writes a looping animated GIF and exits.
        if let i = args.firstIndex(of: "--export-gif"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let fps = value("--fps").flatMap(Double.init) ?? 25
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                // `--seconds` counts the sketch's own time under slow motion too.
                frames = Int((seconds * fps * (slowMotion?.factor ?? 1)).rounded())
            }
            // Replaying with no length given renders the whole take.
            if frames <= 0, let replayTake { frames = replayTake.frameCount }
            let skip = value("--skip").flatMap(Double.init) ?? 0
            let width = value("--gif-width").flatMap(Int.init)
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-gif <path> (--frames N | --seconds S) [--fps F] [--skip S] [--gif-width PX] [--slow-motion N]\n".utf8))
                return true
            }
            OllinApp.exportGIF(make(), to: args[i + 1], frames: frames, fps: fps,
                               width: width, skipSeconds: skip, renderQuality: renderQuality,
                               slowMotion: slowMotion)
            return true
        }
        // `--export-grid <path.png> [--seeds N] [--columns C] [--tile PX]
        // [--frame N] [--fps F]` renders a contact sheet of variations, one
        // labeled tile per seed, and exits. Seeds run consecutively from
        // `--seed` (default 1); re-render a keeper at full resolution with
        // `--export <path> --seed N`.
        if let i = args.firstIndex(of: "--export-grid"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let count = value("--seeds").flatMap(Int.init) ?? 16
            guard count > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-grid <path.png> [--seeds N] [--columns C] [--tile PX] [--frame N] [--fps F] [--seed FIRST]\n".utf8))
                return true
            }
            let start = seedOverride ?? 1
            let seeds = Array(start ..< start + count)
            let columns = value("--columns").flatMap(Int.init)
            let tile = value("--tile").flatMap(Int.init) ?? 320
            let frame = value("--frame").flatMap(Int.init) ?? 0
            let fps = value("--fps").flatMap(Double.init) ?? 60
            OllinApp.exportContactSheet(makeSketch, to: args[i + 1], seeds: seeds,
                                        frame: frame, fps: fps, columns: columns,
                                        tileWidth: tile, quality: renderQuality)
            return true
        }
        // `--export-sweep <path.png> --sweep-param <name> (--values "a,b,c" | --from A
        // --to B [--steps N]) [--columns C] [--tile PX] [--frame N] [--fps F]`
        // renders a contact sheet sweeping one `@Param` across a range, one
        // labeled tile per value, every tile pinned to the same seed (`--seed`,
        // or one rolled and recorded in the sheet's recipe), and exits. The
        // swept parameter is named with `--sweep-param` because `--param` sets a
        // value on every tile alike (`--param name=value`), which is how the
        // rest of the sheet is held still while one parameter moves.
        if let i = args.firstIndex(of: "--export-sweep"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let usage = "usage: --export-sweep <path.png> --sweep-param <name> (--values \"a,b,c\" | --from A --to B [--steps N]) [--columns C] [--tile PX] [--frame N] [--fps F] [--seed N]\n"
            guard let name = value("--sweep-param") else {
                FileHandle.standardError.write(Data(usage.utf8))
                return true
            }
            // Setting the swept parameter as well would flatten the sheet: the value
            // would land after every tile's own, on every tile alike.
            if paramOverrides.contains(where: { $0.name == name }) {
                FileHandle.standardError.write(Data(
                    "Ollin: --param \(name)=… sets the parameter --sweep-param \(name) sweeps; drop one of them\n".utf8))
                return true
            }
            var values: [Double] = []
            if let list = value("--values") {
                values = list.split(separator: ",").compactMap {
                    Double($0.trimmingCharacters(in: .whitespaces))
                }
            } else if let from = value("--from").flatMap(Double.init),
                      let to = value("--to").flatMap(Double.init) {
                let steps = max(value("--steps").flatMap(Int.init) ?? 9, 1)
                values = steps == 1 ? [from] : (0 ..< steps).map {
                    from + (to - from) * Double($0) / Double(steps - 1)
                }
            }
            guard !values.isEmpty else {
                FileHandle.standardError.write(Data(usage.utf8))
                return true
            }
            let columns = value("--columns").flatMap(Int.init)
            let tile = value("--tile").flatMap(Int.init) ?? 320
            let frame = value("--frame").flatMap(Int.init) ?? 0
            let fps = value("--fps").flatMap(Double.init) ?? 60
            OllinApp.exportContactSheet(makeSketch, to: args[i + 1],
                                        sweeping: name, values: values,
                                        seed: seedOverride,
                                        frame: frame, fps: fps, columns: columns,
                                        tileWidth: tile, quality: renderQuality)
            return true
        }
        // `--export-separations <path.png> [--frame N] [--inks "black, fluorescent pink"]
        // [--paper HEX] [--screen dither|halftone] [--pitch PX] [--no-marks]` splits
        // one frame into per-ink grayscale printing masters plus an overprint
        // preview and exits. Inks come from the sketch's declared `printInks` unless
        // `--inks` names catalog inks; `--screen` reduces the masters to 1-bit.
        if let i = args.firstIndex(of: "--export-separations"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let frame = value("--frame").flatMap(Int.init) ?? 0
            var inks: [Ink]?
            if let list = value("--inks") {
                var parsed: [Ink] = []
                for entry in list.split(separator: ",") {
                    let name = entry.trimmingCharacters(in: .whitespaces)
                    guard let ink = Ink.named(name) else {
                        FileHandle.standardError.write(Data(
                            "unknown ink '\(name)': names match the built-in catalog (Ink.catalog), e.g. \"black\", \"fluorescent pink\", \"medium blue\"\n".utf8))
                        return true
                    }
                    parsed.append(ink)
                }
                inks = parsed
            }
            var paper = Color.white
            if let hex = value("--paper") {
                guard let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else {
                    FileHandle.standardError.write(Data("--paper expects a hex color, e.g. FFF7E8\n".utf8))
                    return true
                }
                paper = Color(hex: value)
            }
            let pitch = value("--pitch").flatMap(Double.init) ?? 8
            let screen: (PrintSeparation) -> PrintSeparation
            switch value("--screen") ?? "none" {
            case "none": screen = { $0 }
            case "dither": screen = { $0.dithered() }
            case "halftone": screen = { $0.halftoned(pitch: pitch) }
            default:
                FileHandle.standardError.write(Data(
                    "usage: --export-separations <path.png> [--frame N] [--inks \"a, b\"] [--paper HEX] [--screen dither|halftone] [--pitch PX] [--no-marks]\n".utf8))
                return true
            }
            OllinApp.exportSeparations(make(), to: args[i + 1], inks: inks, paper: paper,
                                       frame: frame, drawsRegistrationMarks: !args.contains("--no-marks"),
                                       quality: renderQuality, screen: screen)
            return true
        }
        // `--export-plates <path.png> [--frame N] [--profile PATH-or-NAME]
        // [--intent perceptual|relative|saturation|absolute] [--paper]
        // [--screen dither|halftone] [--pitch PX] [--no-marks]` splits one frame
        // into process-color printing plates through an ICC profile, plus the
        // proof of the finished print, and exits. The profile comes from the
        // sketch's declared `printProfile` unless `--profile` names a file or an
        // installed profile.
        if let i = args.firstIndex(of: "--export-plates"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let frame = value("--frame").flatMap(Int.init) ?? 0
            var profile: ICCProfile?
            if let named = value("--profile") {
                let expanded = (named as NSString).expandingTildeInPath
                profile = ICCProfile(contentsOf: URL(fileURLWithPath: expanded))
                    ?? ICCProfile.installed(named: named)
                guard profile != nil else {
                    let installed = ICCProfile.installed().filter { $0.space == .cmyk }
                    FileHandle.standardError.write(Data("""
                        unknown profile '\(named)': pass a path to a .icc file, or the name of one \
                        installed on this machine. The printer profiles installed here are: \
                        \(installed.map(\.name).joined(separator: ", "))

                        """.utf8))
                    return true
                }
            }
            var intent = RenderingIntent.relative
            if let named = value("--intent") {
                guard let parsed = RenderingIntent(rawValue: named) else {
                    FileHandle.standardError.write(Data(
                        "unknown intent '\(named)': one of \(RenderingIntent.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                    return true
                }
                intent = parsed
            }
            let pitch = value("--pitch").flatMap(Double.init) ?? 8
            let screen: (ProcessSeparation) -> ProcessSeparation
            switch value("--screen") ?? "none" {
            case "none": screen = { $0 }
            case "dither": screen = { $0.dithered() }
            case "halftone": screen = { $0.halftoned(pitch: pitch) }
            default:
                FileHandle.standardError.write(Data(
                    "usage: --export-plates <path.png> [--frame N] [--profile PATH] [--intent relative|perceptual|saturation|absolute] [--paper] [--screen dither|halftone] [--pitch PX] [--no-marks]\n".utf8))
                return true
            }
            OllinApp.exportPlates(make(), to: args[i + 1], profile: profile, intent: intent,
                                  simulatesPaper: args.contains("--paper"), frame: frame,
                                  drawsRegistrationMarks: !args.contains("--no-marks"),
                                  quality: renderQuality, screen: screen)
            return true
        }
        // `swift run Example-X --export-exr <path.exr> [--frame N]` writes one
        // frame in linear light, before the tone map and the 8-bit quantization
        // every other still export ends at, with the scene's depth beside the
        // color when the frame was drawn through a 3D camera.
        if let i = args.firstIndex(of: "--export-exr"), i + 1 < args.count {
            var frame = 0
            if let f = args.firstIndex(of: "--frame"), f + 1 < args.count {
                frame = Int(args[f + 1]) ?? 0
            }
            OllinApp.exportEXR(make(), to: args[i + 1], frame: frame, quality: renderQuality)
            return true
        }
        if let i = args.firstIndex(of: "--export"), i + 1 < args.count {
            var frame = 0
            if let f = args.firstIndex(of: "--frame"), f + 1 < args.count {
                frame = Int(args[f + 1]) ?? 0
            }
            OllinApp.export(make(), to: args[i + 1], frame: frame, quality: renderQuality)
            return true
        }
        // `swift run Example-X --export-svg <path> [--frame N]` writes a vector SVG
        // of one frame and exits (no window, no GPU); `--export-pdf <path>` writes
        // the same recorded frame as a single-page PDF; `--export-gcode <path>`
        // writes it as a G-code program (`--gcode-machine plotter|laser|mill`,
        // `--gcode-width MM`, `--gcode-margin MM`; any two may be passed at
        // once). Add `--hatch` (or `--cross-hatch`) to plot solid fills as pen
        // line work: `--hatch-spacing N` and `--hatch-angle DEG` tune it.
        let svgFlag = args.firstIndex(of: "--export-svg")
        let pdfFlag = args.firstIndex(of: "--export-pdf")
        let gcodeFlag = args.firstIndex(of: "--export-gcode")
        let embroideryFlag = args.firstIndex(of: "--export-embroidery")
        let dxfFlag = args.firstIndex(of: "--export-dxf")
        if svgFlag != nil || pdfFlag != nil || gcodeFlag != nil || embroideryFlag != nil || dxfFlag != nil {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            var frame = 0
            if let f = value("--frame").flatMap(Int.init) { frame = f }
            var hatching: Hatching?
            if args.contains("--hatch") || args.contains("--cross-hatch") {
                var h = Hatching()
                if let s = value("--hatch-spacing").flatMap(Double.init) { h.spacing = s }
                if let a = value("--hatch-angle").flatMap(Double.init) { h.angle = a * .pi / 180 }
                if args.contains("--cross-hatch") { h.crossHatches = true }
                hatching = h
            }
            var handled = false
            if let i = svgFlag, i + 1 < args.count {
                OllinApp.exportSVG(make(), to: args[i + 1], frame: frame, hatching: hatching)
                handled = true
            }
            if let i = pdfFlag, i + 1 < args.count {
                OllinApp.exportPDF(make(), to: args[i + 1], frame: frame, hatching: hatching)
                handled = true
            }
            if let i = gcodeFlag, i + 1 < args.count {
                let machine: GCode.Machine
                switch value("--gcode-machine") ?? "plotter" {
                case "laser": machine = .laser()
                case "mill": machine = .mill()
                default: machine = .plotter()
                }
                let width = value("--gcode-width").flatMap(Double.init) ?? 150
                let margin = value("--gcode-margin").flatMap(Double.init) ?? 0
                let settings = GCode(machine, width: width, margin: margin)
                OllinApp.exportGCode(make(), to: args[i + 1], settings: settings,
                                     frame: frame, hatching: hatching)
                handled = true
            }
            if let i = embroideryFlag, i + 1 < args.count {
                // `--export-embroidery <path.dst>` writes the frame as the stitches an
                // embroidery machine sews (`--embroidery-width MM`, `--embroidery-margin MM`,
                // `--stitch-length MM`, `--fill-spacing MM`, with 0 sewing fills as outlines).
                let width = value("--embroidery-width").flatMap(Double.init) ?? 100
                let margin = value("--embroidery-margin").flatMap(Double.init) ?? 0
                let stitch = value("--stitch-length").flatMap(Double.init) ?? 2.5
                let spacing = value("--fill-spacing").flatMap(Double.init) ?? 0.4
                let settings = Embroidery(width: width, margin: margin, stitchLength: stitch,
                                          fillSpacing: spacing > 0 ? spacing : nil)
                OllinApp.exportEmbroidery(make(), to: args[i + 1], settings: settings, frame: frame)
                handled = true
            }
            if let i = dxfFlag, i + 1 < args.count {
                // `--export-dxf <path.dxf>` writes the frame as a drawing a CAD program
                // or a laser's software opens, a layer per color (`--dxf-width MM`,
                // `--dxf-margin MM`, sharing `--hatch`).
                let width = value("--dxf-width").flatMap(Double.init) ?? 150
                let margin = value("--dxf-margin").flatMap(Double.init) ?? 0
                OllinApp.exportDXF(make(), to: args[i + 1], settings: DXF(width: width, margin: margin),
                                   frame: frame, hatching: hatching)
                handled = true
            }
            if !handled {
                FileHandle.standardError.write(Data(
                    "usage: --export-svg <path.svg> | --export-pdf <path.pdf> | --export-gcode <path.gcode> | --export-dxf <path.dxf> | --export-embroidery <path.dst> [--frame N] [--gcode-machine plotter|laser|mill] [--gcode-width MM] [--gcode-margin MM] [--hatch | --cross-hatch] [--hatch-spacing N] [--hatch-angle DEG]\n".utf8))
            }
            return true
        }
        // `swift run Example-X --export-usdz <path> [--frame N] [--meters-per-unit U]`
        // writes one frame's 3D geometry as a spatial model and exits (no window,
        // no GPU). `.usda` in the path writes the readable text layer instead of
        // the package.
        if let i = args.firstIndex(of: "--export-usdz") {
            guard i + 1 < args.count else {
                FileHandle.standardError.write(Data(
                    "usage: --export-usdz <path.usdz | path.usda> [--frame N] [--meters-per-unit U]\n".utf8))
                return true
            }
            var frame = 0
            if let f = args.firstIndex(of: "--frame"), f + 1 < args.count {
                frame = Int(args[f + 1]) ?? 0
            }
            var metersPerUnit = 1.0
            if let m = args.firstIndex(of: "--meters-per-unit"), m + 1 < args.count {
                metersPerUnit = Double(args[m + 1]) ?? 1
            }
            OllinApp.exportSpatial(make(), to: args[i + 1], frame: frame,
                                   metersPerUnit: metersPerUnit)
            return true
        }
        if let i = args.firstIndex(of: "--bench") {
            var frames = 600
            if i + 1 < args.count, let f = Int(args[i + 1]) { frames = f }
            OllinApp.benchmark(make(), frames: frames, gpu: args.contains("--gpu"),
                               quality: args.contains("--render-quality") ? renderQuality : .default)
            return true
        }
        return false
    }
}

// MARK: - Standalone SwiftUI launcher

#if os(macOS)

/// SwiftUI `App` that runs a single `Sketch` — the `swift run Example-X`
/// launcher behind `Sketch.main()` / `OllinApp.run`. The app *lifecycle* stays
/// SwiftUI (it owns the main menu, so `OllinHUDCommands` plugs in), but the
/// sketch window itself is an AppKit `NSWindow` hosting the SwiftUI
/// `SketchView` through `NSHostingView`, built by the delegate below.
///
/// The AppKit window is deliberate: on macOS 26, windows owned by SwiftUI
/// window scenes that host a Metal layer intermittently flicker between 100%
/// and 98% of their frame size while being dragged — a WindowServer bug (the
/// oscillation shows in `CGWindowListCopyWindowInfo` bounds while the app-side
/// geometry stays constant). AppKit-owned windows with identical content have
/// not shown it. The placeholder `Settings` scene satisfies SwiftUI's scene
/// requirement without opening a window, and the empty `.appSettings` command
/// group removes the dangling "Settings…" menu item it would otherwise add.
@MainActor
struct OllinSketchApp: App {
    @NSApplicationDelegateAdaptor(StandaloneAppDelegate.self) private var delegate

    var body: some SwiftUI.Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {}
                OllinHUDCommands()
                OllinCameraCommands()
            }
    }
}

/// Builds and owns the AppKit sketch window, brings the bundleless `swift run`
/// process to the front, and quits when the window closes so the terminal
/// command returns. A standalone example is a single window run from the
/// terminal, so a stray Cmd+W (Close) should end the run like Cmd+Q — the full
/// `OllinLive` host and examples gallery are actual apps and keep the normal
/// close-doesn't-quit behavior.
private final class StandaloneAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    /// Held for the run: it owns the power assertion and the system observers.
    private var installationHost: InstallationHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        openSketchWindow()
        NSApp.activate(ignoringOtherApps: true)
        // Quit explicitly when the sketch window closes — Cmd+W then ends the
        // run like Cmd+Q. Quit only when no real window is left: the floating
        // "Show Inspector" panel is an `NSPanel` (closing *it* mustn't quit),
        // and opening it spins up and tears down transient helper windows whose
        // close must be ignored too. So react after the close settles and check
        // what's still on screen.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                // A window of a wall is not a window somebody opened: it belongs
                // to the piece in the window that just closed, so it must not
                // keep the run alive after it.
                let realWindowsLeft = NSApp.windows.contains {
                    $0.isVisible && !($0 is NSPanel) && !($0 is OllinDisplayWindow)
                }
                if !realWindowsLeft { NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting is an ordinary end to a run, so the state goes down with it.
        OllinActiveSketch.runner?.saveCheckpointNow()
        OllinActiveSketch.runner?.finishTake()
        installationHost?.release()
    }

    /// Create the sketch window: AppKit shell, SwiftUI content.
    @MainActor
    private func openSketchWindow() {
        guard let sketch = OllinApp.standaloneSketch else { return }
        // A piece that runs unattended opens on the whole screen and keeps its
        // proportions inside it, rather than at the preview size a session at a
        // desk wants. The host takes the window over once it is on screen.
        let installation = Installation.resolved(for: sketch)
        if installation.runsUnattended {
            openInstallationWindow(sketch: sketch, installation: installation)
            return
        }
        let contentSize = OllinApp.windowSize(for: sketch)
        let isResizable: Bool = {
            if case .resizable = sketch.windowMode { return true }
            return false
        }()

        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if isResizable { style.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = sketch.title
        window.isReleasedWhenClosed = false

        // `.resizable` follows the user's drag down to a sane floor (the canvas
        // tracks the view); fixed modes pin the content size exactly, which
        // also clamps any stale autosaved frame restored below.
        if isResizable {
            window.contentMinSize = NSSize(width: 200, height: 200)
        } else {
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
        }

        let root: AnyView = isResizable
            ? AnyView(SketchView(sketch)
                .frame(minWidth: 200, maxWidth: .infinity,
                       minHeight: 200, maxHeight: .infinity))
            : AnyView(SketchView(sketch)
                .frame(width: contentSize.width, height: contentSize.height))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        window.center()
        // Same autosave name the previous SwiftUI window scene wrote, so an
        // existing saved position carries over.
        window.setFrameAutosaveName("ollin-sketch")
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// The window for a piece left running: the screen's size, the canvas
    /// centered inside it at its own proportions on black, and no saved frame
    /// (a position remembered from a session at a desk is the wrong one here).
    @MainActor
    private func openInstallationWindow(sketch: Sketch, installation: Installation) {
        let screen = NSScreen.main
        let contentSize = screen?.frame.size ?? OllinApp.windowSize(for: sketch)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = sketch.title
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 200, height: 200)
        // Built before the view, so the host is in hand when the runner arrives:
        // the runner registers itself globally on its first frame, and a piece
        // whose schedule opens dark never draws one until the schedule says so.
        let host = InstallationHost(installation)

        // This window always fits its picture in the present pass rather than
        // in the layout, even when the sketch declares nothing: the canvas keeps
        // its proportions either way, and Command-K then has corners to drag on
        // any piece. What the sketch declared comes first; the corners this
        // display was last lined up with win over it, because they belong to the
        // room rather than to the work.
        //
        // The wall works that out for every display the piece goes on, this one
        // among them. A piece on one display is a wall of one, which is the same
        // run it has always been.
        let canvas = sketch.canvasSize.cgSize
        let wall = DisplayWall(installation,
                               canvas: Vector2(Double(canvas.width), Double(canvas.height)),
                               rehearsing: WallFlags.rehearsal(CommandLine.arguments))
        let calibrator = wall.primary.calibrator
        // Opening straight into the handles, for the evening the projector is
        // hung: the piece is up on the wall and out of true, and reaching for a
        // keyboard shortcut is the last thing anybody wants to look up.
        if CommandLine.arguments.contains("--calibrate") {
            for each in wall.calibrators { each.open() }
        }

        let root = AnyView(
            ZStack {
                SwiftUI.Color.black
                // No detached stats panel: the "Show Inspector" toggle is
                // remembered between runs, and a panel left on at a desk would
                // otherwise float over the piece on the wall.
                SketchView(sketch, showsInspectorPanel: false) { runner in
                    runner.beginInstallation(installation)
                    wall.open(with: runner, sketch: sketch)
                    host.attach(runner)
                }
                CalibrationOverlay(calibrator: calibrator)
            }
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        // The piece's own window goes where its own part of the wall is, which
        // for one display is the display it opened on.
        if let frame = wall.primaryFrame {
            window.setFrame(installation.fillsScreen ? frame
                                : window.frameRect(forContentRect: frame), display: true)
        } else if let screen {
            window.setFrame(screen.frame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window

        host.take(over: window, wall: wall)
        self.installationHost = host
    }
}

#endif
