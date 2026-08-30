import Foundation

/// How much slower than real time an export plays, and where the frames between
/// the drawn ones come from.
///
/// An export writes the frames a sketch drew, at the rate it drew them, so the
/// video plays at the speed you watched. Slow motion is the one place those two
/// rates come apart. The file still plays at `fps`, and the run is covered by
/// `factor` times as many frames, so the motion takes `factor` times as long.
/// Four seconds of sketch time at factor 4 becomes sixteen seconds of video.
///
/// The two forms differ in where those frames come from, and the difference
/// decides which one a sketch wants.
///
/// ``drawn(_:)`` asks the sketch for every one of them. `time` steps `factor`
/// times finer and `deltaTime` shrinks to match, so each frame in the file is a
/// frame the sketch drew. It is exact, it fits any sketch, and it costs
/// `factor` times the render time. It is the default, and it keeps the promise
/// every other export makes.
///
/// ``made(_:)`` draws the frames it would have drawn anyway and has the GPU
/// make the ones between them out of the pair on either side. It hands over
/// pictures the sketch never drew, which is why it must be asked for by name.
/// It has two conditions the drawn form has none of: the frame needs a 3D scene
/// under a perspective camera, and the platform makes one frame per gap, so the
/// factor is 2. A made frame is cheaper than a drawn one rather than free.
/// Measured on a busy 3D scene at 1080 square: about 11 ms against 20 ms, so
/// half speed took 1.9 s where drawing every frame took 2.4 s. The heavier the
/// frame, the more it saves: at nine times the sampling the same clip took 3.3 s
/// against 5.1 s.
///
/// Motion measured in seconds slows down under either form. Motion measured in
/// frames (`x += 2` once per `draw()`, with no `deltaTime` in it) does not slow
/// down under ``drawn(_:)``, because a finer clock hands it more frames to step
/// through. ``made(_:)`` is the form that slows that sketch down.
public struct SlowMotion: Sendable, Equatable {

    /// Where the frames between the drawn ones come from.
    public enum Source: String, Sendable, Equatable, CaseIterable {
        /// The sketch draws all of them, on a finer clock.
        case drawn
        /// The GPU makes them from the drawn frames on either side.
        case made
    }

    /// How many times longer the motion takes to play. 2 is half speed, 4 is
    /// quarter speed. Never below 1.
    public let factor: Double

    /// Where the frames between the drawn ones come from.
    public let source: Source

    private init(factor: Double, source: Source) {
        self.factor = factor.isFinite ? max(1, factor) : 1
        self.source = source
    }

    /// Slow motion out of frames the sketch draws itself, on a clock that steps
    /// `factor` times finer. Exact, and it fits any sketch.
    public static func drawn(_ factor: Double) -> SlowMotion {
        SlowMotion(factor: factor, source: .drawn)
    }

    /// Slow motion out of frames the GPU makes between the drawn ones. Needs a
    /// 3D scene under a perspective camera, and the platform makes one frame
    /// per gap, so anything other than 2 is refused.
    public static func made(_ factor: Double) -> SlowMotion {
        SlowMotion(factor: factor, source: .made)
    }

    /// The rate the sketch's own clock runs at while the file plays at `fps`.
    /// The drawn form steps finer to fill the file; the made form draws at the
    /// file's own rate and fills the gaps afterward.
    func clockRate(playingAt fps: Double) -> Double {
        source == .drawn ? fps * factor : fps
    }

    /// How many frames the sketch itself draws to fill `written` frames of file.
    /// The made form fills one frame per gap, so a run of `n` drawn frames
    /// carries `2n - 1` written ones: enough drawn frames to cover what was
    /// asked for, with the last made frame dropped when the count is even.
    func drawnFrames(forWritten written: Int) -> Int {
        guard source == .made else { return written }
        return max(1, (written + 2) / 2)
    }

    /// How many frames a run of `drawn` drawn frames writes.
    func writtenFrames(forDrawn drawn: Int) -> Int {
        guard source == .made else { return drawn }
        return max(1, drawn * 2 - 1)
    }

    /// Whether this asks for anything at all. Factor 1 is the plain export.
    var isActive: Bool { factor > 1 }

    /// The line an export prints so nobody has to work out what they were
    /// handed. `written` frames play at `fps`, out of `seconds` of sketch time.
    func note(written: Int, fps: Double) -> String {
        let videoSeconds = Double(written) / max(fps, 0.001)
        let sketchSeconds = videoSeconds / factor
        let speed = String(format: "%g", factor)
        switch source {
        case .drawn:
            return String(format: "Ollin: slow motion %@x, every frame drawn: %.3gs of sketch time plays as %.3gs of video",
                          speed, sketchSeconds, videoSeconds)
        case .made:
            let drawn = drawnFrames(forWritten: written)
            return String(format: "Ollin: slow motion %@x, made frames: %d of the %d frames were made by the GPU, not drawn by the sketch",
                          speed, written - drawn, written)
        }
    }
}
