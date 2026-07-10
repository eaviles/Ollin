import Foundation

/// A harmonograph: the Victorian drawing machine whose pen hangs from swinging
/// pendulums, each losing energy as it swings. The horizontal position is the
/// sum of the `x` pendulums, the vertical the sum of the `y` pendulums, and
/// every pendulum contributes a damped sine wave:
/// `amplitude * sin(frequency * tau * t + phase) * exp(-damping * t)`.
///
/// The signature look comes from near-unison frequencies (say `2` against
/// `2.01`): the slight detune makes the trace precess, and the damping pulls
/// each lap inside the last, weaving the nested web. Two pendulums per axis
/// is the classic machine; one per axis gives damped Lissajous figures.
///
/// The trace is a pure function of the pendulums: no randomness, so the same
/// settings always draw the same figure. Read it with `point(at:)` to animate
/// the pen live, or bake the whole trace once with `contour(duration:samples:)`
/// and stroke, hatch, or export it like any other geometry.
///
/// ```swift
/// let h = Harmonograph(
///     x: [.init(amplitude: 360, frequency: 2.00, damping: 0.015),
///         .init(amplitude: 120, frequency: 6.01, phase: .pi / 2, damping: 0.02)],
///     y: [.init(amplitude: 360, frequency: 2.01, phase: .pi / 4, damping: 0.015)])
/// let trace = h.contour()
/// ```
public struct Harmonograph: Sendable, Equatable {
    /// One damped pendulum: a sine wave whose swing decays over time.
    public struct Pendulum: Sendable, Equatable {
        /// The swing's starting half-width, in canvas units.
        public var amplitude: Double
        /// Full swings per unit of time (the sine runs at `frequency * tau`).
        /// Near-unison pairs (`2` and `2.01`) make the trace precess slowly.
        public var frequency: Double
        /// The angle the swing starts from, in radians.
        public var phase: Double
        /// Exponential decay per unit of time: the swing shrinks by
        /// `exp(-damping * t)`. Zero never settles; around `0.01...0.05`
        /// draws a trace that winds inward over a minute or two of `t`.
        public var damping: Double

        public init(amplitude: Double = 1, frequency: Double,
                    phase: Double = 0, damping: Double = 0.02) {
            self.amplitude = amplitude
            self.frequency = frequency
            self.phase = phase
            self.damping = damping
        }

        /// The pendulum's contribution at time `t`.
        public func value(at t: Double) -> Double {
            amplitude * sin(frequency * .tau * t + phase) * exp(-damping * t)
        }
    }

    /// The pendulums summed into the horizontal position.
    public var x: [Pendulum]
    /// The pendulums summed into the vertical position.
    public var y: [Pendulum]

    public init(x: [Pendulum], y: [Pendulum]) {
        self.x = x
        self.y = y
    }

    /// The pen's position at time `t`, centered on the origin; place it with
    /// the transform stack. Feed a growing `t` each frame to draw the machine
    /// live, the way the physical instrument performs.
    public func point(at t: Double) -> Vector2 {
        var px = 0.0
        var py = 0.0
        for pendulum in x { px += pendulum.value(at: t) }
        for pendulum in y { py += pendulum.value(at: t) }
        return Vector2(px, py)
    }

    /// The time by which the slowest-decaying pendulum has shrunk to 1% of
    /// its starting swing, when the trace has effectively finished. Infinite
    /// if every pendulum is undamped.
    public var settleTime: Double {
        guard let slowest = (x + y).map(\.damping).filter({ $0 > 0 }).min() else {
            return .infinity
        }
        return log(100.0) / slowest
    }

    /// The whole trace baked as an open `Contour`, from `t = 0` through
    /// `duration` (defaulting to `settleTime`, capped at 240 for undamped
    /// setups). Leave `samples` nil to size the sampling to the trace: fast
    /// pendulums over a long duration get more points, up to a cap.
    public func contour(duration: Double? = nil, samples: Int? = nil) -> Contour {
        let pendulums = x + y
        guard !pendulums.isEmpty else { return Contour([], closed: false) }
        let time = duration ?? min(settleTime, 240)
        guard time > 0, time.isFinite else { return Contour([], closed: false) }
        let fastest = pendulums.map { abs($0.frequency) }.max() ?? 1
        let count = samples.map { max(2, $0) }
            ?? min(max(1024, Int(fastest * time * 64)), 65_536)
        return Contour((0...count).map { i in
            point(at: time * Double(i) / Double(count))
        }, closed: false)
    }
}
