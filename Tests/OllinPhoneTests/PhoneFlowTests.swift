import Testing
import Foundation
import simd
import CoreGraphics
import Vision
import Ollin
@testable import OllinPhone

/// Exercises the phone's motion field with no phone attached: the `.flow` wire
/// kind's round trip, the quarter turns that stand a camera-native map upright
/// (the grid and every vector in it), and the reads over staged maps, which
/// are the Mac tracker's own reads (the query's y turned over, the canvas
/// mapping through the rectangle, the mirror, the grid of samples). The last
/// test runs the same Vision request the phone runs, over two frames of
/// confetti, and pins which way its raw vectors point, since that is the one
/// convention the phone's streamer is written against and cannot be checked
/// on the phone from here.
@Suite(.timeLimit(.minutes(1))) struct PhoneFlowTests {

    // MARK: The wire

    @Test func roundTripsAReading() {
        let sample = PhoneFlowSample(
            isTracked: true, timestamp: 12.25, interval: 0.0667,
            flowWidth: 3, flowHeight: 2, orientation: 1, confidence: 0.83,
            flow: [SIMD2<Float>(1.5, -0.25), SIMD2<Float>(0, 0), SIMD2<Float>(-2, 3),
                   SIMD2<Float>(0.125, 0.5), SIMD2<Float>(7, -7), SIMD2<Float>(0.001, 9)],
            colorJPEG: Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]))
        #expect(roundTrip(.flow(sample)) == .flow(sample))
    }

    @Test func roundTripsAnEmptyMap() {
        // A reading with no vectors is a valid frame (the Mac then reads no
        // motion anywhere), not a broken one.
        let sample = PhoneFlowSample(isTracked: false, timestamp: 0, interval: 0,
                                     flowWidth: 0, flowHeight: 0, flow: [])
        #expect(roundTrip(.flow(sample)) == .flow(sample))
    }

    @Test func aTruncatedReadingDecodesToNothing() {
        // Cut inside the last vector: the whole reading is refused rather than
        // half a map handed over.
        let sample = PhoneFlowSample(isTracked: true, timestamp: 1, interval: 0.05,
                                     flowWidth: 2, flowHeight: 1,
                                     flow: [SIMD2<Float>(1, 2), SIMD2<Float>(3, 4)])
        let framed = PhoneWire.encode(.flow(sample))
        let header = PhoneHeader.parse(framed)!
        let payload = framed.dropFirst(PhoneWire.headerByteCount).dropLast(3)
        #expect(PhoneWire.decode(header: PhoneHeader(kind: header.kind,
                                                     payloadLength: payload.count),
                                 payload: Data(payload)) == nil)
    }

    // MARK: Standing the map upright

    /// A 4x2 camera-native map with one vector at its top-left cell, pointing
    /// right along the sensor.
    private func nativeMap(orientation: UInt8) -> PhoneFlowSample {
        var flow = [SIMD2<Float>](repeating: .zero, count: 8)
        flow[0] = SIMD2<Float>(2, 0)
        return PhoneFlowSample(isTracked: true, timestamp: 0, interval: 0.1,
                               flowWidth: 4, flowHeight: 2, orientation: orientation,
                               flow: flow)
    }

    @Test func aQuarterTurnTurnsTheGridAndTheVectors() throws {
        // One clockwise turn: the top row becomes the right column, so the
        // top-left cell lands top-right of a 2x4 upright map, and a vector that
        // pointed right along the sensor now points DOWN the upright picture.
        let plane = try #require(PhoneFlowPlane.upright(nativeMap(orientation: 1)))
        #expect(plane.width == 2 && plane.height == 4)
        #expect(plane.vectors[0 * 2 + 1] == SIMD2<Float>(0, 2))
        #expect(plane.vectors.filter { $0 != .zero }.count == 1)
    }

    @Test func aHalfTurnReversesEverything() throws {
        let plane = try #require(PhoneFlowPlane.upright(nativeMap(orientation: 2)))
        #expect(plane.width == 4 && plane.height == 2)
        #expect(plane.vectors[1 * 4 + 3] == SIMD2<Float>(-2, 0))
        #expect(plane.vectors.filter { $0 != .zero }.count == 1)
    }

    @Test func threeQuarterTurnsTurnTheOtherWay() throws {
        // A counterclockwise turn: the top row becomes the left column read
        // bottom to top, so the top-left cell lands bottom-left, and right
        // turns into UP.
        let plane = try #require(PhoneFlowPlane.upright(nativeMap(orientation: 3)))
        #expect(plane.width == 2 && plane.height == 4)
        #expect(plane.vectors[3 * 2 + 0] == SIMD2<Float>(0, -2))
        #expect(plane.vectors.filter { $0 != .zero }.count == 1)
    }

    @Test func theTurnsAgreeWithThePictureTheyStandUp() throws {
        // The color frame is stood up by the same turn count through the
        // shared image rotation, so a map's turn must land a cell where that
        // rotation lands the pixel under it: a 4x2 picture with its top-left
        // pixel lit, turned once, is lit at the top-right of a 2x4 picture.
        let ctx = try #require(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 1, width: 1, height: 1))     // CG's y is up: row 0 is y = 1
        let turned = try #require(rotatedCGImage(ctx.makeImage()!, quarterTurnsCW: 1))
        #expect(turned.width == 2 && turned.height == 4)
        var pixels = [UInt8](repeating: 0, count: 2 * 4 * 4)
        let read = try #require(CGContext(data: &pixels, width: 2, height: 4, bitsPerComponent: 8,
                                          bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        read.draw(turned, in: CGRect(x: 0, y: 0, width: 2, height: 4))
        // A bitmap context's first row in memory is the top of the picture.
        let topRight = pixels[(0 * 2 + 1) * 4]
        let topLeft = pixels[(0 * 2 + 0) * 4]
        #expect(topRight > 200 && topLeft < 50, "rows: \(pixels)")
    }

    // MARK: Reading it like the Mac's field

    /// A 4x2 upright map whose top-left cell alone moves, two map pixels to
    /// the right.
    private var topLeftMoves: PhoneFlow { PhoneFlow(nativeMap(orientation: 0)) }

    @Test func queriesTurnTheRowsOver() {
        // The map's rows run from the top of the picture down, and the query
        // point arrives lower-left normalized: a point near the top of the
        // picture (y close to 1) must read the FIRST row. A query that skips
        // the turn reads zero here and this goes red.
        let motion = topLeftMoves
        let top = motion.flowNormalized(at: Vector2(0.1, 0.9))
        let bottom = motion.flowNormalized(at: Vector2(0.1, 0.1))
        #expect(top.x > 0.4 && abs(top.y) < 1e-6)      // 2 px of a 4 px wide map: 0.5
        #expect(bottom == .zero)
    }

    @Test func vectorsMapThroughTheRectangle() {
        // A whole map moving one map pixel right and one down, drawn into a
        // 400x200 rectangle: a quarter of the width to the right, and half the
        // height DOWN the canvas (canvas y grows down, like the picture's).
        let sample = PhoneFlowSample(isTracked: true, timestamp: 0, interval: 0.1,
                                     flowWidth: 4, flowHeight: 2,
                                     flow: Array(repeating: SIMD2<Float>(1, 1), count: 8))
        let motion = PhoneFlow(sample)
        let rect = Rectangle(x: 10, y: 20, width: 400, height: 200)
        let v = motion.vector(at: Vector2(210, 120), in: rect)
        #expect(abs(v.x - 100) < 1e-6)
        #expect(abs(v.y - 100) < 1e-6)
        // The global drift agrees, and in normalized (y up) space the downward
        // half is negative.
        let drift = motion.averageFlow(in: rect)
        #expect(abs(drift.x - 100) < 1e-6 && abs(drift.y - 100) < 1e-6)
        #expect(abs(motion.averageFlowNormalized.y + 0.5) < 1e-6)
        #expect(motion.size == Vector2(4, 2))
    }

    @Test func mirroredFlipsTheQueryAndTheAnswer() {
        // Drawn mirrored, the moving top-left cell sits top-RIGHT on the
        // canvas, and its rightward motion reads leftward there.
        let motion = topLeftMoves
        let rect = Rectangle(x: 0, y: 0, width: 400, height: 200)
        let mirrored = motion.vector(at: Vector2(390, 10), in: rect, mirrored: true)
        #expect(mirrored.x < -100)
        let plain = motion.vector(at: Vector2(390, 10), in: rect)
        #expect(plain == .zero)
    }

    @Test func samplesCoverTheRectangle() {
        let sample = PhoneFlowSample(isTracked: true, timestamp: 0, interval: 0.1,
                                     flowWidth: 4, flowHeight: 2,
                                     flow: Array(repeating: SIMD2<Float>(1, 0), count: 8))
        let motion = PhoneFlow(sample)
        let rect = Rectangle(x: 0, y: 0, width: 320, height: 240)
        let samples = motion.samples(in: rect, every: 32)
        // One sample per 32-point cell: 10 columns by 7 rows, all inside.
        #expect(samples.count == 70)
        #expect(samples.allSatisfy {
            $0.position.x > 0 && $0.position.x < 320 && $0.position.y > 0 && $0.position.y < 240
        })
        #expect(samples.allSatisfy { abs($0.flow.x - 80) < 1e-6 && abs($0.flow.y) < 1e-6 })
    }

    @Test func aQueryBetweenCellsBlends() {
        // Halfway between a still cell and one moving right, the read is half
        // the motion: the map is coarse and the picture is not, so a particle
        // drifting across a cell edge must not snap.
        let sample = PhoneFlowSample(isTracked: true, timestamp: 0, interval: 0.1,
                                     flowWidth: 2, flowHeight: 1,
                                     flow: [SIMD2<Float>(0, 0), SIMD2<Float>(2, 0)])
        let motion = PhoneFlow(sample)
        let mid = motion.flowNormalized(at: Vector2(0.5, 0.5))
        #expect(abs(mid.x - 0.5) < 1e-6)             // (0 + 2) / 2, over a width of 2
        // The edges clamp to their own cell rather than reaching outside.
        #expect(motion.flowNormalized(at: Vector2(-3, 0.5)) == .zero)
        #expect(abs(motion.flowNormalized(at: Vector2(7, 0.5)).x - 1) < 1e-6)
    }

    @Test func aMalformedMapReadsAsNoMotion() {
        // Dims that outrun the vectors are refused, so a query can never index
        // past the plane; the reading then answers zero everywhere and says so
        // through its size.
        let motion = PhoneFlow(PhoneFlowSample(isTracked: true, timestamp: 0, interval: 0.1,
                                               flowWidth: 10, flowHeight: 10,
                                               flow: [SIMD2<Float>(5, 5)]))
        #expect(motion.size == .zero)
        #expect(motion.vector(at: Vector2(50, 50), in: Rectangle(x: 0, y: 0, width: 100, height: 100)) == .zero)
        #expect(decodePhoneFlow(PhoneFlowSample(isTracked: true, timestamp: 0, interval: 0.1,
                                                flowWidth: 10, flowHeight: 10,
                                                flow: [SIMD2<Float>(5, 5)]), sequence: 1) == nil)
    }

    @Test func theFieldIsTheMacTrackersOwnValue() {
        // `field` is a core `MotionField`, so a helper written against the Mac
        // tracker's field takes the phone's, and the two agree read for read.
        func drift(of field: MotionField, in rect: Rectangle) -> Vector2 { field.averageFlow(in: rect) }
        let sample = PhoneFlowSample(isTracked: true, timestamp: 3, interval: 0.05,
                                     flowWidth: 4, flowHeight: 2, confidence: 0.7,
                                     flow: Array(repeating: SIMD2<Float>(0, -1), count: 8))
        let motion = PhoneFlow(sample)
        let rect = Rectangle(x: 0, y: 0, width: 400, height: 200)
        #expect(drift(of: motion.field, in: rect) == motion.averageFlow(in: rect))
        #expect(abs(drift(of: motion.field, in: rect).y + 100) < 1e-6)   // up the picture is up the canvas
        #expect(abs(motion.confidence - 0.7) < 1e-6)
        #expect(motion.interval == 0.05 && motion.timestamp == 3 && motion.isTracked)
    }

    // MARK: What the phone's model reports

    /// The phone hands Vision's flow request the older frame through the
    /// handler and the newer one as the target, and puts the raw map on the
    /// wire as the motion of the picture itself, with no sign change. This runs
    /// that same request over two frames of confetti, the second slid eight
    /// pixels to the right, and reads the raw vectors over the middle of the
    /// picture: they must point RIGHT, the way the picture moved. (The Mac's
    /// tracker, over the newer Vision API, gets the opposite sign and negates;
    /// the two requests do not agree, which is why this is pinned here.) If
    /// Vision ever reports the other way, this goes red and `wireField` in the
    /// phone's streamer is the one place to flip.
    /// Whether Vision can run its optical-flow request on this machine at all.
    /// A CI runner's paravirtual GPU has no compute device for it ("No available
    /// compute device for VNComputeStageMain", run 34834525008, 2026-09-14), so
    /// the request throws there instead of reporting a sign; this asks once,
    /// over two tiny frames, and the sign test refuses itself where the answer
    /// is no. Vision's own failure is the probe, so nothing else can stand in.
    static let visionComputesFlow: Bool = {
        func frame(shift: Double) -> CGImage? {
            let ctx = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            ctx?.setFillColor(CGColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1))
            for i in 0..<6 {
                ctx?.fill(CGRect(x: 6 + Double(i) * 9 + shift, y: 8 + Double(i % 3) * 12, width: 5, height: 5))
            }
            return ctx?.makeImage()
        }
        guard let older = frame(shift: 0), let newer = frame(shift: 3) else { return false }
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: newer, options: [:])
        request.computationAccuracy = .low
        let handler = VNImageRequestHandler(cgImage: older, options: [:])
        guard (try? handler.perform([request])) != nil else { return false }
        return request.results?.first is VNPixelBufferObservation
    }()

    @Test(.enabled(if: Self.visionComputesFlow, "Vision has no compute device for optical flow here"))
    func visionsFlowRequestReportsTheMotionOfThePicture() throws {
        let older = confetti(shiftRight: 0)
        let newer = confetti(shiftRight: 8)
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: newer, options: [:])
        // The accuracy the phone's streamer asks for, which is the one whose
        // sign the wire depends on.
        request.computationAccuracy = .medium
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        let handler = VNImageRequestHandler(cgImage: older, options: [:])
        try handler.perform([request])
        let observation = try #require(request.results?.first as? VNPixelBufferObservation)
        let map = observation.pixelBuffer
        #expect(CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_TwoComponent32Float)
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
        let base = try #require(CVPixelBufferGetBaseAddress(map))
        let stride = CVPixelBufferGetBytesPerRow(map)
        // The mean over the middle of the picture, where the confetti is dense
        // and no edge is near.
        var sumX: Float = 0, sumY: Float = 0, n: Float = 0
        for row in (h / 3)..<(2 * h / 3) {
            let line = base.advanced(by: row * stride).assumingMemoryBound(to: Float.self)
            for col in (w / 3)..<(2 * w / 3) {
                sumX += line[2 * col]; sumY += line[2 * col + 1]; n += 1
            }
        }
        let dx = sumX / n, dy = sumY / n
        #expect(dx > 2 && dx < 12, "raw mean dx \(dx), dy \(dy) over a \(w)x\(h) map")
        #expect(abs(dy) < 3, "raw mean dx \(dx), dy \(dy)")
    }

    /// A 320x240 frame tiled with a deterministic confetti of colored squares
    /// (dense texture, so the flow is well-defined everywhere), drawn shifted
    /// right by `shiftRight` pixels.
    private func confetti(shiftRight: Double) -> CGImage {
        let w = 320, h = 240
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var seed: UInt64 = 0x5DEECE66D
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt64(1) << 31)
        }
        for _ in 0..<1200 {
            let x = next() * 400 - 40 + shiftRight
            let y = next() * 320 - 40
            let side = 5 + next() * 14
            ctx.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: side, height: side))
        }
        return ctx.makeImage()!
    }

    // MARK: Helpers

    private func roundTrip(_ message: PhoneMessage) -> PhoneMessage? {
        let framed = PhoneWire.encode(message)
        guard let header = PhoneHeader.parse(framed) else { return nil }
        let payload = framed.dropFirst(PhoneWire.headerByteCount)
        return PhoneWire.decode(header: header, payload: Data(payload))
    }
}
