@testable import Ollin
import Testing

/// The camera rig on an export's clock: frame N is posed at N/fps, the time
/// `time` reads on that frame, at any frame rate; and a framing argument tuned
/// in the window lands where an export framed with that value puts it.
///
/// Each sketch is driven the way the export loop drives one (frame k at k/fps,
/// a 1/fps step each), and the camera is read back from `activeCamera`, so no
/// GPU is involved.
@Suite
@MainActor
struct CameraClockTests {

    private final class Turntable: Sketch {
        var radius = 10.0
        override func draw() { cameraMove(.turntable(period: 30), radius: radius) }
    }

    private final class PushIn: Sketch {
        override func draw() { cameraMove(.pushIn(by: 0.5, in: 2), radius: 10) }
    }

    /// The eye of every frame of `sketch` over `frames` frames at `fps`, with
    /// `before` run ahead of each frame (the window's parameter edits).
    private func eyes(_ sketch: Sketch, fps: Double, frames: Int,
                      before: (Int) -> Void = { _ in }) -> [Vector3] {
        sketch.setCanvasSize(width: 200, height: 200)
        sketch.setup()
        var out: [Vector3] = []
        for k in 0..<frames {
            before(k)
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            out.append(sketch.activeCamera?.eye ?? .zero)
        }
        return out
    }

    private func azimuth(_ eye: Vector3) -> Double { atan2(eye.x, eye.z) }

    /// Frame N of a turntable shows the turn at N/fps: frame 0 at its start.
    @Test(arguments: [30.0, 60.0])
    func frameNIsPosedAtNOverFps(fps: Double) {
        let poses = eyes(Turntable(), fps: fps, frames: Int(fps) + 1)
        #expect(azimuth(poses[0]) == 0)
        for (k, eye) in poses.enumerated() {
            #expect(abs(azimuth(eye) - Double(k) / fps * .tau / 30) < 1e-9)
        }
    }

    /// Two exports at different frame rates agree wherever their frames fall on
    /// the same time.
    @Test func twoFrameRatesAgreeAtOneTime() {
        let at30 = eyes(Turntable(), fps: 30, frames: 31)
        let at60 = eyes(Turntable(), fps: 60, frames: 61)
        for k in stride(from: 0, through: 30, by: 3) {
            #expect(at30[k].distance(to: at60[2 * k]) < 1e-9)
        }
    }

    /// A finite move's first frame is its start: a push-in opens at its full radius.
    @Test func aMoveOpensAtItsStart() {
        let first = eyes(PushIn(), fps: 30, frames: 1)[0]
        #expect(abs(first.length - 10) < 1e-12)
    }

    /// A radius tuned in the window lands where an export with that value frames
    /// it: the window's camera glides to it, and from then on matches the export
    /// frame for frame.
    @Test func aTunedRadiusLandsWhereTheExportFramesIt() {
        let window = Turntable(), export = Turntable()
        export.radius = 14
        let tuned = eyes(window, fps: 60, frames: 300) { k in if k == 30 { window.radius = 14 } }
        let framed = eyes(export, fps: 60, frames: 300)
        #expect(tuned[29].distance(to: framed[29]) > 1)
        #expect(tuned[31].distance(to: framed[31]) > 1)            // a glide, not a cut
        #expect(tuned[299].distance(to: framed[299]) < 1e-9)
    }
}
