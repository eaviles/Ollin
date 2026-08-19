import Foundation

/// A builder for one curved or straight outline, sampled into a polygonal
/// `Contour` (and a single-contour `Shape`) you can fill or stroke.
///
/// `Path` is the curve-aware way to author a `Shape`: you trace an outline with
/// pen-style commands — `move(to:)` to start, then `line`, `curve`, `quadCurve`,
/// or `cubicCurve`, and an optional `close()` — and the curves are *sampled to
/// points* when you read `contour`/`shape`, so they ride the same triangulated
/// fill + stroked path everything else does (no special pipeline).
///
/// The three curve verbs differ in who supplies the bend:
/// - `curve(to:)` — a smooth curve that passes *through* the points, with the
///   tangents derived automatically from the neighbors (a Catmull-Rom spline).
///   Consecutive `curve(to:)` calls form one smooth run. This is the "draw a
///   wiggle straight from points" curve; see also the top-level `drawCurve`.
/// - `quadCurve(to:control:)` — a quadratic Bézier; you give one control point.
/// - `cubicCurve(to:control1:control2:)` — a cubic Bézier; you give two.
///
/// A `Path` describes a *single* outline (open or closed). For a filled region
/// with holes (a donut, a frame), compose contours with `Shape(outer:holes:)`.
///
/// ```swift
/// let blob = Path { p in
///     p.move(to: Vector2(200, 300))
///     p.curve(to: Vector2(400, 200))
///     p.curve(to: Vector2(600, 360))
///     p.close()
/// }
/// drawShape(blob.shape)
/// ```
public struct Path: Equatable, Sendable {
    /// One recorded pen command. Curves keep their control points; sampling
    /// happens lazily when the outline is read.
    enum Command: Equatable, Sendable {
        case move(Vector2)
        case line(Vector2)
        case curve(Vector2)                                       // Catmull-Rom anchor
        case quad(control: Vector2, end: Vector2)                 // quadratic Bézier
        case cubic(control1: Vector2, control2: Vector2, end: Vector2)  // cubic Bézier
        case close
    }

    private var commands: [Command] = []

    /// An empty path; trace it with the pen methods.
    public init() {}

    /// Build a path inline: `Path { p in p.move(to: a); p.curve(to: b) }`.
    public init(_ build: (inout Path) -> Void) {
        var path = Path()
        build(&path)
        self = path
    }

    // MARK: Pen commands

    /// Set where the outline starts (lift the pen and put it down). Typically
    /// the first call.
    public mutating func move(to point: Vector2) { commands.append(.move(point)) }

    /// Add a straight segment to `point`.
    public mutating func line(to point: Vector2) { commands.append(.line(point)) }

    /// Add a smooth segment to `point`, passing through it with tangents derived
    /// from the surrounding points (Catmull-Rom). Consecutive `curve(to:)` calls
    /// form one continuous smooth run.
    public mutating func curve(to point: Vector2) { commands.append(.curve(point)) }

    /// Add a quadratic Bézier curve to `point`, bending toward `control`.
    public mutating func quadCurve(to point: Vector2, control: Vector2) {
        commands.append(.quad(control: control, end: point))
    }

    /// Add a cubic Bézier curve to `point`, shaped by `control1` (leaving the
    /// current point) and `control2` (arriving at `point`).
    public mutating func cubicCurve(to point: Vector2, control1: Vector2, control2: Vector2) {
        commands.append(.cubic(control1: control1, control2: control2, end: point))
    }

    /// Close the outline (join the end back to the start), making it a fillable
    /// loop. Optional — an unclosed path is an open, stroke-only outline.
    public mutating func close() { commands.append(.close) }

    // MARK: Outputs

    /// The outline sampled into a polygonal `Contour` (curves flattened to
    /// points). `isClosed` reflects whether `close()` was called.
    public var contour: Contour {
        let (points, closed) = sampledPoints()
        return Contour(points, closed: closed)
    }

    /// The outline as a single-contour `Shape`, ready for `drawShape`.
    public var shape: Shape { Shape(contours: [contour]) }

    // MARK: Sampling

