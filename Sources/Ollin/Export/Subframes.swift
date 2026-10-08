import CoreGraphics
import Foundation
import Metal
import QuartzCore

/// The moments an export draws for one frame under `--subframes`.
///
/// A camera's shutter stays open for part of each frame, and what moves while
/// it is open smears across the picture. An export can do the same thing the
/// slow way: draw the frame `count` times at moments spread across the open
/// shutter and average the pictures in linear light, the published
/// accumulation-buffer technique (credited in ATTRIBUTION.md). It blurs anything
/// a sketch draws, 2D and shaders included, and it is the reference the canvas
/// motion blur is measured against, at `count` times the render cost.
///
/// The shutter is centered on the frame's own instant, as the canvas blur's
/// streak is, so swapping one for the other moves nothing. Moment `i` sits at
/// the middle of its share of the opening, which spreads the moments evenly and
/// keeps them symmetric about the instant. A moment that would fall before the
/// run began is drawn at time 0: the world holds still before it starts.
struct SubframeShutter: Equatable {
    /// How many moments each frame is drawn at, 2 or more.
    let count: Int
    /// The fraction of a frame interval the shutter stays open, 0.5 being the
    /// half-open shutter film runs at.
    let shutter: Double

    /// The sketch's time for moment `index` of the frame whose instant is
    /// `time`, on a clock of `rate` frames a second.
    func time(ofMoment index: Int, at time: Double, rate: Double) -> Double {
        let offset = (Double(index) + 0.5) / Double(count) - 0.5
        return max(0, time + shutter / rate * offset)
    }

    /// The time between two neighboring moments, which the first draw of a run
    /// takes as its `deltaTime` (it has no draw before it to measure from).
    func spacing(rate: Double) -> Double {
        shutter / rate / Double(count)
    }
}

extension OllinApp {
    /// The moments the next exported frame of `sketch` is drawn at, or nil when
    /// each frame is drawn once (`exportSubframes` 1). The shutter is
    /// `exportShutter` when set, else the one the sketch asked of its canvas
    /// blur on its last draw (`motionBlur(shutter:)`), else 0.5. It is read
    /// before each frame, so a sketch that has not drawn yet takes 0.5 for its
    /// first frame.
    static func subframeShutter(for sketch: Sketch) -> SubframeShutter? {
        guard exportSubframes > 1 else { return nil }
        let drawer = sketch.drawer
        let declared = drawer.motionBlurEnabled ? drawer.motionBlurShutter : nil
        return SubframeShutter(count: exportSubframes,
                               shutter: max(0, exportShutter ?? declared ?? 0.5))
    }

    /// Why `--subframes` cannot draw this sketch, or nil when it can. A picture
    /// the GPU carries from one draw to the next steps once per draw, so the
    /// moments would run it `count` times as fast and the file would not show
    /// what the window does. Read after a draw, since what the frame carries is
    /// only known once it has drawn.
    static func subframeRefusal(_ drawer: Drawer, count: Int) -> String? {
        var carried: String?
        if drawer.accumulates {
            carried = "its piling canvas (noClear())"
        } else {
            for target in drawer.renderTargets {
                switch target.origin {
                case .feedback: carried = "a feedback layer (makeFeedback)"
                case .simField: carried = "a simulation field (makeSimField)"
                case .accumulate: carried = "an Accumulator (makeAccumulator, or the one a LineSpray holds)"
                default: break
                }
                if carried != nil { break }
            }
            if carried == nil, drawer.usesFeedback {
                carried = "the history of its screen-space reflections"
            }
        }
        guard let carried else { return nil }
        return "--subframes cannot draw this sketch: \(carried) steps once per draw, "
            + "so \(count) subframes would run it \(count) times as fast. "
            + "Drop --subframes and each frame is drawn once at its instant"
    }

