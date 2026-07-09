import CoreGraphics
import Foundation
import simd

// PDF export: the print-ready sibling of SVG export. The same vector commands
// the SVG path records (see SVGExport.swift and `svgRecord` in Drawer.swift)
// replay into a Core Graphics PDF context, so one recording feeds both
// serializers and the two outputs can't drift apart. Like the SVG path it
// records on the CPU and needs no GPU.

// MARK: - Serialization

/// Render recorded primitives into a single-page PDF document. One canvas
/// pixel maps to one PDF point (a `dpi(_:)`-scaled canvas instead declares its
/// page in points and the pixel geometry scales down onto it), and the page is
/// flipped once up front so the recorded top-left geometry lands upright
/// (PDF's origin is bottom-left). Linear and radial gradient paints draw as
/// native gradients clipped to their shape; along-path strokes are split into
/// short solid runs first, and along-path fills fall back to the ramp's
/// midpoint color (the same approximations the SVG serializer applies, via
/// `approximateAlongPaths`).
func serializePDF(_ commands: [SVGCommand], background: Color,
                  width: Int, height: Int,
                  pointWidth: Int? = nil, pointHeight: Int? = nil) -> Data {
    let pageWidth = pointWidth ?? width
    let pageHeight = pointHeight ?? height
    var mediaBox = CGRect(x: 0, y: 0, width: Double(pageWidth), height: Double(pageHeight))
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox,
                              [kCGPDFContextCreator: "Ollin"] as CFDictionary),
          let space = CGColorSpace(name: CGColorSpace.sRGB) else {
        return Data()
    }
    let painter = PDFPainter(ctx: ctx, space: space)
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: 0, y: CGFloat(pageHeight))
    ctx.scaleBy(x: 1, y: -1)
    // A high-dpi canvas draws in pixel coordinates onto the smaller point page.
    if pageWidth != width || pageHeight != height {
        ctx.scaleBy(x: CGFloat(pageWidth) / CGFloat(width),
                    y: CGFloat(pageHeight) / CGFloat(height))
    }
    ctx.setMiterLimit(4)   // SVG's default limit, so sharp miters clip the same way
    ctx.setFillColor(painter.color(background))
    ctx.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))
    // Clip regions map onto graphics-state save/restore pairs, so nesting
    // intersects exactly like the render's stencil levels (and the SVG groups).
    var open = 0
    for event in approximateAlongPaths(commands) {
        switch event {
        case .draw(let command):
            painter.draw(command)
        case .clipPush(let shape, let transform):
            ctx.saveGState()
            var placement = affine(transform)
            if let placed = pdfPath(.path(shape))?.copy(using: &placement) {
                ctx.addPath(placed)
            }
            ctx.clip(using: shape.winding == .evenOdd ? .evenOdd : .winding)
            open += 1
        case .clipPop:
            if open > 0 {
                ctx.restoreGState()
                open -= 1
            }
        }
    }
    while open > 0 {   // balance a block left open by an early exit
        ctx.restoreGState()
        open -= 1
    }
    ctx.endPDFPage()
    ctx.closePDF()
    return data as Data
}

/// Draws recorded commands into one PDF context; holds the context and the
/// document color space so per-command helpers don't re-create them.
private struct PDFPainter {
    let ctx: CGContext
    let space: CGColorSpace

    /// Draw one recorded primitive: concatenate its CTM, build its path, then
    /// fill and stroke in that order (the SVG paint order).
    func draw(_ command: RecordedSVG) {
        guard let path = pdfPath(command.geometry) else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.concatenate(affine(command.transform))
        // Only a `.path` carries a fill rule; everything else matches SVG's
        // non-zero default (their outlines don't self-intersect anyway).
        var rule = CGPathFillRule.winding
        if case let .path(shape) = command.geometry, shape.winding == .evenOdd {
            rule = .evenOdd
        }
        if let fill = command.style.fill {
            switch resolved(fill) {
            case .color(let c):
                ctx.setFillColor(color(c))
                ctx.addPath(path)
                ctx.fillPath(using: rule)
            case .gradient(let g):
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip(using: rule)
                drawGradient(g)
                ctx.restoreGState()
            }
        }
        if let stroke = command.style.stroke {
            ctx.setLineWidth(CGFloat(command.style.strokeWidth))
            ctx.setLineJoin(join(command.style.join))
            ctx.setLineCap(cap(command.style.cap))
            switch resolved(stroke) {
            case .color(let c):
                ctx.setStrokeColor(color(c))
                ctx.addPath(path)
                ctx.strokePath()
            case .gradient(let g):
                // A gradient stroke: turn the stroke into its outline region,
                // clip to it, and draw the gradient through (the PDF analog of
                // SVG's stroke="url(#…)").
                ctx.saveGState()
                ctx.addPath(path)
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                drawGradient(g)
                ctx.restoreGState()
            }
        }
    }

    /// A paint with the inexpressible case resolved: an along-path gradient
    /// that kept no path (an ellipse/rect outline sweep) falls back to its
    /// ramp's midpoint color, the same fallback the SVG serializer uses.
    private func resolved(_ paint: Paint) -> Paint {
        if case .gradient(let g) = paint, g.geometry == .alongPath {
            return .color(g.ramp.color(at: 0.5))
        }
        return paint
    }

