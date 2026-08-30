import Foundation

/// A smooth field fitted through scattered points: you know a value at a handful of
/// places, and you want one everywhere.
///
/// A grid can be interpolated by looking at the four cells around a spot. Scattered
/// points have no such neighbors, so the answer has to come from all of them at once,
/// weighted by how far away each one is. That is what a radial basis function does: every
/// known point gets a bump centered on it, and the bumps are scaled so that their sum
/// passes exactly through every value you gave.
///
/// ```swift
/// let field = RadialBasis(points: [Vector2(120, 140), Vector2(700, 300), Vector2(400, 860)],
///                         values: [0.1, 0.9, 0.4])
/// for y in stride(from: 0.0, to: height, by: 8) {
///     for x in stride(from: 0.0, to: width, by: 8) {
///         fill(Color(white: field?.value(at: Vector2(x, y)) ?? 0))
///         drawRect(x, y, 8, 8)
///     }
/// }
/// ```
///
/// The values can be numbers, `Vector2`s, `Vector3`s, or `Color`s, and the points can be
/// two- or three-dimensional. A field of vectors is a warp, which is the classic use: pin
/// a few places to where they should move to, and everything between them follows
/// smoothly.
///
/// ## What it costs
///
/// Fitting solves a dense system, so it costs about the cube of the number of points.
/// A few hundred points fit in milliseconds, a few thousand take noticeably longer, and
/// tens of thousands are the wrong tool. Reading the field afterward costs one term per
/// point, every time, so a large fit read over a whole canvas is the expensive half.
/// **Fit once in `setup()`, read in `draw()`.**
public struct RadialBasis<Point: RadialBasisPoint, Value: RadialBasisValue>: Sendable {

    /// The bump shape each known point contributes.
    ///
    /// The first three grow without limit as they get further from their point, which
    /// sounds wrong and is not: what matters is the *sum*, and the polynomial term fitted
    /// alongside them cancels the growth. They extrapolate gracefully past the edge of the
    /// data, which is usually what a sketch wants. The last three fall away to nothing
    /// instead, so far from every known point the field settles rather than running off,
    /// and each carries a `scale` in the same units as the points.
    public enum Kernel: Sendable, Hashable {
        /// `r² log r`: the shape a thin steel sheet takes when pinned at the known points,
        /// which is the smoothest surface through them in the bending-energy sense. The
        /// default, and the right first choice for a surface or a warp.
        case thinPlate
        /// `r`: straight cones. Sharp ridges at every known point, and the cheapest.
        case linear
        /// `r³`: smoother than thin plate and keener to overshoot between distant points.
        case cubic
        /// `√(r² + scale²)`: broad and smooth. `scale` sets how broad, and it wants to be
        /// about the spacing between points.
        case multiquadric(scale: Double = 1)
        /// `1 / √(r² + scale²)`: a bump that fades, so distant points stop having a say.
        case inverseMultiquadric(scale: Double = 1)
        /// `exp(-(r / scale)²)`: a bump that fades fast. Tight and local, and the one most
        /// likely to give a badly conditioned fit if `scale` is much smaller than the
        /// spacing between points.
        case gaussian(scale: Double = 1)

        /// The same shape with any scale it carries divided by `factor`, so a kernel
        /// written in the sketch's own units keeps its meaning once the fit has put the
        /// points into units of their own spacing. The three that carry no scale are
        /// unchanged, which is what makes them the scale-free ones.
        func scaled(by factor: Double) -> Kernel {
            switch self {
            case .thinPlate, .linear, .cubic: return self
            case .multiquadric(let c): return .multiquadric(scale: c * factor)
            case .inverseMultiquadric(let c): return .inverseMultiquadric(scale: c * factor)
            case .gaussian(let c): return .gaussian(scale: c * factor)
            }
        }

        /// The bump's height at distance `r`.
        func callAsFunction(_ r: Double) -> Double {
            switch self {
            case .thinPlate: return r < 1e-12 ? 0 : r * r * log(r)
            case .linear: return r
            case .cubic: return r * r * r
            case .multiquadric(let c): return (r * r + c * c).squareRoot()
            case .inverseMultiquadric(let c): return 1 / (r * r + c * c).squareRoot()
            case .gaussian(let c): return exp(-(r * r) / max(c * c, 1e-12))
            }
        }
    }

    /// The points the field was fitted through.
    public let points: [Point]
    /// The bump shape in use, as it was asked for.
    public let kernel: Kernel
    /// The same shape with its scale put into the units the fit works in.
    private let fitted: Kernel

