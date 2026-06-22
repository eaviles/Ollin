import Foundation

// Vector outlines for the analytic SDF shapes, for the SVG exporter (which has no
// access to the GPU fragment that normally evaluates them). The polygonal shapes
// build their corners directly; the curved ones are traced with marching squares
// over the *same* signed-distance functions the shader uses (ported to Swift in
// this file, mirroring ShaderShapes.metal), so the exported outline matches the render.
//
// All builders return points in the shape's *local* space, centered on the same
// point the draw call anchors at; the `Drawer` offsets them into user space and
// the CTM rides as the SVG element transform.

enum SDFOutline {

    // MARK: Polygonal shapes (exact)

    /// A regular n-gon, circumradius `radius`, one vertex pointing up (−y).
    static func ngon(radius: Double, sides: Int) -> [Vector2] {
        (0..<sides).map { k in
            let a = 2 * Double.pi * Double(k) / Double(sides)
            return Vector2(radius * sin(a), -radius * cos(a))
        }
    }

    /// A star, `points` tips at `outer`, valleys at `inner`, one tip pointing up.
    static func star(outer: Double, inner: Double, points: Int) -> [Vector2] {
        (0..<(2 * points)).map { j in
            let r = j % 2 == 0 ? outer : inner
            let a = Double.pi * Double(j) / Double(points)
            return Vector2(r * sin(a), -r * cos(a))
        }
    }

    /// An equilateral triangle, circumradius `radius`, point up; centroid at origin.
    static func triangleEquilateral(radius: Double) -> [Vector2] {
        let halfBase = radius * 0.8660254037844386   // r·√3/2
        return [Vector2(0, -radius),
                Vector2(halfBase, radius / 2),
                Vector2(-halfBase, radius / 2)]
    }

    /// An isosceles triangle, apex at origin, opening +y (down) by `height`.
    static func triangleIsosceles(base: Double, height: Double) -> [Vector2] {
        [Vector2(0, 0), Vector2(base / 2, height), Vector2(-base / 2, height)]
    }

    /// A rhombus with full diagonals `width`×`height` (sharp; corners via marching).
    static func rhombus(width: Double, height: Double) -> [Vector2] {
        [Vector2(width / 2, 0), Vector2(0, height / 2),
         Vector2(-width / 2, 0), Vector2(0, -height / 2)]
    }

    /// A plus-sign cross, `length` tip-to-tip both axes, arms `thickness` wide (sharp).
    static func cross(length: Double, thickness: Double) -> [Vector2] {
        let l = length / 2, w = min(thickness, length) / 2
        return [Vector2(-w, -l), Vector2(w, -l), Vector2(w, -w), Vector2(l, -w),
                Vector2(l, w), Vector2(w, w), Vector2(w, l), Vector2(-w, l),
                Vector2(-w, w), Vector2(-l, w), Vector2(-l, -w), Vector2(-w, -w)]
    }

    /// An isosceles trapezoid, `topWidth`/`bottomWidth` across, `height` tall.
    static func trapezoid(topWidth: Double, bottomWidth: Double, height: Double) -> [Vector2] {
        let he = height / 2
        return [Vector2(-topWidth / 2, -he), Vector2(topWidth / 2, -he),
                Vector2(bottomWidth / 2, he), Vector2(-bottomWidth / 2, he)]
    }

    /// A parallelogram, `width`×`height`, top edge sheared `skew` toward +x.
    static func parallelogram(width: Double, height: Double, skew: Double) -> [Vector2] {
        let wi = width / 2, he = height / 2
        return [Vector2(-wi + skew, -he), Vector2(wi + skew, -he),
                Vector2(wi - skew, he), Vector2(-wi - skew, he)]
    }

