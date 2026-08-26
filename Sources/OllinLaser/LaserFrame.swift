import Foundation
import Ollin

/// One path for the beam to trace: a run of points in canvas coordinates, with
/// a color for the whole run or one color per point.
///
/// A path is the laser's unit of line work, the way a `Contour` is the drawing
/// core's. Build one from a contour, a shape's outline, or bare points:
///
/// ```swift
/// var frame = LaserFrame(canvas: bounds)
/// frame.add(circle, color: .cyan)              // a Contour
/// frame.add(letters, color: .white)            // a Shape's contours
/// frame.add([a, b], color: .red, closed: false)
/// ```
///
/// A laser draws lines, never fills: a `Shape` contributes its outlines, and a
/// filled region has to be hatched into line work first (`Hatching`, the same
/// step the pen-plotter path takes).
public struct LaserPath: Equatable, Sendable {

    /// The path's points, in canvas coordinates.
    public var points: [Vector2]

    /// One color for the whole path, or one per point (any other count is read
    /// as the first color). A per-point run gives a line that changes color
    /// along its length, interpolated as the optimizer fills the segments in.
    public var colors: [Color]

    /// Whether the last point joins back to the first.
    public var isClosed: Bool

    /// A path drawn in one color.
    public init(_ points: [Vector2], color: Color, closed: Bool = false) {
        self.points = points
        self.colors = [color]
        self.isClosed = closed
    }

    /// A path whose color changes along its length: one color per point.
    public init(_ points: [Vector2], colors: [Color], closed: Bool = false) {
        self.points = points
        self.colors = colors
        self.isClosed = closed
    }

    /// The color at point `index`, or the single color when the path carries
    /// one. An out-of-range index reads the nearest end.
    public func color(at index: Int) -> Color {
        guard colors.count > 1 else { return colors.first ?? .white }
        return colors[min(max(index, 0), colors.count - 1)]
    }

    /// Whether this path carries a color per point rather than one color.
    var isMulticolored: Bool { colors.count > 1 && colors.count == points.count }
}

/// One frame of line work for a laser projector: the paths to trace, and the
/// canvas region they are measured in.
///
/// Fill a frame in `draw()` and hand it to a `LaserProjector`. The frame stays
/// in canvas coordinates (the same numbers the drawing calls take), and the
/// turn into the projector's own square happens once, at the optimizer's edge.
///
/// ```swift
/// override func draw() {
///     background(.black)
///     let ring = Contour.circle(center: center, radius: 300)
///     drawContour(ring)                       // on screen
///
///     var frame = LaserFrame(canvas: bounds)
///     frame.add(ring, color: .green)          // and in the air
///     laser.send(frame)
/// }
/// ```
public struct LaserFrame: Sendable {

    /// The paths to trace, in the order they were added. The optimizer is free
    /// to reorder them to shorten the dark travel between paths.
    public var paths: [LaserPath] = []

    /// The canvas region that maps onto the projector's field. The whole
    /// rectangle fits inside the field, so nothing is projected outside it;
    /// the longer side reaches the field's edge.
    public var canvas: Rectangle

    /// An empty frame measured in `canvas` (a sketch usually passes `bounds`).
    public init(canvas: Rectangle) {
        self.canvas = canvas
    }

    /// An empty frame measured in a canvas `width` by `height` from the origin.
    public init(width: Double, height: Double) {
        self.canvas = Rectangle(x: 0, y: 0, width: width, height: height)
    }

    // MARK: Adding line work

    /// Add a path.
    public mutating func add(_ path: LaserPath) {
        paths.append(path)
    }

    /// Add bare points as one path.
    public mutating func add(_ points: [Vector2], color: Color, closed: Bool = false) {
        paths.append(LaserPath(points, color: color, closed: closed))
    }

    /// Add bare points as one path whose color changes along its length.
    public mutating func add(_ points: [Vector2], colors: [Color], closed: Bool = false) {
        paths.append(LaserPath(points, colors: colors, closed: closed))
    }

    /// Add a contour, keeping its open or closed state.
    public mutating func add(_ contour: Contour, color: Color) {
        paths.append(LaserPath(contour.points, color: color, closed: contour.isClosed))
    }

    /// Add every contour of a shape as its own path. A laser draws the outline:
    /// the shape's fill and winding rule play no part.
    public mutating func add(_ shape: Shape, color: Color) {
        for contour in shape.contours { add(contour, color: color) }
    }

    /// Add several shapes' outlines (what `textToShapes` hands back, say).
    public mutating func add(_ shapes: [Shape], color: Color) {
        for shape in shapes { add(shape, color: color) }
    }

    /// Add a straight line between two points.
    public mutating func addLine(from a: Vector2, to b: Vector2, color: Color) {
        paths.append(LaserPath([a, b], color: color, closed: false))
    }

    /// Whether the frame holds no line work at all.
    public var isEmpty: Bool {
        paths.allSatisfy { $0.points.count < 2 }
    }
}

// MARK: - Projector space

/// The projector's own coordinate square: `-1…1` on both axes, the origin at
/// the center, with **x right and y up**. That is the convention both the ILDA
/// file format and the DAC wire share, and it is the opposite of the canvas's
/// downward y.
///
/// The optimizer works here rather than in canvas pixels, because every number
/// it cares about (how far apart to place points, how far the beam travels in
/// the dark) is a distance the galvos actually move. Measured in field units,
/// a setting means the same thing whatever size the canvas is.
public enum ProjectorSpace {

    /// The map from `canvas` into the field: the rectangle is centered and
    /// fitted, so its longer side reaches `±1` and nothing lands outside.
    public static func transform(from canvas: Rectangle) -> (Vector2) -> Vector2 {
        let longer = max(canvas.width, canvas.height)
        let scale = longer > 1e-9 ? 2 / longer : 0
        let cx = canvas.corner.x + canvas.width / 2
        let cy = canvas.corner.y + canvas.height / 2
        return { point in
            Vector2((point.x - cx) * scale, -(point.y - cy) * scale)
        }
    }

    /// The map back into canvas coordinates: the inverse of `transform(from:)`,
    /// which is what a preview needs to draw the beam's path on screen.
    public static func inverse(to canvas: Rectangle) -> (Vector2) -> Vector2 {
        let longer = max(canvas.width, canvas.height)
        let scale = longer > 1e-9 ? longer / 2 : 0
        let cx = canvas.corner.x + canvas.width / 2
        let cy = canvas.corner.y + canvas.height / 2
        return { point in
            Vector2(point.x * scale + cx, -point.y * scale + cy)
        }
    }

    /// A position clamped into the field square, so a point drawn off the
    /// canvas can never ask the galvos for a swing they do not have.
    public static func clamped(_ point: Vector2) -> Vector2 {
        Vector2(min(max(point.x, -1), 1), min(max(point.y, -1), 1))
    }
}
