import Foundation

/// A one-dimensional iterated map with a dial: `x' = f(x, r)`, the simplest
/// systems that turn orderly and then chaotic as a single parameter grows. The
/// logistic map is the canonical member (May's population model, whose
/// **bifurcation diagram** sweeps `r` and plots where the orbit settles: the
/// period-doubling cascade picture), with the sine, tent, and Gauss maps
/// beside it.
///
/// Where `ChaoticMap` iterates a fixed 2D rule, an `IteratedMap` is a whole
/// *family*: the parameter rides every call, so one value type answers "what
/// does the orbit do at r?" (`orbit(at:count:settle:)`, the staircase
/// `cobweb(at:steps:)`), "where does it settle across all r?"
/// (`bifurcation(over:...)` points, `bifurcationImage(width:height:...)` as a
/// density field), and "is it chaotic there?" (`lyapunovExponent(at:)`).
///
/// Everything is a pure function of the map and its arguments, with no
/// randomness anywhere, so every diagram reproduces exactly. Pick a family
/// from the built-in factories (`.logistic()`, `.sine()`, `.tent()`,
/// `.gauss()`), or supply your own rule.
public struct IteratedMap: Sendable {

    /// The iteration rule: the next value given the current value `x` and the
    /// family parameter `r`.
    public var next: @Sendable (_ x: Double, _ r: Double) -> Double

    /// The rule's derivative `∂f/∂x` at `(x, r)`, used by `lyapunovExponent`.
    /// Optional: when `nil`, the exponent falls back to a central-difference
    /// estimate, which is fine for smooth rules.
    public var derivative: (@Sendable (_ x: Double, _ r: Double) -> Double)?

    /// The parameter window the diagram helpers sweep by default, the
    /// family's canonical picture (for `.logistic()`, `2.4...4`: the stable
    /// line, the first fork at 3, the cascade, chaos, and the period-3
    /// window). `orbit(at:)` and friends accept any parameter regardless.
    public var parameterRange: ClosedRange<Double>

    /// The interval the orbit lives in, which is the diagram's vertical axis
    /// and the cobweb's square frame.
    public var valueRange: ClosedRange<Double>

    /// The default starting value. Any point in the basin works (the orbit
    /// forgets it during `settle`), so this mostly spares call sites an
    /// argument.
    public var start: Double

    /// A family defined by its rule, the canonical parameter window, and the
    /// interval the orbit lives in.
    public init(parameterRange: ClosedRange<Double>,
                valueRange: ClosedRange<Double>,
                start: Double,
                derivative: (@Sendable (_ x: Double, _ r: Double) -> Double)? = nil,
                next: @escaping @Sendable (_ x: Double, _ r: Double) -> Double) {
        self.next = next
        self.derivative = derivative
        self.parameterRange = parameterRange
        self.valueRange = valueRange
        self.start = start
    }

    // MARK: - One parameter at a time

