import COllinShaders
import CoreGraphics
import Foundation
import Metal
import simd
import Testing
@testable import Ollin

/// Per-copy motion for instanced meshes: `drawMesh(_:instances:)` inside
/// `withMotion` keeps last frame's placement of every copy under the block's
/// key, and the velocity pass carries each copy back through its own matrix.
///
/// What a sketch is promised: each copy writes its own motion, the same motion
/// it would write drawn as a mover of its own; copies are matched by their
/// place in the list, so a frame whose count changed writes none rather than
/// pairing a copy with a stranger; an instanced draw hides a mover behind it in
/// the velocity pass as a solid one does; and an export streaks the copies and
/// repeats itself.
@Suite
@MainActor
struct InstancedMotionTests {

    /// Copies of a 20-unit box on an orthographic camera framing 128 world units
    /// on a 128 px readback (1 unit = 1 px, +x right, +y up). `offsets` moves
    /// copy *i* from its home; `perCopy` draws each copy as its own mover
    /// instead of one instanced draw, the path the instanced one has to match.
    final class CopiesProbe: Sketch {
        var homes = [Vector3(-40, 0, 0), Vector3(0, 0, 0), Vector3(40, 0, 0)]
        var offsets = [Vector3](repeating: .zero, count: 3)
        var moving = true
        var perCopy = false
        var wall = false
        var plainMover = false
        var blur = false
        override var canvasSize: CanvasSize { .square(128) }

        let box = Mesh.box(width: 20, height: 20, depth: 2)

        var placements: [MeshInstance] {
            zip(homes, offsets).map { MeshInstance(position: $0 + $1) }
        }

        override func draw() {
            background(.black)
            ortho(eye: Vector3(0, 0, 100), target: .zero, height: 128, near: 1, far: 200)
            temporalAntialiasing()
            if blur { motionBlur(shutter: 1) }
            noLights()
            fill(.white)
            if wall {
                // An instanced wall between the camera and the middle of the scene.
                drawMesh(.box(width: 40, height: 40, depth: 2),
                         instances: [MeshInstance(position: Vector3(0, 0, 40))])
            }
            if plainMover {
                withMotion("crate") {
                    translate(offsets[1].x, offsets[1].y, offsets[1].z)
                    drawMesh(box)
                }
                return
            }
            if perCopy {
                for (i, placement) in placements.enumerated() {
                    withState {
                        withMotion("copy-\(i)") {
                            translate(placement.position.x, placement.position.y, placement.position.z)
                            drawMesh(box)
                        }
                    }
                }
            } else if moving {
                withMotion("copies") { drawMesh(box, instances: placements) }
            } else {
                drawMesh(box, instances: placements)
            }
        }
    }

    // MARK: Recording

    @Test func theFirstSightingRecordsNothingAndTheSecondRecordsEveryCopy() {
        let s = CopiesProbe()
        s.setup()
        s.performDraw()
        #expect(s.drawer.instancedMoverRanges.isEmpty, "no previous placement yet")
        let first = s.drawer.meshInstances.map(\.model)
        s.offsets = [Vector3(5, 0, 0), .zero, Vector3(0, -3, 0)]
        s.performDraw()
        let ranges = s.drawer.instancedMoverRanges
        #expect(ranges.count == 1)
        #expect(ranges.first?.instanceCount == 3)
        #expect(s.drawer.moverPreviousInstances == first, "last frame's matrices, copy for copy")
        #expect(s.drawer.hasMovers)
    }

    @Test func aChangedCountRecordsNothingAndStartsOver() {
        let s = CopiesProbe()
        s.setup()
        s.performDraw()
        s.performDraw()
        #expect(s.drawer.instancedMoverRanges.count == 1)
        s.homes.append(Vector3(0, 40, 0))
        s.offsets.append(.zero)
        s.performDraw()
        #expect(s.drawer.instancedMoverRanges.isEmpty, "four copies cannot be matched to three")
        s.performDraw()
        #expect(s.drawer.instancedMoverRanges.first?.instanceCount == 4, "the new count's history holds")
    }

    @Test func aSkippedFrameStartsOver() {
        let s = CopiesProbe()
        s.setup()
        s.performDraw()
        s.moving = false
        s.performDraw()
        s.moving = true
        s.performDraw()
        #expect(s.drawer.instancedMoverRanges.isEmpty, "two frames ago is not last frame")
    }

    @Test func copiesOutsideABlockAreNotMovers() {
        let s = CopiesProbe()
        s.moving = false
        s.setup()
        s.performDraw()
        s.performDraw()
        #expect(s.drawer.instancedMoverRanges.isEmpty && !s.drawer.hasMovers)
    }

    // MARK: The velocity pass

