import Foundation

extension Double {

    /// This number on the nearest mark of a grid of `size` counted from
    /// `origin`, as the decimal that mark names.
    ///
    /// A mark is `origin + k * size`, and in binary that sum is rarely the
    /// number a person wrote: the 140th mark of 0.01 from 0.1 comes out as
    /// 1.5000000000000002. A value kept that way is not the 1.5 its own range
    /// and step spell, so asking for 1.5 by name finds nothing equal to it.
    /// When the size and the origin are both short decimals, every mark is one
    /// too, with no more digits than the longer of the two, and the sum is read
    /// back at that many digits: 1.5.
    ///
    /// A grid that is not a short decimal (a third, a step computed from pi)
    /// names no decimal to land on, so its marks are the arithmetic as it
    /// comes, bit for bit.
    func onGrid(of size: Double, from origin: Double,
                rounding rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Double {
        guard isFinite, size.isFinite, size > 0, origin.isFinite else { return self }
        let mark = origin + ((self - origin) / size).rounded(rule) * size
        guard let sizeDigits = size.decimalDigits, let originDigits = origin.decimalDigits else { return mark }
        return Double(String(format: "%.\(Swift.max(sizeDigits, originDigits))f", mark)) ?? mark
    }

    /// How many digits after the point this number takes when it is exactly a
    /// short decimal (the double nearest one of twelve digits or fewer), or
    /// `nil` when it is not one.
    var decimalDigits: Int? {
        guard isFinite else { return nil }
        for digits in 0 ... 12 where Double(String(format: "%.\(digits)f", self)) == self {
            return digits
        }
        return nil
    }
}