    /// A staircase of `steps`, each `stepWidth`×`stepHeight`, ascending to the right.
    static func stairs(stepWidth: Double, stepHeight: Double, steps: Int) -> [Vector2] {
        let n = steps
        let bx = stepWidth * Double(n), by = stepHeight * Double(n)
        var native: [Vector2] = [Vector2(0, 0), Vector2(bx, 0)]
        for i in stride(from: n - 1, through: 0, by: -1) {
            native.append(Vector2(Double(i + 1) * stepWidth, Double(i + 1) * stepHeight))
            native.append(Vector2(Double(i) * stepWidth, Double(i + 1) * stepHeight))
        }
        // Fragment recenter + Y-flip: screen = (ux − bx/2, by/2 − uy).
        return native.map { Vector2($0.x - bx / 2, by / 2 - $0.y) }
    }

    /// A closed circle outline, used for the ring's two contours and point dots.
    static func circle(radius: Double, segments: Int = 64) -> [Vector2] {
        (0..<segments).map { k in
            let a = 2 * Double.pi * Double(k) / Double(segments)
            return Vector2(radius * cos(a), radius * sin(a))
        }
    }

    // MARK: Point markers (exact)

    static func markerSquare(_ h: Double) -> [Vector2] {
        [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
    }

    static func markerDiamond(_ h: Double) -> [Vector2] {
        [Vector2(h, 0), Vector2(0, h), Vector2(-h, 0), Vector2(0, -h)]
    }

    /// The filled plus marker: arms reach ±h, half-width `t` (= 0.28·h on the point path).
    static func markerCross(_ h: Double, _ t: Double) -> [Vector2] {
        cross(length: 2 * h, thickness: 2 * t)
    }

    /// The X marker: the sharp plus (arm half-length h√2 − t, half-width t) rotated −45°.
    static func markerX(_ h: Double, _ t: Double) -> [Vector2] {
        let plus = cross(length: 2 * (h * 1.4142135623730951 - t), thickness: 2 * t)
        let k = 0.7071067811865476
        return plus.map { Vector2($0.x * k + $0.y * k, -$0.x * k + $0.y * k) }
    }

    // MARK: Curved shapes (marching squares over the ported SDF)

    static func rhombusRounded(width: Double, height: Double, cornerRadius r: Double) -> [Vector2] {
        let b = Vector2(width / 2, height / 2)
        let core = Vector2(max(b.x - r, 1e-4), max(b.y - r, 1e-4))
        return trace(halfX: width / 2, halfY: height / 2) { sdRhombus($0, core) - r }
    }

    static func crossRounded(length: Double, thickness: Double, cornerRadius r: Double) -> [Vector2] {
        let l = length / 2, w = min(thickness, length) / 2
        return trace(halfX: l, halfY: l) {
            min(sdRoundBox($0, Vector2(l, w), r), sdRoundBox($0, Vector2(w, l), r))
        }
    }

    static func vesica(width: Double, height: Double, cornerRadius rr: Double) -> [Vector2] {
        let horizontal = width > height
        let a = (horizontal ? width : height) / 2
        let w = max((horizontal ? height : width) / 2, 1e-4)
        let rCircle = (w + a * a / w) / 2
        let dOff = (a * a - w * w) / (2 * w)
        return trace(halfX: width / 2 + rr, halfY: height / 2 + rr) { p in
            let q = horizontal ? Vector2(p.y, p.x) : p
            return sdVesica(q, rCircle, dOff) - rr
        }
    }

    /// The oriented vesica in its own frame: tips on the local x-axis at
    /// `(±halfLength, 0)`, bulging to `halfWidth` across the y-axis. The Drawer
    /// rotates these into place between the two tip points.
    static func orientedVesica(halfLength a: Double, halfWidth w: Double) -> [Vector2] {
        let ww = max(w, 1e-4)
        let rCircle = (ww + a * a / ww) / 2
        let dOff = (a * a - ww * ww) / (2 * ww)
        return trace(halfX: a, halfY: ww) { sdVesica(Vector2($0.y, $0.x), rCircle, dOff) }
    }

    static func moon(outerRadius: Double, innerRadius: Double, offset: Double, cornerRadius rr: Double) -> [Vector2] {
        trace(halfX: outerRadius + rr, halfY: outerRadius + rr) {
            sdMoon($0, offset, outerRadius, innerRadius) - rr
        }
    }

    static func cutDisk(radius: Double, cut: Double) -> [Vector2] {
        trace(halfX: radius, halfY: radius) { sdCutDisk(Vector2($0.x, -$0.y), radius, cut) }
    }

    static func unevenCapsule(a: Vector2, b: Vector2, ra: Double, rb: Double) -> [Vector2] {
        // Local frame centered on (a+b)/2; replicate the fragment's rotation/shift.
        let d = b - a
        let len = d.length
        let dir = d / len
        let c = dir.y, s = dir.x   // param1 = (dir.y, dir.x)
        let bound = len / 2 + max(ra, rb)
        return trace(halfX: bound, halfY: bound) { p in
            var q = Vector2(p.x * c - p.y * s, p.x * s + p.y * c)
            q = Vector2(q.x, q.y + len * 0.5)
            return sdUnevenCapsule(q, ra, rb, len)
        }
    }

    static func horseshoe(radius: Double, thickness: Double, gap: Double) -> [Vector2] {
        let an = min(max(gap / 2, 1e-3), Double.pi - 1e-3)
        let c = Vector2(cos(an), sin(an))
        let w = Vector2(thickness / 2, thickness / 2)
        let bound = radius + thickness
        return trace(halfX: bound, halfY: bound) {
            sdHorseshoe(Vector2($0.x, -$0.y), c, radius, w)
        }
    }

    static func parabola(width: Double, height: Double) -> [Vector2] {
        let wi = width / 2, he = height
        return trace(halfX: width / 2, halfY: height / 2) { p in
            let u = Vector2(p.x, he * 0.5 - p.y)
            return max(sdParabolaSegment(u, wi, he), -u.y)
        }
    }

    static func egg(bottomRadius ra: Double, topRadius rb: Double) -> [Vector2] {
        let apex = 1.7320508075688772 * (ra - rb) + rb
        let yc = (apex - ra) * 0.5
        let halfHeight = (apex + ra) / 2
        return trace(halfX: ra, halfY: halfHeight) { sdEgg(Vector2($0.x, -$0.y + yc), ra, rb) }
    }

    static func heart(size: Double) -> [Vector2] {
        let s = size / 1.2036
        return trace(halfX: 0.6018 * s, halfY: 0.54925 * s) { p in
            let u = Vector2(p.x / s, -p.y / s + 0.5538)
            return sdHeart(u) * s
        }
    }

    static func roundedX(length: Double, thickness: Double) -> [Vector2] {
        let r = thickness / 2
        let w = max(length - thickness * 0.7071067811865476, 0)
        return trace(halfX: length / 2 + r, halfY: length / 2 + r) { sdRoundedX($0, w, r) }
    }

    static func blobbyCross(radius: Double, blobbiness: Double) -> [Vector2] {
        let he = min(max(blobbiness, 0.3), 0.6)
        let tipUnit = 1 / (he * 1.4142135623730951) - 1
        let s = radius / tipUnit
        return trace(halfX: radius * 1.08, halfY: radius * 1.08) { sdBlobbyCross($0 / s, he) * s }
    }

    static func tunnel(width: Double, height: Double) -> [Vector2] {
        let whx = width / 2, why = height - whx
        let yc = (whx - why) * 0.5
        return trace(halfX: width / 2, halfY: height / 2) {
            sdTunnel(Vector2($0.x, yc - $0.y), Vector2(whx, why))
        }
    }

    static func coolS(size: Double) -> [Vector2] {
        let s = size / 2.1
        return trace(halfX: size / 2 + s * 0.1, halfY: size / 2 + s * 0.1) { sdCoolS($0 / s) * s }
    }
}

// MARK: - Marching-squares contour tracer

private extension SDFOutline {
    /// Trace the zero contour of `sdf` over a box around the origin, returning a
    /// closed polyline. The box is grown a little past the footprint so the
    /// contour stays interior (and thus closes cleanly).
    static func trace(halfX: Double, halfY: Double, sdf: (Vector2) -> Double) -> [Vector2] {
        let mx = halfX * 1.06 + 1, my = halfY * 1.06 + 1
        let resX = min(max(Int((mx * 2 / 1.5).rounded(.up)), 24), 360)
        let resY = min(max(Int((my * 2 / 1.5).rounded(.up)), 24), 360)
        let nx = resX + 1, ny = resY + 1
        func gx(_ i: Int) -> Double { -mx + 2 * mx * Double(i) / Double(resX) }
        func gy(_ j: Int) -> Double { -my + 2 * my * Double(j) / Double(resY) }
        var vals = [Double](repeating: 0, count: nx * ny)
        for j in 0..<ny { for i in 0..<nx { vals[j * nx + i] = sdf(Vector2(gx(i), gy(j))) } }

        func interp(_ ax: Double, _ ay: Double, _ av: Double, _ bx: Double, _ by: Double, _ bv: Double) -> Vector2 {
            let t = av / (av - bv)
            return Vector2(ax + t * (bx - ax), ay + t * (by - ay))
        }
        var segments: [(Vector2, Vector2)] = []
        for j in 0..<resY { for i in 0..<resX {
            let x0 = gx(i), x1 = gx(i + 1), y0 = gy(j), y1 = gy(j + 1)
            let v0 = vals[j * nx + i], v1 = vals[j * nx + i + 1]
            let v2 = vals[(j + 1) * nx + i + 1], v3 = vals[(j + 1) * nx + i]
            var code = 0
            if v0 < 0 { code |= 1 }; if v1 < 0 { code |= 2 }
            if v2 < 0 { code |= 4 }; if v3 < 0 { code |= 8 }
            if code == 0 || code == 15 { continue }
            func e0() -> Vector2 { interp(x0, y0, v0, x1, y0, v1) }   // bottom
            func e1() -> Vector2 { interp(x1, y0, v1, x1, y1, v2) }   // right
            func e2() -> Vector2 { interp(x0, y1, v3, x1, y1, v2) }   // top
            func e3() -> Vector2 { interp(x0, y0, v0, x0, y1, v3) }   // left
            switch code {
            case 1: segments.append((e3(), e0()))
            case 2: segments.append((e0(), e1()))
            case 3: segments.append((e3(), e1()))
            case 4: segments.append((e1(), e2()))
            case 5: segments.append((e3(), e0())); segments.append((e1(), e2()))
            case 6: segments.append((e0(), e2()))
            case 7: segments.append((e3(), e2()))
            case 8: segments.append((e2(), e3()))
            case 9: segments.append((e2(), e0()))
            case 10: segments.append((e0(), e1())); segments.append((e2(), e3()))
            case 11: segments.append((e2(), e1()))
            case 12: segments.append((e1(), e3()))
            case 13: segments.append((e1(), e0()))
            case 14: segments.append((e0(), e3()))
            default: break
            }
        }}
        return stitch(segments)
    }

