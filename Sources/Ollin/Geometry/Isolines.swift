import Foundation

/// Isolines: the level curves of a scalar field, traced by marching squares.
/// Give it any `(Vector2) -> Double` field (noise, an SDF, image brightness,
/// your own math) and a level, and back come the contours where the field
/// crosses that level: the topographic-map reading of a surface, and the
/// engine behind metaball outlines, terrain maps, and tone-line renderings
/// of a picture.
///
/// ```swift
/// let rings = isolines(at: 0.5, in: frame) { p in
///     fbm(p.x * 0.004, p.y * 0.004)
/// }
/// for ring in rings { drawPolyline(ring.points, closed: ring.isClosed) }
/// ```
///
/// A contour that closes inside the bounds comes back as a closed `Contour`;
/// one that runs off the edge comes back open, ending on the boundary. The
/// output feeds `drawPolyline`, `drawCurve` (for the smoothed reading),
/// `smoothed(iterations:)`, hatching, and SVG export. Deterministic given
/// the field, and cheap enough to re-trace every frame at the default
/// resolution.

/// The contours of `field` at `level` inside `bounds`. The field is sampled
/// on a grid `resolution` cells across the longer side (square-ish cells, so
/// the short side gets proportionally fewer); raise it for tighter curves,
/// at linearly more field samples per cell. Saddle cells are disambiguated
/// by the cell's average, the standard rule. A cell with a corner where the
/// field is NaN or infinite holds no contour, so a hole in the field leaves
/// the contours open at its edge. Deterministic.
public func isolines(at level: Double,
                     in bounds: Rectangle,
                     resolution: Int = 128,
                     field: (Vector2) -> Double) -> [Contour] {
    guard let grid = IsolineGrid(bounds: bounds, resolution: resolution) else { return [] }
    return grid.trace(values: grid.sample(field), level: level)
}

/// The contours of `field` at each of `levels`, one `[Contour]` per level in
/// order. The field is sampled once and the cells are marched once, each cell
/// tracing only the levels that pass between its corners, so a stack of
/// levels (the topographic map) costs one sampling pass plus its crossings.
/// Each level's contours are the ones `isolines(at:in:resolution:field:)`
/// traces for it alone.
public func isolines(at levels: [Double],
                     in bounds: Rectangle,
                     resolution: Int = 128,
                     field: (Vector2) -> Double) -> [[Contour]] {
    guard let grid = IsolineGrid(bounds: bounds, resolution: resolution) else {
        return levels.map { _ in [] }
    }
    return grid.trace(values: grid.sample(field), levels: levels)
}

// MARK: - Sketch sugar

@MainActor
private enum IsolineNotes {
    static var printed = false
    static func note() {
        guard !printed else { return }
        printed = true
        print("Ollin: isolines needs CPU pixels; a texture-backed image has none. Read a video frame through its snapshot first.")
    }
}

public extension Sketch {
    /// The contours of `field` at `level` inside `bounds` (the whole canvas
    /// by default). See `isolines(at:in:resolution:field:)`.
    func isolines(at level: Double,
                  in bounds: Rectangle? = nil,
                  resolution: Int = 128,
                  field: (Vector2) -> Double) -> [Contour] {
        Ollin.isolines(at: level, in: bounds ?? canvasRectangle,
                       resolution: resolution, field: field)
    }

    /// The contours of `field` at each of `levels` inside `bounds` (the
    /// whole canvas by default), one `[Contour]` per level in order, from a
    /// single sampling pass.
    func isolines(at levels: [Double],
                  in bounds: Rectangle? = nil,
                  resolution: Int = 128,
                  field: (Vector2) -> Double) -> [[Contour]] {
        Ollin.isolines(at: levels, in: bounds ?? canvasRectangle,
                       resolution: resolution, field: field)
    }

    /// The tone lines of `image`: contours traced where its brightness
    /// crosses `level`, a tone from `0` (black) to `1` (white). Brightness
    /// is read as if the picture sat on white paper, so transparency counts
    /// as light. The image is stretched over `bounds` (the whole canvas by
    /// default); pass a `Rectangle(fitting:in:)` of the image's size to keep
    /// its aspect.
    func isolines(of image: Image,
                  at level: Double,
                  in bounds: Rectangle? = nil,
                  resolution: Int = 128) -> [Contour] {
        guard let sampler = ImageToneSampler(image) else {
            IsolineNotes.note()
            return []
        }
        let rect = bounds ?? canvasRectangle
        return Ollin.isolines(at: Color.srgbToLinear(clamp(level, 0, 1)), in: rect,
                              resolution: resolution) { sampler.tone(at: $0, in: rect) }
    }