    /// One weight per point, per channel, and then the polynomial tail's coefficients
    /// (constant first, then one per axis).
    private let weights: [[Double]]
    /// The fit runs on the points shifted to their own middle and divided by their own
    /// typical spacing, and every query is put through the same shift and divide.
    ///
    /// This leaves the answer alone and is worth doing twice over. The kernels that carry
    /// no scale of their own are homogeneous, so scaling the points only rescales the
    /// weights and the field comes out the same; the ones that do carry a scale have it
    /// divided by the same amount, so it keeps its meaning. What it buys is that the matrix
    /// stops depending on whether a sketch measures in pixels or in fractions. Numbers in
    /// the trillions become numbers near one, which is kinder to the solve, and `smoothing`
    /// becomes one knob that means one thing rather than a number whose effect depends on
    /// how big the canvas is.
    private let middle: [Double]
    private let spacing: Double

    /// Fit a field through `points`, where the value at `points[i]` is `values[i]`.
    ///
    /// Returns `nil` when there is nothing to fit (no points, or a mismatched number of
    /// values) or when the points cannot pin a field down: two points in the same place
    /// disagreeing about the value, or, for the three kernels that grow, points that all
    /// sit on one straight line, which leaves the polynomial tail undetermined.
    ///
    /// `smoothing` trades passing through the values for a calmer surface. At zero the
    /// field hits every value exactly, which is what you want from clean data and what
    /// makes noisy data ring. Raise it and the field is allowed to miss, by more the higher
    /// it goes, in exchange for fewer wobbles between the points. It is measured against
    /// the scale of the fit rather than in raw units, so the same number means the same
    /// thing whether the points are spread over a thousand pixels or over one; around 0.01
    /// is a light touch and 1 is heavy.
    public init?(points: [Point], values: [Value], kernel: Kernel = .thinPlate,
                 smoothing: Double = 0) {
        guard !points.isEmpty, points.count == values.count else { return nil }
        let n = points.count
        let tail = Point.axisCount + 1                     // constant plus one per axis
        let size = n + tail

        // The middle of the points, and how far apart they typically are.
        var middle = [Double](repeating: 0, count: Point.axisCount)
        for point in points {
            for axis in 0 ..< Point.axisCount { middle[axis] += point.component(axis) }
        }
        for axis in 0 ..< Point.axisCount { middle[axis] /= Double(n) }
        var spread = 0.0
        for i in 0 ..< n {
            for j in (i + 1) ..< n { spread += points[i].distance(to: points[j]) }
        }
        let pairs = n * (n - 1) / 2
        let spacing = pairs > 0 && spread > 0 ? spread / Double(pairs) : 1
        let fitted = kernel.scaled(by: 1 / spacing)
        func place(_ point: Point, _ axis: Int) -> Double {
            (point.component(axis) - middle[axis]) / spacing
        }
        func gap(_ a: Point, _ b: Point) -> Double { a.distance(to: b) / spacing }

        // The system is the kernel matrix bordered by the polynomial tail. The tail's own
        // block is zero: those rows say the weights sum to nothing and have no moment
        // along any axis, which is what stops the tail and the bumps from describing the
        // same thing twice and leaving the fit undetermined.
        var matrix = [Double](repeating: 0, count: size * size)
        var magnitude = 0.0
        for i in 0 ..< n {
            for j in 0 ..< n {
                let bump = fitted(gap(points[i], points[j]))
                matrix[i * size + j] = bump
                magnitude += abs(bump)
            }
        }
        // Smoothing rides the diagonal, where it reads as "this point is allowed to be
        // this wrong", and it is measured against the typical size of a bump rather than
        // taken raw. That scaling is not tidiness: the bumps are as large as the points are
        // far apart, so on a canvas in pixels a raw 1 would sit beside entries in the
        // millions and do nothing at all, while on the same fit in fractions of the canvas
        // it would flatten the field. Against the mean it means the same thing either way.
        // Thin plate also puts *zeros* down its own diagonal, so there is nothing local to
        // compare a raw number against there in the first place.
        let unit = magnitude > 0 ? magnitude / Double(n * n) : 1
        for i in 0 ..< n {
            matrix[i * size + i] += smoothing * unit
            matrix[i * size + n] = 1
            matrix[n * size + i] = 1
            for axis in 0 ..< Point.axisCount {
                let c = place(points[i], axis)
                matrix[i * size + n + 1 + axis] = c
                matrix[(n + 1 + axis) * size + i] = c
            }
        }

        // One right-hand side per channel. They share the matrix, so a field of colors
        // costs one factorization rather than four.
        let channels = Value.channelCount
        var sides = [[Double]](repeating: [Double](repeating: 0, count: size), count: channels)
        for (i, value) in values.enumerated() {
            let parts = value.channels
            for c in 0 ..< channels { sides[c][i] = parts[c] }
        }

        guard let solved = RadialBasisSolver.solve(matrix, sides: sides, size: size) else {
            return nil
        }
        self.points = points
        self.kernel = kernel
        self.fitted = fitted
        self.weights = solved
        self.middle = middle
        self.spacing = spacing
    }

