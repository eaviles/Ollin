import Foundation

/// Nudging a handful of numbers until something matches.
///
/// You have a few parameters and a way of saying how wrong a setting of them is. `Fit.minimize`
/// walks the parameters downhill until the wrongness stops falling:
///
/// ```swift
/// // Find the circle that passes closest to a set of marks.
/// let best = Fit.minimize(from: [width / 2, height / 2, 100]) { p in
///     marks.reduce(0) { total, mark in
///         let off = Vector2(p[0], p[1]).distance(to: mark) - p[2]
///         return total + off * off
///     }
/// }
/// drawCircle(best.values[0], best.values[1], best.values[2])
/// ```
///
/// It is not a general optimizer and does not pretend to be. It suits a few numbers with a
/// cost that changes smoothly as they change: fitting a shape to marks, a palette to a
/// picture, a spring constant to a motion you recorded. It walks *downhill from where you
/// start*, so a cost with several separate valleys hands back whichever one your starting
/// point sat in. When that matters, start it from several places and keep the best answer.
public enum Fit {

    /// Where a walk ended up.
    public struct Result: Sendable {
        /// The best setting found.
        public let values: [Double]
        /// What the cost was there.
        public let cost: Double
        /// How many steps it actually took, which is fewer than asked for when the walk
        /// settled early.
        public let steps: Int
        /// Whether it settled on its own rather than running out of steps. A walk that
        /// used every step may simply need more of them, or a larger `rate`.
        public let settled: Bool
    }

    /// Walk `start` downhill on `cost` and hand back the best setting found.
    ///
    /// - Parameters:
    ///   - start: the setting to begin from, and how many parameters there are.
    ///   - bounds: an optional range per parameter, which the walk is held inside.
    ///   - steps: the most steps to take.
    ///   - rate: how far a step moves a parameter, in the parameter's own units. Each parameter moves by
    ///     about this much per step regardless of how steep the cost is there, so it is a
    ///     step size rather than a gain, and a sensible value is a small fraction of the
    ///     range you expect the answer to live in.
    ///   - tolerance: settle once a step improves the cost by less than this.
    ///   - cost: how wrong a setting is. Lower is better; the walk never reads its shape,
    ///     only its value.
    ///
    /// The slope is measured rather than derived, by trying each parameter a little either side
    /// of where it stands, so `cost` is called about twice per parameter per step. Keep it cheap.
    public static func minimize(from start: [Double], bounds: [ClosedRange<Double>]? = nil,
                                steps: Int = 300, rate: Double = 0.05,
                                tolerance: Double = 1e-9,
                                _ cost: ([Double]) -> Double) -> Result {
        let n = start.count
        guard n > 0 else { return Result(values: start, cost: 0, steps: 0, settled: true) }

        func held(_ values: [Double]) -> [Double] {
            guard let bounds else { return values }
            return values.enumerated().map { i, v in
                i < bounds.count ? min(max(v, bounds[i].lowerBound), bounds[i].upperBound) : v
            }
        }

        var current = held(start)
        var currentCost = cost(current)
        var best = current, bestCost = currentCost

        // The step is scaled per parameter by a running estimate of how steep the cost is along
        // it, which is what lets one `rate` serve parameters measured in pixels beside parameters
        // measured in turns. Without it a single step size either creeps along the wide
        // parameter or throws the narrow one across its whole range.
        var momentum = [Double](repeating: 0, count: n)
        var steepness = [Double](repeating: 0, count: n)
        let smoothing = 0.9, steepSmoothing = 0.999, floor = 1e-8

        var taken = 0
        var settled = false
        for step in 1 ... max(1, steps) {
            taken = step
            // The slope, measured. The probe is scaled to the parameter so a parameter holding
            // hundreds of pixels and one holding a fraction are both probed sensibly.
            var slope = [Double](repeating: 0, count: n)
            for i in 0 ..< n {
                let nudge = max(abs(current[i]), 1) * 1e-5
                var up = current, down = current
                up[i] += nudge
                down[i] -= nudge
                slope[i] = (cost(held(up)) - cost(held(down))) / (2 * nudge)
            }

            for i in 0 ..< n {
                momentum[i] = smoothing * momentum[i] + (1 - smoothing) * slope[i]
                steepness[i] = steepSmoothing * steepness[i]
                    + (1 - steepSmoothing) * slope[i] * slope[i]
                // Both running averages start at zero, so early on they under-report by a
                // known amount. Dividing that out is what lets the first few steps move at
                // all instead of crawling.
                let m = momentum[i] / (1 - pow(smoothing, Double(step)))
                let v = steepness[i] / (1 - pow(steepSmoothing, Double(step)))
                current[i] -= rate * m / (v.squareRoot() + floor)
            }
            current = held(current)

            let stepped = cost(current)
            if stepped < bestCost {
                bestCost = stepped
                best = current
            }
            if abs(currentCost - stepped) < tolerance {
                settled = true
                currentCost = stepped
                break
            }
            currentCost = stepped
        }
        return Result(values: best, cost: bestCost, steps: taken, settled: settled)
    }
}