    /// Walk the recorded commands into a flat point list, flattening each curve
    /// as it goes. A run of consecutive `curve` anchors is splined together (they
    /// need each other as tangents); Béziers flatten independently.
    private func sampledPoints() -> (points: [Vector2], closed: Bool) {
        var points: [Vector2] = []
        var current = Vector2.zero
        var started = false
        var closed = false

        func start(at p: Vector2) {
            current = p
            points.append(p)
            started = true
        }

        var i = 0
        while i < commands.count {
            switch commands[i] {
            case .move(let p):
                // One outline: a later move just relocates the pen, connecting on.
                start(at: p)
                i += 1
            case .line(let p):
                if !started { start(at: p) } else { points.append(p); current = p }
                i += 1
            case .quad(let c, let end):
                if !started { start(at: current) }
                points.append(contentsOf: CurveSampling.quadratic(from: current, control: c, end: end))
                current = end
                i += 1
            case .cubic(let c1, let c2, let end):
                if !started { start(at: current) }
                points.append(contentsOf: CurveSampling.cubic(from: current, control1: c1, control2: c2, end: end))
                current = end
                i += 1
            case .curve:
                // Gather the maximal run of consecutive curve anchors, including
                // the current pen position as the run's first anchor.
                var anchors: [Vector2] = started ? [current] : []
                while i < commands.count, case .curve(let p) = commands[i] {
                    anchors.append(p)
                    i += 1
                }
                if !started, let first = anchors.first { start(at: first) }
                // anchors[0] is already the last appended point; add the rest.
                let sampled = CurveSampling.catmullRom(through: anchors, closed: false)
                points.append(contentsOf: sampled.dropFirst())
                if let last = anchors.last { current = last }
            case .close:
                closed = true
                i += 1
            }
        }
        return (points, closed)
    }
}

/// Curve-to-polyline flattening shared by `Path` and the `curveThrough`
/// convenience initialisers. Segment counts scale with on-canvas length so big
/// curves stay smooth and small ones stay cheap (the ~8-point target edge the
/// circle tessellator uses).
enum CurveSampling {
    /// Target chord length per flattened segment, in points.
    private static let targetEdge = 8.0

    private static func segments(forLength length: Double) -> Int {
        min(100, max(6, Int((length / targetEdge).rounded(.up))))
    }

    /// A quadratic Bézier flattened to points, **excluding** the start `from`
    /// (the caller already has it).
    static func quadratic(from: Vector2, control: Vector2, end: Vector2) -> [Vector2] {
        let length = (control - from).length + (end - control).length
        let n = segments(forLength: length)
        var out: [Vector2] = []
        out.reserveCapacity(n)
        for i in 1...n {
            let t = Double(i) / Double(n)
            let u = 1 - t
            out.append(from * (u * u) + control * (2 * u * t) + end * (t * t))
        }
        return out
    }

    /// A cubic Bézier flattened to points, **excluding** the start `from`.
    static func cubic(from: Vector2, control1: Vector2, control2: Vector2, end: Vector2) -> [Vector2] {
        let length = (control1 - from).length + (control2 - control1).length + (end - control2).length
        let n = segments(forLength: length)
        var out: [Vector2] = []
        out.reserveCapacity(n)
        for i in 1...n {
            let t = Double(i) / Double(n)
            let u = 1 - t
            out.append(from * (u * u * u)
                       + control1 * (3 * u * u * t)
                       + control2 * (3 * u * t * t)
                       + end * (t * t * t))
        }
        return out
    }

    /// A smooth Catmull-Rom curve through `anchors`, returned as the full sampled
    /// polyline (including the first anchor). Open runs clamp their end tangents
    /// by duplicating the endpoints; closed loops wrap around.
    static func catmullRom(through anchors: [Vector2], closed: Bool) -> [Vector2] {
        let n = anchors.count
        guard n >= 3 else { return anchors }   // 0/1/2 points: nothing to smooth

        func at(_ index: Int) -> Vector2 {
            if closed { return anchors[((index % n) + n) % n] }
            return anchors[min(max(index, 0), n - 1)]
        }

        var out: [Vector2] = [anchors[0]]
        let lastSegment = closed ? n : n - 1
        for i in 0..<lastSegment {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            let steps = segments(forLength: (p2 - p1).length)
            // On a closed loop the final segment's t = 1 lands back on the start,
            // which the closed contour already implies — so skip it.
            let top = (closed && i == lastSegment - 1) ? steps - 1 : steps
            guard top >= 1 else { continue }
            for s in 1...top {
                let t = Double(s) / Double(steps)
                out.append(catmullRomPoint(p0, p1, p2, p3, t))
            }
        }
        return out
    }

    /// Uniform Catmull-Rom interpolation on the segment between `p1` and `p2`.
    private static func catmullRomPoint(_ p0: Vector2, _ p1: Vector2, _ p2: Vector2,
                                        _ p3: Vector2, _ t: Double) -> Vector2 {
        let t2 = t * t
        let t3 = t2 * t
        return (p1 * 2.0
                + (p2 - p0) * t
                + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
                + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) * 0.5
    }
}

public extension Contour {
    /// A smooth contour passing through `points` (a Catmull-Rom spline). Closed
    /// loops wrap for seamless smoothness; open ones clamp their ends.
    init(curveThrough points: [Vector2], closed: Bool = true) {
        self.init(CurveSampling.catmullRom(through: points, closed: closed), closed: closed)
    }
}

public extension Shape {
    /// A single-contour shape whose outline is a smooth curve through `points`
    /// (see `Contour(curveThrough:closed:)`).
    init(curveThrough points: [Vector2], closed: Bool = true) {
        self.init(contours: [Contour(curveThrough: points, closed: closed)])
    }
}
