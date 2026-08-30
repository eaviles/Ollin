import Testing
import Ollin
import CoreGraphics
import Foundation
@testable import OllinVision

/// Optical flow is classical (no neural model), so it's fully checkable here on
/// any Mac: render a textured frame, shift it by a known amount, and confirm the
/// field reports that motion — magnitude, direction, and the canvas mapping — no
/// camera, no asset.
@Suite struct FlowTrackerTests {

    /// A 320×240 frame tiled edge to edge with a deterministic confetti of
    /// colored squares (dense texture, so the flow is well-defined everywhere),
    /// drawn shifted by (`shiftRight`, `shiftDown`) in canvas terms — frame B of
    /// a pair is the same picture moved right and down by a known amount.
    private func texturedFrame(shiftRight: Double = 0, shiftDown: Double = 0) -> Image {
        let w = 320, h = 240
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // A fixed linear-congruential sequence so both frames draw the same
        // confetti; only the shift differs. CG's y points up, so canvas-down
        // becomes a negative CG y offset.
        var seed: UInt64 = 0x5DEECE66D
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt32.max)
        }
        for _ in 0..<1200 {
            let x = next() * 400 - 40 + shiftRight
            let y = next() * 320 - 40 - shiftDown
            let side = 5 + next() * 14
            ctx.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: side, height: side))
        }
        return Image(cgImage: ctx.makeImage()!)
    }

    private let imageRect = Rectangle(x: 0, y: 0, width: 320, height: 240)

    @Test func queriesReadTheRightPartOfThePicture() async throws {
        // Only the picture's TOP half moves: the query under a top canvas
        // point must read that motion and a bottom point must not. Pins the
        // **top-down** indexing of Vision's `flow(at:)` (queries used to read
        // the vertically mirrored spot — a real bug the uniform-shift fixtures
        // couldn't catch, being invariant under the flip).
        let a = splitFrame(shiftTopRightBy: 0)
        let b = splitFrame(shiftTopRightBy: 7)
        let field = try #require(try await FlowTracker.detect(from: a, to: b))
        let top = field.vector(at: Vector2(160, 60), in: imageRect)
        let bottom = field.vector(at: Vector2(160, 180), in: imageRect)
        #expect(top.x > bottom.x + 2)
        #expect(top.x > 2)              // rightward, clearly read
        #expect(abs(bottom.x) < 2)      // the static half stays near zero
    }

    /// Confetti where only the picture's top half (canvas y < 120) is drawn
    /// shifted — the position-dependent companion to `texturedFrame`.
    private func splitFrame(shiftTopRightBy dx: Double) -> Image {
        let w = 320, h = 240
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // The generator divides the 31 surviving bits by 2³¹ so it spans the
        // whole 0…1 (the shared fixture's `/ UInt32.max` form tops out at 0.5,
        // which would leave the top half permanently confetti-free — and this
        // fixture's whole point is having both halves populated).
        var seed: UInt64 = 0x5DEECE66D
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt64(1) << 31)
        }
        for _ in 0..<1200 {
            let x = next() * 400 - 40
            let y = next() * 320 - 40
            let side = 5 + next() * 14
            // CG's y points up: rows with y ≥ 120 are the picture's top half.
            let inTop = y >= 120
            ctx.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 1))
            ctx.fill(CGRect(x: x + (inTop ? dx : 0), y: y, width: side, height: side))
        }
        return Image(cgImage: ctx.makeImage()!)
    }

    @Test func pairReportsTheShift() async throws {
        let a = texturedFrame()
        let b = texturedFrame(shiftRight: 8, shiftDown: 5)
        let field = try #require(try await FlowTracker.detect(from: a, to: b))

        // The flow map comes back at the input's own resolution.
        #expect(field.size.x == 320 && field.size.y == 240)

        // Mapped 1:1 into the image's own rect, the motion at the center reads
        // back as roughly the shift itself, in canvas points (y down = down).
        let v = field.vector(at: Vector2(160, 120), in: imageRect)
        #expect(v.x > 5 && v.x < 11)
        #expect(v.y > 2.5 && v.y < 7.5)

        // The whole frame moved together, so the global drift agrees: rightward
        // (+x) and downward, which in normalized (y up) space is negative y.
        #expect(field.averageFlowNormalized.x > 0.01)
        #expect(field.averageFlowNormalized.y < -0.005)
        let drift = field.averageFlow(in: imageRect)
        #expect(drift.x > 4 && drift.x < 12)
        #expect(drift.y > 2 && drift.y < 8)
    }

    @Test func mappingScalesAndMirrors() async throws {
        let a = texturedFrame()
        let b = texturedFrame(shiftRight: 8, shiftDown: 5)
        let field = try #require(try await FlowTracker.detect(from: a, to: b))

        // Drawn into a rect twice the size, the same motion is twice as long.
        let doubled = Rectangle(x: 0, y: 0, width: 640, height: 480)
        let v = field.vector(at: Vector2(320, 240), in: doubled)
        #expect(v.x > 10 && v.x < 22)
        #expect(v.y > 5 && v.y < 15)

        // Mirrored (the selfie orientation), rightward motion reads leftward;
        // the center is its own mirror image, so only x flips.
        let mirrored = field.vector(at: Vector2(160, 120), in: imageRect, mirrored: true)
        #expect(mirrored.x < -5 && mirrored.x > -11)
        #expect(mirrored.y > 2.5 && mirrored.y < 7.5)
    }

    @Test func samplesCoverTheRect() async throws {
        let a = texturedFrame()
        let b = texturedFrame(shiftRight: 8, shiftDown: 0)
        let field = try #require(try await FlowTracker.detect(from: a, to: b))

        let samples = field.samples(in: imageRect, every: 32)
        // One sample per 32-point cell: 10 columns × 7 rows.
        #expect(samples.count == 70)
        #expect(samples.allSatisfy {
            $0.position.x > 0 && $0.position.x < 320 && $0.position.y > 0 && $0.position.y < 240
        })
        // A purely horizontal shift: the samples agree on direction.
        let rightward = samples.filter { $0.flow.x > 2 }.count
        #expect(rightward > samples.count * 3 / 4)
    }

    /// Vision's `flow(at:)` does no bounds clamping: it rounds to the nearest
    /// pixel and traps past the last one (any coordinate ≥ (w − 0.5)/w — even
    /// 0.999999), so the field clamps queries to the last pixel's coordinate.
    /// The frame's far corner — where a drifting particle lands — must answer,
    /// not crash.
    @Test func edgeQueriesAreSafe() async throws {
        let a = texturedFrame()
        let b = texturedFrame(shiftRight: 8, shiftDown: 5)
        let field = try #require(try await FlowTracker.detect(from: a, to: b))

        // The coordinates that trap unclamped: exactly 1 and just under it.
        _ = field.flowNormalized(at: Vector2(1, 1))
        _ = field.flowNormalized(at: Vector2(0.999999, 0.999999))
        _ = field.flowNormalized(at: Vector2(-0.5, 2))
        // A point pinned to the rect's far corner — the live-particle crash.
        let v = field.vector(at: Vector2(320, 240), in: imageRect)
        #expect(v.x.isFinite && v.y.isFinite)
    }

    /// The live path re-performs one stateful request on successive frames (the
    /// way `ObjectTracker` does) — this pins that that actually produces flow,
    /// frame over frame, with the same conventions as the two-image path.
    @Test func statefulSequenceTracksFrameOverFrame() async throws {
        let frames = [texturedFrame(),
                      texturedFrame(shiftRight: 6, shiftDown: 4),
                      texturedFrame(shiftRight: 12, shiftDown: 8)]
        let fields = try await FlowTracker.detect(across: frames)
        #expect(fields.count == 3)

        // Flow needs a frame before it, so the first produces nothing.
        #expect(fields[0] == nil)

        // Each frame after the first measures against the one before it, so both
        // steps read the same (+6, +4) motion — right and down, with the live
        // default's conservative magnitudes (direction is what's pinned here).
        for field in fields.dropFirst() {
            let field = try #require(field)
            let v = field.vector(at: Vector2(160, 120), in: imageRect)
            #expect(v.x > 1.5 && v.x < 9)
            #expect(v.y > 1 && v.y < 7)
        }
    }
}
