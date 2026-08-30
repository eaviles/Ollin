import Foundation

/// Crack growth: straight cracks race across the canvas and the plane
/// subdivides into city-block cells. Each crack writes its angle into a
/// raster grid as it advances; a crack that steps onto a cell holding some
/// *other* angle has met an older line, so it stops, restarts perpendicular
/// to a random point on the existing pattern, and recruits one more crack.
/// From a few cracks and a handful of phantom seed angles the whole canvas
/// fills with a street-map texture.
///
/// It's a stateful stepper you hold and draw *incrementally*: `step()`
/// advances every active crack one tick and returns this tick's marks, ready
/// to lay onto an accumulating canvas (`noClear()`). Each mark carries the
/// new crack point plus a one-sided wash span (the open space beside the
/// crack) and a slowly wandering `gain`; `CrackGrowth.grains` lays the
/// classic translucent sand wash along that span. Seed it for a reproducible
/// pattern. `segments` is every crack line so far, for stroking or SVG
/// export.
///
/// ```swift
/// let cracks = CrackGrowth(width: 1080, height: 1080, seed: 7)
///
/// override func setup() { noClear() }
///
/// override func draw() {
///     if frameCount == 1 { background(.white) }
///     for mark in cracks.step(4) {
///         let ink = palette[mark.crack % palette.count]
///         for grain in CrackGrowth.grains(from: mark.point, to: mark.washExtent,
///                                         gain: mark.gain) {
///             fill(ink.withAlpha(grain.alpha))
///             drawPoint(at: grain.position)
///         }
///         fill(Color.black.withAlpha(0.33))
///         drawPoint(at: mark.point)
///     }
/// }
/// ```
public final class CrackGrowth {
    /// One tick of one crack: the new point on its line, and the wash span
    /// beside it.
    public struct Mark {
        /// The index of the crack that moved. Stable for the crack's whole
        /// life (restarts included), so it maps cleanly onto a palette.
        public let crack: Int
        /// The new point on the crack's line.
        public let point: Vector2
        /// The far end of the open space beside the crack (always on the
        /// same side of the line), where the wash fades out.
        public let washExtent: Vector2
        /// This tick's wash strength (`0...1`), a slow random walk per
        /// crack, so the wash breathes along the line.
        public let gain: Double
    }

    /// One grain of the wash: a position along the span and its alpha.
    public struct Grain {
        /// Where the grain lands.
        public let position: Vector2
        /// The grain's alpha (multiply into the wash color).
        public let alpha: Double
    }

    /// The number of cracks so far (they only ever multiply, up to
    /// `maxCracks`).
    public var count: Int { cracks.count }
    /// The population cap: every stop recruits one more crack until this
    /// many exist.
    public let maxCracks: Int

    /// Every crack line so far: the finished runs plus each active crack
    /// from its origin to its current tip. Straight segments, ready for
    /// stroking or the vector exports.
    public var segments: [(Vector2, Vector2)] {
        var all = finished
        for crack in cracks where crack.alive && crack.origin != crack.position {
            all.append((crack.origin, crack.position))
        }
        return all
    }

    private struct Crack {
        var position: Vector2
        var angle: Double        // radians
        var origin: Vector2
        var gain: Double
        var alive: Bool
    }

    private let width: Int
    private let height: Int
    private var grid: [Double]   // the angle that cracked each cell; .infinity = untouched
    private var crackedCells: [Int] = []   // every claimed cell, in claim order
    private var cracks: [Crack] = []
    private var finished: [(Vector2, Vector2)] = []
    private var rng: SplitMix64

    private static let stepLength = 0.42       // one tick's advance
    private static let firstNudge = 0.61       // clears the parent cell on restart
    private static let washStep = 0.81         // the sideways open-space scan
    private static let sameLine = 5 * Double.pi / 180   // within this, a cell reads as my own line
    private static let spawnWobble = 2 * Double.pi / 180 // deviation around the perpendicular
    private static let cellFuzz = 0.33         // sub-pixel jitter on the grid check

    /// A fresh field of cracks over a `width` by `height` canvas.
    ///
    /// - Parameters:
    ///   - cracks: how many cracks start moving at once.
    ///   - seedAngles: how many phantom angles are scattered on the empty
    ///     grid, so the first cracks have somewhere to start.
    ///   - maxCracks: the population cap.
    ///   - seed: the whole run repeats from the same seed.
    public init(width: Double, height: Double, cracks startCount: Int = 3,
                seedAngles: Int = 16, maxCracks: Int = 200, seed: UInt64 = 0) {
        self.width = Swift.max(Int(width), 1)
        self.height = Swift.max(Int(height), 1)
        self.maxCracks = Swift.max(maxCracks, 1)
        self.rng = SplitMix64(seed: seed)
        self.grid = Array(repeating: .infinity, count: self.width * self.height)
        for _ in 0 ..< Swift.max(seedAngles, 1) {
            let i = Int.random(in: 0 ..< grid.count, using: &rng)
            if !grid[i].isFinite { crackedCells.append(i) }
            grid[i] = Double.random(in: 0 ..< .tau, using: &rng)
        }
        for _ in 0 ..< Swift.max(startCount, 1) { recruit() }
    }

