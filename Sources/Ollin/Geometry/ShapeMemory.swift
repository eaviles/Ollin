import Synchronization

/// One vertex of a stroke's expansion before the transform: where it sits and
/// how much of it the stroke covers. A solid stroke of one width lays its
/// color on every vertex alike, so this is all of it a shape needs to keep.
struct ExpandedStrokeVertex: Sendable {
    var position: SIMD2<Float>
    var coverage: Float
}

/// What a `Shape` remembers of being drawn, so a shape kept from one frame to
/// the next and drawn again unchanged (a traced outline recolored every frame)
/// costs a copy of its triangles and its stroke rather than a triangulation and
/// an expansion. The copies of one value share it, the way they share their
/// points.
///
/// It keeps nothing until the same contours are drawn twice, so a shape made
/// and drawn once a frame pays for a lock and nothing more: the fill is kept
/// from its second draw, a contour's stroke from its second draw at the same
/// width, join, cap, and scale, and both are handed back from the third.
///
/// It knows which contours it remembers by holding them. A copy of the shape
/// edited since has to copy those contours before it can change them, so an
/// edited shape never matches what is kept here; two different shapes sharing
/// one memory (a shape and an edited copy, drawn in turn) record over each
/// other and draw correctly, only without the saving.
final class ShapeMemory: Sendable {
    /// The settings a stroke's expansion depends on beyond its points.
    struct StrokeKey: Equatable, Sendable {
        var halfWidth: Double
        var join: StrokeJoin
        var cap: StrokeCap
        var ctmScale: Double
    }

    private struct KeptStroke: Sendable {
        var key: StrokeKey
        var vertices: [ExpandedStrokeVertex]?
    }

    private struct State: Sendable {
        /// The contours the rest was made from, held so that an edit to them
        /// copies them first (see the type's notes).
        var contours: [Contour] = []
        var winding: FillWinding = .evenOdd
        var fillSeen = false
        var fill: [Vector2]?
        var strokes: [KeptStroke?] = []

        /// Whether `shape` is the shape this state remembers: the same contour
        /// storage, and the same winding.
        func remembers(_ shape: Shape) -> Bool {
            guard !contours.isEmpty, contours.count == shape.contours.count,
                  winding == shape.winding else { return false }
            return Self.storage(of: contours) == Self.storage(of: shape.contours)
        }

        /// Start remembering `shape` when it is not the shape remembered.
        mutating func adopt(_ shape: Shape) {
            guard !remembers(shape) else { return }
            self = State(contours: shape.contours, winding: shape.winding,
                         strokes: Array(repeating: nil, count: shape.contours.count))
        }

        /// Where the contour array keeps its elements. Two arrays share it only
        /// when one is a copy of the other that neither has changed since.
        private static func storage(of contours: [Contour]) -> UnsafeRawPointer? {
            contours.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
        }
    }

    private enum Step<Value> {
        case kept(Value)
        case record
        case plain
    }

    private let state = Mutex(State())

    /// The fill triangles of `shape`, from memory when they were kept, or
    /// from `triangulate` (and kept, on the shape's second fill).
    func fill(of shape: Shape, triangulate: () -> [Vector2]) -> [Vector2] {
        guard !shape.contours.isEmpty else { return triangulate() }
        let step = state.withLock { state -> Step<[Vector2]> in
            state.adopt(shape)
            if let fill = state.fill { return .kept(fill) }
            if state.fillSeen { return .record }
            state.fillSeen = true
            return .plain
        }
        switch step {
        case .kept(let fill):
            return fill
        case .plain:
            return triangulate()
        case .record:
            let fill = triangulate()
            state.withLock { state in
                if state.remembers(shape) { state.fill = fill }
            }
            return fill
        }
    }

    /// The expanded stroke of contour `index` of `shape` under `key`, from
    /// memory when it was kept, or from `expand` (and kept, on the contour's
    /// second stroke under the same key).
    func stroke(of shape: Shape, contour index: Int, key: StrokeKey,
                expand: () -> [ExpandedStrokeVertex]) -> [ExpandedStrokeVertex] {
        guard shape.contours.indices.contains(index) else { return expand() }
        let step = state.withLock { state -> Step<[ExpandedStrokeVertex]> in
            state.adopt(shape)
            if let kept = state.strokes[index], kept.key == key {
                if let vertices = kept.vertices { return .kept(vertices) }
                return .record
            }
            state.strokes[index] = KeptStroke(key: key, vertices: nil)
            return .plain
        }
        switch step {
        case .kept(let vertices):
            return vertices
        case .plain:
            return expand()
        case .record:
            let vertices = expand()
            state.withLock { state in
                if state.remembers(shape), state.strokes[index]?.key == key {
                    state.strokes[index]?.vertices = vertices
                }
            }
            return vertices
        }
    }
}
