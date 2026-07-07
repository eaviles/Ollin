import Foundation
import simd

// SVG export: a vector sink that sits beside the raster exporter. A frame's draw
// calls are recorded as semantic geometry (not tessellated triangles or SDF
// instances) and serialized to an SVG document, so a sketch can drive a pen
// plotter or feed any vector pipeline. It records on the CPU and needs no GPU.
//
// The recording happens at the `Drawer` draw-call boundary (see `svgRecord` in
// Drawer.swift), where the user-space geometry still exists; this file holds the
// recorded model, the serializer, and the `OllinApp` entry points.

// MARK: - Recorded model

/// The drawing state captured alongside each recorded command. A primitive's
/// fill/stroke is resolved at record time, so the serializer needs no access to
/// the live `Drawer` state. Paints carry gradients through: linear and radial
/// serialize as native SVG gradient defs; along-path strokes are approximated
/// as short solid runs before serialization (see `approximateAlongPaths`).
struct SVGStyle {
    var fill: Paint?
    var stroke: Paint?        // already nil when there's no visible stroke
    var strokeWidth: Double
    var join: StrokeJoin
    var cap: StrokeCap
}

/// One vector primitive, in user space (before the CTM). The serializer maps each
/// case to an SVG element; the matching CTM rides alongside as a `transform`.
enum SVGGeometry {
    case ellipse(center: Vector2, rx: Double, ry: Double)   // circle when rx == ry
    case rect(corner: Vector2, width: Double, height: Double, cornerRadius: Double)
    case line(Vector2, Vector2)                             // round-capped
    case quad(start: Vector2, control: Vector2, end: Vector2)  // round-capped
    case polyline([Vector2])                               // open, stroke-only
    case polygon([Vector2])                                // closed
    case path(Shape)                                       // contours + winding
}

/// A recorded primitive: its geometry, the resolved style, and the CTM in force.
struct RecordedSVG {
    var geometry: SVGGeometry
    var style: SVGStyle
    var transform: simd_float3x3
}

/// Accumulates the recorded primitives for one frame. Held by the `Drawer` while
/// an SVG export is in flight (`Drawer.svgRecorder`).
final class SVGRecorder {
    var commands: [RecordedSVG] = []
    /// `drawImage` calls dropped from the vector output (raster has no place in an
    /// SVG/plotter file); surfaced as a comment so the omission is visible.
    var skippedImages = 0
}

// MARK: - Hatching transform

/// Replace each filled command with hatch line work (and, optionally, its
/// outline) so the frame plots on a pen — see `Hatching`. Stroke-only geometry
/// (lines, curves, polylines, and unfilled shapes) passes through untouched.
///
/// The hatch is computed in *device* space — each fill's outline is pushed
/// through its CTM first — so the line spacing is uniform on the page regardless
/// of a sketch's transforms; the emitted polylines carry the identity transform.
func applyHatching(_ commands: [RecordedSVG], _ options: Hatching) -> [RecordedSVG] {
    var out: [RecordedSVG] = []
    for command in commands {
        guard let fill = command.style.fill,
              let (contours, winding) = fillContours(command.geometry) else {
            out.append(command)                  // nothing to fill — leave as-is
            continue
        }
        // Tone → density: a darker, more opaque fill hatches more tightly. A
        // gradient fill keys density to its ramp's midpoint tone (one density
        // per shape — the hatch is a single pen pass, not a shaded raster).
        let tone = paintTone(fill)
        let spacing = options.toneDensity ? toneSpacing(options.spacing, tone) : options.spacing
        if let spacing {
            let device = contours.map { $0.map { transformed($0, command.transform) } }
            let pen = SVGStyle(fill: nil, stroke: .color(opaque(tone)), strokeWidth: options.penWidth,
                               join: .miter, cap: .butt)
            for line in hatchLines(device, winding: winding, spacing: spacing,
                                   angle: options.angle, crossHatch: options.crossHatch) {
                out.append(RecordedSVG(geometry: .polyline(line), style: pen,
                                       transform: matrix_identity_float3x3))
            }
        }
        if options.keepOutline {
            var style = command.style          // keep the original border as a stroke
            style.fill = nil
            if style.stroke == nil {
                style.stroke = .color(opaque(tone))
                style.strokeWidth = options.penWidth
            }
            out.append(RecordedSVG(geometry: command.geometry, style: style,
                                   transform: command.transform))
        }
    }
    return out
}

