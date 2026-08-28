// Where a draw call was written, and what the pointer is over. Together these
// are the reading half of dragging a shape in a live window and having the
// numbers in the file change; the writing half is the host's.
//
// Off unless a host asks for it: a sketch that nobody is editing records
// nothing and pays one branch per draw call.

import Foundation
import simd

/// Where in a `.swift` file one draw call was written, and which of its
/// arguments carry the shape's position.
///
/// Captured at the call site through `#fileID` / `#line` / `#column` default
/// arguments, so it costs the caller nothing to write and cannot drift from
/// the code. The column is the call's opening parenthesis, in UTF-8 bytes from
/// the start of the line, which is what Swift reports.
package struct SourceSite: Sendable {
    /// `Module/File.swift`. Match on the *name*, never the whole path: a live
    /// compile builds from a copy of the file under its own name, so the path
    /// belongs to a work directory that no longer exists.
    package let file: StaticString
    package let line: Int
    /// The byte column of the call's `(`.
    package let column: Int
    /// Which arguments hold the position.
    package let move: SourceMove

    package init(file: StaticString, line: Int, column: Int, move: SourceMove) {
        self.file = file
        self.line = line
        self.column = column
        self.move = move
    }

    /// The file's own name, without its module or folder.
    package var fileName: String {
        (file.description as NSString).lastPathComponent
    }
}

extension SourceSite: Equatable {
    package static func == (a: SourceSite, b: SourceSite) -> Bool {
        a.line == b.line && a.column == b.column && a.move == b.move
            && a.file.description == b.file.description
    }
}

/// Which of a call's arguments hold the position, and in what form.
///
/// A shape with two ends (a line, a capsule) lists both of its points, so
/// moving it moves the whole shape rather than one end.
package enum SourceMove: Sendable, Equatable {
    /// The position arrives as bare scalars, at these argument indices, in
    /// x, y order: `drawCircle(200, 300, 40)` is `.scalars([0, 1])`.
    case scalars([Int])
    /// The position arrives as `Vector2` arguments, at these indices:
    /// `drawCircle(center: Vector2(200, 300), radius: 40)` is `.points([0])`.
    case points([Int])

    /// The everyday case: a shape placed by `x, y` as its first two arguments.
    package static let xy = SourceMove.scalars([0, 1])
    /// The everyday labeled case: a shape placed by one point argument.
    package static let point = SourceMove.points([0])
}

/// One shape the pointer can be over, as the drawer recorded it: the region in
/// the space the call drew in, plus the transform that puts that space on the
/// canvas.
struct SourcePickTarget {
    /// The region a click has to land in, in the call's own coordinates.
    enum Region {
        case ellipse(center: Vector2, radii: Vector2)
        case box(center: Vector2, half: Vector2)
        /// An isosceles wedge with its apex at `apex`, opening toward +y.
        case wedge(apex: Vector2, halfBase: Double, height: Double)
        case capsule(a: Vector2, b: Vector2, radius: Double)
    }

    let site: SourceSite
    /// Local space to canvas points.
    let transform: matrix_float3x3
    let region: Region

    /// Whether `point` (in the call's own coordinates) is inside the shape.
    func contains(local point: Vector2) -> Bool {
        switch region {
        case .ellipse(let center, let radii):
            guard radii.x > 0, radii.y > 0 else { return false }
            let d = point - center
            let u = d.x / radii.x, v = d.y / radii.y
            return u * u + v * v <= 1
        case .box(let center, let half):
            let d = point - center
            return abs(d.x) <= half.x && abs(d.y) <= half.y
        case .wedge(let apex, let halfBase, let height):
            guard height > 0 else { return false }
            let d = point - apex
            // The wedge opens toward +y in Ollin's y-down space, widening from
            // nothing at the apex to `halfBase` at the far edge.
            guard d.y >= 0, d.y <= height else { return false }
            return abs(d.x) <= halfBase * (d.y / height)
        case .capsule(let a, let b, let radius):
            let ab = b - a
            let length2 = ab.x * ab.x + ab.y * ab.y
            guard length2 > 1e-12 else { return (point - a).length <= radius }
            let t = Swift.max(0, Swift.min(1, ((point - a).x * ab.x + (point - a).y * ab.y) / length2))
            return (point - (a + ab * t)).length <= radius
        }
    }

