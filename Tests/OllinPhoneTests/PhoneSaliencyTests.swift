import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises `PhoneSaliency`'s accessors over staged wire samples (GPU-free,
/// CI-safe): the heat-map query with its top-down-to-lower-left turn, the edge
/// clamping, the region box's canvas mapping, and the world side. The numbers
/// are chosen so each expectation has one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) struct PhoneSaliencyTests {

    /// A 4x2 heat map whose single bright pixel sits at the top-left of the
    /// upright picture (row 0, column 0 in the wire's top-down plane).
    private var brightTopLeft: PhoneSaliency {
        PhoneSaliency(PhoneSaliencySample(
            isTracked: true, timestamp: 2,
            heatWidth: 4, heatHeight: 2,
            heat: [255, 0, 0, 0,
                   0, 0, 0, 0]))
    }

    @Test func salienceQueryTurnsTheHeatRowsOver() {
        // The wire's heat rows run from the top of the picture down, and the
        // query point arrives lower-left normalized: a point near the top of the
        // picture (y close to 1) must read the FIRST row, not the last. A query
        // that skips the turn reads 0 here and this goes red.
        let reading = brightTopLeft
        #expect(reading.salienceNormalized(at: Vector2(0.1, 0.9)) == 1.0)
        // The same corner of the plane read without the flip (y close to 0) is
        // the bottom of the picture, which is dark.
        #expect(reading.salienceNormalized(at: Vector2(0.1, 0.1)) == 0.0)
    }

    @Test func salienceQueryClampsToTheEdge() {
        // Out-of-range points read the nearest edge pixel rather than trapping
        // or wrapping: far off the top-left they read the bright pixel, far off
        // the bottom-right the dark one.
        let reading = brightTopLeft
        #expect(reading.salienceNormalized(at: Vector2(-3, 7)) == 1.0)
        #expect(reading.salienceNormalized(at: Vector2(5, -2)) == 0.0)
    }

    @Test func salienceReadsCanvasPointsThroughTheRectangle() {
        // A canvas point near the top of a 100x200 frame drawn at (10, 20) maps
        // to the upright picture's top, where the bright pixel is.
        let reading = brightTopLeft
        let rect = Rectangle(x: 10, y: 20, width: 100, height: 200)
        #expect(reading.salience(at: Vector2(15, 25), in: rect) == 1.0)
        #expect(reading.salience(at: Vector2(105, 215), in: rect) == 0.0)
    }

    @Test func aMalformedHeatPlaneReadsAsSilence() {
        // Dims that outrun the bytes are refused at init, so a query can never
        // index past the plane; the reading then answers 0 everywhere.
        let reading = PhoneSaliency(PhoneSaliencySample(
            isTracked: true, timestamp: 0, heatWidth: 10, heatHeight: 10,
            heat: [255, 255]))
        #expect(reading.heatWidth == 0)
        #expect(reading.salienceNormalized(at: Vector2(0.5, 0.5)) == 0.0)
    }

    @Test func regionBoundsMapUprightIntoTheCanvas() {
        // A box at (0.2, 0.6) sized 0.4x0.2, lower-left origin, into a 100x200
        // rectangle at (10, 20): x = 10 + 20 = 30, and the TOP edge lands at
        // y = 20 + (1 - (0.6 + 0.2)) * 200 = 60.
        let region = PhoneSalientRegion(PhoneSalientRegionSample(
            x: 0.2, y: 0.6, width: 0.4, height: 0.2, confidence: 0.8))
        let rect = Rectangle(x: 10, y: 20, width: 100, height: 200)
        let b = region.bounds(in: rect)
        #expect(abs(b.x - 30) < 1e-5)
        #expect(abs(b.y - 60) < 1e-5)
        #expect(abs(b.width - 40) < 1e-5)
        #expect(abs(b.height - 40) < 1e-5)
        let c = region.center(in: rect)
        #expect(abs(c.x - 50) < 1e-5)
        #expect(abs(c.y - 80) < 1e-5)
    }

    @Test func theStrongestRegionWinsByConfidence() {
        let reading = PhoneSaliency(PhoneSaliencySample(
            isTracked: true, timestamp: 0, heatWidth: 1, heatHeight: 1, heat: [0],
            regions: [
                PhoneSalientRegionSample(x: 0.1, y: 0.1, width: 0.2, height: 0.2,
                                         confidence: 0.3),
                PhoneSalientRegionSample(x: 0.5, y: 0.5, width: 0.2, height: 0.2,
                                         confidence: 0.9),
            ]))
        #expect(abs((reading.strongestRegion?.confidence ?? 0) - 0.9) < 1e-6)
    }

    @Test func aFlatRegionHasNoWorldPlacement() {
        // A 2D-only region (no LiDAR to lift through): the world side stays honest.
        let flat = PhoneSalientRegion(PhoneSalientRegionSample(
            x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        #expect(!flat.hasWorldPlacement)
        #expect(flat.worldCenter == .zero)

        let lifted = PhoneSalientRegion(PhoneSalientRegionSample(
            x: 0.1, y: 0.1, width: 0.2, height: 0.2, confidence: 1,
            hasWorldCenter: true, worldCenter: SIMD3<Float>(0.5, 1.25, -2)))
        #expect(lifted.hasWorldPlacement)
        #expect(abs(lifted.worldCenter.y - 1.25) < 1e-6)
    }
}
