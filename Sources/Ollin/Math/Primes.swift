import Foundation

/// Whole numbers as material. A prime is a number greater than one that nothing
/// divides but itself and one, and the way they fall along the number line is
/// irregular enough to draw with and orderly enough to be worth drawing.
///
/// ```swift
/// for p in primes(upTo: 500) { drawCircle(Double(p), height / 2, 3) }
/// ```

/// Every prime up to and including `limit`, in order. Nothing above `limit` and
/// nothing below two; a `limit` under two gives an empty list.
///
/// This is the sieve of Eratosthenes: write out the numbers, then walk each one
/// that is still standing and cross off its multiples. It answers the whole run
/// at once, which is what makes a field of thousands of numbers cheap. For a
/// single number, ``isPrime(_:)`` is the shorter way round.
public func primes(upTo limit: Int) -> [Int] {
    guard limit >= 2 else { return [] }
    var standing = [Bool](repeating: true, count: limit + 1)
    standing[0] = false
    standing[1] = false
    var factor = 2
    while factor * factor <= limit {
        if standing[factor] {
            // Everything under factor² is already crossed off by a smaller factor.
            var multiple = factor * factor
            while multiple <= limit {
                standing[multiple] = false
                multiple += factor
            }
        }
        factor += 1
    }
    return (2 ... limit).filter { standing[$0] }
}

/// Whether `number` is prime. Negative numbers, zero, and one are not.
///
/// It divides by two, by three, and then by every number of the form `6k ± 1` up
/// to the square root, since every prime past three is one of those. Asking
/// about a whole run of numbers is faster through ``primes(upTo:)``.
public func isPrime(_ number: Int) -> Bool {
    if number < 2 { return false }
    if number < 4 { return true }
    if number % 2 == 0 || number % 3 == 0 { return false }
    var factor = 5
    while factor * factor <= number {
        if number % factor == 0 || number % (factor + 2) == 0 { return false }
        factor += 6
    }
    return true
}
