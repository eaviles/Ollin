// Where a draw call was written, and what the pointer is over. Together these
// are the reading half of dragging a shape in a live window and having the
// numbers in the file change; the writing half is the host's.
//
// Off unless a host asks for it: a sketch that nobody is editing records
// nothing and pays one branch per draw call.

import Foundation
import simd

/// Where in a `.swift` file one draw call was written, and which of its
/// arguments carry the shape's position, size, and angle.
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
    /// Which arguments hold the position, the size, and the angle.
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

/// Which of a call's arguments hold the shape's position, size, and angle, and
/// where in the shape those position numbers sit.
///
/// A shape with two ends (a line, an oriented box) lists both of its points, so
/// moving it moves the whole shape rather than one end, and turning it swings
/// both ends about the middle.
package struct SourceMove: Sendable, Equatable {

    /// Which arguments hold the position, and in what form.
    package enum Position: Sendable, Equatable {
        /// Bare scalars, in x, y order: `drawCircle(200, 300, 40)` is
        /// `.scalars([0, 1])`, and a line is `.scalars([0, 1, 2, 3])`.
        case scalars([Int])
        /// `Vector2` arguments at these indices:
        /// `drawCircle(center: Vector2(200, 300), radius: 40)` is `.points([0])`.
        case points([Int])
    }

    /// Which arguments give the shape its size, and how a corner handle changes
    /// them. A count (`sides:`, `points:`) and a corner radius are not sizes:
    /// they stay as written.
    package enum Size: Sendable, Equatable {
        /// Nothing on the line says how big the shape is, so it has no corner
        /// handle. A shape placed by two points is sized by where those points
        /// are, which is a move rather than a resize.
        case none
        /// Sizes that scale together whichever way the corner is dragged: a
        /// circle's radius, a star's two radii, a moon's three numbers.
        case uniform([Int])
        /// A size across and a size down, each following its own side of the
        /// drag. A trapezoid's two widths both go in `x`.
        case axes(x: [Int], y: [Int])
    }

    /// Where in the shape the position numbers sit, so a resize can hold that
    /// point still and change only the size.
    package enum Anchor: Sendable, Equatable {
        /// The middle of the shape (nearly everything).
        case center
        /// Its top-left corner (`drawRect(x, y, width, height)`).
        case corner
        /// The point it opens from (the isosceles `drawTriangle`).
        case apex
    }

    package let position: Position
    package let size: Size
    package let anchor: Anchor
    /// Arguments holding an angle in radians, all turned by the same amount
    /// (an arc's `start:` and `stop:`).
    package let angles: [Int]

    package init(position: Position, size: Size = .none,
                 anchor: Anchor = .center, angles: [Int] = []) {
        self.position = position
        self.size = size
        self.anchor = anchor
        self.angles = angles
    }

    // MARK: The forms a draw call takes

    /// The everyday case: a shape placed by `x, y` as its first two arguments,
    /// with nothing on the line saying how big it is.
    package static let xy = SourceMove(position: .scalars([0, 1]))
    /// The everyday labeled case: a shape placed by one point argument.
    package static let point = SourceMove(position: .points([0]))

    /// `drawCircle(x, y, radius)`: placed by two numbers, sized by one.
    package static func xy(radius: Int) -> SourceMove {
        SourceMove(position: .scalars([0, 1]), size: .uniform([radius]))
    }
    /// `drawStar(x, y, outerRadius, innerRadius, points:)`: sizes that scale together.
    package static func xy(radii: [Int]) -> SourceMove {
        SourceMove(position: .scalars([0, 1]), size: .uniform(radii))
    }
    /// `drawRect(x, y, width, height)`: a size across and a size down.
    package static func xy(width: Int, height: Int) -> SourceMove {
        SourceMove(position: .scalars([0, 1]), size: .axes(x: [width], y: [height]))
    }
    /// `drawTrapezoid(x, y, topWidth, bottomWidth, height)`: two widths, one height.
    package static func xy(widths: [Int], height: Int) -> SourceMove {
        SourceMove(position: .scalars([0, 1]), size: .axes(x: widths, y: [height]))
    }

    /// `drawCircle(center:radius:)`: placed by one point, sized by one number.
    package static func point(radius: Int) -> SourceMove {
        SourceMove(position: .points([0]), size: .uniform([radius]))
    }
    /// `drawStar(center:outerRadius:innerRadius:points:)`.
    package static func point(radii: [Int]) -> SourceMove {
        SourceMove(position: .points([0]), size: .uniform(radii))
    }
    /// `drawRect(center:width:height:)`.
    package static func point(width: Int, height: Int) -> SourceMove {
        SourceMove(position: .points([0]), size: .axes(x: [width], y: [height]))
    }
    /// `drawTrapezoid(center:topWidth:bottomWidth:height:)`.
    package static func point(widths: [Int], height: Int) -> SourceMove {
        SourceMove(position: .points([0]), size: .axes(x: widths, y: [height]))
    }

    /// Bare scalars at these indices, in x, y order.
    package static func scalars(_ indices: [Int]) -> SourceMove {
        SourceMove(position: .scalars(indices))
    }
    /// `Vector2` arguments at these indices.
    package static func points(_ indices: [Int]) -> SourceMove {
        SourceMove(position: .points(indices))
    }

    /// The same call, with its position numbers naming the shape's top-left
    /// corner rather than its middle.
    package var fromCorner: SourceMove {
        SourceMove(position: position, size: size, anchor: .corner, angles: angles)
    }
    /// The same call, with its position numbers naming the apex the shape opens
    /// from.
    package var fromApex: SourceMove {
        SourceMove(position: position, size: size, anchor: .apex, angles: angles)
    }
    /// The same call, with the arguments at these indices holding angles in
    /// radians that turn together.
    package func turning(_ indices: Int...) -> SourceMove {
        SourceMove(position: position, size: size, anchor: anchor, angles: indices)
    }

    // MARK: What can be done to it

    /// How many points place the shape: one for a circle, two for a line.
    package var pointCount: Int {
        switch position {
        case .scalars(let indices): return indices.count / 2
        case .points(let indices): return indices.count
        }
    }

    /// Whether anything on the line says which way the shape faces: an angle
    /// argument, or two points that can swing about their middle.
    package var canTurn: Bool { pointCount >= 2 || !angles.isEmpty }
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

    /// The box around the region, in the call's own coordinates.
    var localBounds: (center: Vector2, half: Vector2) {
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
    }

    /// The point the call's own position numbers stand at, in those same
    /// coordinates. A resize holds this still.
    var localAnchor: Vector2 {
        let (center, half) = localBounds
        switch site.move.anchor {
        case .center: return center
        case .corner: return Vector2(center.x - half.x, center.y - half.y)
        case .apex: return Vector2(center.x, center.y - half.y)
        }
    }

    /// The region's corners, in the call's own coordinates, for the outline a
    /// host draws over the shape it is about to move. In order: top-left,
    /// top-right, bottom-right, bottom-left.
    var localCorners: [Vector2] {
        let (center, half) = localBounds
        return [Vector2(center.x - half.x, center.y - half.y),
                Vector2(center.x + half.x, center.y - half.y),
                Vector2(center.x + half.x, center.y + half.y),
                Vector2(center.x - half.x, center.y + half.y)]
    }
}

