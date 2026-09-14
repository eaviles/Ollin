import Testing
import Foundation
@testable import Ollin

/// The core `MotionField` on its own, backed by a closure, the way any source of
/// motion builds one: the canvas mapping, the mirror, the grid of samples, and
/// the drift. The Mac's flow tracker and the phone's field both stand on this
/// and are pinned in their own suites; this one pins the value they share.
@Suite struct MotionFieldTests {

    /// A field whose read returns a fixed normalized motion and records the
    /// point it was asked about.
    private func constantField(_ flow: Vector2) -> MotionField {
        MotionField(width: 64, height: 48, confidence: 0.9) { _ in flow }
    }

    @Test func aReadMapsIntoTheCanvas() {
        // A tenth of the frame to the right and a fifth of it UP (normalized,
        // +y up) drawn into a 400x200 rectangle is 40 points right and 40
        // points up the canvas, which is a negative canvas y.
        let field = constantField(Vector2(0.1, 0.2))
        let rect = Rectangle(x: 10, y: 20, width: 400, height: 200)
        let v = field.vector(at: Vector2(100, 100), in: rect)
        #expect(abs(v.x - 40) < 1e-9 && abs(v.y + 40) < 1e-9)
        #expect(field.size == Vector2(64, 48))
        #expect(abs(field.confidence - 0.9) < 1e-9)
    }

    @Test func theDriftIsTheMeanOfTheReads() {
        // A constant read averages to itself, in normalized units, and maps
        // into the rectangle the way a single read does.
        let field = constantField(Vector2(0.25, -0.5))
        #expect(abs(field.averageFlowNormalized.x - 0.25) < 1e-9)
        #expect(abs(field.averageFlowNormalized.y + 0.5) < 1e-9)
        let drift = field.averageFlow(in: Rectangle(x: 0, y: 0, width: 200, height: 100))
        #expect(abs(drift.x - 50) < 1e-9 && abs(drift.y - 50) < 1e-9)
    }

    @Test func mirroredFlipsTheQueryAndTheAnswer() {
        // The read gets the mirrored point (a canvas point near the left edge
        // asks about the right of the picture), and the answer's x flips with
        // the picture while its y does not.
        let field = MotionField(width: 10, height: 10, confidence: 1) { point in
            point.x > 0.5 ? Vector2(0.1, 0.1) : .zero
        }
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let plain = field.vector(at: Vector2(10, 50), in: rect)
        let mirrored = field.vector(at: Vector2(10, 50), in: rect, mirrored: true)
        #expect(plain == .zero)
        #expect(abs(mirrored.x + 10) < 1e-9 && abs(mirrored.y + 10) < 1e-9)
    }

    @Test func samplesLandOnCellCenters() {
        let field = constantField(Vector2(0.1, 0))
        let rect = Rectangle(x: 0, y: 0, width: 320, height: 240)
        let samples = field.samples(in: rect, every: 32)
        // One sample per 32-point cell: 10 columns by 7 rows, the first at the
        // center of the first cell.
        #expect(samples.count == 70)
        #expect(samples.first?.position == Vector2(16, 16))
        #expect(samples.allSatisfy { abs($0.flow.x - 32) < 1e-9 && $0.flow.y == 0 })
        #expect(field.samples(in: rect, every: 0).isEmpty)
    }
}