    /// The field's value at `point`.
    ///
    /// Exact at each fitted point (unless `smoothing` was raised), smooth everywhere
    /// between, and defined outside the points too, where the polynomial tail carries it.
    public func value(at point: Point) -> Value {
        var parts = [Double](repeating: 0, count: Value.channelCount)
        for (i, fittedPoint) in points.enumerated() {
            let bump = fitted(fittedPoint.distance(to: point) / spacing)
            for c in 0 ..< parts.count { parts[c] += weights[c][i] * bump }
        }
        let n = points.count
        for c in 0 ..< parts.count {
            parts[c] += weights[c][n]
            for axis in 0 ..< Point.axisCount {
                parts[c] += weights[c][n + 1 + axis]
                    * (point.component(axis) - middle[axis]) / spacing
            }
        }
        return Value(channels: parts)
    }

    /// `field(point)`, the same as ``value(at:)``.
    public func callAsFunction(_ point: Point) -> Value { value(at: point) }
}

// MARK: - What can be a point, and what can be a value

/// A point a `RadialBasis` can be fitted at: `Vector2` or `Vector3`.
public protocol RadialBasisPoint: Sendable {
    /// How many numbers a point is made of.
    static var axisCount: Int { get }
    /// The point's coordinate along one axis.
    func component(_ axis: Int) -> Double
    /// How far this point is from another.
    func distance(to other: Self) -> Double
}

extension Vector2: RadialBasisPoint {
    public static var axisCount: Int { 2 }
    public func component(_ axis: Int) -> Double { axis == 0 ? x : y }
}

extension Vector3: RadialBasisPoint {
    public static var axisCount: Int { 3 }
    public func component(_ axis: Int) -> Double { axis == 0 ? x : (axis == 1 ? y : z) }
}

/// Something a `RadialBasis` can carry: a number, a vector, or a color. Each channel is
/// fitted on its own, sharing one solve.
public protocol RadialBasisValue: Sendable {
    /// How many numbers this value is made of.
    static var channelCount: Int { get }
    /// The numbers, in a fixed order.
    var channels: [Double] { get }
    /// Rebuild a value from those numbers.
    init(channels: [Double])
}

extension Double: RadialBasisValue {
    public static var channelCount: Int { 1 }
    public var channels: [Double] { [self] }
    public init(channels: [Double]) { self = channels[0] }
}

extension Vector2: RadialBasisValue {
    public static var channelCount: Int { 2 }
    public var channels: [Double] { [x, y] }
    public init(channels: [Double]) { self.init(channels[0], channels[1]) }
}

extension Vector3: RadialBasisValue {
    public static var channelCount: Int { 3 }
    public var channels: [Double] { [x, y, z] }
    public init(channels: [Double]) { self.init(channels[0], channels[1], channels[2]) }
}

extension Color: RadialBasisValue {
    public static var channelCount: Int { 4 }
    public var channels: [Double] { [red, green, blue, alpha] }
    public init(channels: [Double]) {
        self.init(red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3])
    }
}

// MARK: - The solve

/// Solving a dense square system by elimination with partial pivoting, for several
/// right-hand sides at once. Kept private because it exists to serve the fit above:
/// the sizes here are the number of scattered points, which is tens or hundreds.
enum RadialBasisSolver {

    /// Solve `matrix * x = side` for each side, or `nil` if the matrix is singular.
    ///
    /// Rows are swapped so the largest remaining entry in a column does the dividing.
    /// Without that, a perfectly solvable system can still come apart: the bordered
    /// matrix a fit builds has **zeros down part of its diagonal** by construction, so the
    /// first division without a pivot search is a division by zero.
    static func solve(_ matrix: [Double], sides: [[Double]], size n: Int) -> [[Double]]? {
        var a = matrix
        var b = sides
        for column in 0 ..< n {
            var pivot = column
            var best = abs(a[column * n + column])
            for row in (column + 1) ..< n where abs(a[row * n + column]) > best {
                best = abs(a[row * n + column])
                pivot = row
            }
            guard best > 1e-12 else { return nil }
            if pivot != column {
                for k in 0 ..< n { a.swapAt(column * n + k, pivot * n + k) }
                for s in 0 ..< b.count { b[s].swapAt(column, pivot) }
            }
            let diagonal = a[column * n + column]
            for row in (column + 1) ..< n {
                let factor = a[row * n + column] / diagonal
                if factor == 0 { continue }
                for k in column ..< n { a[row * n + k] -= factor * a[column * n + k] }
                for s in 0 ..< b.count { b[s][row] -= factor * b[s][column] }
            }
        }
        for s in 0 ..< b.count {
            for row in stride(from: n - 1, through: 0, by: -1) {
                var sum = b[s][row]
                for k in (row + 1) ..< n { sum -= a[row * n + k] * b[s][k] }
                b[s][row] = sum / a[row * n + row]
            }
        }
        return b
    }
}
