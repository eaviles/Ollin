import Foundation

// Hatching: turn a filled region into line work. A pen plotter has only a pen —
// it can't fill — so a solid shape has to be plotted as parallel (or cross-hatch)
// lines clipped to its outline, the spacing carrying the fill's tone. This is the
// missing piece for plotting solid sketches, and it's a transform over geometry,
// not a renderer change: the SVG exporter applies it to each recorded fill (see
// SVGExport.swift), and a sketch can call `Hatching.lines(filling:)` directly to
// draw the same line work on the canvas.
//
// The clip is a scan-fill: rotate the region so the hatch lines run horizontal,
// intersect each scan line with the outline edges, and pair the crossings by the
// fill rule (even-odd or non-zero) to get the interior spans — so concave shapes
// and holes hatch correctly.

/// How a filled region is converted to hatch line work for a pen plotter (or for
/// drawing line-shaded fills on the canvas). The line geometry comes from
/// `lines(filling:)`; the rest of the parameters apply when the SVG exporter hatches a
/// recorded fill.
public struct Hatching: Equatable, Sendable {
    /// Distance between adjacent hatch lines, in canvas points, for a fully-toned
    /// (solid black, opaque) fill. Lighter fills space their lines further apart
    /// when `usesToneDensity` is on. Smaller spacing means denser shading.
    public var spacing: Double

    /// Direction of the hatch lines, in radians. `0` runs them horizontally;
    /// `.pi / 4` is the common 45° diagonal.
    public var angle: Double

    /// Add a second set of lines perpendicular to the first, for cross-hatching.
    public var crossHatches: Bool

    /// Scale the line spacing by the fill's tone when the exporter hatches it: a
    /// dark or opaque fill hatches densely, a light or translucent one sparsely,
    /// and a near-white fill drops out entirely. Off, every fill uses `spacing`.
    /// (Only the export path reads this — `lines(filling:)` always uses `spacing`.)
    public var usesToneDensity: Bool

    /// Stroke width of the emitted hatch lines, in canvas points — the plotter's
    /// pen width. Used by the SVG exporter for the hatch and outline strokes.
    public var penWidth: Double

    /// Also stroke each hatched shape's outline (in its fill color) so the region
    /// keeps a clean border, not just interior lines. Export-only.
    public var keepsOutline: Bool

    public init(spacing: Double = 4, angle: Double = .pi / 4, crossHatches: Bool = false,
                usesToneDensity: Bool = true, penWidth: Double = 1, keepsOutline: Bool = true) {
        self.spacing = spacing
        self.angle = angle
        self.crossHatches = crossHatches
        self.usesToneDensity = usesToneDensity
        self.penWidth = penWidth
        self.keepsOutline = keepsOutline
    }

    /// The hatch lines (open polylines) filling `shape`, in the shape's own
    /// coordinates — ready to `drawPolyline` or feed a plotter. Uses `spacing`,
    /// `angle`, and `crossHatches`; `shape.winding` decides which regions are
    /// interior, so holes and concavities are respected.
    public func lines(filling shape: Shape) -> [[Vector2]] {
        let contours = shape.contours.map(\.points).filter { $0.count >= 3 }
        return hatchLines(contours, winding: shape.winding, spacing: spacing,
                          angle: angle, crossHatches: crossHatches)
    }

    /// The hatch lines filling a rectangle.
    public func lines(filling rect: Rectangle) -> [[Vector2]] {
        lines(filling: Shape([rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft]))
    }

    /// The hatch lines filling a circle.
    public func lines(filling circle: Circle) -> [[Vector2]] {
        let n = max(48, Int((circle.radius * 0.8).rounded(.up)))
        let pts = (0..<n).map { k -> Vector2 in
            let a = 2 * Double.pi * Double(k) / Double(n)
            return circle.center + Vector2(cos(a), sin(a)) * circle.radius
        }
        return lines(filling: Shape(pts))
    }
}

/// Scan-fill `contours` into hatch line segments at `spacing` and `angle`. The
/// world is rotated by `-angle` so the hatch lines become horizontal scan lines;
/// each scan line's crossings with the (rotated) edges are paired by `winding`
/// into interior spans, which are rotated back into world space. Adding the
/// perpendicular pass gives cross-hatch.
func hatchLines(_ contours: [[Vector2]], winding: FillWinding, spacing: Double,
                angle: Double, crossHatches: Bool) -> [[Vector2]] {
    guard spacing > 0, !contours.isEmpty else { return [] }
    var out = hatchPass(contours, winding: winding, spacing: spacing, angle: angle)
    if crossHatches {
        out += hatchPass(contours, winding: winding, spacing: spacing, angle: angle + .pi / 2)
    }
    return out
}

/// One direction of hatching.
private func hatchPass(_ contours: [[Vector2]], winding: FillWinding,
                       spacing: Double, angle: Double) -> [[Vector2]] {
    // Rotate into a frame where the hatch lines are horizontal, then back.
    let c = cos(-angle), s = sin(-angle)
    func rot(_ p: Vector2) -> Vector2 { Vector2(p.x * c - p.y * s, p.x * s + p.y * c) }
    let cu = cos(angle), su = sin(angle)
    func unrot(_ p: Vector2) -> Vector2 { Vector2(p.x * cu - p.y * su, p.x * su + p.y * cu) }

    // Edges in the rotated frame, plus the y-range to scan.
    var edges: [(a: Vector2, b: Vector2)] = []
    var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
    for contour in contours {
        let pts = contour.map(rot)
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            edges.append((a, b))
            minY = min(minY, a.y); maxY = max(maxY, a.y)
        }
    }
    guard maxY > minY else { return [] }

    var lines: [[Vector2]] = []
    // Offset the first scan line by half a step so lines sit inside the bounds.
    var y = (minY / spacing).rounded(.up) * spacing + spacing / 2
    while y < maxY {
        // Crossings of this scan line with the edges; `dir` is the y-direction,
        // for the non-zero winding count.
        var crossings: [(x: Double, dir: Int)] = []
        for (a, b) in edges {
            // Half-open in y so a vertex shared by two edges counts once.
            let hits = (a.y <= y && b.y > y) || (b.y <= y && a.y > y)
            if hits {
                let t = (y - a.y) / (b.y - a.y)
                crossings.append((a.x + t * (b.x - a.x), a.y < b.y ? 1 : -1))
            }
        }
        crossings.sort { $0.x < $1.x }
        appendSpans(crossings, y: y, winding: winding, unrot: unrot, into: &lines)
        y += spacing
    }
    return lines
}

/// Pair sorted crossings into interior spans by the fill rule and emit them as
/// two-point polylines (rotated back into world space).
private func appendSpans(_ crossings: [(x: Double, dir: Int)], y: Double,
                         winding: FillWinding, unrot: (Vector2) -> Vector2,
                         into lines: inout [[Vector2]]) {
    func emit(_ x0: Double, _ x1: Double) {
        guard x1 - x0 > 1e-6 else { return }
        lines.append([unrot(Vector2(x0, y)), unrot(Vector2(x1, y))])
    }
    switch winding {
    case .evenOdd:
        var i = 0
        while i + 1 < crossings.count {
            emit(crossings[i].x, crossings[i + 1].x)
            i += 2
        }
    case .nonZero:
        var wind = 0
        var spanStart = 0.0
        for crossing in crossings {
            let before = wind
            wind += crossing.dir
            if before == 0, wind != 0 {
                spanStart = crossing.x
            } else if before != 0, wind == 0 {
                emit(spanStart, crossing.x)
            }
        }
    }
}
