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
/// the live `Drawer` state.
struct SVGStyle {
    var fill: Color?
    var stroke: Color?        // already nil when there's no visible stroke
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

// MARK: - Serialization

/// Render recorded primitives into an SVG document string.
func serializeSVG(_ commands: [RecordedSVG], background: Color,
                  width: Int, height: Int, skippedImages: Int = 0) -> String {
    var out = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">

    """
    out += "  <rect width=\"\(width)\" height=\"\(height)\" fill=\"\(svgColor(background))\"\(svgOpacity("fill", background))/>\n"
    if skippedImages > 0 {
        out += "  <!-- \(skippedImages) image draw(s) skipped: raster is omitted from vector export -->\n"
    }
    for command in commands {
        out += "  " + svgElement(command) + "\n"
    }
    out += "</svg>\n"
    return out
}

/// One recorded primitive as an SVG element.
private func svgElement(_ c: RecordedSVG) -> String {
    let t = matrixAttr(c.transform)
    switch c.geometry {
    case let .ellipse(center, rx, ry):
        let fillStroke = fillStrokeAttrs(c.style)
        if abs(rx - ry) < 1e-9 {
            return "<circle cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" r=\"\(n(rx))\"\(fillStroke)\(t)/>"
        }
        return "<ellipse cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" rx=\"\(n(rx))\" ry=\"\(n(ry))\"\(fillStroke)\(t)/>"

    case let .rect(corner, w, h, r):
        let radius = r > 0 ? " rx=\"\(n(r))\"" : ""
        return "<rect x=\"\(n(corner.x))\" y=\"\(n(corner.y))\" width=\"\(n(w))\" height=\"\(n(h))\"\(radius)\(fillStrokeAttrs(c.style))\(t)/>"

    case let .line(a, b):
        return "<line x1=\"\(n(a.x))\" y1=\"\(n(a.y))\" x2=\"\(n(b.x))\" y2=\"\(n(b.y))\"\(strokeOnlyAttrs(c.style, forceCap: "round"))\(t)/>"

    case let .quad(s, control, e):
        let d = "M \(n(s.x)) \(n(s.y)) Q \(n(control.x)) \(n(control.y)) \(n(e.x)) \(n(e.y))"
        return "<path d=\"\(d)\"\(strokeOnlyAttrs(c.style, forceCap: "round"))\(t)/>"

    case let .polyline(points):
        return "<polyline points=\"\(pointList(points))\"\(strokeOnlyAttrs(c.style))\(t)/>"

    case let .polygon(points):
        return "<polygon points=\"\(pointList(points))\"\(fillStrokeAttrs(c.style))\(t)/>"

    case let .path(shape):
        let rule = shape.winding == .evenOdd ? " fill-rule=\"evenodd\"" : ""
        return "<path d=\"\(pathData(shape))\"\(fillStrokeAttrs(c.style))\(rule)\(t)/>"
    }
}

// MARK: - Attribute helpers

/// Fill + stroke attributes for a filled, possibly stroked shape.
private func fillStrokeAttrs(_ s: SVGStyle) -> String {
    var attrs = " fill=\"\(s.fill.map(svgColor) ?? "none")\""
    if let fill = s.fill { attrs += svgOpacity("fill", fill) }
    attrs += strokeAttrs(s)
    return attrs
}

/// Attributes for a stroke-only shape (no fill).
private func strokeOnlyAttrs(_ s: SVGStyle, forceCap: String? = nil) -> String {
    " fill=\"none\"" + strokeAttrs(s, forceCap: forceCap)
}

/// The stroke half: nothing when there's no visible stroke.
private func strokeAttrs(_ s: SVGStyle, forceCap: String? = nil) -> String {
    guard let stroke = s.stroke else { return "" }
    var attrs = " stroke=\"\(svgColor(stroke))\"\(svgOpacity("stroke", stroke)) stroke-width=\"\(n(s.strokeWidth))\""
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
    static func svg(of sketch: Sketch, frame: Int = 0, fps: Double = 60) -> String {
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
        return serializeSVG(recorder.commands, background: sketch.drawer.backgroundColor,
                            width: size.width, height: size.height, skippedImages: recorder.skippedImages)
    }

    /// Render one frame of `sketch` and write it as an SVG file — no window, no GPU.
    /// The vector counterpart of `export`; the basis for the `--export-svg` flag.
    static func exportSVG(_ sketch: Sketch, to path: String, frame: Int = 0, fps: Double = 60) {
        let document = svg(of: sketch, frame: frame, fps: fps)
        do {
            try document.write(toFile: path, atomically: true, encoding: .utf8)
            print("Ollin: exported frame \(frame) → \(path) (SVG)")
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
    }
}