/// A paint's representative color for tone decisions: the color itself, or a
/// gradient's ramp midpoint.
private func paintTone(_ paint: Paint) -> Color {
    switch paint {
    case .color(let c): return c
    case .gradient(let g): return g.ramp.color(at: 0.5)
    }
}

/// A fill's outline as one or more closed contours in its local space, or `nil`
/// when the geometry has no fillable region (lines, curves, open polylines).
private func fillContours(_ geometry: SVGGeometry) -> (contours: [[Vector2]], winding: FillWinding)? {
    switch geometry {
    case let .ellipse(center, rx, ry):
        let n = max(48, Int((max(rx, ry) * 0.8).rounded(.up)))
        let pts = (0..<n).map { k -> Vector2 in
            let a = 2 * Double.pi * Double(k) / Double(n)
            return center + Vector2(cos(a) * rx, sin(a) * ry)
        }
        return ([pts], .evenOdd)
    case let .rect(corner, w, h, r):
        return ([roundedRect(corner: corner, width: w, height: h, radius: r)], .evenOdd)
    case let .polygon(points):
        return points.count >= 3 ? ([points], .evenOdd) : nil
    case let .path(shape):
        let contours = shape.contours.filter(\.isClosed).map(\.points).filter { $0.count >= 3 }
        return contours.isEmpty ? nil : (contours, shape.winding)
    case .line, .quad, .polyline:
        return nil
    }
}

/// A rectangle contour, with quarter-arc corners when `radius > 0`.
private func roundedRect(corner: Vector2, width w: Double, height h: Double, radius r: Double) -> [Vector2] {
    let x0 = corner.x, y0 = corner.y, x1 = corner.x + w, y1 = corner.y + h
    let rr = min(r, min(w, h) / 2)
    guard rr > 0 else { return [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)] }
    let seg = 8
    func arc(cx: Double, cy: Double, from: Double, to: Double) -> [Vector2] {
        (0...seg).map { k -> Vector2 in
            let a = from + (to - from) * Double(k) / Double(seg)
            return Vector2(cx + cos(a) * rr, cy + sin(a) * rr)
        }
    }
    var pts: [Vector2] = []
    pts += arc(cx: x1 - rr, cy: y0 + rr, from: -.pi / 2, to: 0)        // top-right
    pts += arc(cx: x1 - rr, cy: y1 - rr, from: 0, to: .pi / 2)         // bottom-right
    pts += arc(cx: x0 + rr, cy: y1 - rr, from: .pi / 2, to: .pi)       // bottom-left
    pts += arc(cx: x0 + rr, cy: y0 + rr, from: .pi, to: 3 * .pi / 2)   // top-left
    return pts
}

/// Hatch spacing scaled by a fill's tone: darker and more opaque fills hatch
/// tighter, a near-white or near-transparent fill returns `nil` (no hatch). Tone
/// is perceived darkness times alpha; `base` is the spacing at full tone.
private func toneSpacing(_ base: Double, _ fill: Color) -> Double? {
    let luminance = 0.2126 * fill.red + 0.7152 * fill.green + 0.0722 * fill.blue
    let tone = (1 - luminance) * fill.alpha
    guard tone > 0.03 else { return nil }
    return base / tone
}

/// A fully-opaque copy of a color — the hatch lines are solid pen strokes; their
/// spacing, not their alpha, carries the fill's tone.
private func opaque(_ c: Color) -> Color { Color(red: c.red, green: c.green, blue: c.blue) }

/// Apply a 2D homogeneous CTM to a point (the same `M · (x, y, 1)` the renderer
/// uses), in `Double`.
private func transformed(_ p: Vector2, _ m: simd_float3x3) -> Vector2 {
    let v = m * SIMD3<Float>(Float(p.x), Float(p.y), 1)
    return Vector2(Double(v.x), Double(v.y))
}

