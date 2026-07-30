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
/// by the cell's average, the standard rule. Deterministic.
public func isolines(at level: Double,
                     in bounds: Rectangle,
                     resolution: Int = 128,
                     field: (Vector2) -> Double) -> [Contour] {
    guard let grid = IsolineGrid(bounds: bounds, resolution: resolution) else { return [] }
    return grid.trace(values: grid.sample(field), level: level)
}

/// The contours of `field` at each of `levels`, one `[Contour]` per level in
/// order. The field is sampled once and traced per level, so a stack of
/// levels (the topographic map) costs one sampling pass.
public func isolines(at levels: [Double],
                     in bounds: Rectangle,
                     resolution: Int = 128,
                     field: (Vector2) -> Double) -> [[Contour]] {
    guard let grid = IsolineGrid(bounds: bounds, resolution: resolution) else {
        return levels.map { _ in [] }
    }
    let values = grid.sample(field)
    return levels.map { grid.trace(values: values, level: $0) }
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
        let stride = cols + 1
        var segments: [(from: Vector2, to: Vector2)] = []
        for j in 0 ..< rows {
            for i in 0 ..< cols {
                // Corners counterclockwise from the cell's low corner:
                // 0 = (i, j), 1 = (i+1, j), 2 = (i+1, j+1), 3 = (i, j+1).
                let v0 = values[j * stride + i] - level
                let v1 = values[j * stride + i + 1] - level
                let v2 = values[(j + 1) * stride + i + 1] - level
                let v3 = values[(j + 1) * stride + i] - level
                var code = 0
                if v0 < 0 { code |= 1 }; if v1 < 0 { code |= 2 }
                if v2 < 0 { code |= 4 }; if v3 < 0 { code |= 8 }
                guard code != 0, code != 15 else { continue }

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
        }
        return stitch(segments)
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
    private func stitch(_ raw: [(from: Vector2, to: Vector2)]) -> [Contour] {
        // A contour passing exactly through a grid corner (a corner value of
        // exactly zero) makes its cell emit a null segment; the real curve
        // already routes through the neighbor cells, so nulls only leave
        // two-point litter. Drop them before walking.
        let segments = raw.filter { EndpointKey($0.from) != EndpointKey($0.to) }
        guard !segments.isEmpty else { return [] }
        var bySource: [EndpointKey: [Int]] = [:]
        var byTarget: [EndpointKey: [Int]] = [:]
        for (s, segment) in segments.enumerated() {
            bySource[EndpointKey(segment.from), default: []].append(s)
            byTarget[EndpointKey(segment.to), default: []].append(s)
        }
        var used = [Bool](repeating: false, count: segments.count)
        var contours: [Contour] = []
        for start in segments.indices where !used[start] {
            used[start] = true
            let startKey = EndpointKey(segments[start].from)
            var points = [segments[start].from, segments[start].to]
            var closed = false

            var key = EndpointKey(segments[start].to)
            while let next = bySource[key]?.first(where: { !used[$0] }) {
                used[next] = true
                let target = segments[next].to
                key = EndpointKey(target)
                if key == startKey { closed = true; break }
                points.append(target)
            }

            if !closed {
                var back: [Vector2] = []
                var backKey = startKey
                while let previous = byTarget[backKey]?.first(where: { !used[$0] }) {
                    used[previous] = true
                    back.append(segments[previous].from)
                    backKey = EndpointKey(segments[previous].from)
                }
                if !back.isEmpty { points = back.reversed() + points }
            }
            if closed && points.count < 3 { continue }   // degenerate sliver
            contours.append(Contour(points, closed: closed))
        }
        return contours
    }
}