    /// Walk marching-squares segments into one ordered closed loop. Endpoints on a
    /// shared cell edge are computed identically by both cells, so quantized keys
    /// match exactly.
    static func stitch(_ segments: [(Vector2, Vector2)]) -> [Vector2] {
        guard !segments.isEmpty else { return [] }
        func key(_ v: Vector2) -> Int64 {
            Int64((v.x * 1000).rounded()) &* 2_000_003 &+ Int64((v.y * 1000).rounded())
        }
        var adjacency: [Int64: [Int]] = [:]
        for (i, s) in segments.enumerated() {
            adjacency[key(s.0), default: []].append(i)
            adjacency[key(s.1), default: []].append(i)
        }
        var used = [Bool](repeating: false, count: segments.count)
        used[0] = true
        let startKey = key(segments[0].0)
        var loop = [segments[0].0, segments[0].1]
        var current = segments[0].1
        while true {
            let k = key(current)
            guard let candidates = adjacency[k],
                  let next = candidates.first(where: { !used[$0] }) else { break }
            used[next] = true
            let seg = segments[next]
            let other = key(seg.0) == k ? seg.1 : seg.0
            if key(other) == startKey { break }
            loop.append(other)
            current = other
        }
        return loop
    }
}

// MARK: - Ported signed-distance functions (mirror ShaderShapes.metal, from iq's 2D
// distance functions). CPU copies used only to trace outlines for SVG export.

private func dot(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.x + a.y * b.y }
private func dot2(_ v: Vector2) -> Double { v.x * v.x + v.y * v.y }
private func ndot(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.x - a.y * b.y }
private func clampd(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
private func signd(_ x: Double) -> Double { x < 0 ? -1 : (x > 0 ? 1 : 0) }

private func sdRoundBox(_ p: Vector2, _ b: Vector2, _ r: Double) -> Double {
    let q = Vector2(abs(p.x) - b.x + r, abs(p.y) - b.y + r)
    return min(max(q.x, q.y), 0) + Vector2(max(q.x, 0), max(q.y, 0)).length - r
}

private func sdRhombus(_ p: Vector2, _ b: Vector2) -> Double {
    let q = Vector2(abs(p.x), abs(p.y))
    let h = clampd(ndot(Vector2(b.x - 2 * q.x, b.y - 2 * q.y), b) / dot(b, b), -1, 1)
    let d = Vector2(q.x - 0.5 * b.x * (1 - h), q.y - 0.5 * b.y * (1 + h)).length
    return d * signd(q.x * b.y + q.y * b.x - b.x * b.y)
}

private func sdVesica(_ p: Vector2, _ r: Double, _ d: Double) -> Double {
    let q = Vector2(abs(p.x), abs(p.y))
    let b = (r * r - d * d).squareRoot()
    if (q.y - b) * d > q.x * b {
        return Vector2(q.x, q.y - b).length * signd(d)
    }
    return Vector2(q.x + d, q.y).length - r
}

private func sdMoon(_ p: Vector2, _ d: Double, _ ra: Double, _ rb: Double) -> Double {
    let q = Vector2(p.x, abs(p.y))
    let a = (ra * ra - rb * rb + d * d) / (2 * d)
    let b = max(ra * ra - a * a, 0).squareRoot()
    if d * (q.x * b - q.y * a) > d * d * max(b - q.y, 0) {
        return Vector2(q.x - a, q.y - b).length
    }
    return max(q.length - ra, -(Vector2(q.x - d, q.y).length - rb))
}

private func sdCutDisk(_ p: Vector2, _ r: Double, _ h: Double) -> Double {
    let w = (r * r - h * h).squareRoot()
    let px = abs(p.x)
    let s = max((h - r) * px * px + w * w * (h + r - 2 * p.y), h * px - w * p.y)
    if s < 0 { return Vector2(px, p.y).length - r }
    if px < w { return h - p.y }
    return Vector2(px - w, p.y - h).length
}

private func sdUnevenCapsule(_ p: Vector2, _ r1: Double, _ r2: Double, _ h: Double) -> Double {
    let px = abs(p.x)
    let b = (r1 - r2) / h
    let a = (1 - b * b).squareRoot()
    let k = dot(Vector2(px, p.y), Vector2(-b, a))
    if k < 0 { return Vector2(px, p.y).length - r1 }
    if k > a * h { return Vector2(px, p.y - h).length - r2 }
    return dot(Vector2(px, p.y), Vector2(a, b)) - r1
}

private func sdHorseshoe(_ p: Vector2, _ c: Vector2, _ r: Double, _ w: Vector2) -> Double {
    let px = abs(p.x)
    let l = Vector2(px, p.y).length
    // mat2(col0=(-c.x,c.y), col1=(c.y,c.x)) * (px, p.y)
    var q = Vector2(-c.x * px + c.y * p.y, c.y * px + c.x * p.y)
    q = Vector2((q.y > 0 || q.x > 0) ? q.x : l * signd(-c.x),
                (q.x > 0) ? q.y : l)
    q = Vector2(q.x - w.x, abs(q.y - r) - w.y)
    return Vector2(max(q.x, 0), max(q.y, 0)).length + min(0, max(q.x, q.y))
}

private func sdParabolaSegment(_ pos: Vector2, _ wi: Double, _ he: Double) -> Double {
    let px = abs(pos.x)
    let ik = wi * wi / he
    let p = ik * (he - pos.y - 0.5 * ik) / 3
    let q = px * ik * ik / 4
    let h = q * q - p * p * p
    var x: Double
    if h > 0 {
        let r = pow(q + h.squareRoot(), 1.0 / 3.0)
        x = r + p / r
    } else {
        let r = p.squareRoot()
        x = 2 * r * cos(acos(q / (p * r)) / 3)
    }
    x = min(x, wi)
    return Vector2(px - x, pos.y - (he - x * x / ik)).length * signd(ik * (pos.y - he) + px * px)
}

private func sdEgg(_ p: Vector2, _ ra: Double, _ rb: Double) -> Double {
    let k = 1.7320508075688772
    let px = abs(p.x)
    let r = ra - rb
    let base: Double
    if p.y < 0 {
        base = Vector2(px, p.y).length - r
    } else if k * (px + r) < p.y {
        base = Vector2(px, p.y - k * r).length
    } else {
        base = Vector2(px + r, p.y).length - 2 * r
    }
    return base - rb
}

private func sdHeart(_ p: Vector2) -> Double {
    let px = abs(p.x)
    if p.y + px > 1 {
        return dot2(Vector2(px - 0.25, p.y - 0.75)).squareRoot() - 0.35355339
    }
    let m = 0.5 * max(px + p.y, 0)
    return min(dot2(Vector2(px, p.y - 1)), dot2(Vector2(px - m, p.y - m))).squareRoot() * signd(px - p.y)
}

private func sdRoundedX(_ p: Vector2, _ w: Double, _ r: Double) -> Double {
    let px = abs(p.x), py = abs(p.y)
    let m = min(px + py, w) * 0.5
    return Vector2(px - m, py - m).length - r
}

private func sdBlobbyCross(_ pos: Vector2, _ he: Double) -> Double {
    var p = Vector2(abs(pos.x), abs(pos.y))
    p = Vector2(abs(p.x - p.y), 1 - p.x - p.y) / 2.0.squareRoot()
    let pp = (he - p.y - 0.25 / he) / (6 * he)
    let q = p.x / (he * he * 16)
    let h = q * q - pp * pp * pp
    var x: Double
    if h > 0 {
        let r = h.squareRoot()
        x = pow(q + r, 1.0 / 3.0) - pow(abs(q - r), 1.0 / 3.0) * signd(r - q)
    } else {
        let r = pp.squareRoot()
        x = 2 * r * cos(acos(q / (pp * r)) / 3)
    }
    x = min(x, 2.0.squareRoot() / 2)
    let z = Vector2(x - p.x, he * (1 - 2 * x * x) - p.y)
    return z.length * signd(z.y)
}

private func sdTunnel(_ p: Vector2, _ wh: Vector2) -> Double {
    let px = abs(p.x), py = -p.y
    var q = Vector2(px - wh.x, py - wh.y)
    let d1 = dot2(Vector2(max(q.x, 0), q.y))
    q = Vector2((py > 0) ? q.x : Vector2(px, py).length - wh.x, q.y)
    let d2 = dot2(Vector2(q.x, max(q.y, 0)))
    let d = min(d1, d2).squareRoot()
    return (max(q.x, q.y) < 0) ? -d : d
}

private func sdCoolS(_ p: Vector2) -> Double {
    let six = (p.y < 0) ? -p.x : p.x
    let px = abs(p.x)
    let py = abs(p.y) - 0.2
    let rex = px - min((px / 0.4).rounded(), 0.4)
    let aby = abs(py - 0.2) - 0.6
    let c1 = clampd(0.5 * (six - py), 0, 0.2)
    var d = dot2(Vector2(six - c1, -py - c1))
    let c2 = clampd(0.5 * (px - aby), 0, 0.4)
    d = min(d, dot2(Vector2(px - c2, -aby - c2)))
    d = min(d, dot2(Vector2(rex, py - clampd(py, 0, 0.4))))
    let s = 2 * px + aby + abs(aby + 0.4) - 0.4
    return d.squareRoot() * signd(s)
}
