import Foundation

/// Re-map a number from one range onto another.
///
/// Linearly maps `value` from `start1...stop1` onto `start2...stop2`:
///
/// ```swift
/// let x = map(sin(time), -1, 1, 0, width)   // -1...1  ->  0...width
/// ```
///
/// By default the result is *not* bounded — a `value` outside the source range
/// maps proportionally outside the destination range. Pass `clamp: true` to
/// hold the result within `start2...stop2` (correct even when that range runs
/// high-to-low).
public func map(_ value: Double,
                _ start1: Double, _ stop1: Double,
                _ start2: Double, _ stop2: Double,
                clamp: Bool = false) -> Double {
    let mapped = start2 + (stop2 - start2) * ((value - start1) / (stop1 - start1))
    guard clamp else { return mapped }
    let lo = Swift.min(start2, stop2)
    let hi = Swift.max(start2, stop2)
    return Swift.min(Swift.max(mapped, lo), hi)
}

/// Euclidean distance between two points.
///
/// ```swift
/// let d = dist(x, y, mouseX, mouseY)
/// ```
public func dist(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    let dx = x2 - x1
    let dy = y2 - y1
    return (dx * dx + dy * dy).squareRoot()
}