// MARK: - Serialization

/// Render recorded primitives into an SVG document string. Linear and radial
/// gradient paints become native `<linearGradient>`/`<radialGradient>` defs in
/// user space (so they transform with the element, matching the render);
/// along-path strokes are split into short solid runs first, and along-path
/// fills (the conic sweep) fall back to the ramp's midpoint color.
func serializeSVG(_ commands: [RecordedSVG], background: Color,
                  width: Int, height: Int, skippedImages: Int = 0) -> String {
    let resolved = approximateAlongPaths(commands)
    let (defs, ids) = gradientDefs(resolved)
    var out = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">

    """
    out += defs
    out += "  <rect width=\"\(width)\" height=\"\(height)\" fill=\"\(svgColor(background))\"\(svgOpacity("fill", background))/>\n"
    if skippedImages > 0 {
        out += "  <!-- \(skippedImages) image draw(s) skipped: raster is omitted from vector export -->\n"
    }
    for command in resolved {
        out += "  " + svgElement(command, ids) + "\n"
    }
    out += "</svg>\n"
    return out
}

/// Replace along-path paints with what SVG can express: a gradient *stroke*
/// following a path becomes a run of short solid segments (one `<line>` per
/// piece, round-capped so they chain seamlessly), and an along-path *fill* —
/// the conic sweep — becomes its ramp's midpoint color.
private func approximateAlongPaths(_ commands: [RecordedSVG]) -> [RecordedSVG] {
    var out: [RecordedSVG] = []
    for command in commands {
        var command = command
        var runs: [RecordedSVG] = []
        if case .gradient(let g) = command.style.stroke, g.geometry == .alongPath,
           let split = alongStrokeRuns(command, g) {
            command.style.stroke = nil
            runs = split
        }
        if case .gradient(let g) = command.style.fill, g.geometry == .alongPath {
            command.style.fill = .color(g.ramp.color(at: 0.5))
        }
        if command.style.fill != nil || command.style.stroke != nil {
            out.append(command)
        }
        out.append(contentsOf: runs)
    }
    return out
}

/// An along-path stroke as solid runs, or `nil` when the geometry has no path
/// to follow (an ellipse/rect outline sweep stays a midpoint-color stroke).
private func alongStrokeRuns(_ command: RecordedSVG, _ gradient: Gradient) -> [RecordedSVG]? {
    var paths: [(points: [Vector2], closed: Bool)]
    switch command.geometry {
    case let .line(a, b):
        paths = [([a, b], false)]
    case let .quad(start, control, end):
        let n = 24
        let pts = (0...n).map { k -> Vector2 in
            let t = Double(k) / Double(n)
            let u = 1 - t
            return start * (u * u) + control * (2 * u * t) + end * (t * t)
        }
        paths = [(pts, false)]
    case let .polyline(points):
        paths = [(points, false)]
    case let .polygon(points):
        paths = [(points, true)]
    case let .path(shape):
        paths = shape.contours.map { ($0.points, $0.isClosed) }
    case .ellipse, .rect:
        return nil
    }

    var penStyle = command.style
    penStyle.fill = nil
    var out: [RecordedSVG] = []
    for (points, closed) in paths {
        var pts = points
        if closed, let first = pts.first { pts.append(first) }
        guard pts.count >= 2 else { continue }
        // Split long segments (the same ~12-point pieces the renderer shades
        // across), then color each piece at its midpoint arc length.
        var split: [Vector2] = []
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            split.append(a)
            let pieces = Int(((b - a).length / 12).rounded(.up))
            if pieces > 1 {
                for k in 1..<pieces { split.append(a + (b - a) * (Double(k) / Double(pieces))) }
            }
        }
        split.append(pts[pts.count - 1])
        var cumulative: [Double] = [0]
        for i in 1..<split.count { cumulative.append(cumulative[i - 1] + (split[i] - split[i - 1]).length) }
        let total = cumulative[split.count - 1]
        guard total > 0 else { continue }
        for i in 0..<(split.count - 1) {
            let midT = (cumulative[i] + cumulative[i + 1]) / (2 * total)
            penStyle.stroke = .color(gradient.ramp.color(at: midT))
            out.append(RecordedSVG(geometry: .line(split[i], split[i + 1]),
                                   style: penStyle, transform: command.transform))
        }
    }
    return out
}

/// Collect one def per distinct linear/radial gradient paint, keyed for
/// `url(#…)` references. `userSpaceOnUse` puts the coordinates in the same
/// pre-CTM space the geometry is recorded in, so an element's `transform`
/// carries its gradient along — exactly the render semantics.
private func gradientDefs(_ commands: [RecordedSVG]) -> (defs: String, ids: [Gradient: String]) {
    var ids: [Gradient: String] = [:]
    var lines: [String] = []
    func register(_ paint: Paint?) {
        guard case .gradient(let g) = paint, ids[g] == nil else { return }
        switch g.geometry {
        case let .linear(start, end):
            let id = "grad\(ids.count)"
            ids[g] = id
            lines.append("    <linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" "
                         + "x1=\"\(n(start.x))\" y1=\"\(n(start.y))\" x2=\"\(n(end.x))\" y2=\"\(n(end.y))\">")
            lines.append(contentsOf: stopLines(g.ramp))
            lines.append("    </linearGradient>")
        case let .radial(center, radius):
            let id = "grad\(ids.count)"
            ids[g] = id
            lines.append("    <radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" "
                         + "cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" r=\"\(n(radius))\">")
            lines.append(contentsOf: stopLines(g.ramp))
            lines.append("    </radialGradient>")
        case .alongPath:
            break   // resolved by approximateAlongPaths before serialization
        }
    }
    for command in commands {
        register(command.style.fill)
        register(command.style.stroke)
    }
    guard !lines.isEmpty else { return ("", ids) }
    return ("  <defs>\n" + lines.joined(separator: "\n") + "\n  </defs>\n", ids)
}

/// A ramp as SVG `<stop>`s. SVG interpolates stops in plain sRGB, so spans of a
/// ramp mixing in any other space are subdivided to track the ramp's curve;
/// duplicate-position stops (hard edges) pass through untouched.
private func stopLines(_ ramp: Ramp) -> [String] {
    var stops: [(position: Double, color: Color)] = []
    for (i, stop) in ramp.stops.enumerated() {
        stops.append((stop.position, stop.color))
        if ramp.space != .rgb, i + 1 < ramp.stops.count {
            let span = ramp.stops[i + 1].position - stop.position
            if span > 1e-9 {
                for k in 1...3 {
                    let p = stop.position + span * Double(k) / 4
                    stops.append((p, ramp.color(at: p)))
                }
            }
        }
    }
    return stops.map { stop in
        let opacity = stop.color.alpha < 1 ? " stop-opacity=\"\(n(stop.color.alpha))\"" : ""
        return "      <stop offset=\"\(n(stop.position))\" stop-color=\"\(svgColor(stop.color))\"\(opacity)/>"
    }
}

/// One recorded primitive as an SVG element.
private func svgElement(_ c: RecordedSVG, _ ids: [Gradient: String]) -> String {
    let t = matrixAttr(c.transform)
    switch c.geometry {
    case let .ellipse(center, rx, ry):
        let fillStroke = fillStrokeAttrs(c.style, ids)
        if abs(rx - ry) < 1e-9 {
            return "<circle cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" r=\"\(n(rx))\"\(fillStroke)\(t)/>"
        }
        return "<ellipse cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" rx=\"\(n(rx))\" ry=\"\(n(ry))\"\(fillStroke)\(t)/>"

    case let .rect(corner, w, h, r):
        let radius = r > 0 ? " rx=\"\(n(r))\"" : ""
        return "<rect x=\"\(n(corner.x))\" y=\"\(n(corner.y))\" width=\"\(n(w))\" height=\"\(n(h))\"\(radius)\(fillStrokeAttrs(c.style, ids))\(t)/>"

    case let .line(a, b):
        return "<line x1=\"\(n(a.x))\" y1=\"\(n(a.y))\" x2=\"\(n(b.x))\" y2=\"\(n(b.y))\"\(strokeOnlyAttrs(c.style, ids, forceCap: "round"))\(t)/>"

    case let .quad(s, control, e):
        let d = "M \(n(s.x)) \(n(s.y)) Q \(n(control.x)) \(n(control.y)) \(n(e.x)) \(n(e.y))"
        return "<path d=\"\(d)\"\(strokeOnlyAttrs(c.style, ids, forceCap: "round"))\(t)/>"

    case let .polyline(points):
        return "<polyline points=\"\(pointList(points))\"\(strokeOnlyAttrs(c.style, ids))\(t)/>"

    case let .polygon(points):
        return "<polygon points=\"\(pointList(points))\"\(fillStrokeAttrs(c.style, ids))\(t)/>"

    case let .path(shape):
        let rule = shape.winding == .evenOdd ? " fill-rule=\"evenodd\"" : ""
        return "<path d=\"\(pathData(shape))\"\(fillStrokeAttrs(c.style, ids))\(rule)\(t)/>"
    }
}

// MARK: - Attribute helpers

/// A paint as an SVG paint value: a color, or a gradient def reference. An
/// unregistered gradient (an along-path paint that had no path) falls back to
/// its ramp midpoint.
private func paintValue(_ paint: Paint, _ ids: [Gradient: String]) -> String {
    switch paint {
    case .color(let c):
        return svgColor(c)
    case .gradient(let g):
        if let id = ids[g] { return "url(#\(id))" }
        return svgColor(g.ramp.color(at: 0.5))
    }
}

/// The `*-opacity` attribute for a paint: only a flat color carries one (a
/// gradient's alpha rides its stops).
private func paintOpacity(_ kind: String, _ paint: Paint) -> String {
    if case .color(let c) = paint { return svgOpacity(kind, c) }
    return ""
}

/// Fill + stroke attributes for a filled, possibly stroked shape.
private func fillStrokeAttrs(_ s: SVGStyle, _ ids: [Gradient: String]) -> String {
    var attrs = " fill=\"\(s.fill.map { paintValue($0, ids) } ?? "none")\""
    if let fill = s.fill { attrs += paintOpacity("fill", fill) }
    attrs += strokeAttrs(s, ids)
    return attrs
}

/// Attributes for a stroke-only shape (no fill).
private func strokeOnlyAttrs(_ s: SVGStyle, _ ids: [Gradient: String], forceCap: String? = nil) -> String {
    " fill=\"none\"" + strokeAttrs(s, ids, forceCap: forceCap)
}

/// The stroke half: nothing when there's no visible stroke.
private func strokeAttrs(_ s: SVGStyle, _ ids: [Gradient: String], forceCap: String? = nil) -> String {
    guard let stroke = s.stroke else { return "" }
    var attrs = " stroke=\"\(paintValue(stroke, ids))\"\(paintOpacity("stroke", stroke)) stroke-width=\"\(n(s.strokeWidth))\""
    attrs += " stroke-linejoin=\"\(joinName(s.join))\""
    attrs += " stroke-linecap=\"\(forceCap ?? capName(s.cap))\""
    return attrs
}

private func joinName(_ j: StrokeJoin) -> String {
    switch j {
    case .miter: return "miter"
    case .bevel: return "bevel"
    case .round: return "round"
    }
}

private func capName(_ c: StrokeCap) -> String {
    switch c {
    case .butt: return "butt"
    case .round: return "round"
    case .square: return "square"
    }
}

/// `transform="matrix(...)"` for a non-identity CTM, else nothing. SVG's
/// `matrix(a b c d e f)` is the column-major affine: x' = a·x + c·y + e.
private func matrixAttr(_ m: simd_float3x3) -> String {
    let a = m.columns.0.x, b = m.columns.0.y
    let c = m.columns.1.x, d = m.columns.1.y
    let e = m.columns.2.x, f = m.columns.2.y
    if a == 1, b == 0, c == 0, d == 1, e == 0, f == 0 { return "" }
    return " transform=\"matrix(\(n(Double(a))) \(n(Double(b))) \(n(Double(c))) \(n(Double(d))) \(n(Double(e))) \(n(Double(f))))\""
}

/// `rgb(r,g,b)` with 0…255 channels (alpha rides separately as *-opacity).
private func svgColor(_ c: Color) -> String {
    func ch(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return "rgb(\(ch(c.red)),\(ch(c.green)),\(ch(c.blue)))"
}

/// A `fill-opacity` / `stroke-opacity` attribute when the color isn't opaque.
private func svgOpacity(_ kind: String, _ c: Color) -> String {
    c.alpha < 1 ? " \(kind)-opacity=\"\(n(c.alpha))\"" : ""
}

private func pointList(_ points: [Vector2]) -> String {
    points.map { "\(n($0.x)),\(n($0.y))" }.joined(separator: " ")
}

/// A `<path>` `d` from a shape's contours: each contour an `M … L …`, closed
/// contours appending `Z`.
private func pathData(_ shape: Shape) -> String {
    var parts: [String] = []
    for contour in shape.contours where contour.points.count >= 2 {
        var d = "M \(n(contour.points[0].x)) \(n(contour.points[0].y))"
        for p in contour.points.dropFirst() { d += " L \(n(p.x)) \(n(p.y))" }
        if contour.isClosed { d += " Z" }
        parts.append(d)
    }
    return parts.joined(separator: " ")
}

/// Format a coordinate: up to 3 decimals, trailing zeros trimmed, so the output
/// stays compact and `-0` reads as `0`.
private func n(_ value: Double) -> String {
    if value == 0 { return "0" }
    var s = String(format: "%.3f", value)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    return s == "-0" ? "0" : s
}

// MARK: - OllinApp entry points

public extension OllinApp {
    /// Render one frame of `sketch` as an SVG document string — no window, no GPU.
    /// Drives the sketch headlessly the way `image(of:)` does (`setup()`, then
    /// `draw()` advanced to `frame` at `fps`), but records the draw calls as vector
    /// geometry instead of rasterizing them. Because it never touches Metal, it
    /// runs anywhere and is deterministic.
    ///
    /// Curves and the analytic SDF-only shapes are emitted as fine polyline/path
    /// approximations; raster `drawImage` calls are skipped (noted as a comment).
    ///
    /// Pass `hatching` to plot solid fills as line work: each fill becomes
    /// parallel (or cross-hatch) lines clipped to its outline, spaced by tone, so
    /// a pen plotter can shade it (see `Hatching`).
    static func svg(of sketch: Sketch, frame: Int = 0, fps: Double = 60,
                    hatching: Hatching? = nil) -> String {
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()
        let recorder = SVGRecorder()
        for k in 0...max(0, frame) {                 // advance so frame N is correct
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.drawer.svgRecorder = (k == frame) ? recorder : nil
            sketch.performDraw()
        }
        sketch.drawer.svgRecorder = nil
        let commands = hatching.map { applyHatching(recorder.commands, $0) } ?? recorder.commands
        return serializeSVG(commands, background: sketch.drawer.backgroundColor,
                            width: size.width, height: size.height, skippedImages: recorder.skippedImages)
    }

    /// Render one frame of `sketch` and write it as an SVG file — no window, no GPU.
    /// The vector counterpart of `export`; the basis for the `--export-svg` flag.
    /// Pass `hatching` to plot solid fills as pen line work (see `svg(of:)`).
    static func exportSVG(_ sketch: Sketch, to path: String, frame: Int = 0, fps: Double = 60,
                          hatching: Hatching? = nil) {
        let document = svg(of: sketch, frame: frame, fps: fps, hatching: hatching)
        do {
            try document.write(toFile: path, atomically: true, encoding: .utf8)
            print("Ollin: exported frame \(frame) → \(path) (SVG)")
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
    }
}
