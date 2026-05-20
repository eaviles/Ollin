import Foundation
import simd

/// One vertex of stroked/filled geometry, as consumed by the Metal pipeline.
///
/// The memory layout of this struct must match `Vertex` in `Shaders.metal`:
///   - `position` (float2) at offset 0
///   - `color`    (float4) at offset 16 (float4 has 16-byte alignment)
/// Both sides therefore have a stride of 32 bytes. Keep them in sync if you
/// add fields.
struct OllinVertex {
    var position: SIMD2<Float>   // sketch-space, points, top-left origin, y-down
    var color: SIMD4<Float>      // straight (non-premultiplied) RGBA, 0...1
}

/// The drawing state machine and per-frame geometry recorder.
///
/// `Drawer` is p5/OPENRNDR-flavored: you set *state* (fill, stroke, weight,
/// background) and then call *primitives* (circle, …). Each primitive is
/// tessellated on the CPU into triangles and appended to `vertices`, which the
/// renderer uploads and draws in a single pass.
///
/// State (fill/stroke/weight/background) persists across frames, just like p5.
/// Geometry does not: the runner calls `beginFrame()` each frame to clear it.
final class Drawer {
    // MARK: Drawing state (persists across frames)

    /// The clear color for the frame. `nil`-fill / `nil`-stroke mean "don't draw".
    private(set) var backgroundColor: Color = .black
    private var fillColor: Color? = .white     // p5 default: white fill
    private var strokeColor: Color? = .black    // p5 default: black stroke
    private var strokeWidth: Double = 1         // p5 default: 1px

    // MARK: Per-frame geometry (reset every frame)

    private(set) var vertices: [OllinVertex] = []

    // MARK: State setters (mirrors the bare API on `Sketch`)

    /// Set the background/clear color. Like p5, this also wipes anything drawn
    /// so far this frame (background paints over everything).
    func background(_ color: Color) {
        backgroundColor = color
        vertices.removeAll(keepingCapacity: true)
    }

    func fill(_ color: Color) { fillColor = color }
    func noFill() { fillColor = nil }
    func stroke(_ color: Color) { strokeColor = color }
    func noStroke() { strokeColor = nil }
    func strokeWeight(_ weight: Double) { strokeWidth = max(0, weight) }

    // MARK: Frame lifecycle

    /// Drop last frame's geometry but keep drawing state. Called once per frame
    /// by the runner before `Sketch.draw()`.
    func beginFrame() {
        vertices.removeAll(keepingCapacity: true)
    }

    // MARK: Primitives

    /// A circle centered at `(x, y)` with the given `radius` (points).
    ///
    /// If a fill is set, the disk is emitted as a triangle fan. If a stroke is
    /// set, the outline is emitted as a triangle-strip annulus (a ring of width
    /// `strokeWeight`). Both go through the same solid-color pipeline; the
    /// MTKView's 4× MSAA gives us the anti-aliased edge for free.
    func circle(x: Double, y: Double, radius: Double) {
        guard radius > 0 else { return }
        let segments = circleSegments(for: radius)
        if let fill = fillColor {
            appendDisk(cx: x, cy: y, radius: radius, segments: segments, color: fill)
        }
        if let stroke = strokeColor, strokeWidth > 0 {
            appendRing(cx: x, cy: y, radius: radius, weight: strokeWidth,
                       segments: segments, color: stroke)
        }
    }

    // MARK: Tessellation helpers

    /// Pick a vertex count that keeps each edge segment ≲ 4 points long, so big
    /// circles stay smooth and small ones stay cheap.
    private func circleSegments(for radius: Double) -> Int {
        let targetEdgeLength = 4.0
        let circumference = 2.0 * .pi * radius
        return max(24, Int((circumference / targetEdgeLength).rounded(.up)))
    }

    private func point(cx: Double, cy: Double, radius: Double, angle: Double) -> SIMD2<Float> {
        SIMD2<Float>(Float(cx + cos(angle) * radius),
                     Float(cy + sin(angle) * radius))
    }

    /// Filled disk as a triangle fan, expanded into explicit triangles so the
    /// whole frame can be one `.triangle` draw call.
    private func appendDisk(cx: Double, cy: Double, radius: Double,
                            segments: Int, color: Color) {
        let c = color.simd4
        let center = SIMD2<Float>(Float(cx), Float(cy))
        for i in 0..<segments {
            let a0 = Double(i)     / Double(segments) * 2.0 * .pi
            let a1 = Double(i + 1) / Double(segments) * 2.0 * .pi
            let p0 = point(cx: cx, cy: cy, radius: radius, angle: a0)
            let p1 = point(cx: cx, cy: cy, radius: radius, angle: a1)
            vertices.append(OllinVertex(position: center, color: c))
            vertices.append(OllinVertex(position: p0, color: c))
            vertices.append(OllinVertex(position: p1, color: c))
        }
    }

    /// Stroked outline as an annulus (ring) between an inner and outer radius,
    /// expanded into triangles. The stroke straddles the geometric radius.
    private func appendRing(cx: Double, cy: Double, radius: Double, weight: Double,
                            segments: Int, color: Color) {
        let c = color.simd4
        let inner = max(0, radius - weight / 2)
        let outer = radius + weight / 2
        for i in 0..<segments {
            let a0 = Double(i)     / Double(segments) * 2.0 * .pi
            let a1 = Double(i + 1) / Double(segments) * 2.0 * .pi
            let i0 = point(cx: cx, cy: cy, radius: inner, angle: a0)
            let o0 = point(cx: cx, cy: cy, radius: outer, angle: a0)
            let i1 = point(cx: cx, cy: cy, radius: inner, angle: a1)
            let o1 = point(cx: cx, cy: cy, radius: outer, angle: a1)
            // Quad (i0, o0, o1, i1) -> two triangles.
            vertices.append(OllinVertex(position: i0, color: c))
            vertices.append(OllinVertex(position: o0, color: c))
            vertices.append(OllinVertex(position: o1, color: c))
            vertices.append(OllinVertex(position: i0, color: c))
            vertices.append(OllinVertex(position: o1, color: c))
            vertices.append(OllinVertex(position: i1, color: c))
        }
    }
}

extension Color {
    /// GPU vertex-color representation.
    var simd4: SIMD4<Float> {
        SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }
}