    /// Advance every active crack one tick. Returns this tick's marks, one
    /// per crack that moved.
    @discardableResult
    public func step() -> [Mark] {
        var marks: [Mark] = []
        marks.reserveCapacity(cracks.count)
        // Walk by index: a collision appends a recruit, and the recruit
        // waits for the next tick.
        for i in 0 ..< cracks.count where cracks[i].alive {
            if let mark = advance(i) { marks.append(mark) }
        }
        return marks
    }

    /// Advance every active crack `steps` times, collecting all the marks.
    @discardableResult
    public func step(_ steps: Int) -> [Mark] {
        var marks: [Mark] = []
        for _ in 0 ..< Swift.max(steps, 0) { marks.append(contentsOf: step()) }
        return marks
    }

    /// The classic wash: `count` translucent grains along `from → to`,
    /// crowded toward the crack by a doubled sine ease. `gain` (`0...1`)
    /// sets how far along the span they reach; alpha fades with index from
    /// `0.1` toward zero. Pure, so a sketch can restyle it freely.
    public static func grains(from: Vector2, to: Vector2, gain: Double,
                              count: Int = 64) -> [Grain] {
        guard count > 1 else { return [] }
        let g = Swift.min(Swift.max(gain, 0), 1)
        let w = g / Double(count - 1)
        return (0 ..< count).map { i in
            let f = sin(sin(Double(i) * w))
            return Grain(position: from + (to - from) * f,
                         alpha: 0.1 - Double(i) / (Double(count) * 10))
        }
    }

    // MARK: - Internals

    /// Add one crack starting somewhere on the existing pattern (up to the
    /// cap).
    private func recruit() {
        guard cracks.count < maxCracks else { return }
        var crack = Crack(position: .zero, angle: 0, origin: .zero,
                          gain: Double.random(in: 0.01 ... 0.1, using: &rng),
                          alive: false)
        restart(&crack)
        cracks.append(crack)
    }

    /// Land the crack on a random cracked cell and turn it perpendicular
    /// (with a little wobble). Picking uniformly from the claimed cells
    /// makes a longer crack the likelier parent, so busy regions subdivide
    /// harder; that bias is part of the look.
    private func restart(_ crack: inout Crack) {
        guard !crackedCells.isEmpty else { crack.alive = false; return }
        let cell = crackedCells[Int.random(in: 0 ..< crackedCells.count, using: &rng)]
        let cx = cell % width, cy = cell / width
        let stored = grid[cell]
        let side: Double = Bool.random(using: &rng) ? 1 : -1
        let wobble = Double.random(in: -Self.spawnWobble ... Self.spawnWobble, using: &rng)
        crack.angle = stored + side * (.pi / 2) + wobble
        crack.position = Vector2(Double(cx), Double(cy))
            + Vector2(angle: crack.angle, length: Self.firstNudge)
        crack.origin = crack.position
        crack.alive = true
    }

    /// One tick of one crack: move, mark, then either claim the cell or
    /// stop (archiving the run, restarting, and recruiting).
    private func advance(_ i: Int) -> Mark? {
        cracks[i].position += Vector2(angle: cracks[i].angle, length: Self.stepLength)
        let position = cracks[i].position

        // The wash breathes: a slow random walk on the gain.
        cracks[i].gain = Swift.min(Swift.max(
            cracks[i].gain + Double.random(in: -0.05 ... 0.05, using: &rng), 0), 1)

        let mark = Mark(crack: i, point: position,
                        washExtent: washExtent(from: position, angle: cracks[i].angle),
                        gain: cracks[i].gain)

        // The grid check carries sub-pixel fuzz, so collisions land organically.
        let fx = position.x + Double.random(in: -Self.cellFuzz ... Self.cellFuzz, using: &rng)
        let fy = position.y + Double.random(in: -Self.cellFuzz ... Self.cellFuzz, using: &rng)
        let cx = Int(floor(fx)), cy = Int(floor(fy))

        if cx >= 0, cx < width, cy >= 0, cy < height {
            let stored = grid[cy * width + cx]
            if !stored.isFinite || angleGap(stored, cracks[i].angle) < Self.sameLine {
                if !stored.isFinite { crackedCells.append(cy * width + cx) }
                grid[cy * width + cx] = cracks[i].angle
            } else {
                stop(i)
            }
        } else {
            stop(i)
        }
        return mark
    }

    /// Archive the run, restart this crack elsewhere, and recruit one more.
    private func stop(_ i: Int) {
        if cracks[i].origin != cracks[i].position {
            finished.append((cracks[i].origin, cracks[i].position))
        }
        restart(&cracks[i])
        recruit()
    }

    /// Scan sideways (always the same side of the line) until the open
    /// space ends, in wash-sized steps.
    private func washExtent(from: Vector2, angle: Double) -> Vector2 {
        let side = Vector2(sin(angle), -cos(angle)) * Self.washStep
        var reach = from
        for _ in 0 ..< (width + height) {
            reach += side
            let cx = Int(floor(reach.x)), cy = Int(floor(reach.y))
            guard cx >= 0, cx < width, cy >= 0, cy < height,
                  !grid[cy * width + cx].isFinite else { break }
        }
        return reach
    }

    /// The smallest turn between two angles, wrap-safe.
    private func angleGap(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: .tau)
        return Swift.min(d, .tau - d)
    }
}
