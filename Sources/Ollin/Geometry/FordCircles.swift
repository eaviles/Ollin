import Foundation

/// One Ford circle: the circle a fraction owns.
///
/// Every fraction `p/q` in lowest terms gets a circle of radius `1/(2q²)` sitting
/// on the number line at `p/q`, touching it and nothing else below. The
/// arrangement that comes out is the point: no two of these circles ever overlap,
/// and two of them touch exactly when their fractions are neighbors, meaning
/// `ps - qr` is `1` or `-1`. Lester Ford described them in 1938 as a way of
/// seeing how well a real number can be approximated by fractions.
public struct FordCircle: Equatable, Sendable {
    /// The fraction the circle belongs to.
    public let fraction: Fraction
    /// The circle as drawn, in canvas coordinates.
    public let circle: Circle

    public init(fraction: Fraction, circle: Circle) {
        self.fraction = fraction
        self.circle = circle
    }

    /// Whether two circles touch, decided on the fractions rather than on the
    /// distance, so the answer is exact.
    public func touches(_ other: FordCircle) -> Bool {
        fraction.isNeighbor(of: other.fraction)
    }
}

/// The Ford circles of every fraction from 0 to 1 with a denominator of `order` or
/// less, laid along the bottom edge of `bounds`.
///
/// ```swift
/// noFill(); stroke(.white)
/// for ford in fordCircles(order: 12, in: bounds) {
///     drawCircle(ford.circle)
/// }
/// ```
///
/// The unit interval spans the width, and the circles are scaled by that same
/// width, which is what keeps them touching. The largest of them (at `0/1` and
/// `1/1`) is then half the width across, so it reaches the top of a square region
/// and hangs half outside the left and right edges. That is the classic picture,
/// but `interval` narrows the run of fractions when the ends are not wanted.
///
/// The count grows with the square of the order, so `order: 60` is already about
/// 1,100 circles. They come back in fraction order, left to right.
public func fordCircles(order: Int, in bounds: Rectangle,
                        interval: ClosedRange<Double> = 0 ... 1) -> [FordCircle] {
    guard order >= 1, bounds.width > 0 else { return [] }
    let scale = bounds.width
    let baseline = bounds.y + bounds.height
    return fareySequence(order: order).compactMap { fraction in
        let x = fraction.value
        guard x >= interval.lowerBound, x <= interval.upperBound else { return nil }
        let radius = scale / (2 * Double(fraction.denominator * fraction.denominator))
        let center = Vector2(bounds.x + x * scale, baseline - radius)
        return FordCircle(fraction: fraction, circle: Circle(center: center, radius: radius))
    }
}

public extension Sketch {
    /// The Ford circles of every fraction with a denominator of `order` or less,
    /// laid along the bottom edge of `bounds` (the whole canvas by default).
    ///
    /// ```swift
    /// for ford in fordCircles(order: 12) { drawCircle(ford.circle) }
    /// ```
    /// The labels mirror the free function's exactly, since a member shadows a
    /// global of the same name inside a sketch: a call written for the free
    /// function has to keep working here.
    func fordCircles(order: Int, in bounds: Rectangle? = nil,
                     interval: ClosedRange<Double> = 0 ... 1) -> [FordCircle] {
        Ollin.fordCircles(order: order, in: bounds ?? self.bounds, interval: interval)
    }

    /// Draw the Ford circles in the current `fill` and `stroke`, one circle each.
    /// For any other reading, hold the `fordCircles(…)` values and draw them
    /// yourself.
    func drawFordCircles(order: Int, in bounds: Rectangle? = nil,
                         interval: ClosedRange<Double> = 0 ... 1) {
        drawCircles(fordCircles(order: order, in: bounds, interval: interval).map(\.circle))
    }
}
