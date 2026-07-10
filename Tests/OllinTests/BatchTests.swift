@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// CPU checks on retained-batch recording (`makeBatch` / `drawBatch`): what a
/// recording captures, what the reference batch carries, the recording gates,
/// and the vector-export splice. The rendered result is pinned by the
/// `retained-batch` snapshot; the GPU replay's pixel equivalence with the
/// per-frame path gets its own Metal-gated test at the bottom.
@Suite
@MainActor
struct BatchTests {

    // MARK: Recording

    @Test func recordingCapturesGeometryAndRestoresTheFrame() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.drawCircle(10, 10, 5)                    // frame content before
        let batch = drawer.makeBatch {
            drawer.drawCircle(0, 0, 8)                  // sdf
            drawer.drawPolygon([Vector2(0, 0), Vector2(30, 0), Vector2(15, 20)])  // triangles
            drawer.drawLine(Vector2(0, 0), Vector2(40, 40))               // fringe
        }
        drawer.drawCircle(20, 20, 5)                    // frame content after

        // The batch holds the body's geometry as its own call-ordered runs.
        #expect(!batch.isEmpty)
        #expect(batch.sdfInstances.count == 1)
        #expect(!batch.vertices.isEmpty)
        #expect(batch.innerBatches.map(\.kind).contains(.sdf))
        #expect(batch.innerBatches.map(\.kind).contains(.triangles))
        #expect(batch.innerBatches.map(\.kind).contains(.fringe))
        // Recorded runs are context-neutral: main canvas, unclipped.
        #expect(batch.innerBatches.allSatisfy { $0.target == nil && $0.clipLevel == 0 })
        // The frame's own recording is exactly the two circles around the block.
        #expect(drawer.sdfInstances.count == 2)
        #expect(drawer.batches.map(\.kind) == [.sdf])   // one merged sdf run
    }

    @Test func recordingRestoresStateAndStartsFromIdentity() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.fill(Color.red)
        drawer.translate(Vector2(100, 0))
        var recordedX: Float = -1
        let batch = drawer.makeBatch {
            // The body records in its own canvas-space frame: identity CTM.
            drawer.drawCircle(10, 0, 5)
            drawer.fill(Color.blue)
            drawer.strokeWeight(9)
        }
        recordedX = batch.sdfInstances[0].center.x
        #expect(recordedX == 10)                        // not shifted by the outer translate
        // Style changes inside the body don't leak (the withState rule)...
        #expect(drawer.fillPaint == .color(.red))
        #expect(drawer.strokeWidth != 9)
        // ...and the outer transform is back in force.
        drawer.drawCircle(10, 0, 5)
        #expect(drawer.sdfInstances.last.map { $0.transform.columns.2.x } == 100)
    }

    @Test func gradientRowsAreHandleRelative() {
        let drawer = Drawer()
        drawer.beginFrame()
        // A frame gradient first, so the frame's row table is non-empty.
        drawer.fill(Gradient.linear(from: .zero, to: Vector2(0, 50), [.red, .blue]))
        drawer.drawRect(Rectangle(x: 0, y: 0, width: 50, height: 50))
        let batch = drawer.makeBatch {
            drawer.fill(Gradient.linear(from: .zero, to: Vector2(50, 0), [.green, .yellow]))
            drawer.drawRect(Rectangle(x: 0, y: 0, width: 40, height: 40))
        }
        // The batch's one gradient is row 0 of its *own* strip, not row 1 of the
        // frame's, and the frame's table is back to its own single row.
        #expect(batch.gradientRows.count == 1)
        #expect(batch.sdfInstances[0].fillGradient == 0)
        #expect(drawer.gradientRows.count == 1)
    }

    // MARK: Replay

    @Test func drawBatchAppendsOneReferenceRun() {
        let drawer = Drawer()
        drawer.beginFrame()
        let batch = drawer.makeBatch { drawer.drawCircle(0, 0, 8) }
        drawer.drawBatch(batch)
        #expect(drawer.batches.map(\.kind) == [.retained])
        #expect(drawer.batches[0].retained === batch)
        // Identity CTM → nil transform, so the encode keeps the shader flag 0.
        #expect(drawer.batches[0].retainedTransform == nil)
        // The reference consumed no frame geometry.
        #expect(drawer.sdfInstances.isEmpty && drawer.vertices.isEmpty)

        // Under a transform the reference carries the CTM, and a following
        // primitive opens its own fresh batch.
        drawer.translate(Vector2(30, 40))
        drawer.drawBatch(batch)
        drawer.drawCircle(1, 1, 1)
        #expect(drawer.batches.map(\.kind) == [.retained, .retained, .sdf])
        #expect(drawer.batches[1].retainedTransform != nil)
        #expect(drawer.batches[1].retainedTransform?.columns.2.x == 30)
    }

    @Test func drawBatchCarriesTheDrawTimeContext() {
        let drawer = Drawer()
        drawer.beginFrame()
        let batch = drawer.makeBatch { drawer.drawCircle(0, 0, 8) }
        drawer.withClip(Shape([Vector2(0, 0), Vector2(50, 0), Vector2(50, 50), Vector2(0, 50)])) {
            drawer.drawBatch(batch)
        }
        let reference = drawer.batches.first { $0.kind == .retained }
        #expect(reference?.clipLevel == 1)
    }

    // MARK: Gates

    @Test func unsupportedContentIsSkippedNotRecorded() {
        let drawer = Drawer()
        drawer.beginFrame()
        let batch = drawer.makeBatch {
            drawer.background(.red)                     // gated: the frame's wipe
            drawer.withTarget(RenderTarget(width: 8, height: 8, scale: 1, drawer: drawer)) {
                drawer.drawCircle(0, 0, 4)              // gated: skipped whole
            }
            drawer.drawCircle(0, 0, 8)                  // recorded
        }
        #expect(batch.sdfInstances.count == 1)
        #expect(batch.innerBatches.map(\.kind) == [.sdf])
        #expect(drawer.backgroundColor != .red)
        // The frame's layer list is untouched by the skipped block.
        #expect(drawer.renderTargets.isEmpty)
    }

    @Test func nestedRecordingReturnsEmpty() {
        let drawer = Drawer()
        drawer.beginFrame()
        var inner: Batch?
        let outer = drawer.makeBatch {
            inner = drawer.makeBatch { drawer.drawCircle(0, 0, 4) }
            drawer.drawCircle(0, 0, 8)
        }
        #expect(inner?.isEmpty == true)
        #expect(outer.sdfInstances.count == 1)
    }

    @Test func pointCloudRecordsWithoutACamera() {
        let drawer = Drawer()
        drawer.beginFrame()
        let cloud = PointCloud(points: [PointCloud.Point(position: Vector3(0, 0, -2))])
        let batch = drawer.makeBatch { drawer.drawPointCloud(cloud) }
        #expect(batch.points.count == 1)
        #expect(batch.innerBatches.map(\.kind) == [.points3D])
    }

    // MARK: Vector export

    @Test func vectorExportSplicesTheRecordingUnderTheDrawTimeCTM() {
        let svg = OllinApp.svg(of: VectorBatchSketch(), frame: 0)
        // The one recorded circle replays twice: once in place, once translated.
        let circles = svg.components(separatedBy: "<circle").count - 1
        let ellipses = svg.components(separatedBy: "<ellipse").count - 1
        #expect(circles + ellipses == 2)
        // The second replay carries the draw-time CTM (SVG's column-major affine).
        #expect(svg.contains("matrix(1 0 0 1 60 60)"))
    }
}