    /// Iterate `count` values of the orbit at parameter `r`, discarding
    /// `settle` warmup steps first so the transient from `start` is gone.
    public func orbit(at r: Double, count: Int, settle: Int = 0,
                      from start: Double? = nil) -> [Double] {
        guard count > 0 else { return [] }
        var x = start ?? self.start
        for _ in 0..<max(0, settle) { x = next(x, r) }
        var values = [Double]()
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(x)
            x = next(x, r)
        }
        return values
    }

    /// The rule's curve `y = f(x, r)` sampled across `valueRange`, as points
    /// in `(x, y)` map space: the hump a cobweb bounces between. Draw it with
    /// the diagonal `y = x` to frame a `cobweb(at:steps:)` staircase.
    public func graph(at r: Double, samples: Int = 256) -> [Vector2] {
        guard samples > 1 else { return [] }
        let lo = valueRange.lowerBound, span = valueRange.upperBound - lo
        return (0..<samples).map { i in
            let x = lo + span * Double(i) / Double(samples - 1)
            return Vector2(x, next(x, r))
        }
    }

    /// The cobweb staircase at parameter `r`: the classic way to watch one
    /// orbit converge, cycle, or wander. Starting from `(x₀, floor)`, each
    /// step rises vertically to the curve `(x, f(x))` and slides horizontally
    /// to the diagonal `(f(x), f(x))`; the polyline is those corners in order,
    /// `2·steps + 1` points in `(x, y)` map space (`valueRange` on both axes).
    /// Draw it over `graph(at:)` and the diagonal to complete the figure.
    public func cobweb(at r: Double, steps: Int, from start: Double? = nil) -> [Vector2] {
        guard steps > 0 else { return [] }
        var x = start ?? self.start
        var points = [Vector2]()
        points.reserveCapacity(2 * steps + 1)
        points.append(Vector2(x, valueRange.lowerBound))
        for _ in 0..<steps {
            let fx = next(x, r)
            points.append(Vector2(x, fx))     // rise to the curve
            points.append(Vector2(fx, fx))    // slide to the diagonal
            x = fx
        }
        return points
    }

    // MARK: - Sweeping the parameter

    /// The bifurcation diagram as raw points: sweep `over` (default
    /// `parameterRange`) in `columns` steps and, at each parameter, record
    /// `perColumn` successive orbit values after `settle` warmup steps. Each
    /// point is `(r, x)`; map them onto a rectangle and draw them as dots
    /// (`drawBifurcation` does exactly that). Columns sample at step
    /// *centers*, never the range's exact endpoints, which for some families
    /// are numerically degenerate (the tent map at exactly 2 collapses to 0
    /// in floating point).
    public func bifurcation(over range: ClosedRange<Double>? = nil,
                            columns: Int = 800, perColumn: Int = 200,
                            settle: Int = 1000) -> [Vector2] {
        let range = range ?? parameterRange
        guard columns > 0, perColumn > 0 else { return [] }
        let span = range.upperBound - range.lowerBound
        var points = [Vector2]()
        points.reserveCapacity(columns * perColumn)
        for column in 0..<columns {
            let r = range.lowerBound + span * (Double(column) + 0.5) / Double(columns)
            var x = start
            for _ in 0..<max(0, settle) { x = next(x, r) }
            for _ in 0..<perColumn {
                points.append(Vector2(r, x))
                x = next(x, r)
            }
        }
        return points
    }

    /// The bifurcation diagram as a density field: one parameter per pixel
    /// column, each column's orbit binned into pixel rows, tone from visit
    /// counts (log-scaled by one global factor, so periodic orbits print as
    /// crisp dark lines while chaotic bands wash gray). Ink on white, higher
    /// values up, `valueRange` spanning the height; samples outside it are
    /// dropped. Deterministic, so a diagram is render-once `setup()` work.
    public func bifurcationImage(width: Int, height: Int,
                                 over range: ClosedRange<Double>? = nil,
                                 samplesPerColumn: Int = 2000,
                                 settle: Int = 1000) -> Image? {
        guard width > 0, height > 0, samplesPerColumn > 0 else { return nil }
        let range = range ?? parameterRange
        let rSpan = range.upperBound - range.lowerBound
        let xLo = valueRange.lowerBound
        let xSpan = valueRange.upperBound - xLo
        guard xSpan > 0 else { return nil }

        var counts = [Int](repeating: 0, count: width * height)
        var peak = 0
        for column in 0..<width {
            let r = range.lowerBound + rSpan * (Double(column) + 0.5) / Double(width)
            var x = start
            for _ in 0..<max(0, settle) { x = next(x, r) }
            for _ in 0..<samplesPerColumn {
                let v = (valueRange.upperBound - x) / xSpan
                if v >= 0, v < 1 {
                    let index = Int(v * Double(height)) * width + column
                    counts[index] += 1
                    if counts[index] > peak { peak = counts[index] }
                }
                x = next(x, r)
            }
        }

        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        if peak > 0 {
            let norm = 1.0 / log1p(Double(peak))
            for (i, count) in counts.enumerated() where count > 0 {
                let ink = log1p(Double(count)) * norm
                let gray = UInt8((255.0 * (1 - ink)).rounded())
                bytes[i * 4] = gray
                bytes[i * 4 + 1] = gray
                bytes[i * 4 + 2] = gray
            }
        }
        return Image(width: width, height: height, premultipliedRGBA: bytes)
    }

    /// The largest Lyapunov exponent at parameter `r`: the average of
    /// `ln |f′(x)|` along the orbit. Negative means nearby orbits converge (a
    /// stable cycle), positive means they separate exponentially, which is
    /// chaos. For the logistic map it dips below zero in every periodic
    /// window and reaches exactly `ln 2` at r = 4. Uses the analytic
    /// `derivative` when the family carries one, else a central difference; a
    /// visit to a point with `f′ = 0` (a superstable orbit) is floored rather
    /// than sent to negative infinity.
    public func lyapunovExponent(at r: Double, iterations: Int = 10_000,
                                 settle: Int = 1000) -> Double {
        guard iterations > 0 else { return 0 }
        var x = start
        for _ in 0..<max(0, settle) { x = next(x, r) }
        var sum = 0.0
        for _ in 0..<iterations {
            let slope: Double
            if let derivative {
                slope = derivative(x, r)
            } else {
                let h = 1e-6
                slope = (next(x + h, r) - next(x - h, r)) / (2 * h)
            }
            sum += log(max(abs(slope), 1e-12))
            x = next(x, r)
        }
        return sum / Double(iterations)
    }
}