    private func makeRenderer() throws -> MetalRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                 sampleCount: ollinPreferredSampleCount(device))
    }

    /// Draw the probe at `from` then `to` and read the velocity texture back.
    private func field(_ s: CopiesProbe, from: [Vector3], to: [Vector3],
                       renderer: MetalRenderer) throws -> [SIMD2<Float>]? {
        s.setup()
        s.offsets = from
        s.performDraw()
        let camera = try #require(s.drawer.camera3D)
        let previous = camera.projectionMatrix(aspect: 1) * camera.viewMatrix
        s.offsets = to
        s.performDraw()
        return renderer.debugVelocityReadback(s.drawer, width: 128, height: 128,
                                              previousViewProjection: previous)
    }

    private func at(_ field: [SIMD2<Float>], _ x: Int, _ y: Int) -> SIMD2<Float> { field[y * 128 + x] }
    private func isWritten(_ v: SIMD2<Float>) -> Bool { v.x > 0.5 * OLLIN_VELOCITY_NONE }

    @Test(.enabled(if: Snapshot.hasMetal))
    func eachCopyWritesItsOwnMotion() throws {
        guard let renderer = try makeRenderer() else { return }
        let still = [Vector3](repeating: .zero, count: 3)
        // The left copy moves right 10, the middle one holds, the right one drops
        // 6: previous minus current, in y-down pixels.
        let moved = [Vector3(10, 0, 0), .zero, Vector3(0, -6, 0)]
        let v = try #require(try field(CopiesProbe(), from: still, to: moved, renderer: renderer))
        let left = at(v, 64 - 40 + 10, 64), middle = at(v, 64, 64), right = at(v, 64 + 40, 64 + 6)
        #expect(isWritten(left) && isWritten(middle) && isWritten(right))
        #expect(simd_distance(left, SIMD2(-10, 0)) < 0.15, "left copy: \(left)")
        #expect(simd_length(middle) < 0.05, "a copy that held still writes zero: \(middle)")
        #expect(simd_distance(right, SIMD2(0, -6)) < 0.15, "right copy: \(right)")
        #expect(!isWritten(at(v, 8, 8)))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCopiesWriteWhatEachWouldAsAMoverOfItsOwn() throws {
        guard let renderer = try makeRenderer() else { return }
        let from = [Vector3(0, 0, 0), Vector3(-4, 2, 0), Vector3(3, 3, 0)]
        let to = [Vector3(7, -2, 0), Vector3(-4, 2, 0), Vector3(-5, 9, 0)]
        let instanced = try #require(try field(CopiesProbe(), from: from, to: to, renderer: renderer))
        let separate = CopiesProbe()
        separate.perCopy = true
        let own = try #require(try field(separate, from: from, to: to, renderer: renderer))
        var differing = 0, written = 0
        for i in instanced.indices {
            let a = instanced[i], b = own[i]
            if isWritten(a) != isWritten(b) { differing += 1; continue }
            guard isWritten(a) else { continue }
            written += 1
            if simd_distance(a, b) > 0.02 { differing += 1 }
        }
        #expect(written > 1000, "only \(written) texels written")
        #expect(differing == 0, "\(differing) texels differ from the per-copy movers")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anInstancedDrawHidesAMoverBehindIt() throws {
        guard let renderer = try makeRenderer() else { return }
        let s = CopiesProbe()
        s.wall = true
        s.plainMover = true
        let still = [Vector3](repeating: .zero, count: 3)
        let moved = [Vector3.zero, Vector3(4, 0, 0), .zero]
        let v = try #require(try field(s, from: still, to: moved, renderer: renderer))
        // The 40-unit wall spans pixels 44 to 84 and stands in front of the mover.
        #expect(!isWritten(at(v, 64, 64)), "the mover wrote through the instanced wall")
    }

    // MARK: In an export

    private func bytes(_ sketch: Sketch, frame: Int) throws -> [UInt8] {
        let image = try OllinApp.image(of: sketch, frame: frame)
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// Copies sliding right a few units a frame under motion blur.
    final class SlidingCopies: Sketch {
        var mode = 0   // 0 instanced inside withMotion, 1 instanced outside, 2 one mover a copy
        override var canvasSize: CanvasSize { .square(128) }
        let box = Mesh.box(width: 14, height: 14, depth: 2)
        override func draw() {
            background(.black)
            ortho(eye: Vector3(0, 0, 100), target: .zero, height: 128, near: 1, far: 200)
            motionBlur(shutter: 1)
            noLights()
            fill(.white)
            let shift = Double(frameCount) * 4
            let copies = (0 ..< 4).map { MeshInstance(position: Vector3(-50 + Double($0) * 30 + shift, 0, 0)) }
            switch mode {
            case 0: withMotion("copies") { drawMesh(box, instances: copies) }
            case 1: drawMesh(box, instances: copies)
            default:
                for (i, c) in copies.enumerated() {
                    withState { withMotion("copy-\(i)") { translate(c.position.x, 0, 0); drawMesh(box) } }
                }
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportStreaksTheCopiesAsItStreaksSeparateMovers() throws {
        func render(_ mode: Int) throws -> [UInt8] {
            let s = SlidingCopies()
            s.mode = mode
            return try bytes(s, frame: 6)
        }
        let streaked = try render(0), unstreaked = try render(1), separate = try render(2)
        func differing(_ a: [UInt8], _ b: [UInt8]) -> Int { zip(a, b).filter { abs(Int($0) - Int($1)) > 8 }.count }
        // The streaks separate movers lay down, against none at all, are the
        // yardstick: the copies have to lay down as many, in the same places.
        let own = differing(separate, unstreaked)
        #expect(own > 100, "the separate movers streaked only \(own) bytes")
        #expect(differing(streaked, unstreaked) * 10 >= own * 9, "the copies streak less than separate movers")
        let apart = differing(streaked, separate)
        #expect(apart * 20 < own, "\(apart) bytes differ from one mover a copy, against \(own) streaked")
        #expect(try render(0) == streaked, "two exports of one frame differ")
    }
}
