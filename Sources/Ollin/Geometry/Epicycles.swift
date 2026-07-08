import Foundation

/// A closed outline rebuilt as a chain of rotating circles.
///
/// The discrete Fourier transform reads evenly spaced samples of a closed
/// contour as points in the plane and rewrites them as a sum of circular
/// motions: each `Term` is a circle of fixed `amplitude` spinning a
/// whole-number `frequency` of turns per lap, starting from `phase`. Chained
/// tip to tail around the fixed `center`, the last tip traces the outline;
/// the more terms the chain keeps, the closer the trace. Truncating to the
/// largest `k` terms gives the best `k`-circle approximation, which is why
/// the chain is stored biggest first.
///
/// Build one from any closed `Contour` (an imported SVG outline, a glyph from
/// `textToShapes`, points you computed) and read it three ways: `point(at:)`
/// for the traced position at a lap phase, `joints(at:)` for the chain's
/// circle centers (the classic spinning-circles drawing), and `path()` for
/// the whole reconstruction as geometry. There is no randomness: the same
/// contour always produces the same chain, so a fixed frame reproduces.
///
/// The transform is the plain O(n²) DFT, computed once at construction; at
/// the default 256 samples that is a sub-millisecond, setup-time cost.
public struct Epicycles: Sendable, Equatable {
    /// One rotating circle in the chain.
    public struct Term: Sendable, Equatable {
        /// Whole turns this circle completes per lap. Negative frequencies
        /// spin the other way; both directions are needed to trace an
        /// arbitrary outline.
        public var frequency: Int
        /// The circle's radius.
        public var amplitude: Double
        /// The angle the circle starts from at phase `0`.
        public var phase: Double

        public init(frequency: Int, amplitude: Double, phase: Double) {
            self.frequency = frequency
            self.amplitude = amplitude
            self.phase = phase
        }
    }

    /// The fixed center of the chain: the average of the samples (the
    /// transform's constant term).
    public var center: Vector2

    /// The rotating terms, largest amplitude first. `terms:` arguments on the
    /// read methods count a prefix of this array, so `terms: 8` always means
    /// "the eight biggest circles".
    public var terms: [Term]

    /// Build the chain from points already evenly spaced around a closed
    /// outline. The transform assumes even spacing; points that arrive uneven
    /// (a glyph outline, an SVG path) should come through
    /// `init(_:samples:)` or `Contour.resampled(spacing:)` first.
    public init(points: [Vector2]) {
        let n = points.count
        guard n > 0 else {
            center = .zero
            terms = []
            return
        }
        var built: [Term] = []
        built.reserveCapacity(n - 1)
        var dc = Vector2.zero
        for k in 0 ..< n {
            var re = 0.0
            var im = 0.0
            for (i, p) in points.enumerated() {
                let angle = -Double.tau * Double(k) * Double(i) / Double(n)
                let c = cos(angle)
                let s = sin(angle)
                re += p.x * c - p.y * s
                im += p.x * s + p.y * c
            }
            re /= Double(n)
            im /= Double(n)
            if k == 0 {
                dc = Vector2(re, im)
                continue
            }
            // Map the second half of the spectrum onto negative turn counts,
            // so every term spins at most n/2 turns per lap.
            let frequency = k <= n / 2 ? k : k - n
            built.append(Term(frequency: frequency,
                              amplitude: (re * re + im * im).squareRoot(),
                              phase: atan2(im, re)))
        }
        // Biggest circle first. Ties break by slowest spin, then positive
        // direction, so the order (and everything drawn from it) is
        // deterministic even for symmetric inputs.
        built.sort {
            if $0.amplitude != $1.amplitude { return $0.amplitude > $1.amplitude }
            if abs($0.frequency) != abs($1.frequency) { return abs($0.frequency) < abs($1.frequency) }
            return $0.frequency > $1.frequency
        }
        center = dc
        terms = built
    }

    /// Build the chain from a contour, resampled first to `samples` points an
    /// even walked-length apart (uneven spacing would bend the reconstruction
    /// toward the densely sampled stretches). The contour is traced as a
    /// loop, so it should be closed; an open contour is closed across its
    /// ends.
    public init(_ contour: Contour, samples: Int = 256) {
        let count = max(4, samples)
        let source = Contour(contour.points, closed: true)
        self.init(points: (0 ..< count).map { source.point(at: Double($0) / Double(count)) })
    }

    /// The traced position at lap phase `t` (`0...1`; one lap per unit, so a
    /// looping sketch passes `loopProgress(over:)` straight in), keeping the
    /// largest `terms` circles. With every term kept, phase `i / n` lands
    /// exactly on input sample `i`.
    public func point(at t: Double, terms count: Int = .max) -> Vector2 {
        var p = center
        for term in terms.prefix(max(0, count)) {
            let angle = term.phase + Double(term.frequency) * t * .tau
            p += Vector2(angle: angle, length: term.amplitude)
        }
        return p
    }

    /// The chain's joints at lap phase `t`: the fixed `center`, then each
    /// kept circle's tip in order, ending at the traced point. Joint `i` is
    /// the center of circle `i` (radius `terms[i].amplitude`), and the last
    /// joint equals `point(at:terms:)`, which is everything a sketch needs to
    /// draw the classic spinning-circles construction.
    public func joints(at t: Double, terms count: Int = .max) -> [Vector2] {
        var p = center
        var result = [p]
        for term in terms.prefix(max(0, count)) {
            let angle = term.phase + Double(term.frequency) * t * .tau
            p += Vector2(angle: angle, length: term.amplitude)
            result.append(p)
        }
        return result
    }

    /// The whole reconstruction as a closed contour: `samples` traced points
    /// around one lap, keeping the largest `terms` circles. Feed it to
    /// `drawShape`, the booleans, or hatching like any other geometry.
    public func path(samples: Int = 512, terms count: Int = .max) -> Contour {
        let n = max(3, samples)
        return Contour((0 ..< n).map { point(at: Double($0) / Double(n), terms: count) },
                       closed: true)
    }
}

public extension Sketch {
    /// Draw the classic epicycle construction at lap phase `t`: each kept
    /// circle as an unfilled outline in the current stroke, with a spoke from
    /// its center to the next joint. The current fill is untouched. Read the
    /// traced tip with `epicycles.point(at:terms:)` to build the trail.
    func drawEpicycles(_ epicycles: Epicycles, at t: Double, terms count: Int = .max) {
        let joints = epicycles.joints(at: t, terms: count)
        guard joints.count > 1 else { return }
        withState {
            noFill()
            for (i, term) in epicycles.terms.prefix(max(0, count)).enumerated() {
                drawCircle(center: joints[i], radius: term.amplitude)
                drawLine(joints[i], joints[i + 1])
            }
        }
    }
}