/// The vector-export fixture: records one circle in `setup()` (under the
/// whole-drive vector flag this captures commands, not geometry) and replays it
/// twice in `draw()`, the second under a translate.
@MainActor
private final class VectorBatchSketch: Sketch {
    override var canvasSize: CanvasSize { .square(128) }
    private var motif: Batch!

    override func setup() {
        motif = makeBatch {
            noStroke()
            fill(.white)
            drawCircle(20, 20, 10)
        }
    }

    override func draw() {
        background(.black)
        drawBatch(motif)
        withState {
            translate(60, 60)
            drawBatch(motif)
        }
    }
}

/// GPU equivalence: the identity replay of a recording renders the same pixels
/// as the very draws it recorded, run through the ordinary per-frame path.
@Suite(.serialized)
@MainActor
struct BatchRenderTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func identityReplayMatchesThePerFrameDrawing() throws {
        let retained = try #require(OllinApp.image(of: BatchABSketch(useBatch: true)))
        let dynamic = try #require(OllinApp.image(of: BatchABSketch(useBatch: false)))
        // Both come off the same readback path, so equal drawings mean equal bytes.
        let retainedBytes = try #require(retained.dataProvider?.data as Data?)
        let dynamicBytes = try #require(dynamic.dataProvider?.data as Data?)
        #expect(retainedBytes == dynamicBytes,
                "the identity replay should render byte-identically to the per-frame path")
    }
}

/// One fixture, two paths: the same drawing either recorded once and replayed
/// (`useBatch`) or issued per frame. Content spans the SDF, triangle, and
/// fringe paths plus a gradient fill.
@MainActor
private final class BatchABSketch: Sketch {
    override var canvasSize: CanvasSize { .square(160) }
    private let useBatch: Bool
    private var motif: Batch?

    init(useBatch: Bool) {
        self.useBatch = useBatch
        super.init()
    }

    required init() {
        self.useBatch = true
        super.init()
    }

    private func content() {
        noStroke()
        fill(Gradient.linear(from: Vector2(20, 20), to: Vector2(90, 90),
                             [Color(hex: 0x4FC3F7), Color(hex: 0xE84C8B)]))
        drawRect(20, 20, 70, 70)
        fill(Color(hex: 0xE8A23C))
        drawPolygon([Vector2(30, 140), Vector2(80, 100), Vector2(130, 140), Vector2(80, 120)])
        stroke(.white)
        strokeWeight(2.5)
        noFill()
        drawPolyline([Vector2(100, 30), Vector2(120, 50), Vector2(140, 35)])
    }

    override func setup() {
        if useBatch { motif = makeBatch { content() } }
    }

    override func draw() {
        background(Color(hex: 0x14141E))
        if let motif {
            drawBatch(motif)
        } else {
            content()
        }
    }
}