/// Something on a picked shape the pointer can take hold of.
package struct SourceHandle: Sendable, Equatable {
    package enum Kind: Sendable, Equatable {
        /// A corner that changes the shape's size numbers.
        case resize
        /// The knob above the shape that changes which way it faces.
        case turn
    }
    package let kind: Kind
    /// Where it sits, in canvas points.
    package let position: Vector2
    /// For a resize handle, which corner it holds, as a sign on each axis.
    let corner: Vector2
}

/// A shape the pointer is over, handed to a host so it can outline the shape
/// and turn a drag into an edit of the file the sketch was written in.
package struct SourcePick: Sendable {
    /// Where the call that drew it was written.
    package let site: SourceSite
    /// The shape's corners in canvas points, in order, for a highlight. Under a
    /// rotation these are a rotated quad, not an axis-aligned box.
    package let outline: [Vector2]
    /// The handles on it, in canvas points: a corner for each side of the shape
    /// that can be resized, and one knob above it when the shape can turn.
    package let handles: [SourceHandle]
    /// Canvas points to the call's own coordinates, without the translation:
    /// a drag is a difference, so only the rotation and scale apply.
    let canvasToLocal: matrix_float2x2
    /// Canvas points to the call's own coordinates, translation and all, and
    /// the way back.
    let canvasToLocalPoint: matrix_float3x3
    let localToCanvas: matrix_float3x3
    /// The shape's corners in the call's own coordinates.
    let localCorners: [Vector2]
    /// The middle of the shape and its half-size, in the call's own coordinates.
    let localCenter: Vector2
    let localHalf: Vector2
    /// The point the call's position numbers stand at, in those coordinates.
    let localAnchor: Vector2

    /// Where the shape's own numbers put it, when one point places it. `nil`
    /// for a shape placed by two points, which has no single position.
    package var placedAt: Vector2? {
        site.move.pointCount == 1 ? localAnchor : nil
    }

    /// How much the call's numbers have to change for the shape to follow a
    /// drag of `canvasDelta` on screen. Under `translate`/`rotate`/`scale` this
    /// is not the same as the drag: a shape drawn at half scale moves by twice
    /// the numbers.
    package func numbersDelta(forCanvasDelta canvasDelta: Vector2) -> Vector2 {
        let d = canvasToLocal * SIMD2<Float>(Float(canvasDelta.x), Float(canvasDelta.y))
        return Vector2(Double(d.x), Double(d.y))
    }

    /// What the size numbers are multiplied by when `handle` is dragged by
    /// `canvasDelta`: `x` for the size across, `y` for the size down, and `x`
    /// alone for sizes that scale together. `nil` when the call carries no size.
    ///
    /// One drag cannot take a shape below a twentieth of the size it started
    /// at, so a corner pulled past the anchor leaves something to grab again.
    package func sizeFactor(for handle: SourceHandle, canvasDelta: Vector2) -> Vector2? {
        guard handle.kind == .resize else { return nil }
        let delta = numbersDelta(forCanvasDelta: canvasDelta)
        let from = Vector2(localCenter.x + handle.corner.x * localHalf.x,
                           localCenter.y + handle.corner.y * localHalf.y) - localAnchor
        let to = from + delta
        let floorFactor = 0.05
        switch site.move.size {
        case .none:
            return nil
        case .uniform:
            let length2 = from.x * from.x + from.y * from.y
            guard length2 > 1e-12 else { return nil }
            // Along the corner's own direction, so pulling sideways past the
            // anchor shrinks the shape instead of growing it again.
            let along = (to.x * from.x + to.y * from.y) / length2
            let factor = Swift.max(floorFactor, along)
            return Vector2(factor, factor)
        case .axes:
            // A corner sitting on the anchor's own row or column changes one
            // side only: the right edge of a corner-placed rectangle is where
            // its width is dragged, and its height stays as written.
            guard abs(from.x) > 1e-9 || abs(from.y) > 1e-9 else { return nil }
            let x = abs(from.x) > 1e-9 ? Swift.max(floorFactor, to.x / from.x) : 1
            let y = abs(from.y) > 1e-9 ? Swift.max(floorFactor, to.y / from.y) : 1
            return Vector2(x, y)
        }
    }

    /// The angle, in radians, a turn drag from `start` to `end` swings the
    /// shape by, measured in the call's own frame about the middle of the shape.
    package func turnAngle(from start: Vector2, to end: Vector2) -> Double {
        let a = local(start) - localCenter
        let b = local(end) - localCenter
        guard a.length > 1e-6, b.length > 1e-6 else { return 0 }
        let turned = atan2(b.y, b.x) - atan2(a.y, a.x)
        // Back into -pi ... pi, so a knob dragged the long way round does not
        // write a whole extra turn.
        return atan2(sin(turned), cos(turned))
    }

    /// The handle nearest `canvasPoint`, when one stands within `radius` canvas
    /// points of it.
    package func handle(at canvasPoint: Vector2, within radius: Double) -> SourceHandle? {
        var best: (handle: SourceHandle, distance: Double)?
        for handle in handles {
            let distance = (handle.position - canvasPoint).length
            guard distance <= radius else { continue }
            if best == nil || distance < best!.distance { best = (handle, distance) }
        }
        return best?.handle
    }

    /// The outline as a resize by `factor` would leave it, in canvas points,
    /// for a host showing where a drag is going before it writes anything.
    package func resized(by factor: Vector2) -> [Vector2] {
        localCorners.map { corner in
            canvas(Vector2(localAnchor.x + (corner.x - localAnchor.x) * factor.x,
                           localAnchor.y + (corner.y - localAnchor.y) * factor.y))
        }
    }

    /// The outline as a turn of `angle` radians would leave it, in canvas points.
    package func turned(by angle: Double) -> [Vector2] {
        let cosine = cos(angle), sine = sin(angle)
        return localCorners.map { corner in
            let dx = corner.x - localCenter.x, dy = corner.y - localCenter.y
            return canvas(Vector2(localCenter.x + dx * cosine - dy * sine,
                                  localCenter.y + dx * sine + dy * cosine))
        }
    }

    /// A point of the call's own coordinates on the canvas.
    private func canvas(_ localPoint: Vector2) -> Vector2 {
        let p = localToCanvas * SIMD3<Float>(Float(localPoint.x), Float(localPoint.y), 1)
        return Vector2(Double(p.x), Double(p.y))
    }

    /// A canvas point in the call's own coordinates.
    private func local(_ canvasPoint: Vector2) -> Vector2 {
        let p = canvasToLocalPoint * SIMD3<Float>(Float(canvasPoint.x), Float(canvasPoint.y), 1)
        return Vector2(Double(p.x), Double(p.y))
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
            return pick(target, inverse: inverse)
        }
        return nil
    }

    /// Build the answer for one target: its outline and handles on the canvas,
    /// and the frames a host measures a drag in.
    private func pick(_ target: SourcePickTarget, inverse: matrix_float3x3) -> SourcePick {
        func canvas(_ local: Vector2) -> Vector2 {
            let c = target.transform * SIMD3<Float>(Float(local.x), Float(local.y), 1)
            return Vector2(Double(c.x), Double(c.y))
        }
        let (localCenter, localHalf) = target.localBounds
        let localAnchor = target.localAnchor
        let corners = target.localCorners
        let outline = corners.map(canvas)
        let center = canvas(localCenter)

        var handles: [SourceHandle] = []
        // A corner handle only where there is something for it to change: the
        // corner standing on the anchor itself can scale nothing, which is why
        // a corner-placed rectangle has three handles and not four.
        if target.site.move.size != .none {
            let signs = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
            for (index, sign) in signs.enumerated() {
                let from = Vector2(localCenter.x + sign.x * localHalf.x,
                                   localCenter.y + sign.y * localHalf.y) - localAnchor
                let usable: Bool
                switch target.site.move.size {
                case .none: usable = false
                case .uniform: usable = from.length > 1e-9
                case .axes: usable = abs(from.x) > 1e-9 || abs(from.y) > 1e-9
                }
                guard usable else { continue }
                handles.append(SourceHandle(kind: .resize, position: outline[index], corner: sign))
            }
        }
        // The turn knob stands clear above the top edge, measured on the canvas
        // so it keeps its distance whatever scale the shape is drawn at.
        if target.site.move.canTurn {
            let topMiddle = (outline[0] + outline[1]) / 2
            let away = topMiddle - center
            let length = away.length
            let out = length > 1e-6 ? away / length : Vector2(0, -1)
            handles.append(SourceHandle(kind: .turn, position: topMiddle + out * 26, corner: .zero))
        }

        let linear = matrix_float2x2(SIMD2<Float>(inverse.columns.0.x, inverse.columns.0.y),
                                     SIMD2<Float>(inverse.columns.1.x, inverse.columns.1.y))
        return SourcePick(site: target.site, outline: outline, handles: handles,
                          canvasToLocal: linear, canvasToLocalPoint: inverse,
                          localToCanvas: target.transform, localCorners: corners,
                          localCenter: localCenter, localHalf: localHalf, localAnchor: localAnchor)
    }
}
