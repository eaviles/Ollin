import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises `PhoneText`'s accessors over staged wire samples (GPU-free, CI-safe):
/// the 2D canvas mapping, the world quad's measurements, and the placement frame a
/// sketch hands to `transform(_:)`. The numbers are chosen so each expectation has
/// one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) struct PhoneTextTests {

    /// A line reading "OLLIN" hanging on a wall at z = -2: eighty centimeters
    /// wide, twenty tall, centered at (0, 1.5, -2), facing whoever reads it
    /// (toward +z). Corners ride in perimeter order: tl, tr, br, bl.
    private var wallSign: PhoneText {
        PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 3, text: "OLLIN", confidence: 0.9,
            corners: [SIMD2<Float>(0.3, 0.7), SIMD2<Float>(0.7, 0.7),
                      SIMD2<Float>(0.7, 0.6), SIMD2<Float>(0.3, 0.6)],
            hasWorldCorners: true,
            worldCorners: [SIMD3<Float>(-0.4, 1.6, -2), SIMD3<Float>(0.4, 1.6, -2),
                           SIMD3<Float>(0.4, 1.4, -2), SIMD3<Float>(-0.4, 1.4, -2)]))
    }

    @Test func cornersMapUprightIntoTheCanvas() throws {
        // Normalized (0.25, 0.75), lower-left origin, into a 100x200 rectangle at
        // (10, 20): x = 10 + 25, and y flips to 20 + (1 - 0.75) * 200 = 70.
        let line = PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 0, text: "A",
            corners: [SIMD2<Float>(0.25, 0.75), SIMD2<Float>(0.5, 0.75),
                      SIMD2<Float>(0.5, 0.5), SIMD2<Float>(0.25, 0.5)]))
        let rect = Rectangle(x: 10, y: 20, width: 100, height: 200)
        let corners = line.corners(in: rect)
        #expect(corners.count == 4)
        #expect(abs(corners[0].x - 35) < 1e-6)
        #expect(abs(corners[0].y - 70) < 1e-6)
        // The bottom-left corner sits lower on the canvas (bigger y, top-left origin).
        #expect(abs(corners[3].x - 35) < 1e-6)
        #expect(abs(corners[3].y - 120) < 1e-6)
    }

    @Test func boundsIsTheBoxAroundTheCorners() {
        // A tilted quad: the box must hug the extremes, not any one edge.
        let line = PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 0, text: "tilt",
            corners: [SIMD2<Float>(0.2, 0.9), SIMD2<Float>(0.8, 0.8),
                      SIMD2<Float>(0.7, 0.6), SIMD2<Float>(0.1, 0.7)]))
        let b = line.bounds(in: Rectangle(x: 0, y: 0, width: 100, height: 100))
        #expect(abs(b.x - 10) < 1e-4)
        #expect(abs(b.y - 10) < 1e-4)          // top edge: 1 - 0.9
        #expect(abs(b.width - 70) < 1e-4)      // 0.1 … 0.8
        #expect(abs(b.height - 30) < 1e-4)     // 0.6 … 0.9 flipped
    }

    @Test func aFlatLineHasNoWorldPlacement() {
        // A 2D-only line (no LiDAR to lift through): the world side stays honest.
        let line = PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 0, text: "flat",
            corners: [SIMD2<Float>(0.1, 0.2), SIMD2<Float>(0.3, 0.2),
                      SIMD2<Float>(0.3, 0.1), SIMD2<Float>(0.1, 0.1)]))
        #expect(!line.hasWorldPlacement)
        #expect(line.worldCorners.isEmpty)
        #expect(line.worldCenter == .zero)
        #expect(line.worldWidth == 0)
        #expect(line.worldHeight == 0)
        #expect(line.worldTransform == nil)
    }

    @Test func worldPlacementMeasuresTheQuad() {
        let sign = wallSign
        #expect(sign.hasWorldPlacement)
        #expect(sign.worldCorners.count == 4)
        let c = sign.worldCenter
        #expect(abs(c.x) < 1e-6)
        #expect(abs(c.y - 1.5) < 1e-6)
        #expect(abs(c.z + 2) < 1e-6)
        #expect(abs(sign.worldWidth - 0.8) < 1e-6)
        #expect(abs(sign.worldHeight - 0.2) < 1e-6)
    }

    @Test func worldTransformStandsTheLineOnItsSurface() throws {
        // The wall sign's frame: x along the reading direction, y up the line,
        // z off the wall toward the reader, the origin at the quad's center.
        let m = try #require(wallSign.worldTransform)
        #expect(simd_distance(m.columns.0, SIMD4<Float>(1, 0, 0, 0)) < 1e-5)
        #expect(simd_distance(m.columns.1, SIMD4<Float>(0, 1, 0, 0)) < 1e-5)
        #expect(simd_distance(m.columns.2, SIMD4<Float>(0, 0, 1, 0)) < 1e-5)
        #expect(simd_distance(m.columns.3, SIMD4<Float>(0, 1.5, -2, 1)) < 1e-5)
    }

    @Test func worldTransformStaysOrthonormalOnASkewedQuad() throws {
        // A quad read at an angle never comes back perfectly square, so the
        // frame must orthonormalize what it is given rather than trust it.
        let line = PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 0, text: "skew",
            corners: [SIMD2<Float>(0.2, 0.7), SIMD2<Float>(0.6, 0.72),
                      SIMD2<Float>(0.6, 0.62), SIMD2<Float>(0.2, 0.6)],
            hasWorldCorners: true,
            worldCorners: [SIMD3<Float>(-0.42, 1.61, -2.02), SIMD3<Float>(0.38, 1.63, -1.7),
                           SIMD3<Float>(0.41, 1.42, -1.69), SIMD3<Float>(-0.4, 1.4, -2)]))
        let m = try #require(line.worldTransform)
        let x = SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let y = SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let z = SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        #expect(abs(simd_length(x) - 1) < 1e-5)
        #expect(abs(simd_length(y) - 1) < 1e-5)
        #expect(abs(simd_length(z) - 1) < 1e-5)
        #expect(abs(simd_dot(x, y)) < 1e-5)
        #expect(abs(simd_dot(x, z)) < 1e-5)
        #expect(abs(simd_dot(y, z)) < 1e-5)
    }

    @Test func aDegenerateQuadGivesNoFrame() {
        // Four corners on one point can't say which way the line runs.
        let point = SIMD3<Float>(0.5, 1, -1)
        let line = PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 0, text: "dot",
            corners: [SIMD2<Float>(0.5, 0.5), SIMD2<Float>(0.5, 0.5),
                      SIMD2<Float>(0.5, 0.5), SIMD2<Float>(0.5, 0.5)],
            hasWorldCorners: true,
            worldCorners: [point, point, point, point]))
        #expect(line.worldTransform == nil)
    }

    @Test func imageAreaRanksTheBiggerLine() {
        // The shoelace area of the normalized quad: a 0.4 x 0.1 line covers 0.04
        // of the picture, and a malformed record (short corner list) covers none.
        let big = PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 0, text: "big",
            corners: [SIMD2<Float>(0.3, 0.7), SIMD2<Float>(0.7, 0.7),
                      SIMD2<Float>(0.7, 0.6), SIMD2<Float>(0.3, 0.6)]))
        #expect(abs(big.imageArea - 0.04) < 1e-6)
        let malformed = PhoneText(PhoneTextSample(
            isTracked: true, timestamp: 0, text: "short",
            corners: [SIMD2<Float>(0.5, 0.5)]))
        #expect(malformed.imageArea == 0)
    }
}
