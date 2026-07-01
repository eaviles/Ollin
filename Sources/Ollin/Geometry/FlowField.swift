import Foundation

/// A flow field: a direction at every point of the plane. Trace *streamlines*
/// through it (curves that follow the flow, the flow-field look) or *advect*
/// particles and strokes along it. The direction is given by an `angle`
/// function, so a field can come from noise, a formula, or anything you like.
///
/// Build one from Perlin noise with the `flowField` / `curlField` sketch sugar,
/// or hand `FlowField` your own angle function. Streamlines are ordinary point
/// lists, so they feed stroking, the shape booleans, hatching, and SVG export;
/// trace them once and hold them (a field is a pure function of its inputs and
/// the seed, so the same seed traces the same lines).
///
/// ```swift
/// seed(3)
/// let field = flowField(scale: 0.0016)
/// let seeds = poissonDisk(radius: 14)
/// stroke(.white); strokeWeight(2); noFill()
/// for line in field.streamlines(from: seeds, stepLength: 4, steps: 220,
///                               bounds: bounds, separation: 12) {
///     drawPolyline(line)
/// }
/// ```
public struct FlowField {
    /// The flow direction (radians) at a point.
    public let angle: (Vector2) -> Double

    /// A field from an angle function (radians at each point).
    public init(angle: @escaping (Vector2) -> Double) {
        self.angle = angle
    }

    /// The unit flow vector at `p`.
    public func direction(at p: Vector2) -> Vector2 {
        Vector2(angle: angle(p))
    }

    /// Trace a streamline through `start`, stepping along the field both forward
    /// and backward so the seed sits in the middle of the curve. It stops after
    /// `steps` steps each way, or when it leaves `bounds`.
    public func streamline(from start: Vector2, stepLength: Double = 4, steps: Int = 200,
                           bounds: Rectangle? = nil) -> [Vector2] {
        let forward = trace(from: start, sign: 1, stepLength: stepLength, steps: steps, bounds: bounds)
        let backward = trace(from: start, sign: -1, stepLength: stepLength, steps: steps, bounds: bounds)
        return backward.dropFirst().reversed() + forward
    }

    /// Trace a streamline from each of `seeds`. With no `separation` the lines are
    /// independent and may cross; with a `separation` they are traced as
    /// *evenly-spaced* streamlines (a line stops when it comes within `separation`
    /// of one already traced), so they fan out without crossing, the flow-field
    /// look. A seed that already sits within `separation` of a line is skipped.
    public func streamlines(from seeds: [Vector2], stepLength: Double = 4, steps: Int = 200,
                            bounds: Rectangle? = nil, separation: Double? = nil) -> [[Vector2]] {
        guard let separation, separation > 0 else {
            return seeds.map { streamline(from: $0, stepLength: stepLength, steps: steps, bounds: bounds) }
        }

        let cell = separation
        var grid: [FlowCell: [Vector2]] = [:]
        let sep2 = separation * separation

        func tooClose(_ p: Vector2) -> Bool {
            let col = Int(floor(p.x / cell)), row = Int(floor(p.y / cell))
            for cc in (col - 1) ... (col + 1) {
                for rr in (row - 1) ... (row + 1) {
                    guard let bucket = grid[FlowCell(cc, rr)] else { continue }
                    for q in bucket where p.distanceSquared(to: q) < sep2 { return true }
                }
            }
            return false
        }

        func commit(_ points: [Vector2]) {
            for p in points {
                grid[FlowCell(Int(floor(p.x / cell)), Int(floor(p.y / cell))), default: []].append(p)
            }
        }

        var lines: [[Vector2]] = []
        for seed in seeds where !tooClose(seed) {
            let forward = trace(from: seed, sign: 1, stepLength: stepLength, steps: steps,
                                bounds: bounds, stop: tooClose)
            let backward = trace(from: seed, sign: -1, stepLength: stepLength, steps: steps,
                                 bounds: bounds, stop: tooClose)
            let line = Array(backward.dropFirst().reversed() + forward)
            if line.count >= 2 {
                commit(line)
                lines.append(line)
            }
        }
        return lines
    }

    /// Advance each of `points` one step of `stepLength` along the field, for
    /// advecting particles or strokes frame by frame.
    public func advected(_ points: [Vector2], stepLength: Double = 2) -> [Vector2] {
        points.map { $0 + direction(at: $0) * stepLength }
    }

    // MARK: - Tracing

    /// Step from `start` along the field (times `sign`) until leaving `bounds`,
    /// hitting `steps`, or `stop` returns true for the next point.
    private func trace(from start: Vector2, sign: Double, stepLength: Double, steps: Int,
                       bounds: Rectangle?, stop: ((Vector2) -> Bool)? = nil) -> [Vector2] {
        var points = [start]
        var p = start
        for _ in 0 ..< Swift.max(steps, 0) {
            let next = p + direction(at: p) * (stepLength * sign)
            if let bounds, !bounds.contains(next) { break }
            if let stop, stop(next) { break }
            points.append(next)
            p = next
        }
        return points
    }
}

/// A uniform-grid cell key for the evenly-spaced streamline separation test.
private struct FlowCell: Hashable {
    let column: Int, row: Int
    init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A flow field driven by Perlin noise: the angle at a point is the signed
    /// noise there mapped across a half-turn per unit (`turns`), sampled at
    /// `scale` (smaller is smoother), on the `z` slice (animate it for a drifting
    /// field). Seeded by the sketch's noise, so `seed(_:)` fixes the field.
    ///
    /// The field captures the sketch's noise, so trace streamlines from it and
    /// hold *those* rather than storing the field itself.
    func flowField(scale: Double = 0.002, turns: Double = 1, z: Double = 0) -> FlowField {
        FlowField { p in self.signedNoise(p.x * scale, p.y * scale, z) * .pi * turns }
    }

    /// A flow field pointing along the divergence-free curl of the Perlin field,
    /// so streamlines read as smooth, sourceless swirls. Sampled at `scale`, on
    /// the `z` slice. Seeded by the sketch's noise.
    func curlField(scale: Double = 0.003, z: Double = 0) -> FlowField {
        FlowField { p in self.curlNoise(p.x * scale + z, p.y * scale).angle }
    }
}