    /// The tone lines of `image` at each of `levels` (tones from `0` black
    /// to `1` white), one `[Contour]` per level in order: the multi-level
    /// stack that reads a photograph as a topographic map.
    func isolines(of image: Image,
                  at levels: [Double],
                  in bounds: Rectangle? = nil,
                  resolution: Int = 128) -> [[Contour]] {
        guard let sampler = ImageToneSampler(image) else {
            IsolineNotes.note()
            return levels.map { _ in [] }
        }
        let rect = bounds ?? canvasRectangle
        let linear = levels.map { Color.srgbToLinear(clamp($0, 0, 1)) }
        return Ollin.isolines(at: linear, in: rect,
                              resolution: resolution) { sampler.tone(at: $0, in: rect) }
    }
}

// MARK: - Image tone sampling

/// Straight sRGB byte to linear light, tabulated once.
private let srgbByteToLinear: [Double] = (0 ... 255).map {
    Color.srgbToLinear(Double($0) / 255)
}

/// An image reduced to one linear-light tone per pixel (composited on white,
/// so transparency reads as paper), sampled bilinearly so the traced curves
/// stay smooth past the pixel grid.
private struct ImageToneSampler {
    let width: Int
    let height: Int
    let tones: [Double]

    @MainActor
    init?(_ image: Image) {
        guard image.width > 0, image.height > 0,
              let pixels = image.premultipliedPixels() else { return nil }
        width = image.width
        height = image.height
        var tones = [Double](repeating: 1, count: width * height)
        for p in 0 ..< width * height {
            let i = p * 4
            let alphaByte = Int(pixels[i + 3])
            guard alphaByte > 0 else { continue }
            let alpha = Double(alphaByte) / 255
            let red = Swift.min(Int(pixels[i]) * 255 / alphaByte, 255)
            let green = Swift.min(Int(pixels[i + 1]) * 255 / alphaByte, 255)
            let blue = Swift.min(Int(pixels[i + 2]) * 255 / alphaByte, 255)
            let luma = 0.2126 * srgbByteToLinear[red]
                     + 0.7152 * srgbByteToLinear[green]
                     + 0.0722 * srgbByteToLinear[blue]
            tones[p] = luma * alpha + (1 - alpha)
        }
        self.tones = tones
    }

    /// The tone under canvas point `p`, with the image stretched over
    /// `rect`: bilinear between pixel centers, clamped at the edges.
    func tone(at p: Vector2, in rect: Rectangle) -> Double {
        let fx = clamp((p.x - rect.x) / rect.width * Double(width) - 0.5,
                       0, Double(width - 1))
        let fy = clamp((p.y - rect.y) / rect.height * Double(height) - 0.5,
                       0, Double(height - 1))
        let x0 = Int(fx), y0 = Int(fy)
        let x1 = Swift.min(x0 + 1, width - 1), y1 = Swift.min(y0 + 1, height - 1)
        let tx = fx - Double(x0), ty = fy - Double(y0)
        let top = tones[y0 * width + x0] * (1 - tx) + tones[y0 * width + x1] * tx
        let bottom = tones[y1 * width + x0] * (1 - tx) + tones[y1 * width + x1] * tx
        return top * (1 - ty) + bottom * ty
    }
}

// MARK: - Marching squares

/// The sampling lattice: `cols x rows` cells over `bounds`, corner positions
/// on a `(cols + 1) x (rows + 1)` grid.
private struct IsolineGrid {
    let bounds: Rectangle
    let cols: Int
    let rows: Int

    init?(bounds: Rectangle, resolution: Int) {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let cell = Swift.max(bounds.width, bounds.height) / Double(Swift.max(resolution, 1))
        self.bounds = bounds
        self.cols = Swift.max(Int((bounds.width / cell).rounded()), 1)
        self.rows = Swift.max(Int((bounds.height / cell).rounded()), 1)
    }

    func x(_ i: Int) -> Double { bounds.x + bounds.width * Double(i) / Double(cols) }
    func y(_ j: Int) -> Double { bounds.y + bounds.height * Double(j) / Double(rows) }

    func sample(_ field: (Vector2) -> Double) -> [Double] {
        var values = [Double](repeating: 0, count: (cols + 1) * (rows + 1))
        for j in 0 ... rows {
            let py = y(j)
            for i in 0 ... cols {
                values[j * (cols + 1) + i] = field(Vector2(x(i), py))
            }
        }
        return values
    }

    /// March the cells, emitting one oriented segment per crossing (two in a
    /// saddle cell, paired by the cell-average rule), then stitch segments
    /// into contours.
    func trace(values: [Double], level: Double) -> [Contour] {
        var segments: [(from: Vector2, to: Vector2)] = []
        for j in 0 ..< rows {
            for i in 0 ..< cols {
                appendCrossings(of: level, inCell: i, j, values: values, to: &segments)
            }
        }
        return stitch(segments)
    }

