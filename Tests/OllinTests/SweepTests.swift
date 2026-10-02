import Foundation
import Testing
@testable import Ollin

/// The 3D path and what rides it: `Curve3D`'s frames (rotation-minimizing, by
/// double reflection) against the twist a curve's torsion predicts, a profile
/// swept along a path keeping its shape at every station, the strip between
/// two lines exact rung by rung, and `Pace` walking a curve at one speed or a
/// strip at one rate of area. GPU-free.
struct SweepTests {

    // MARK: - Frames

    /// The angle of `normal` about `tangent`, measured from `from` toward
    /// `tangent × from`.
    private func angle(of normal: Vector3, from: Vector3, about tangent: Vector3) -> Double {
        atan2(normal.dot(tangent.cross(from)), normal.dot(from))
    }

    /// The difference of two angles folded into `-π...π`.
    private func wrapped(_ a: Double) -> Double {
        atan2(sin(a), cos(a))
    }

    /// A rotation-minimizing frame turns against the curve's own (Frenet)
    /// frame at minus the torsion: on a helix of radius `a` and pitch `2πb`,
    /// one turn leaves it `2πb / √(a² + b²)` behind the Frenet normal, which
    /// points at the axis the whole way.
    @Test func helixFramesFallBehindByTheTorsion() {
        let a = 1.0, b = 0.6
        let perTurn = 256
        let h = Double.tau / Double(perTurn)
        // Half a turn of run-up at each end, so the two places compared are
        // read with centered tangents.
        let points = (0...(perTurn * 2)).map { k -> Vector3 in
            let t = -Double.pi + Double(k) * h
            return Vector3(a * cos(t), a * sin(t), b * t)
        }
        let curve = Curve3D(points)
        func frenet(_ t: Double) -> Vector3 { Vector3(-cos(t), -sin(t), 0) }
        let start = curve.frames[perTurn / 2], end = curve.frames[perTurn / 2 + perTurn]
        let fell = angle(of: end.normal, from: frenet(.tau), about: end.tangent)
            - angle(of: start.normal, from: frenet(0), about: start.tangent)
        let expected = -Double.tau * b / (a * a + b * b).squareRoot()
        #expect(abs(wrapped(fell - expected)) < 1e-4, "fell \(fell), expected \(expected)")
    }

    /// The (2, 3) torus knot's derivatives, written out, for its torsion.
    private func knotDerivatives(_ t: Double) -> (Vector3, Vector3, Vector3) {
        let p = 2.0, q = 3.0, big = 1.0, small = 0.4
        let u = p * t, w = q * t
        let rho = big + small * cos(w)
        let rho1 = -small * q * sin(w), rho2 = -small * q * q * cos(w), rho3 = small * q * q * q * sin(w)
        let cu = cos(u), su = sin(u)
        let d1 = Vector3(rho1 * cu - rho * p * su, rho1 * su + rho * p * cu, small * q * cos(w))
        let d2 = Vector3(rho2 * cu - 2 * rho1 * p * su - rho * p * p * cu,
                         rho2 * su + 2 * rho1 * p * cu - rho * p * p * su,
                         -small * q * q * sin(w))
        let d3 = Vector3(rho3 * cu - 3 * rho2 * p * su - 3 * rho1 * p * p * cu + rho * p * p * p * su,
                         rho3 * su + 3 * rho2 * p * cu - 3 * rho1 * p * p * su - rho * p * p * p * cu,
                         -small * q * q * q * cos(w))
        return (d1, d2, d3)
    }

    private func knot(_ t: Double) -> Vector3 {
        let rho = 1 + 0.4 * cos(3 * t)
        return Vector3(rho * cos(2 * t), rho * sin(2 * t), 0.4 * sin(3 * t))
    }