    /// What `--subframes` cannot share an export with, or nil when it can run:
    /// `--settle` draws one moment several times, the made frames are built from
    /// the motion between two single draws, and a take carries one frame of
    /// input per drawn frame.
    static func subframeConflict(for sketch: Sketch, slowMotion: SlowMotion?) -> String? {
        guard exportSubframes > 1 else { return nil }
        if sketch.takePlayer != nil || sketch.takeRecorder != nil {
            return "--subframes cannot replay or record a take: a take carries one frame of input "
                + "per drawn frame, and the moments draw each frame several times"
        }
        if exportSettle > 1 {
            return "--subframes cannot settle: --settle draws one moment several times and "
                + "--subframes draws several moments once each. Drop one of them"
        }
        if slowMotion?.isActive == true, slowMotion?.source == .made {
            return "--subframes cannot use --made-frames: a made frame is built from the motion "
                + "between two frames drawn once each. Drop --made-frames and every frame is drawn"
        }
        return nil
    }

    /// `renderImage(of:)` under `--subframes`: the frames before the one asked
    /// for are drawn once each at their instant, for the state they leave, and
    /// the frame asked for is drawn at `shutter`'s moments and averaged. A
    /// sketch that stops its loop holds the frame it stopped on, which has no
    /// motion to blur, so that frame renders once as it is.
    static func renderSubframeImage(of sketch: Sketch, frame: Int, fps: Double,
                                    renderer: MetalRenderer, path: String) throws -> CGImage? {
        if let conflict = subframeConflict(for: sketch, slowMotion: nil) {
            throw ExportError(.unsupported, path: path, problem: conflict)
        }
        let size = sketch.canvasSizeForRun()
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.runSetup()
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        let width = size.width, height = size.height
        let target = max(0, frame)
        defer { renderer.subframe = nil }

        // The held frame, drawn once and rendered as it is.
        func held(drawSeconds: Double) -> CGImage? {
            renderer.subframe = nil
            let image = renderer.image(of: sketch.drawer, viewport: viewport, width: width, height: height)
            reportHeadlessFrame(sketch, renderer: renderer, deltaTime: 1 / fps, fps: fps,
                                drawSeconds: drawSeconds)
            return image
        }

        var lastTime: Double?
        for k in 0..<target {
            var drawSeconds = 0.0
            try autoreleasepool {
                sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
                let drawStart = CACurrentMediaTime()
                sketch.performDraw()
                drawSeconds = CACurrentMediaTime() - drawStart
                if let refusal = subframeRefusal(sketch.drawer, count: exportSubframes) {
                    throw ExportError(.unsupported, path: path, problem: refusal)
                }
                // A frame not captured still steps any simulation on the GPU.
                renderer.stepCompute(sketch.drawer)
            }
            lastTime = Double(k) / fps
            if sketch.exportHoldsFrame { return held(drawSeconds: drawSeconds) }
        }

        guard let shutter = subframeShutter(for: sketch) else { return nil }
        lastSubframeShutter = shutter.shutter
        let instant = Double(target) / fps
        var image: CGImage?
        for i in 0..<shutter.count {
            let time = shutter.time(ofMoment: i, at: instant, rate: fps)
            let deltaTime = lastTime.map { time - $0 } ?? shutter.spacing(rate: fps)
            let stop: Bool = try autoreleasepool {
                sketch.advance(time: time, deltaTime: deltaTime, frameRate: fps)
                let drawStart = CACurrentMediaTime()
                sketch.performDraw()
                let drawSeconds = CACurrentMediaTime() - drawStart
                if let refusal = subframeRefusal(sketch.drawer, count: shutter.count) {
                    throw ExportError(.unsupported, path: path, problem: refusal)
                }
                if sketch.exportHoldsFrame {
                    image = held(drawSeconds: drawSeconds)
                    return true
                }
                renderer.subframe = MetalRenderer.Subframe(index: i, count: shutter.count)
                guard let rendered = renderer.renderedFrame(of: sketch.drawer, viewport: viewport,
                                                            width: width, height: height) else {
                    throw ExportError(.unrendered, path: path, frame: 0,
                                      problem: "moment \(i) of frame \(target) did not come back from the GPU")
                }
                reportHeadlessFrame(sketch, renderer: renderer, deltaTime: deltaTime, fps: fps,
                                    drawSeconds: drawSeconds)
                if i == shutter.count - 1 {
                    image = renderer.displayImage(from: rendered.buffer, width: width, height: height,
                                                  transparent: sketch.drawer.hasTransparentBackground)
                }
                return false
            }
            lastTime = time
            if stop { break }
        }
        lastPathTraceReport = renderer.lastPathTraceReport
        return image
    }
}