    /// The region's corners, in the call's own coordinates, for the outline a
    /// host draws over the shape it is about to move.
    var localCorners: [Vector2] {
        let (center, half): (Vector2, Vector2) = {
            switch region {
            case .ellipse(let c, let r): return (c, r)
            case .box(let c, let h): return (c, h)
            case .wedge(let apex, let halfBase, let height):
                return (Vector2(apex.x, apex.y + height / 2), Vector2(halfBase, height / 2))
            case .capsule(let a, let b, let radius):
                let lo = Vector2(Swift.min(a.x, b.x) - radius, Swift.min(a.y, b.y) - radius)
                let hi = Vector2(Swift.max(a.x, b.x) + radius, Swift.max(a.y, b.y) + radius)
                return ((lo + hi) / 2, (hi - lo) / 2)
            }
        }()
        return [Vector2(center.x - half.x, center.y - half.y),
                Vector2(center.x + half.x, center.y - half.y),
                Vector2(center.x + half.x, center.y + half.y),
                Vector2(center.x - half.x, center.y + half.y)]
    }
}

/// A shape the pointer is over, handed to a host so it can outline the shape
/// and turn a drag into an edit of the file the sketch was written in.
package struct SourcePick: Sendable {
    /// Where the call that drew it was written.
    package let site: SourceSite
    /// The shape's corners in canvas points, in order, for a highlight. Under a
    /// rotation these are a rotated quad, not an axis-aligned box.
    package let outline: [Vector2]
    /// Canvas points to the call's own coordinates, without the translation:
    /// a drag is a difference, so only the rotation and scale apply.
    let canvasToLocal: matrix_float2x2

    /// How much the call's numbers have to change for the shape to follow a
    /// drag of `canvasDelta` on screen. Under `translate`/`rotate`/`scale` this
    /// is not the same as the drag: a shape drawn at half scale moves by twice
    /// the numbers.
    package func numbersDelta(forCanvasDelta canvasDelta: Vector2) -> Vector2 {
        let d = canvasToLocal * SIMD2<Float>(Float(canvasDelta.x), Float(canvasDelta.y))
        return Vector2(Double(d.x), Double(d.y))
    }
}

/// A host that can edit the sketch's own source, driven by the canvas view.
///
/// The framework does the reading (which shape, which line); everything that
/// writes a file lives in the host, which is what keeps the sketch the
/// artifact and this a lens on it.
@MainActor
package protocol ShapeDragging: AnyObject {
    /// The editing modifier went down or up. Holding it is what arms the
    /// per-shape recording, so nothing is paid for while nobody is editing.
    func modifierChanged(held: Bool, at canvasPoint: Vector2?)
    /// The pointer moved with the modifier held and no button down.
    func pointerHovered(at canvasPoint: Vector2)
    /// A modified press landed. Return `true` to take the whole press, or
    /// `false` to leave it to the sketch (there was no shape under it).
    func dragBegan(at canvasPoint: Vector2) -> Bool
    func dragMoved(to canvasPoint: Vector2)
    func dragEnded()
}

extension Sketch {
    /// Whether every draw call records where it was written, so a host can find
    /// the shape under the pointer and the numbers that placed it.
    ///
    /// Off by default. A sketch that nobody is editing pays one branch per draw
    /// call for this and nothing else; a live host turns it on for the window
    /// it is watching.
    package var tracksSourceSites: Bool {
        get { drawer.recordsSourceSites }
        set { drawer.recordsSourceSites = newValue }
    }

    /// The shape under `canvasPoint`, or `nil` where nothing was drawn (or
    /// where nothing that records its site was).
    ///
    /// The topmost shape wins, which is the one drawn last, so the answer
    /// matches what the eye picks out. Reads the frame that has just been
    /// drawn, so a host asks between frames.
    package func sourcePick(at canvasPoint: Vector2) -> SourcePick? {
        for target in drawer.sourcePickTargets.reversed() {
            let inverse = simd_inverse(target.transform)
            let p = inverse * SIMD3<Float>(Float(canvasPoint.x), Float(canvasPoint.y), 1)
            guard target.contains(local: Vector2(Double(p.x), Double(p.y))) else { continue }
            let outline = target.localCorners.map { corner -> Vector2 in
                let c = target.transform * SIMD3<Float>(Float(corner.x), Float(corner.y), 1)
                return Vector2(Double(c.x), Double(c.y))
            }
            let linear = matrix_float2x2(SIMD2<Float>(inverse.columns.0.x, inverse.columns.0.y),
                                         SIMD2<Float>(inverse.columns.1.x, inverse.columns.1.y))
            return SourcePick(site: target.site, outline: outline, canvasToLocal: linear)
        }
        return nil
    }
}