// MARK: - Built-in families

public extension IteratedMap {

    /// The logistic map `x' = r·x·(1 − x)`, May's population model and the
    /// canonical route to chaos. Its full domain is r in 0...4 (beyond 4 the
    /// orbit escapes the unit interval); the default window `2.4...4` is the
    /// classic diagram: the stable line, the first fork at r = 3, the
    /// period-doubling cascade to chaos at r ≈ 3.5699, and the period-3
    /// window opening at 1 + √8 ≈ 3.828.
    static func logistic() -> IteratedMap {
        IteratedMap(parameterRange: 2.4...4.0, valueRange: 0...1, start: 0.3,
                    derivative: { x, r in r * (1 - 2 * x) },
                    next: { x, r in r * x * (1 - x) })
    }

    /// The sine map `x' = r·sin(π·x)` for r in 0...1: a different formula
    /// with the same single smooth hump, so its diagram repeats the logistic
    /// cascade almost exactly, the universality Feigenbaum explained.
    static func sine() -> IteratedMap {
        IteratedMap(parameterRange: 0.6...1.0, valueRange: 0...1, start: 0.3,
                    derivative: { x, r in r * .pi * cos(.pi * x) },
                    next: { x, r in r * sin(.pi * x) })
    }

    /// The tent map `x' = r·min(x, 1 − x)` for r in 0...2: the piecewise-
    /// linear hump. No period doubling; it snaps from a fixed point straight
    /// into chaos past r = 1, its diagram all merging bands, and its Lyapunov
    /// exponent is exactly `ln r`. (At exactly r = 2 a floating-point orbit
    /// collapses to 0, one doubled bit at a time; the diagram helpers sample
    /// step centers, so a sweep to 2 never lands on it.)
    static func tent() -> IteratedMap {
        IteratedMap(parameterRange: 1.0...2.0, valueRange: 0...1, start: 0.3,
                    derivative: { x, r in x < 0.5 ? r : -r },
                    next: { x, r in r * min(x, 1 - x) })
    }

    /// The Gauss map `x' = exp(−α·x²) + r`, the bell-curve hump swept by its
    /// offset, nicknamed the mouse map for the two-eared diagram it draws
    /// over r in −1...1. Unlike the single-hump families it can hold two
    /// attractors at once, so parts of the diagram depend on where the orbit
    /// starts.
    static func gauss(alpha: Double = 4.9) -> IteratedMap {
        IteratedMap(parameterRange: -1.0...1.0, valueRange: -1.0...1.5, start: 0,
                    derivative: { x, _ in -2 * alpha * x * exp(-alpha * x * x) },
                    next: { x, r in exp(-alpha * x * x) + r })
    }
}

// MARK: - Sketch sugar

public extension Sketch {

    /// Draw a family's bifurcation diagram as dots in the current `fill` at
    /// the current `pointSize`, mapped into `rect` (default: the whole
    /// canvas): the parameter sweeps left to right across `over` (default:
    /// the family's `parameterRange`), settled orbit values plot bottom to
    /// top across `valueRange`. One column per pixel of width unless
    /// `columns` says otherwise. A translucent fill lets the columns' revisit
    /// density shade itself; for the fully tonal version draw
    /// `bifurcationImage(width:height:)` instead. The diagram never changes
    /// frame to frame, so heavy ones belong in a retained batch
    /// (`makeBatch`/`drawBatch`).
    func drawBifurcation(_ map: IteratedMap, over range: ClosedRange<Double>? = nil,
                         in rect: Rectangle? = nil, columns: Int? = nil,
                         perColumn: Int = 200, settle: Int = 1000) {
        let rect = rect ?? canvasRectangle
        let range = range ?? map.parameterRange
        let columns = columns ?? max(1, Int(rect.width.rounded()))
        let rSpan = range.upperBound - range.lowerBound
        let xSpan = map.valueRange.upperBound - map.valueRange.lowerBound
        guard rSpan > 0, xSpan > 0 else { return }
        let points = map.bifurcation(over: range, columns: columns,
                                     perColumn: perColumn, settle: settle)
        drawPoints(points.map { p in
            rect.point(u: (p.x - range.lowerBound) / rSpan,
                       v: (map.valueRange.upperBound - p.y) / xSpan)
        })
    }
}
