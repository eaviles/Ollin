import Foundation

/// Kuramoto's model of **synchronization**: a crowd of oscillators, each running
/// at its own natural pace, each pulled toward the phase of the others. Weakly
/// coupled they drift apart and the crowd is incoherent; past a critical coupling a
/// locked group forms and grows, and the crowd falls into step. It is the model
/// behind fireflies flashing together, crickets chirping in unison, pacemaker
/// cells, a footbridge swaying under a crowd, and the pendulum clocks Huygens found
/// beating together on one wall.
///
/// Hold one and `advance(by:)` it each frame, then read `phases` to draw: a firefly
/// glows by `(1 + cos(phase)) / 2`, a dot sits on a circle at its phase.
/// `coherence` is the order parameter r (0 scattered, 1 locked), `meanPhase` the
/// phase of the crowd, and `criticalCoupling` the coupling where locking starts
/// for the frequencies this crowd was given.
///
/// ```swift
/// let sync = Kuramoto(count: 300, coupling: 2, seed: 7)
///
/// override func draw() {
///     sync.advance()
///     background(.black)
///     for (i, phase) in sync.phases.enumerated() {
///         fill(Color(white: (1 + cos(phase)) / 2))
///         drawCircle(spots[i].x, spots[i].y, 6)
///     }
/// }
/// ```
///
/// The rule, for an oscillator with natural frequency w: its phase advances at
/// `w + coupling * r * sin(meanPhase - phase - lag)`, the mean-field form Kuramoto
/// solved, which is what makes the model cheap: one pass over the crowd, however
/// large. With a `range` each oscillator instead listens to its neighbors on a
/// ring, so a ring locks locally and can hold a twist, or carry a wave when there
/// is a lag. Integrated by fixed substeps, so a run is a pure function of its seed
/// and parameters and replays exactly.
public final class Kuramoto {

    /// Every oscillator's phase, in radians, kept in `0 ..< 2 * .pi`. Read to draw;
    /// set to kick a phase.
    public var phases: [Double]
    /// Every oscillator's natural frequency in radians per second, the pace it
    /// runs at with no coupling. Drawn from a normal distribution around
    /// `frequency` with `spread` when the crowd is made; set to hand it a spectrum
    /// of your own.
    public var frequencies: [Double]
    /// How hard the crowd pulls on each phase (K, in radians per second). Above
    /// `criticalCoupling` a locked group forms.
    public var coupling: Double
    /// The phase lag in the pull, in radians; 0 is Kuramoto's own model. With a lag
    /// a locked crowd runs slower than its natural pace, by `coupling * sin(lag)`
    /// when fully locked, and on a ring a lag is what makes patterns travel.
    public var lag: Double
    /// How many neighbors each way on a ring an oscillator listens to; 0 means
    /// everyone listens to everyone (the mean field). With a range the pull is
    /// averaged over those neighbors, so `coupling` means the same per neighbor.
    public var range: Int
    /// The center of the natural frequencies this crowd was made with, in radians
    /// per second.
    public let frequency: Double
    /// The standard deviation of the natural frequencies this crowd was made with,
    /// in radians per second.
    public let spread: Double

    /// A crowd of `count` oscillators at random phases, their natural frequencies
    /// drawn around `frequency` with the standard deviation `spread`.
    ///
    /// - Parameters:
    ///   - count: How many oscillators.
    ///   - coupling: How hard the crowd pulls on each phase (K). Compare it with
    ///     `criticalCoupling` after making the crowd.
    ///   - frequency: The center of the natural frequencies, in radians per second
    ///     (1 is one turn every 2 pi seconds).
    ///   - spread: The standard deviation of the natural frequencies, in radians
    ///     per second. 0 makes every oscillator identical.
    ///   - lag: The phase lag in the pull, in radians.
    ///   - range: Neighbors each way on a ring, or 0 for the mean field.
    ///   - seed: Picks the phases and the frequencies, so the same seed replays
    ///     the same crowd.
    public init(count: Int, coupling: Double = 1, frequency: Double = 1, spread: Double = 0.5,
                lag: Double = 0, range: Int = 0, seed: Int = 0) {
        let sigma = max(0, spread)
        self.coupling = coupling
        self.frequency = frequency
        self.spread = sigma
        self.lag = lag
        self.range = max(0, range)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let n = Swift.max(count, 0)
        self.phases = (0 ..< n).map { _ in Double.random(in: 0 ..< 2 * .pi, using: &rng) }
        self.frequencies = (0 ..< n).map { _ in frequency + sigma * Kuramoto.gaussian(using: &rng) }
    }

    /// The number of oscillators.
    public var count: Int { phases.count }

    /// The order parameter r, the length of the mean of every phase's unit vector:
    /// 0 when the phases are spread evenly around the circle, 1 when they all
    /// agree. The measure to watch as a crowd locks.
    public var coherence: Double { order().r }

    /// The phase of the crowd as a whole, in radians: the direction of the mean
    /// unit vector, which a locked crowd shares.
    public var meanPhase: Double { order().psi }

    /// The coupling at which a locked group first forms, for the normal spread of
    /// natural frequencies the crowd was made with: `spread * sqrt(8 / pi)`, from
    /// Kuramoto's `2 / (pi * g(0))` with `g` the frequency distribution. Below it
    /// the crowd stays scattered however long it runs; a few times above it the
    /// crowd locks nearly whole. (Identical oscillators lock at any coupling.)
    public var criticalCoupling: Double { spread * (8 / Double.pi).squareRoot() }

    /// Advance the crowd by `dt` seconds (one frame at 60 fps by default). The
    /// interval is split into fixed substeps, so a bigger `dt` costs more substeps
    /// rather than accuracy, and every phase is wrapped back into `0 ..< 2 * .pi`.
    public func advance(by dt: Double = 1.0 / 60.0) {
        let n = Swift.min(phases.count, frequencies.count)
        guard dt > 0, n > 0 else { return }
        let substeps = Swift.max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(substeps)
        let turn = 2 * Double.pi
        let reach = Swift.min(range, (n - 1) / 2)
        var rates = [Double](repeating: 0, count: n)
        for _ in 0 ..< substeps {
            if reach == 0 {
                let o = order()
                let pull = coupling * o.r
                for i in 0 ..< n {
                    rates[i] = frequencies[i] + pull * sin(o.psi - phases[i] - lag)
                }
            } else {
                let weight = coupling / Double(2 * reach)
                for i in 0 ..< n {
                    var pull = 0.0
                    for k in 1 ... reach {
                        pull += sin(phases[(i + k) % n] - phases[i] - lag)
                        pull += sin(phases[(i - k + n) % n] - phases[i] - lag)
                    }
                    rates[i] = frequencies[i] + weight * pull
                }
            }
            for i in 0 ..< n {
                var p = (phases[i] + rates[i] * h).truncatingRemainder(dividingBy: turn)
                if p < 0 { p += turn }
                phases[i] = p
            }
        }
    }

    /// The mean unit vector of the phases: its length and its direction.
    private func order() -> (r: Double, psi: Double) {
        let n = phases.count
        guard n > 0 else { return (0, 0) }
        var x = 0.0, y = 0.0
        for p in phases {
            x += cos(p)
            y += sin(p)
        }
        x /= Double(n)
        y /= Double(n)
        return ((x * x + y * y).squareRoot(), atan2(y, x))
    }

    /// One standard normal draw, by the Box-Muller transform.
    private static func gaussian<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        let u1 = 1 - Double.random(in: 0 ..< 1, using: &rng)   // (0, 1], so the log is finite
        let u2 = Double.random(in: 0 ..< 1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
