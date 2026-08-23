import Foundation

/// The path a ``Sketch/sway(over:in:shape:phase:)`` traces through one lap.
///
/// The four worked-out shapes start at the low end of the range, so switching
/// between them changes how a value travels and never where it begins.
/// `.wander` starts wherever its field does. All five close their lap exactly,
/// which is what lets a swaying sketch declare a `loopDuration` and export a
/// seamless loop.
public enum SwayShape: Sendable, CaseIterable {
    /// Out and back on a cosine: no corners anywhere, slowest at the two ends.
    /// The default, and the one a breathing, drifting, or floating motion wants.
    case sine
    /// Out and back in a straight line, at one speed, turning sharply at each
    /// end. The shape of ``Sketch/pingPong(over:phase:)``.
    case triangle
    /// A ramp to the high end and a jump back to the low one. The shape of
    /// ``Sketch/loopProgress(over:phase:)``.
    case saw
    /// One end for half the lap, the other end for the rest. Nothing in
    /// between, for a value that switches rather than travels.
    case square
    /// A smooth random drift between the ends, taken from the sketch's own
    /// noise field. It never repeats within a lap and still closes one, because
    /// the lap tours a closed circle through the field (see
    /// ``Sketch/noise(loop:radius:)``). Reseeded by `noiseSeed`, so a run
    /// wanders the same way twice.
    case wander
}

public extension Sketch {
    /// A value that travels from one end of `range` to the other and back, once
    /// every `duration` seconds. The slow sway most sketches write by hand.
    ///
    /// ```swift
    /// drawCircle(width / 2, height / 2, sway(over: 4, in: 100...300))
    /// ```
    ///
    /// It starts at the low end of the range, reaches the high end halfway
    /// through the lap, and is back at the low end as the lap closes. With no
    /// `range` it hands back a plain `0...1` to drive something else with.
    /// (`.wander` is the exception on the starting point: it begins wherever
    /// the noise field does, which is near the middle.)
    ///
    /// `shape` picks the path it takes between the ends, and `phase` shifts the
    /// lap by a fraction of its length, the same argument
    /// ``Sketch/loopProgress(over:phase:)`` takes, so a row of neighbors can
    /// sway in a traveling wave:
    ///
    /// ```swift
    /// for (i, cell) in grid(columns: 12, rows: 1).cells.enumerated() {
    ///     let r = sway(over: 3, in: 8...40, phase: Double(i) / 12)
    ///     drawCircle(center: cell.center, radius: r)
    /// }
    /// ```
    ///
    /// Every shape closes its lap exactly, `.wander` included, so a sketch that
    /// sways can still declare a `loopDuration` and export a seamless loop. A
    /// `duration` of zero or less holds at the low end.
    ///
    /// Two sways with the same arguments are the same value, since this reads
    /// the clock and nothing else. Give them different phases, or different
    /// durations, to tell them apart. For `.wander` a phase is a delay along one
    /// tour rather than a different tour, so several independent drifts are
    /// better driven by ``Sketch/signedNoise(_:loop:radius:)`` with a coordinate
    /// each.
    func sway(over duration: Double, in range: ClosedRange<Double> = 0...1,
              shape: SwayShape = .sine, phase: Double = 0) -> Double {
        guard duration > 0 else { return range.lowerBound }
        let lap = loopProgress(over: duration, phase: phase)
        let unit: Double
        switch shape {
        case .sine:     unit = (1 - cos(lap * .tau)) / 2
        case .triangle: unit = lap > 0.5 ? 2 - lap * 2 : lap * 2
        case .saw:      unit = lap
        case .square:   unit = lap < 0.5 ? 0 : 1
        case .wander:   unit = noise(loop: lap)
        }
        return lerp(range.lowerBound, range.upperBound, unit)
    }
}
