@testable import Ollin
import Testing
import Foundation

/// The gesture marks' members in space: the tube whose section at every station
/// is the flat mark's width there, the solids at the flat chain's stations, and
/// the rule both keep with the flat families, that a growing gesture never moves
/// what it has placed.
struct GestureMarks3DTests {

    /// A tapering S-curve, the shape the flat families are tried on.
    static func gesture(count: Int = 60) -> GestureMark {
        let points = (0 ..< count).map { i -> Vector2 in
            let t = Double(i) / Double(count - 1)
            return Vector2(100 + 600 * t, 300 + 120 * sin(t * 2.6 * .pi))
        }
        let widths = (0 ..< count).map { 60 - 36 * Double($0) / Double(count - 1) }
        return GestureMark(points: points, widths: widths)
    }

    // MARK: The tube

    @Test func theTubesSectionIsTheMarksWidth() {
        // Every ring's vertices sit half the width out from the path at that
        // station, so the tube is as thick as the flat mark wherever it is cut.
        let mark = Self.gesture()
        let tube = mark.tube(sides: 12)
        let ring = 13
        #expect(tube.positions.count % ring == 0)
        let rings = tube.positions.count / ring
        #expect(rings > 100)
        for k in stride(from: 0, to: rings, by: 7) {
            let s = min(Double(k) * GestureSpine.step, mark.length)
            let frame = mark.spine.frame(at: s)
            let center = Vector3(frame.position.x, -frame.position.y, 0)   // the canvas's down is -y
            for j in 0 ..< ring {
                let radius = (tube.positions[k * ring + j] - center).length
                #expect(abs(radius - frame.halfWidth) < 1e-6, "ring \(k) vertex \(j): \(radius) against \(frame.halfWidth)")
            }
        }
        // The last ring is at the gesture's end, at its lifted width.
        let last = mark.spine.frame(at: mark.length)
        let tip = Vector3(last.position.x, -last.position.y, 0)
        #expect(abs((tube.positions[tube.positions.count - 1] - tip).length - last.halfWidth) < 1e-6)
    }

    @Test func theTubeLiesInThePlaneAndCarriesItsUVs() {
        let mark = Self.gesture()
        let tube = mark.tube(sides: 8)
        // Rings are circles in the plane spanned by the path's normal and z: a
        // ring's first vertex is in the plane and its quarter vertex straight up.
        let ring = 9
        for k in stride(from: 0, to: tube.positions.count / ring, by: 11) {
            #expect(abs(tube.positions[k * ring].z) < 1e-9)
            let up = tube.positions[k * ring + 2] - tube.positions[k * ring]
            #expect(up.z > 0)
        }
        // u runs round each ring from 0 to 1; v along the path in widths, never
        // backwards, and reaching the gesture's length in widths at the last ring.
        #expect(tube.uvs.count == tube.positions.count)
        var lastV = -1.0
        for k in 0 ..< tube.positions.count / ring {
            #expect(tube.uvs[k * ring].x == 0 && abs(tube.uvs[k * ring + 8].x - 1) < 1e-12)
            let v = tube.uvs[k * ring].y
            #expect(v >= lastV)
            lastV = v
        }
        #expect(abs(lastV - mark.spine.widthsAlong(mark.length)) < 1e-9)
        #expect(tube.normals.count == tube.positions.count)
        #expect(tube.indices.count == (tube.positions.count / ring - 1) * 8 * 6)
    }

    @Test func aWobbleWindsRoundThePath() {
        // With a wobble the ring centers circle the path at that many half widths
        // out, once every `wavelength` widths; straight, they sit on it.
        let mark = Self.gesture()
        let straight = mark.tube(sides: 8)
        let wound = mark.tube(sides: 8, wobble: 0.5, wavelength: 3)
        let ring = 9
        var offPath = 0
        for k in 0 ..< straight.positions.count / ring {
            var cs = Vector3.zero, cw = Vector3.zero
            for j in 0 ..< 8 { cs = cs + straight.positions[k * ring + j]; cw = cw + wound.positions[k * ring + j] }
            cs = cs / 8; cw = cw / 8
            let s = min(Double(k) * GestureSpine.step, mark.length)
            let frame = mark.spine.frame(at: s)
            #expect((cs - Vector3(frame.position.x, -frame.position.y, 0)).length < 1e-6)
            let reach = (cw - cs).length
            #expect(abs(reach - 0.5 * frame.halfWidth) < 1e-6, "ring \(k) reaches \(reach) for a half width of \(frame.halfWidth)")
            if reach > 1 { offPath += 1 }
        }
        #expect(offPath > 50)
        // The coil turns: a ring a quarter wavelength on is a quarter turn round.
        let quarter = mark.spine.distance(atWidths: 0.75)
        let k = Int((quarter / GestureSpine.step).rounded())
        let c0 = (0 ..< 8).reduce(Vector3.zero) { $0 + wound.positions[$1] } / 8
        let f0 = mark.spine.frame(at: 0)
        #expect(abs(c0.z) < 1e-6 && (c0 - Vector3(f0.position.x, -f0.position.y, 0)).length > 1)
        let ck = (0 ..< 8).reduce(Vector3.zero) { $0 + wound.positions[k * ring + $1] } / 8
        #expect(abs(ck.z) > 1)
    }

