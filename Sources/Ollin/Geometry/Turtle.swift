import Foundation

/// A pen you drive from code. A turtle stands somewhere on the canvas facing
/// some way; you tell it to walk forward, to turn left or right, and to lift
/// or lower its pen, and the path it draws comes back as `Contour`s, one per
/// unbroken run with the pen down. The same turtle the L-system interpreter
/// walks privately, but taking calls instead of reading a string, so a figure
/// is written as the moves that make it.
///
/// ```swift
/// var turtle = Turtle(at: center)         // facing up the screen
/// for _ in 0 ..< 4 {                      // a square
///     turtle.forward(200)
///     turtle.right(90)
/// }
/// for run in turtle.contours { drawPolyline(run.points, closed: run.isClosed) }
/// ```
///
/// Angles are in degrees, as turtle graphics has always had them: `heading`
/// is measured from the positive x-axis, clockwise as the canvas shows it, so
/// `-90` faces up the screen and `right(90)` from there faces right.
/// `pushState()` remembers where the turtle stands, which way it faces, and
/// whether its pen is down, and `popState()` takes it back there, which is
/// how a branch is drawn: walk out a twig, pop, walk the next.
public struct Turtle: Equatable, Sendable {
    /// Where the turtle stands now.
    public private(set) var position: Vector2

    /// Which way it faces, in degrees from the positive x-axis, clockwise as
    /// the canvas shows it. Set it to face a direction outright.
    public var heading: Double

    /// Whether the pen is down, so a move draws.
    public private(set) var isPenDown = true

    private struct Pose: Equatable, Sendable {
        var position: Vector2
        var heading: Double
        var isPenDown: Bool
    }

    private var finished: [Contour] = []
    private var run: [Vector2]
    private var stack: [Pose] = []
    private let origin: Pose

    /// A turtle standing at `position` with its pen down, facing `heading`
    /// degrees (up the screen by default).
    public init(at position: Vector2 = .zero, heading: Double = -90) {
        self.position = position
        self.heading = heading
        self.run = [position]
        self.origin = Pose(position: position, heading: heading, isPenDown: true)
    }

    /// The unit vector the turtle faces along.
    public var direction: Vector2 { Vector2(angle: heading * .pi / 180) }

    /// Everything drawn so far: one open contour per unbroken run with the
    /// pen down, in the order they were drawn, plus any run `close()` closed.
    /// The run in progress is included once it has two points.
    public var contours: [Contour] {
        run.count >= 2 ? finished + [Contour(run, closed: false)] : finished
    }

    // MARK: Moving

    /// Walk `distance` the way the turtle faces, drawing if the pen is down.
    public mutating func forward(_ distance: Double) {
        land(at: position + direction * distance)
    }

    /// Walk `distance` backward, without turning.
    public mutating func back(_ distance: Double) {
        forward(-distance)
    }

    /// Turn `degrees` to the left (counterclockwise as the canvas shows it).
    public mutating func left(_ degrees: Double) {
        heading -= degrees
    }

    /// Turn `degrees` to the right (clockwise as the canvas shows it).
    public mutating func right(_ degrees: Double) {
        heading += degrees
    }

    /// Walk straight to `point` without turning, drawing if the pen is down.
    public mutating func move(to point: Vector2) {
        land(at: point)
    }

    /// Walk straight back to where the turtle started, drawing if the pen is
    /// down, and face the way it started.
    public mutating func home() {
        land(at: origin.position)
        heading = origin.heading
    }

    // MARK: The pen

    /// Lift the pen: the moves that follow leave no line, and the run so far
    /// is kept.
    public mutating func penUp() {
        flush()
        isPenDown = false
    }

    /// Lower the pen: the moves that follow draw, as a new run starting here.
    public mutating func penDown() {
        isPenDown = true
        run = [position]
    }

    /// End the run in progress as a closed outline, so it can be filled. A
    /// run that ends where it began drops the repeated point; one shorter
    /// than three points is kept as it is.
    public mutating func close() {
        guard run.count >= 3 else { flush(); return }
        var points = run
        if let first = points.first, let last = points.last,
           first.distance(to: last) <= 1e-9 * Swift.max(1, abs(first.x) + abs(first.y)) {
            points.removeLast()
        }
        finished.append(Contour(points, closed: true))
        run = [position]
    }

    // MARK: Remembering where it stood

    /// Remember where the turtle stands, which way it faces, and whether the
    /// pen is down.
    public mutating func pushState() {
        stack.append(Pose(position: position, heading: heading, isPenDown: isPenDown))
    }

    /// Go back to the last remembered place without drawing the way there,
    /// facing as it faced then, the pen as it was. The run so far is kept and
    /// a new one starts there. With nothing remembered it changes nothing.
    public mutating func popState() {
        guard let pose = stack.popLast() else { return }
        flush()
        position = pose.position
        heading = pose.heading
        isPenDown = pose.isPenDown
        run = [position]
    }

    // MARK: The runs

    private mutating func land(at point: Vector2) {
        position = point
        if isPenDown { run.append(position) } else { run = [position] }
    }

    private mutating func flush() {
        if run.count >= 2 { finished.append(Contour(run, closed: false)) }
        run = [position]
    }
}