    /// Carried once round a closed curve, a rotation-minimizing frame comes
    /// back turned by minus the curve's total torsion (the Frenet frame closes
    /// up, and the two part at the torsion's rate). The knot's torsion is
    /// integrated from its exact derivatives; the frames' turn is read off an
    /// open run of the same points a little past one lap.
    @Test func closedKnotFramesComeBackTurnedByTheTotalTorsion() {
        // ∫ τ ds = ∫ (r' × r'') · r''' / |r' × r''|² · |r'| dt, by Simpson.
        let steps = 200_000
        var torsion = 0.0
        for k in 0...steps {
            let t = Double.tau * Double(k) / Double(steps)
            let (d1, d2, d3) = knotDerivatives(t)
            let c = d1.cross(d2)
            let f = c.dot(d3) / c.lengthSquared * d1.length
            let weight = (k == 0 || k == steps) ? 1.0 : (k % 2 == 1 ? 4.0 : 2.0)
            torsion += weight * f
        }
        torsion *= Double.tau / Double(steps) / 3

        let lap = 2048
        let h = Double.tau / Double(lap)
        let points = (-16...(lap + 16)).map { knot(Double($0) * h) }
        let open = Curve3D(points)
        let first = open.frames[16], again = open.frames[16 + lap]
        let turned = angle(of: again.normal, from: first.normal, about: first.tangent)
        #expect(abs(wrapped(turned + torsion)) < 1e-4, "turned \(turned), total torsion \(torsion)")

        // The closed curve spreads exactly that turn back out along its length:
        // against the open run's frames (which never unwind), each of its
        // frames is turned back by the share of the length walked to it, so
        // the turn grows at one rate per unit length and the last step leads
        // into the first frame with no seam.
        let loop = Curve3D((0..<lap).map { knot(Double($0) * h) }, closed: true)
        let offset = angle(of: loop.frames[0].normal, from: first.normal, about: first.tangent)
        for i in 0..<lap {
            let f = open.frames[16 + i]
            let unwound = angle(of: loop.frames[i].normal, from: f.normal, about: f.tangent) - offset
            let want = -turned * loop.walked[i] / loop.length
            #expect(abs(wrapped(unwound - want)) < 1e-9, "point \(i): unwound \(unwound), want \(want)")
        }
    }

    /// The frames are unit length and square to each other, `binormal` is
    /// `tangent × normal`, and `rotation` turns x, y, z onto them.
    @Test func framesAreOrthonormalAndTheirRotationMatches() {
        let curve = Curve3D(curveThrough: [Vector3(0, 0, 0), Vector3(1, 2, 0), Vector3(3, 1, 2),
                                           Vector3(2, -1, 3), Vector3(-1, 0, 1)], closed: true)
        for f in curve.frames {
            #expect(abs(f.tangent.length - 1) < 1e-12)
            #expect(abs(f.normal.length - 1) < 1e-12)
            #expect(abs(f.tangent.dot(f.normal)) < 1e-12)
            #expect((f.tangent.cross(f.normal) - f.binormal).length < 1e-12)
            #expect((Vector3.unitX.rotated(by: f.rotation) - f.normal).length < 1e-12)
            #expect((Vector3.unitY.rotated(by: f.rotation) - f.binormal).length < 1e-12)
            #expect((Vector3.unitZ.rotated(by: f.rotation) - f.tangent).length < 1e-12)
        }
    }

    /// The first frame stands upright: along +z it is the extrusion's own
    /// axes, and straight up it keeps x as the normal.
    @Test func theFirstFrameStandsUpright() {
        let along = Curve3D([Vector3(0, 0, 0), Vector3(0, 0, 1)]).frames[0]
        #expect((along.normal - .unitX).length < 1e-12)
        #expect((along.binormal - .unitY).length < 1e-12)
        let up = Curve3D([Vector3(0, 0, 0), Vector3(0, 1, 0)]).frames[0]
        #expect((up.normal - .unitX).length < 1e-12)
        #expect((up.binormal - Vector3(0, 0, -1)).length < 1e-12)
        let leaning = Curve3D([Vector3(0, 0, 0), Vector3(1, 0.5, 0.2)]).frames[0]
        #expect(leaning.binormal.y > 0.8, "the binormal leans toward up")
    }

