import Foundation

/// A fraction in lowest terms, with a positive denominator.
///
/// Whole numbers are exact and fractions of them are not, which is the whole
/// reason this type exists: two fractions are neighbors, or they are not, and no
/// amount of rounding should be able to change the answer. It is the value the
/// `fareySequence(order:)` and the Ford circles are built from.
///
/// ```swift
/// let half = Fraction(2, 4)      // reduces to 1/2
/// half.mediant(with: Fraction(1, 1))   // 2/3, the fraction between them
/// half.isNeighbor(of: Fraction(1, 3))  // true: 1*3 - 2*1 = 1
/// ```
public struct Fraction: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The top of the fraction. Carries the sign.
    public let numerator: Int
    /// The bottom of the fraction, always one or more.
    public let denominator: Int

    /// Reduce `numerator / denominator` to lowest terms, with the sign carried by
    /// the numerator. A denominator of zero is taken as one, since a fraction over
    /// nothing is not a number and there is nothing better to make of it.
    public init(_ numerator: Int, _ denominator: Int = 1) {
        let bottom = denominator == 0 ? 1 : denominator
        let sign = bottom < 0 ? -1 : 1
        let divisor = Swift.max(1, Fraction.greatestCommonDivisor(abs(numerator), abs(bottom)))
        self.numerator = sign * numerator / divisor
        self.denominator = abs(bottom) / divisor
    }

    /// The fraction as a number.
    public var value: Double { Double(numerator) / Double(denominator) }

    /// The fraction between two others, by adding the tops and the bottoms.
    ///
    /// This is not addition, and it is the operation the Farey sequence grows by:
    /// the mediant of two neighbors is the first fraction to appear between them,
    /// and it lands strictly between the two.
    public func mediant(with other: Fraction) -> Fraction {
        Fraction(numerator + other.numerator, denominator + other.denominator)
    }

    /// Whether the two fractions are Farey neighbors: `ps - qr` is `1` or `-1`.
    ///
    /// Neighbors in this sense are the pairs with nothing between them at their own
    /// order, and the pairs whose Ford circles touch.
    public func isNeighbor(of other: Fraction) -> Bool {
        abs(numerator * other.denominator - denominator * other.numerator) == 1
    }

    /// How far apart two fractions are as a determinant: `ps - qr`. It is `±1` for
    /// neighbors, and grows as the two move apart.
    public func determinant(with other: Fraction) -> Int {
        numerator * other.denominator - denominator * other.numerator
    }

    public static func < (a: Fraction, b: Fraction) -> Bool {
        a.numerator * b.denominator < b.numerator * a.denominator
    }

    public var description: String { "\(numerator)/\(denominator)" }

    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}

/// The Farey sequence of `order`: every fraction from 0 to 1 whose denominator is
/// `order` or less, in lowest terms, in order.
///
/// ```swift
/// fareySequence(order: 4)   // 0/1, 1/4, 1/3, 1/2, 2/3, 3/4, 1/1
/// ```
///
/// Two facts make it worth having rather than sorting a pile of fractions. Any two
/// terms next to each other are neighbors (`ps - qr` is `±1`), and the first
/// fraction ever to appear between them is their mediant. Those two together are
/// why the sequence grows the way it does, and why the Ford circles of two
/// neighbors touch.
///
/// The terms are walked out one at a time from the pair before them, so the cost
/// is the length of the answer. That length grows with the square of the order
/// (about `3n²/π²` terms), so an order in the hundreds is already tens of
/// thousands of fractions.
public func fareySequence(order: Int) -> [Fraction] {
    guard order >= 1 else { return [] }
    // Each term is worked out from the two before it, by the largest step that
    // keeps the denominator inside the order.
    var (a, b, c, d) = (0, 1, 1, order)
    var terms = [Fraction(a, b)]
    terms.reserveCapacity(1 + 3 * order * order / 10)
    while c <= order {
        let k = (order + b) / d
        (a, b, c, d) = (c, d, k * c - a, k * d - b)
        terms.append(Fraction(a, b))
    }
    return terms
}
