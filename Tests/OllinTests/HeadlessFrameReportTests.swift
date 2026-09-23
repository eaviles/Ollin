import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// An extension's `afterFrame` fires on the headless drives too, once per
/// frame they render, with the export clock's numbers rather than a live
/// window's smoothed ones: `frameRate` is the rate the frame was timed at,
/// `deltaTime` the step the clock took (none for a settle draw), the profile
/// counted and timed for that render. Before this, an export left
/// `FrameInfo.profile` unreachable, so the cost of a written frame could be
/// read from a window and never from the run that mattered.
@Suite(.serialized)
@MainActor
struct HeadlessFrameReportTests {

    final class Report: SketchExtension {
        var infos: [FrameInfo] = []
        func afterFrame(_ sketch: Sketch, _ info: FrameInfo) { infos.append(info) }
    }

    class Dots: Sketch {
        let report = Report()
        override var canvasSize: CanvasSize { .square(64) }
        override func setup() { extend(report) }
        override func draw() {
            background(.white)
            fill(.black)
            for i in 0..<5 { drawCircle(Double(i * 12 + 8), 32, 4) }
        }
    }

    final class Pile: Dots {
        override func setup() { super.setup(); noClear() }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillReportsTheFrameItRendered() {
        let sketch = Dots()
        #expect(OllinApp.image(of: sketch, frame: 5, fps: 10) != nil)
        // Frames 0 to 4 are advanced and stepped, never rendered; frame 5 is.
        #expect(sketch.report.infos.count == 1)
        guard let info = sketch.report.infos.first else { return }
        #expect(info.frameRate == 10)
        #expect(info.deltaTime == 0.1)
        #expect(info.sdfCount == 5)
        #expect(info.profile.sdfInstances == 5)
        #expect(info.profile.drawCalls > 0)
        #expect(info.profile.passes > 0)
        #expect(info.profile.cpuEncodeMS > 0, "the encode is timed on the headless path")
        #expect(info.profile.gpuMS > 0, "the GPU's run is read from the command buffer's own timestamps")
        #expect(info.profile.waitMS >= info.profile.gpuMS * 0.5,
                "a synchronous render's wait covers the GPU's run")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSequenceReportsEveryRenderedFrameWarmupIncluded() throws {
        let directory = ollinTempPath("ollin-report-sequence")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let sketch = Dots()
        OllinApp.exportSequence(sketch, to: directory, frames: 6, fps: 30, skipSeconds: 2.0 / 30)
        // A warmup frame of a plain sketch is stepped rather than rendered, so
        // only the six written frames report.
        #expect(sketch.report.infos.count == 6)
        #expect(sketch.report.infos.allSatisfy { $0.frameRate == 30 })
        #expect(sketch.report.infos.allSatisfy { abs($0.deltaTime - 1.0 / 30) < 1e-12 })
        #expect(sketch.report.infos.allSatisfy { $0.profile.drawCalls > 0 })
    }

    /// A piling canvas renders every frame, warmup included, so every frame reports.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPilingSketchReportsItsWarmupFramesToo() throws {
        let directory = ollinTempPath("ollin-report-pile")
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let sketch = Pile()
        OllinApp.exportSequence(sketch, to: directory, frames: 3, fps: 30, skipSeconds: 2.0 / 30)
        #expect(sketch.report.infos.count == 5)

        let still = Pile()
        #expect(OllinApp.image(of: still, frame: 3) != nil)
        #expect(still.report.infos.count == 4)
    }

    /// A settled still draws its frame several times with the clock held.
    /// The first draw is the moment's state and is not rendered; every settle
    /// draw after it renders, and each render reports, with no clock step.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSettledFrameReportsEachDraw() {
        let previous = OllinApp.exportSettle
        OllinApp.exportSettle = 3
        defer { OllinApp.exportSettle = previous }
        let sketch = Dots()
        #expect(OllinApp.image(of: sketch, frame: 0, fps: 60) != nil)
        #expect(sketch.report.infos.map(\.deltaTime) == [0, 0])
    }
}