    /// `point(at:)` walks by length, clamping an open path and wrapping a
    /// closed one; `frame(at:)` lands on a point's own frame there and turns
    /// steadily between.
    @Test func walkingAPathByLength() {
        let square = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
        let open = Curve3D(square)
        #expect(open.length == 3)
        #expect((open.point(at: 0.5) - Vector3(1, 0.5, 0)).length < 1e-12)
        #expect((open.point(at: 2) - Vector3(0, 1, 0)).length < 1e-12)
        #expect((open.point(at: -1) - .zero).length < 1e-12)
        let loop = Curve3D(square, closed: true)
        #expect(loop.length == 4)
        #expect((loop.point(at: 0.875) - Vector3(0, 0.5, 0)).length < 1e-12)
        #expect((loop.point(at: 1.375) - Vector3(1, 0.5, 0)).length < 1e-12)
        #expect((loop.point(at: -0.125) - Vector3(0, 0.5, 0)).length < 1e-12)
        #expect(loop.frame(at: 0.25) == loop.frames[1])
        let between = loop.frame(at: 0.125)
        #expect((between.position - Vector3(0.5, 0, 0)).length < 1e-12)
        #expect(abs(between.tangent.length - 1) < 1e-12)
        #expect(abs(between.tangent.dot(between.normal)) < 1e-12)
    }

    /// A smooth path passes through every anchor.
    @Test func aSmoothPathPassesThroughItsAnchors() {
        let anchors = [Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(3, 3, 1), Vector3(1, 4, 2)]
        for closed in [false, true] {
            let curve = Curve3D(curveThrough: anchors, closed: closed, segments: 12)
            for a in anchors {
                #expect(curve.points.contains { ($0 - a).length < 1e-12 }, "\(a) not on the path")
            }
            #expect(curve.points.count > anchors.count * 6)
        }
    }