    // MARK: The solids

    @Test func theSolidsStandAtTheChainsStations() {
        // The same seed: a solid where every square of the chain is, as big as
        // its side, turned as it is turned.
        let mark = Self.gesture()
        let chain = mark.chain(spacing: 0.9, roundness: 0, seed: 4)
        let solids = mark.solids(spacing: 0.9, seed: 4)
        #expect(chain.count == solids.count && chain.count > 10)
        for (square, solid) in zip(chain, solids) {
            let center = square.contour.points.reduce(Vector2.zero, +) / Double(square.contour.points.count)
            #expect((Vector3(center.x, -center.y, 0) - solid.position).length < 1e-6)
            // A square with no rounding is four corners: its side is a corner to
            // the next, and the solid's scale is that side on every axis.
            let corners = square.contour.points
            let side = (corners[1] - corners[0]).length
            #expect(abs(solid.scale.x - side) < 1e-6 && solid.scale.x == solid.scale.y && solid.scale.y == solid.scale.z)
            // The turn: the square's first edge runs along the solid's turned x.
            let edge = (corners[1] - corners[0]) / side
            let turned = Vector3(1, 0, 0).rotated(by: solid.rotation)
            #expect(abs(abs(edge.dot(Vector2(turned.x, -turned.y))) - 1) < 1e-6)   // read back on the canvas
            #expect(abs(turned.z) < 1e-9)
        }
    }

    @Test func theSeedSpreadsTheSolids() {
        let mark = Self.gesture()
        let a = mark.solids(seed: 1), b = mark.solids(seed: 2)
        #expect(a.count > 10)
        #expect(zip(a, b).contains { $0.scale != $1.scale })
        #expect(mark.solids(seed: 1).map(\.scale) == a.map(\.scale))
    }

    // MARK: Growing

    @Test func aGrowingGestureNeverMovesWhatItPlaced() {
        // Point by point, every ring and every solid but the last stays where the
        // shorter gesture put it.
        let whole = Self.gesture(count: 48)
        let ring = 9
        for count in stride(from: 8, through: 48, by: 5) {
            let shorter = GestureMark(points: Array(whole.points.prefix(count)), widths: Array(whole.widths.prefix(count)))
            let longer = GestureMark(points: Array(whole.points.prefix(min(count + 3, 48))),
                                     widths: Array(whole.widths.prefix(min(count + 3, 48))))
            let ts = shorter.tube(sides: 8), tl = longer.tube(sides: 8)
            let keep = ts.positions.count / ring - 1
            #expect(tl.positions.count >= ts.positions.count)
            for i in 0 ..< keep * ring {
                #expect((ts.positions[i] - tl.positions[i]).length < 1e-9, "ring \(i / ring) moved at \(count) points")
                if (ts.positions[i] - tl.positions[i]).length >= 1e-9 { break }
            }
            let ss = shorter.solids(seed: 3), sl = longer.solids(seed: 3)
            for (a, b) in zip(ss.dropLast(), sl) where a.position != b.position || a.scale != b.scale {
                Issue.record("a solid moved at \(count) points: \(a.position) to \(b.position)")
                break
            }
        }
    }

    // MARK: A layer as a feed

    @Test @MainActor func aLayerIsAFeed() throws {
        // A layer stands as a feed: its frame is its live image at its own size,
        // so an environment can be built from it.
        final class Probe: Sketch {
            var fed: RenderTarget?
            var size: Vector2?
            override var canvasSize: CanvasSize { .square(64) }
            override func draw() {
                let layer = makeRenderTarget()
                withTarget(layer) { background(.red) }
                size = layer.frameSize
                fed = layer
                #expect(layer.frame != nil && layer.frame?.width == 64)
                environment(.feed(layer))
                camera(.perspective(eye: Vector3(0, 0, 4)))
                material(.polishedMetal)
                drawSphere(radius: 1)
            }
        }
        let probe = Probe()
        let image = try OllinApp.image(of: probe, frame: 2)
        #expect(image.width == 64)
        #expect(probe.size == Vector2(64, 64))
        #expect(probe.fed?.waitingMessage.hasPrefix("Waiting") == true)
        // The metal reflects the layer, not the placeholder sky: a red world makes
        // a red ball, where the sky would make a blue one. The bake runs after the
        // layer passes, so even the first frame reads the layer.
        let p = Pixels(image)
        let c = 32
        #expect(p.channel(0, c, c) > p.channel(2, c, c) + 40, "center \(p.channel(0, c, c)) red, \(p.channel(2, c, c)) blue")
        let first = Pixels(try OllinApp.image(of: Probe(), frame: 1))
        #expect(first.channel(0, c, c) > first.channel(2, c, c) + 40)
    }
}