    /// Every level's contours from one march. A level crosses a cell only when
    /// some corner is below it and some corner is not, so it lies above the
    /// lowest corner and at or below the highest; a cell visits just the
    /// levels in that range, found by a binary search over the sorted levels,
    /// and the cell code makes the final call on each. Segments reach each
    /// level's list in the order `trace(values:level:)` makes them, so every
    /// level stitches to the same contours as its own march. A cell with a
    /// corner that is not finite holds no contour, and a NaN level crosses
    /// nothing.
    func trace(values: [Double], levels: [Double]) -> [[Contour]] {
        let order = levels.indices.filter { !levels[$0].isNaN }.sorted { levels[$0] < levels[$1] }
        let ascending = order.map { levels[$0] }
        var segments = [[(from: Vector2, to: Vector2)]](repeating: [], count: levels.count)
        guard !ascending.isEmpty else { return levels.map { _ in [] } }
        let stride = cols + 1
        for j in 0 ..< rows {
            for i in 0 ..< cols {
                let c0 = values[j * stride + i], c1 = values[j * stride + i + 1]
                let c2 = values[(j + 1) * stride + i + 1], c3 = values[(j + 1) * stride + i]
                guard c0.isFinite, c1.isFinite, c2.isFinite, c3.isFinite else { continue }
                let lowest = Swift.min(Swift.min(c0, c1), Swift.min(c2, c3))
                let highest = Swift.max(Swift.max(c0, c1), Swift.max(c2, c3))
                // The first level above the lowest corner.
                var first = 0, past = ascending.count
                while first < past {
                    let middle = (first + past) / 2
                    if ascending[middle] > lowest { past = middle } else { first = middle + 1 }
                }
                var k = first
                while k < ascending.count, ascending[k] <= highest {
                    appendCrossings(of: ascending[k], inCell: i, j, values: values,
                                    to: &segments[order[k]])
                    k += 1
                }
            }
        }
        return segments.map(stitch)
    }

    /// The oriented segments where `level` crosses cell `(i, j)`, appended to
    /// `segments`: none when every corner is on one side of it, and none when
    /// a corner is NaN or infinite, since a crossing found against one would
    /// land nowhere. A hole in the field leaves the contours open at its edge.
    @inline(__always) private func appendCrossings(of level: Double, inCell i: Int, _ j: Int, values: [Double],
                                 to segments: inout [(from: Vector2, to: Vector2)]) {
        let stride = cols + 1
        guard values[j * stride + i].isFinite, values[j * stride + i + 1].isFinite,
              values[(j + 1) * stride + i + 1].isFinite, values[(j + 1) * stride + i].isFinite
        else { return }
        // Corners counterclockwise from the cell's low corner:
        // 0 = (i, j), 1 = (i+1, j), 2 = (i+1, j+1), 3 = (i, j+1).
        let v0 = values[j * stride + i] - level
        let v1 = values[j * stride + i + 1] - level
        let v2 = values[(j + 1) * stride + i + 1] - level
        let v3 = values[(j + 1) * stride + i] - level
        var code = 0
        if v0 < 0 { code |= 1 }; if v1 < 0 { code |= 2 }
        if v2 < 0 { code |= 4 }; if v3 < 0 { code |= 8 }
        guard code != 0, code != 15 else { return }

        let x0 = x(i), x1 = x(i + 1), y0 = y(j), y1 = y(j + 1)
        func interp(_ ax: Double, _ ay: Double, _ av: Double,
                    _ bx: Double, _ by: Double, _ bv: Double) -> Vector2 {
            let t = av / (av - bv)
            return Vector2(ax + t * (bx - ax), ay + t * (by - ay))
        }
        func e0() -> Vector2 { interp(x0, y0, v0, x1, y0, v1) }   // low edge
        func e1() -> Vector2 { interp(x1, y0, v1, x1, y1, v2) }   // right
        func e2() -> Vector2 { interp(x0, y1, v3, x1, y1, v2) }   // high edge
        func e3() -> Vector2 { interp(x0, y0, v0, x0, y1, v3) }   // left

        // Oriented so a shared endpoint is one segment's `to` and the
        // next one's `from`, which is what lets the stitch walk
        // directionally. Saddles (5 and 10) pair their two segments
        // by the cell average: below the level, the inside corners
        // connect through the center; above, they stay separate.
        switch code {
        case 1: segments.append((e3(), e0()))
        case 2: segments.append((e0(), e1()))
        case 3: segments.append((e3(), e1()))
        case 4: segments.append((e1(), e2()))
        case 5:
            if (v0 + v1 + v2 + v3) / 4 < 0 {
                segments.append((e1(), e0())); segments.append((e3(), e2()))
            } else {
                segments.append((e3(), e0())); segments.append((e1(), e2()))
            }
        case 6: segments.append((e0(), e2()))
        case 7: segments.append((e3(), e2()))
        case 8: segments.append((e2(), e3()))
        case 9: segments.append((e2(), e0()))
        case 10:
            if (v0 + v1 + v2 + v3) / 4 < 0 {
                segments.append((e0(), e3())); segments.append((e2(), e1()))
            } else {
                segments.append((e0(), e1())); segments.append((e2(), e3()))
            }
        case 11: segments.append((e2(), e1()))
        case 12: segments.append((e1(), e3()))
        case 13: segments.append((e1(), e0()))
        case 14: segments.append((e0(), e3()))
        default: break
        }
    }