    /// Respacing a path puts its points an even step apart along the walk,
    /// keeps an open path's ends, and leaves a closed one's closing step no
    /// longer than the rest.
    @Test func respacingAPathEvensItsSteps() {
        let bent = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 3, 0), Vector3(1, 3, 2)]
        let open = Curve3D(bent).resampled(spacing: 0.25)
        #expect(open.points.first == bent.first && open.points.last == bent.last)
        // Corners are cut, so a step measured straight is at most the spacing;
        // measured along the old path, every step but the last is exactly it.
        let original = Curve3D(bent)
        for i in 1..<(open.points.count - 1) {
            let f = Double(i) * 0.25 / original.length
            #expect((open.points[i] - original.point(at: f)).length < 1e-12)
        }
        let loop = Curve3D(bent, closed: true).resampled(spacing: 0.3)
        #expect(loop.isClosed)
        let closing = (loop.points[0] - loop.points[loop.points.count - 1]).length
        #expect(closing <= 0.3 + 1e-12)
        #expect(Curve3D(bent).resampled(spacing: 0) == Curve3D(bent))
    }

    /// `Mesh.tube(along:)` rides the shared frames: each ring's first vertex
    /// leaves the path along that point's normal, and every ring holds
    /// `sides + 1` vertices.
    @Test func theTubeRidesTheSharedFrames() {
        let path = (0..<40).map { k -> Vector3 in
            let t = Double(k) * 0.2
            return Vector3(cos(t), sin(t), 0.3 * t)
        }
        let tube = Mesh.tube(along: path, radius: 0.1, sides: 8)
        #expect(tube.positions.count == path.count * 9)
        #expect(tube.indices.count == (path.count - 1) * 8 * 6)
        let curve = Curve3D(path, closed: false, startNormal: { t in
            t.cross(abs(t.dot(.unitY)) > 0.99 ? .unitX : .unitY).normalized
        })
        for i in path.indices {
            let ring = tube.positions[i * 9]
            #expect(((ring - path[i]) / 0.1 - curve.frames[i].normal).length < 1e-12)
        }
    }

    // MARK: - Sweeps

    /// A square swept along a bending, rising path keeps its shape at every
    /// station: the four corners the same distances apart, square to the path,
    /// and centered on it. Scaled and turned, they are the square scaled and
    /// turned by exactly what `scale` and `twist` said for that station.
    @Test func aSweptSquareKeepsItsShapeAtEveryStation() {
        let square = Profile.rectangle(width: 0.4, height: 0.2)
        let path = Curve3D(curveThrough: [Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(3, 3, 2),
                                          Vector3(1, 4, 3), Vector3(-1, 3, 1)], segments: 10)
        let scale: (Double) -> Double = { 1 - 0.6 * $0 }
        let twist: (Double) -> Double = { 1.3 * $0 }
        let mesh = Mesh.sweep(square, along: path, scale: scale, twist: twist, capped: false)
        // Every corner is sharp, so each has two columns, one for each side;
        // the first corner's two are the seam's opening and closing columns.
        let width = 8
        #expect(mesh.positions.count == path.points.count * width)
        for (i, frame) in path.frames.enumerated() {
            let fraction = path.walked[i] / path.length
            let s = scale(fraction), c = cos(twist(fraction)), sn = sin(twist(fraction))
            for (j, corner) in square.enumerated() {
                let column = j == 0 ? 0 : 2 * j - 1
                let p = mesh.positions[i * width + column]
                let local = Vector2((corner.x * c - corner.y * sn) * s, (corner.x * sn + corner.y * c) * s)
                #expect((p - frame.point(local)).length < 1e-12)
                #expect(abs((p - frame.position).dot(frame.tangent)) < 1e-12)
            }
            // Congruent: the corners' distances are the square's, scaled.
            let corners = (0..<4).map { mesh.positions[i * width + ($0 == 0 ? 0 : 2 * $0 - 1)] }
            for a in 0..<4 {
                for b in (a + 1)..<4 {
                    let want = (square[a] - square[b]).length * s
                    #expect(abs((corners[a] - corners[b]).length - want) < 1e-12)
                }
            }
            // The uvs: `v` along the path, `u` round the outline.
            #expect(abs(mesh.uvs[i * width].y - fraction) < 1e-12)
            #expect(mesh.uvs[i * width].x == 0 && mesh.uvs[i * width + 7].x == 1)
        }
    }

    /// Swept straight along +z, a shape with a hole is its extrusion: the same
    /// walls with the same normals, the same caps, the same triangle count.
    @Test func aStraightSweepIsAnExtrusion() {
        let outer = Profile.star(points: 5, outerRadius: 1, innerRadius: 0.5)
        let hole = Array(Profile.rectangle(width: 0.3, height: 0.3).reversed())
        let shape = Shape(outer: outer, holes: [hole])
        let swept = Mesh.sweep(shape, along: Curve3D([Vector3(0, 0, -0.25), Vector3(0, 0, 0.25)]))
        let pushed = Mesh.extrude(shape, depth: 0.5)
        #expect(swept.triangleCount == pushed.triangleCount)
        for (p, n) in zip(swept.positions, swept.normals) {
            let match = zip(pushed.positions, pushed.normals).contains {
                ($0.0 - p).length < 1e-12 && ($0.1 - n).length < 1e-9
            }
            #expect(match, "no extruded vertex at \(p) facing \(n)")
        }
    }

    /// The walls face out of the solid whichever way each outline was drawn:
    /// out from the path on the outer outline, in toward it (into the hole) on
    /// the inner one.
    @Test func wallsFaceOutWhicheverWayTheOutlinesRun() {
        let path = Curve3D(curveThrough: [Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(3, 1, 0)])
        let ring = Profile.ellipse(radiusX: 0.2, radiusY: 0.2, segments: 24)
        let small = Profile.ellipse(radiusX: 0.1, radiusY: 0.1, segments: 24)
        for outerReversed in [false, true] {
            for holeReversed in [false, true] {
                let shape = Shape(outer: outerReversed ? ring.reversed() : ring,
                                  holes: [holeReversed ? small.reversed() : small])
                let mesh = Mesh.sweep(shape, along: path, capped: false)
                // Both outlines are smooth, 24 points and the seam: 25 columns
                // a station, the outer outline's stations first.
                let stations = path.points.count
                #expect(mesh.positions.count == 2 * 25 * stations)
                for (k, p) in mesh.positions.enumerated() {
                    let isOuter = k < 25 * stations
                    let station = path.points[(k % (25 * stations)) / 25]
                    let facing = mesh.normals[k].dot(p - station)
                    #expect(isOuter ? facing > 0 : facing < 0,
                            "outer reversed \(outerReversed), hole reversed \(holeReversed): a wall faces in")
                }
            }
        }
    }

    /// A round outline sweeps smooth (one column a point, normals leaving the
    /// path), and its corners only split past 30°.
    @Test func roundOutlinesSweepSmoothAndSharpOnesKeepTheirEdges() {
        let path = Curve3D([Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, 2)])
        let round = Mesh.sweep(Profile.ellipse(radiusX: 1, radiusY: 1, segments: 24), along: path)
        // 24 points plus the seam's closing column, three stations, then caps.
        #expect(round.uvs.count == round.positions.count)
        let wall = Array(round.positions.prefix(25 * 3))
        for (k, p) in wall.enumerated() {
            let radial = Vector3(p.x, p.y, 0).normalized
            #expect((round.normals[k] - radial).length < 1e-9)
        }
        let hexagon = Mesh.sweep(Profile.polygon(sides: 6, radius: 1), along: path, capped: false)
        #expect(hexagon.positions.count == 6 * 2 * 3)
        let dodecagon = Mesh.sweep(Profile.polygon(sides: 12, radius: 1), along: path, capped: false)
        #expect(dodecagon.positions.count == 13 * 3)
    }

    // MARK: - Strips

    /// Rung `i` joins `first[i]` to `second[i]`; each rung's color paints both
    /// its ends; `u` counts rungs and `v` crosses them; the normals are the
    /// lines' direction crossed with the rung, and the triangles face the
    /// same way.
    @Test func aStripsRungsColorsAndUVsAreExact() {
        let n = 30
        let first = (0..<n).map { k -> Vector3 in
            let t = Double(k) / Double(n) * .tau
            return Vector3(cos(t), sin(t), 0.2 * sin(3 * t))
        }
        let second = (0..<n).map { k -> Vector3 in
            let t = Double(k) / Double(n) * .tau
            return Vector3(1.5 * cos(t + 0.3), 1.5 * sin(t + 0.3), 0.5 + 0.3 * cos(2 * t))
        }
        let colors = (0..<n).map { Color(hue: Double($0) / Double(n), saturation: 1, brightness: 1) }
        for closed in [false, true] {
            let strip = Mesh.strip(between: first, and: second, colors: colors, closed: closed)
            let rows = closed ? n + 1 : n
            #expect(strip.positions.count == rows * 2)
            #expect(strip.triangleCount == (rows - 1) * 2)
            for row in 0..<rows {
                let i = row % n
                #expect(strip.positions[row * 2] == first[i])
                #expect(strip.positions[row * 2 + 1] == second[i])
                #expect(strip.colors[row * 2] == colors[i] && strip.colors[row * 2 + 1] == colors[i])
                let u = Double(row) / Double(rows - 1)
                #expect(strip.uvs[row * 2] == Vector2(u, 0) && strip.uvs[row * 2 + 1] == Vector2(u, 1))
                let rung = second[i] - first[i]
                let along: Vector3 = closed
                    ? first[(i + 1) % n] - first[(i - 1 + n) % n]
                    : first[min(i + 1, n - 1)] - first[max(i - 1, 0)]
                #expect((strip.normals[row * 2] - along.cross(rung).normalized).length < 1e-12)
            }
            var k = 0
            while k + 2 < strip.indices.count {
                let i0 = Int(strip.indices[k]), i1 = Int(strip.indices[k + 1]), i2 = Int(strip.indices[k + 2])
                let face = (strip.positions[i1] - strip.positions[i0]).cross(strip.positions[i2] - strip.positions[i0])
                let shaded = strip.normals[i0] + strip.normals[i1] + strip.normals[i2]
                #expect(face.dot(shaded) > 0, "a face wound against its normals")
                k += 3
            }
        }
        // Colors that do not count the rungs are left off.
        #expect(Mesh.strip(between: first, and: second, colors: [.red]).colors.isEmpty)
    }

    /// Lines of different counts: the longer sets the rungs, and each meets
    /// the other at the same fraction of its length; one point makes a fan.
    @Test func linesOfDifferentCountsMeetByLength() {
        let curved = (0...20).map { k -> Vector3 in
            let t = Double(k) / 20
            return Vector3(t * 4, sin(t * 3), 0)
        }
        let straight = [Vector3(0, 2, 0), Vector3(4, 2, 1)]
        let strip = Mesh.strip(between: curved, and: straight)
        #expect(strip.positions.count == curved.count * 2)
        var walked = [0.0]
        for i in 1..<curved.count { walked.append(walked[i - 1] + (curved[i] - curved[i - 1]).length) }
        for i in curved.indices {
            let want = straight[0].lerp(to: straight[1], walked[i] / walked[curved.count - 1])
            #expect((strip.positions[i * 2 + 1] - want).length < 1e-12)
        }
        let fan = Mesh.strip(between: [Vector3.zero], and: curved)
        #expect(fan.positions.count == curved.count * 2)
        #expect(fan.positions.enumerated().allSatisfy { $0.offset % 2 == 1 || $0.element == .zero })
    }

    // MARK: - Pace

    /// The cardioid's length has a closed form, `s(t) = 4 sin(t/2)` up to the
    /// cusp and `8 - 4 sin(t/2)` after, so where a share lands can be checked
    /// exactly, the cusp (where the curve stops dead) included.
    @Test func aCardioidIsWalkedAtOneSpeed() {
        let pace = Pace(byLengthOf: { t in Vector2((1 + cos(t)) * cos(t), (1 + cos(t)) * sin(t)) },
                        period: .tau)
        #expect(abs(pace.total - 8) < 1e-9)
        for k in 0..<64 {
            let share = Double(k) / 64
            let t = pace.parameter(at: share)
            let s = t <= .pi ? 4 * sin(t / 2) : 8 - 4 * sin(t / 2)
            #expect(abs(s / 8 - share) < 1e-9, "share \(share) landed at \(s / 8)")
            #expect(abs(pace.fraction(at: t) - share) < 1e-9)
        }
    }

    /// Even shares of a 3D Lissajous figure are even lengths, each checked by
    /// integrating the figure's exact speed between them.
    @Test func aLissajousStepsAreEqualByLength() {
        func curve(_ t: Double) -> Vector3 { Vector3(sin(3 * t), sin(4 * t + 0.5), 0.6 * cos(5 * t)) }
        func speed(_ t: Double) -> Double {
            Vector3(3 * cos(3 * t), 4 * cos(4 * t + 0.5), -3 * sin(5 * t)).length
        }
        let pace = Pace(byLengthOf: curve, period: .tau)
        let steps = 48
        let parameters = (0...steps).map { pace.parameter(at: Double($0) / Double(steps)) }
        #expect(abs(parameters[steps] - .tau) < 1e-12)
        for k in 0..<steps {
            // Simpson over the step, fine enough to be exact to rounding.
            let a = parameters[k], b = parameters[k + 1], m = 2000
            var sum = 0.0
            for j in 0...m {
                let w = (j == 0 || j == m) ? 1.0 : (j % 2 == 1 ? 4.0 : 2.0)
                sum += w * speed(a + (b - a) * Double(j) / Double(m))
            }
            let length = sum * (b - a) / Double(m) / 3
            #expect(abs(length / (pace.total / Double(steps)) - 1) < 1e-8, "step \(k): \(length)")
        }
    }

    /// A periodic pace keeps counting periods, so a loop never jumps; one
    /// over a range clamps to it; a curve that stands still paces evenly.
    @Test func periodsCountOnAndRangesClamp() {
        let figure: (Double) -> Vector2 = { Vector2(sin(2 * $0), sin(3 * $0)) }
        let loop = Pace(byLengthOf: figure, period: .tau)
        for share in [0.0, 0.2, 0.55, 0.9] {
            #expect(abs(loop.parameter(at: share + 1) - (loop.parameter(at: share) + .tau)) < 1e-12)
            #expect(abs(loop.parameter(at: share - 2) - (loop.parameter(at: share) - 2 * .tau)) < 1e-12)
            let t = loop.parameter(at: share)
            #expect(abs(loop.fraction(at: t + 3 * .tau) - (share + 3)) < 1e-9)
        }
        let span = Pace(byLengthOf: figure, over: 1 ... 2)
        #expect(span.parameter(at: 1.5) == 2 && span.parameter(at: -1) == 1)
        #expect(span.fraction(at: 5) == 1 && span.fraction(at: 0) == 0)
        let still = Pace(byLengthOf: { _ in Vector3(1, 2, 3) }, period: 4)
        #expect(still.total == 0 && still.parameter(at: 0.25) == 1)
        // 2D and 3D read the same figure the same way.
        let lifted = Pace(byLengthOf: { Vector3(sin(2 * $0), sin(3 * $0), 0) }, period: .tau)
        #expect(abs(lifted.parameter(at: 0.3) - loop.parameter(at: 0.3)) < 1e-12)
    }

    /// A strip fanned out from a point sweeps the polar area `½ ∫ ρ² dt`, so
    /// on the limaçon `ρ = 2 + cos t` the share swept by `t` has a closed form,
    /// and the pace inverts it.
    @Test func theAreaPaceMatchesThePolarArea() {
        let pace = Pace(byAreaBetween: { _ in .zero },
                        and: { t in Vector3(cos(t), sin(t), 0) * (2 + cos(t)) },
                        period: .tau)
        #expect(abs(pace.total - 4.5 * .pi) < 1e-9)
        for k in 0..<40 {
            let share = Double(k) / 40
            let t = pace.parameter(at: share)
            let swept = (4.5 * t + 4 * sin(t) + sin(2 * t) / 4) / (9 * .pi)
            #expect(abs(swept - share) < 1e-9, "share \(share) swept \(swept)")
        }
    }

    /// A strip that twists through itself (a band between two circles turning
    /// opposite ways, so its surface turns edge-on along whole rungs) sweeps
    /// the area a brute-force integral of the surface gives.
    @Test func aTwistedStripsAreaMatchesTheSurfaceIntegral() {
        func a(_ t: Double) -> Vector3 { Vector3(cos(t), sin(t), -0.5) }
        func b(_ t: Double) -> Vector3 { Vector3(0.7 * cos(-2 * t), 0.7 * sin(-2 * t), 0.5) }
        func da(_ t: Double) -> Vector3 { Vector3(-sin(t), cos(t), 0) }
        func db(_ t: Double) -> Vector3 { Vector3(1.4 * sin(-2 * t), -1.4 * cos(-2 * t), 0) }
        let pace = Pace(byAreaBetween: a, and: b, period: .tau)
        // Midpoint sums of |r_t × r_v| over a fine grid.
        let nt = 4000, nv = 400
        var area = 0.0
        for i in 0..<nt {
            let t = (Double(i) + 0.5) / Double(nt) * .tau
            let w = b(t) - a(t)
            for j in 0..<nv {
                let v = (Double(j) + 0.5) / Double(nv)
                area += (da(t) + (db(t) - da(t)) * v).cross(w).length
            }
        }
        area *= .tau / Double(nt) / Double(nv)
        #expect(abs(pace.total / area - 1) < 1e-5, "pace \(pace.total), surface \(area)")
    }
}