    /// Draw a linear/radial gradient across the current clip, in the recorded
    /// user space (the element's CTM is already concatenated, matching SVG's
    /// userSpaceOnUse semantics). Both ends extend, SVG's "pad" spread.
    private func drawGradient(_ g: Gradient) {
        let stops = flattenedRampStops(g.ramp)
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: stops.map { color($0.color) } as CFArray,
                                        locations: stops.map { CGFloat($0.position) }) else { return }
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch g.geometry {
        case let .linear(start, end):
            ctx.drawLinearGradient(gradient, start: point(start), end: point(end), options: options)
        case let .radial(center, radius):
            ctx.drawRadialGradient(gradient, startCenter: point(center), startRadius: 0,
                                   endCenter: point(center), endRadius: CGFloat(radius), options: options)
        case .alongPath:
            break   // resolved before serialization / by `resolved(_:)`
        }
    }

    func color(_ c: Color) -> CGColor {
        func ch(_ v: Double) -> CGFloat { CGFloat(min(max(v, 0), 1)) }
        return CGColor(colorSpace: space,
                       components: [ch(c.red), ch(c.green), ch(c.blue), ch(c.alpha)])
            ?? CGColor(gray: 0, alpha: 1)
    }

    private func join(_ j: StrokeJoin) -> CGLineJoin {
        switch j {
        case .miter: return .miter
        case .bevel: return .bevel
        case .round: return .round
        }
    }

    private func cap(_ c: StrokeCap) -> CGLineCap {
        switch c {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

// MARK: - Geometry helpers

/// One recorded geometry as a `CGPath` in its user space, or `nil` when it has
/// nothing to draw. The cases mirror the SVG elements exactly: native ellipse
/// and (rounded) rect, open line/quad/polyline strokes, closed polygons, and
/// multi-contour shapes whose closed contours close their subpath.
private func pdfPath(_ geometry: SVGGeometry) -> CGPath? {
    let path = CGMutablePath()
    switch geometry {
    case let .ellipse(center, rx, ry):
        path.addEllipse(in: CGRect(x: center.x - rx, y: center.y - ry,
                                   width: rx * 2, height: ry * 2))
    case let .rect(corner, w, h, r):
        let rect = CGRect(x: corner.x, y: corner.y, width: w, height: h)
        let rr = min(r, min(w, h) / 2)   // a radius past the half-extent traps
        if rr > 0 {
            path.addRoundedRect(in: rect, cornerWidth: rr, cornerHeight: rr)
        } else {
            path.addRect(rect)
        }
    case let .line(a, b):
        path.move(to: point(a))
        path.addLine(to: point(b))
    case let .quad(start, control, end):
        path.move(to: point(start))
        path.addQuadCurve(to: point(end), control: point(control))
    case let .polyline(points):
        guard points.count >= 2 else { return nil }
        path.addLines(between: points.map(point))
    case let .polygon(points):
        guard points.count >= 2 else { return nil }
        path.addLines(between: points.map(point))
        path.closeSubpath()
    case let .path(shape):
        for contour in shape.contours where contour.points.count >= 2 {
            path.addLines(between: contour.points.map(point))   // starts a new subpath
            if contour.isClosed { path.closeSubpath() }
        }
    }
    return path.isEmpty ? nil : path
}

private func point(_ p: Vector2) -> CGPoint { CGPoint(x: p.x, y: p.y) }

/// A recorded 2D homogeneous CTM as the affine transform Core Graphics takes.
private func affine(_ m: simd_float3x3) -> CGAffineTransform {
    CGAffineTransform(a: CGFloat(m.columns.0.x), b: CGFloat(m.columns.0.y),
                      c: CGFloat(m.columns.1.x), d: CGFloat(m.columns.1.y),
                      tx: CGFloat(m.columns.2.x), ty: CGFloat(m.columns.2.y))
}

// MARK: - OllinApp entry points

public extension OllinApp {
    /// Render one frame of `sketch` as a single-page PDF document: no window,
    /// no GPU. Drives the sketch headlessly the way `svg(of:)` does and replays
    /// the same recorded vector geometry through Core Graphics, so the PDF and
    /// the SVG of a frame always agree. One canvas pixel maps to one PDF point
    /// (a `dpi(_:)`-scaled canvas keeps its declared page size instead, so
    /// `.a4.dpi(300)` still writes a true A4 page), and the output stays true
    /// vector art for print.
    ///
    /// Curves and the analytic SDF-only shapes are emitted as fine polyline/path
    /// approximations; raster `drawImage` calls are skipped.
    ///
    /// Pass `hatching` to plot solid fills as line work: each fill becomes
    /// parallel (or cross-hatch) lines clipped to its outline, spaced by tone
    /// (see `Hatching`).
    static func pdf(of sketch: Sketch, frame: Int = 0, fps: Double = 60,
                    hatching: Hatching? = nil) -> Data {
        let recording = recordVectorFrame(of: sketch, frame: frame, fps: fps, hatching: hatching)
        return serializePDF(recording.commands, background: recording.background,
                            width: recording.width, height: recording.height,
                            pointWidth: recording.pointWidth, pointHeight: recording.pointHeight)
    }

    /// Render one frame of `sketch` and write it as a PDF file: no window, no
    /// GPU. The print-ready counterpart of `exportSVG`; the basis for the
    /// `--export-pdf` flag. Pass `hatching` to plot solid fills as pen line
    /// work (see `pdf(of:)`).
    static func exportPDF(_ sketch: Sketch, to path: String, frame: Int = 0, fps: Double = 60,
                          hatching: Hatching? = nil) {
        let recording = recordVectorFrame(of: sketch, frame: frame, fps: fps, hatching: hatching)
        let document = serializePDF(recording.commands, background: recording.background,
                                    width: recording.width, height: recording.height,
                                    pointWidth: recording.pointWidth, pointHeight: recording.pointHeight)
        if recording.skippedImages > 0 {
            print("Ollin: \(recording.skippedImages) image draw(s) skipped (raster is omitted from vector export)")
        }
        do {
            try document.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("Ollin: exported frame \(frame) → \(path) (PDF)")
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
    }
}