    private struct EndpointKey: Hashable {
        let x: Int64
        let y: Int64
        init(_ v: Vector2) {
            x = Int64((v.x * 1024).rounded())
            y = Int64((v.y * 1024).rounded())
        }
    }

    /// Walk oriented segments into contours: forward along `to -> from`
    /// matches until the chain closes or runs out (the boundary), then
    /// backward from the start for the open case. Endpoints on a shared cell
    /// edge are computed identically by both cells, so quantized keys match
    /// exactly; the maps are only ever indexed, never iterated, so the walk
    /// order is the segment order and the result is deterministic.
    ///
    /// Each endpoint's key is computed once. A key maps to the first segment
    /// that starts (or ends) there, and the rare others that share it (a
    /// crossing exactly on a grid corner) follow in a chain in segment order,
    /// so a lookup takes the first unused one in the same order a list would.
    private func stitch(_ raw: [(from: Vector2, to: Vector2)]) -> [Contour] {
        // A contour passing exactly through a grid corner (a corner value of
        // exactly zero) makes its cell emit a null segment; the real curve
        // already routes through the neighbor cells, so nulls only leave
        // two-point litter. Drop them before walking.
        var segments: [(from: Vector2, to: Vector2)] = []
        var fromKeys: [EndpointKey] = [], toKeys: [EndpointKey] = []
        segments.reserveCapacity(raw.count)
        fromKeys.reserveCapacity(raw.count)
        toKeys.reserveCapacity(raw.count)
        for segment in raw {
            let from = EndpointKey(segment.from), to = EndpointKey(segment.to)
            guard from != to else { continue }
            segments.append(segment)
            fromKeys.append(from)
            toKeys.append(to)
        }
        guard !segments.isEmpty else { return [] }

        // First segment per key, then each segment's next one with the same key.
        func index(_ keys: [EndpointKey]) -> (first: [EndpointKey: Int], next: [Int]) {
            var first: [EndpointKey: Int] = [:]
            first.reserveCapacity(keys.count)
            var last: [EndpointKey: Int] = [:]
            var next = [Int](repeating: -1, count: keys.count)
            for (s, key) in keys.enumerated() {
                if let tail = last[key] {
                    next[tail] = s
                } else if first[key] == nil {
                    first[key] = s
                    continue
                } else {
                    next[first[key]!] = s
                }
                last[key] = s
            }
            return (first, next)
        }
        let bySource = index(fromKeys), byTarget = index(toKeys)
        var used = [Bool](repeating: false, count: segments.count)
        func firstUnused(_ key: EndpointKey, in map: (first: [EndpointKey: Int], next: [Int])) -> Int? {
            var s = map.first[key] ?? -1
            while s >= 0, used[s] { s = map.next[s] }
            return s >= 0 ? s : nil
        }

        var contours: [Contour] = []
        for start in segments.indices where !used[start] {
            used[start] = true
            let startKey = fromKeys[start]
            var points = [segments[start].from, segments[start].to]
            var closed = false

            var key = toKeys[start]
            while let next = firstUnused(key, in: bySource) {
                used[next] = true
                key = toKeys[next]
                if key == startKey { closed = true; break }
                points.append(segments[next].to)
            }

            if !closed {
                var back: [Vector2] = []
                var backKey = startKey
                while let previous = firstUnused(backKey, in: byTarget) {
                    used[previous] = true
                    back.append(segments[previous].from)
                    backKey = fromKeys[previous]
                }
                if !back.isEmpty { points = back.reversed() + points }
            }
            if closed && points.count < 3 { continue }   // degenerate sliver
            contours.append(Contour(points, closed: closed))
        }
        return contours
    }
}
