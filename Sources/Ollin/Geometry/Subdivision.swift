import Foundation

/// Recursive rectangle subdivision: split a rectangle, split the pieces, and
/// keep going until a stopping rule says leaf. The output is the set of leaf
/// rectangles (each with the depth it stopped at), the classic skeleton for
/// grid-based compositions: the grid-painting layout, dashboards of nested
/// panels, treemap-ish mosaics, endpaper patterns.
///
/// Two split styles are built in:
///
/// - `.binary` cuts one way per step, across the longer side, at a random
///   fraction drawn from `fraction`. Uneven, painterly panels (the classic
///   look).
/// - `.quad` cuts into four equal quadrants per step: the quadtree look,
///   square panels of mixed scales.
///
/// Every random choice draws from `rng`, so the same seed always yields the
/// same layout.
///
/// ```swift
/// var rng = SplitMix64(seed: 5)
/// for cell in Subdivision.cells(in: bounds, minSize: 60, chance: 0.8, using: &rng) {
///     drawRect(cell.frame)
/// }
/// ```
public enum Subdivision {
    /// How a cell splits: one aspect-aware cut (`.binary`, the painterly
    /// panels) or four equal quadrants (`.quad`, the quadtree look).
    public enum Style: Sendable, Equatable, Hashable {
        case binary
        case quad
    }

    /// One leaf of a subdivision: its `frame` and the recursion `depth` it
    /// stopped at (the root is depth 0), handy for tinting by scale.
    public struct Cell: Equatable, Hashable, Sendable {
        public let frame: Rectangle
        public let depth: Int
    }

    /// Recursively subdivide `rect` and return the leaves, in stable
    /// depth-first order.
    ///
    /// A cell splits while it can and the coin allows: never below `minSize`
    /// on either side of a cut, never past `maxDepth`, and (past the root,
    /// which always splits when it can) only with probability `chance`. For
    /// `.binary`, the cut runs across the longer side at a fraction drawn
    /// from `fraction`, clamped so both halves respect `minSize`.
    ///
    /// - Parameters:
    ///   - rect: The rectangle to subdivide.
    ///   - minSize: The smallest side length a cut may leave behind.
    ///   - maxDepth: How many levels deep the recursion may go.
    ///   - chance: The probability that a splittable cell splits (the root is
    ///     exempt). 1 subdivides everything to the floor; ~0.7 leaves a mix of
    ///     large and small panels.
    ///   - fraction: Where a `.binary` cut lands along the side, as a range of
    ///     fractions; tighten toward 0.5 for evener panels.
    ///   - style: `.binary` (default) or `.quad`.
    ///   - rng: The random source; seed it for a reproducible layout.
    public static func cells<R: RandomNumberGenerator>(
        in rect: Rectangle,
        minSize: Double,
        maxDepth: Int = 6,
        chance: Double = 1,
        fraction: ClosedRange<Double> = 0.3...0.7,
        style: Style = .binary,
        using rng: inout R
    ) -> [Cell] {
        var out: [Cell] = []
        let minSide = Swift.max(1, minSize)
        subdivide(rect, depth: 0, minSize: minSide, maxDepth: Swift.max(0, maxDepth),
                  chance: chance, fraction: fraction, style: style, into: &out, using: &rng)
        return out
    }

    private static func subdivide<R: RandomNumberGenerator>(
        _ rect: Rectangle, depth: Int, minSize: Double, maxDepth: Int,
        chance: Double, fraction: ClosedRange<Double>, style: Style,
        into out: inout [Cell], using rng: inout R
    ) {
        let canSplitWidth = rect.width >= 2 * minSize
        let canSplitHeight = rect.height >= 2 * minSize
        let canSplit: Bool
        switch style {
        case .binary: canSplit = canSplitWidth || canSplitHeight
        case .quad: canSplit = canSplitWidth && canSplitHeight
        }
        guard depth < maxDepth, canSplit,
              depth == 0 || Double.random(in: 0..<1, using: &rng) < chance else {
            out.append(Cell(frame: rect, depth: depth))
            return
        }

        func recurse(_ child: Rectangle) {
            subdivide(child, depth: depth + 1, minSize: minSize, maxDepth: maxDepth,
                      chance: chance, fraction: fraction, style: style,
                      into: &out, using: &rng)
        }

        switch style {
        case .binary:
            // Cut across the longer splittable side, at a random fraction
            // clamped so both halves keep at least minSize.
            let vertical = canSplitWidth && (!canSplitHeight || rect.width >= rect.height)
            let side = vertical ? rect.width : rect.height
            let f = Double.random(in: fraction.lowerBound...fraction.upperBound, using: &rng)
            let cut = Swift.min(Swift.max(f * side, minSize), side - minSize)
            if vertical {
                recurse(Rectangle(x: rect.x, y: rect.y, width: cut, height: rect.height))
                recurse(Rectangle(x: rect.x + cut, y: rect.y, width: rect.width - cut, height: rect.height))
            } else {
                recurse(Rectangle(x: rect.x, y: rect.y, width: rect.width, height: cut))
                recurse(Rectangle(x: rect.x, y: rect.y + cut, width: rect.width, height: rect.height - cut))
            }
        case .quad:
            let w = rect.width / 2, h = rect.height / 2
            recurse(Rectangle(x: rect.x, y: rect.y, width: w, height: h))
            recurse(Rectangle(x: rect.x + w, y: rect.y, width: w, height: h))
            recurse(Rectangle(x: rect.x, y: rect.y + h, width: w, height: h))
            recurse(Rectangle(x: rect.x + w, y: rect.y + h, width: w, height: h))
        }
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Recursively subdivide `bounds` (the whole canvas by default) into leaf
    /// cells, driven by the seeded `random` so `seed(_:)` makes the layout
    /// reproducible. Each cell carries the depth it stopped at, so tint by
    /// `cell.depth` for scale-aware color.
    ///
    /// ```swift
    /// seed(5)
    /// stroke(.black); strokeWeight(8)
    /// for cell in subdivide(minSize: 90, chance: 0.75) {
    ///     fill(randomChoice([.white, .white, .red, .yellow, .blue]))
    ///     drawRect(cell.frame)
    /// }
    /// ```
    func subdivide(in bounds: Rectangle? = nil,
                   minSize: Double,
                   maxDepth: Int = 6,
                   chance: Double = 1,
                   fraction: ClosedRange<Double> = 0.3...0.7,
                   style: Subdivision.Style = .binary) -> [Subdivision.Cell] {
        Subdivision.cells(in: bounds ?? self.bounds, minSize: minSize, maxDepth: maxDepth,
                          chance: chance, fraction: fraction, style: style, using: &rng)
    }
}
