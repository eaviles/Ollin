import Foundation

/// The dielectric breakdown model: how a spark chooses where to grow. The
/// discharge is held at one voltage and the surroundings at another, and the
/// electric field between them is solved over a lattice. Every empty cell
/// touching the discharge is a candidate, and one is added per step with
/// probability proportional to the local field raised to `eta`. Low `eta`
/// grows a furry, even bush; `eta` near 2 grows the sparse, jagged branches
/// of lightning and the Lichtenberg figures burned into wood and acrylic.
///
/// It's a stateful stepper you hold, like the other growth models: `step()`
/// adds one site, `step(_:)` a batch per frame, `grow()` runs until the
/// discharge reaches ground or the cap. Seed it for a reproducible figure.
/// Sites carry a `parent` link, so the discharge draws as dots (`positions`),
/// segments (`segments`), whole branch polylines (`branches()`, ready for
/// smoothing), or with trunk-to-tip widths (`thicknesses(...)`).
///
/// ```swift
/// let bolt = DielectricBreakdown(seeds: [center], in: bounds, seed: 7)
///
/// override func draw() {
///     bolt.step(6)
///     background(.black); stroke(.white)
///     for (a, b) in bolt.segments { drawLine(a, b) }
/// }
/// ```
public final class DielectricBreakdown {
    /// One cell of the discharge.
    public struct Site {
        /// The cell's center, in the bounds' coordinates.
        public let position: Vector2
        /// The index of the site it grew from (`nil` for a seed).
        public let parent: Int?
    }

    /// What the discharge grows toward (the far electrode, held at full
    /// potential).
    public enum Ground: Equatable, Sendable {
        /// The rim of `bounds`: the discharge grows outward until it arcs to
        /// the edge. The classic radial Lichtenberg figure.
        case border
        /// Specific points (snapped to lattice cells): a wire, a plate, or a
        /// single far electrode, laid down as the cells under each point. The
        /// rim then insulates instead of attracting.
        case points([Vector2])
    }

    /// The discharge so far (seeds first, then in growth order).
    public private(set) var sites: [Site]
    /// The growth exponent: how strongly the field's favorites win. `1` is
    /// the aggregation regime (dense, furry); around `2` the lightning
    /// regime (sparse, directed); higher values approach a single channel.
    public var eta: Double
    /// A cap on the discharge's size.
    public var maxSites: Int
    /// `true` once the discharge has reached ground (or the cap, or run out
    /// of room).
    public private(set) var isFinished = false

    private let bounds: Rectangle
    private let columns: Int
    private let rows: Int
    private let cellSize: Double
    private var rng: SplitMix64

    // The lattice. `state`: 0 empty, 1 discharge, 2 ground. `potential` is
    // the solved field, fixed at 0 on the discharge and 1 on ground.
    private var state: [UInt8]
    private var potential: [Double]
    private var candidates: [Int] = []          // empty cells touching the discharge
    private var isCandidate: [Bool]
    private var siteIndex: [Int32]              // lattice cell -> site index

    /// A discharge started from `seeds` (snapped to lattice cells) inside
    /// `bounds`. `resolution` is the lattice's cell count across the width
    /// (the height follows at square cells); finer lattices give finer
    /// filaments and cost more per step.
    public init(seeds: [Vector2], in bounds: Rectangle, resolution: Int = 140,
                eta: Double = 1.7, ground: Ground = .border,
                maxSites: Int = 3000, seed: UInt64 = 0) {
        self.bounds = bounds
        let columns = Swift.max(16, resolution)
        self.columns = columns
        self.cellSize = bounds.width / Double(columns)
        self.rows = Swift.max(16, Int((bounds.height / cellSize).rounded()))
        self.eta = Swift.max(0, eta)
        self.maxSites = maxSites
        self.rng = SplitMix64(seed: seed)
        let cells = columns * rows
        self.state = [UInt8](repeating: 0, count: cells)
        self.potential = [Double](repeating: 1, count: cells)
        self.isCandidate = [Bool](repeating: false, count: cells)
        self.siteIndex = [Int32](repeating: -1, count: cells)
        self.sites = []

        switch ground {
        case .border:
            for x in 0..<columns {
                state[x] = 2
                state[(rows - 1) * columns + x] = 2
            }
            for y in 0..<rows {
                state[y * columns] = 2
                state[y * columns + columns - 1] = 2
            }
        case .points(let points):
            for p in points {
                if let cell = cell(at: p) { state[cell] = 2 }
            }
        }

        for p in seeds {
            guard let cell = cell(at: p), state[cell] == 0 else { continue }
            attach(cell: cell, parent: nil)
        }
        // Settle the field before the first step: from a fresh start the
        // solver needs many sweeps to carry the boundary inward.
        relax(sweeps: 4 * Swift.max(columns, rows))
    }

    /// The number of sites grown so far.
    public var count: Int { sites.count }

    /// The site positions, ready for `drawCircles`.
    public var positions: [Vector2] { sites.map(\.position) }

    /// The discharge as line segments (each site to the one it grew from).
    public var segments: [(Vector2, Vector2)] {
        sites.compactMap { site in
            site.parent.map { (sites[$0].position, site.position) }
        }
    }

    /// Grow one site: pick a candidate with probability proportional to the
    /// local field to the `eta`, attach it, and let the field settle a
    /// little. Finishes when the discharge arcs to ground, fills its room,
    /// or hits `maxSites`.
    public func step() {
        guard !isFinished else { return }
        guard sites.count < maxSites, !candidates.isEmpty else {
            isFinished = true
            return
        }

        // Weights from the solved field. On the discharge the potential is
        // 0, so a candidate's own potential is the local field strength.
        var total = 0.0
        var weights = [Double]()
        weights.reserveCapacity(candidates.count)
        for cell in candidates {
            let w = pow(Swift.max(potential[cell], 0), eta)
            total += w
            weights.append(w)
        }
        var pick = candidates.count - 1
        if total > 0 {
            var mark = Double.random(in: 0..<total, using: &rng)
            for (i, w) in weights.enumerated() where w > 0 {
                mark -= w
                if mark <= 0 { pick = i; break }
            }
        } else {
            pick = Int.random(in: 0..<candidates.count, using: &rng)
        }

        let cell = candidates[pick]
        candidates.remove(at: pick)
        isCandidate[cell] = false
        attach(cell: cell, parent: parentSite(of: cell))
        relax(sweeps: 2)
    }

    /// Grow a batch of sites (one relaxation ride-along each).
    public func step(_ steps: Int) {
        for _ in 0..<Swift.max(0, steps) {
            if isFinished { return }
            step()
        }
    }

    /// Run until the discharge reaches ground or the cap.
    public func grow() {
        while !isFinished { step() }
    }

    /// The discharge as whole branch polylines: each runs from a seed or a
    /// branching site out to a tip, so the figure strokes as continuous
    /// channels (and takes `smoothed(iterations:)` well). Every grown edge
    /// appears in exactly one branch.
    public func branches() -> [Contour] {
        var childCount = [Int](repeating: 0, count: sites.count)
        for site in sites {
            if let parent = site.parent { childCount[parent] += 1 }
        }
        // A channel runs from a chain end (a tip, or a branching site) up
        // through single-child sites to the next branching site or seed, so
        // every grown edge lands in exactly one channel.
        var out: [Contour] = []
        for (i, site) in sites.enumerated()
        where (childCount[i] == 0 || childCount[i] > 1) && site.parent != nil {
            var path = [sites[i].position]
            var walk = site.parent
            while let index = walk {
                path.append(sites[index].position)
                if sites[index].parent == nil || childCount[index] > 1 { break }
                walk = sites[index].parent
            }
            out.append(Contour(path.reversed(), closed: false))
        }
        return out
    }

    /// The solved field at a point: 0 on the discharge, 1 at ground, in
    /// between elsewhere (sampled at the lattice cell under `point`; 0
    /// outside the bounds). A candidate's growth weight is this value raised
    /// to `eta`. Reading it back draws the field itself: a glow hugging the
    /// figure, contour lines, or field-driven color.
    public func potential(at point: Vector2) -> Double {
        guard let cell = cell(at: point) else { return 0 }
        return potential[cell]
    }

    /// A width per site from the pipe model: every tip carries `tipWidth`,
    /// and a site's width is the sum of its children's raised to `exponent`,
    /// re-normalized, so trunks thicken toward the seed the way a real
    /// discharge brightens its main channel. Indexed like `sites`.
    public func thicknesses(tipWidth: Double = 1.2, exponent: Double = 2.0) -> [Double] {
        var accumulated = [Double](repeating: 0, count: sites.count)
        for i in stride(from: sites.count - 1, through: 0, by: -1) {
            if accumulated[i] == 0 { accumulated[i] = pow(tipWidth, exponent) }
            if let parent = sites[i].parent {
                accumulated[parent] += accumulated[i]
            }
        }
        let inverse = 1 / Swift.max(exponent, 0.01)
        return accumulated.map { pow($0, inverse) }
    }

    // MARK: - The lattice

    private func cell(at point: Vector2) -> Int? {
        let x = Int((point.x - bounds.x) / cellSize)
        let y = Int((point.y - bounds.y) / cellSize)
        guard x >= 0, x < columns, y >= 0, y < rows else { return nil }
        return y * columns + x
    }

    private func position(of cell: Int) -> Vector2 {
        Vector2(bounds.x + (Double(cell % columns) + 0.5) * cellSize,
                bounds.y + (Double(cell / columns) + 0.5) * cellSize)
    }

    /// The four lattice neighbors (the model's square-lattice adjacency).
    private func neighbors(of cell: Int, _ body: (Int) -> Void) {
        let x = cell % columns, y = cell / columns
        if x > 0 { body(cell - 1) }
        if x < columns - 1 { body(cell + 1) }
        if y > 0 { body(cell - columns) }
        if y < rows - 1 { body(cell + columns) }
    }

    /// Make `cell` part of the discharge and refresh the candidate ring.
    /// Touching a ground cell finishes the figure (the arc has connected).
    private func attach(cell: Int, parent: Int?) {
        state[cell] = 1
        potential[cell] = 0
        siteIndex[cell] = Int32(sites.count)
        sites.append(Site(position: position(of: cell), parent: parent))
        neighbors(of: cell) { neighbor in
            if state[neighbor] == 0, !isCandidate[neighbor] {
                isCandidate[neighbor] = true
                candidates.append(neighbor)
            }
            if state[neighbor] == 2 { isFinished = true }
        }
    }

    /// The already-grown site this candidate cell would attach to (its
    /// strongest-field discharge neighbor, deterministically the first in
    /// lattice order on ties).
    private func parentSite(of cell: Int) -> Int? {
        var best: Int? = nil
        neighbors(of: cell) { neighbor in
            if state[neighbor] == 1, best == nil { best = Int(siteIndex[neighbor]) }
        }
        return best
    }

    /// Gauss-Seidel sweeps of the Laplace field, discharge and ground held
    /// fixed, the rim mirroring when it isn't ground (an insulating edge).
    private func relax(sweeps: Int) {
        for _ in 0..<sweeps {
            for y in 0..<rows {
                for x in 0..<columns {
                    let cell = y * columns + x
                    guard state[cell] == 0 else {
                        potential[cell] = state[cell] == 1 ? 0 : 1
                        continue
                    }
                    let left = potential[x > 0 ? cell - 1 : cell]
                    let right = potential[x < columns - 1 ? cell + 1 : cell]
                    let up = potential[y > 0 ? cell - columns : cell]
                    let down = potential[y < rows - 1 ? cell + columns : cell]
                    potential[cell] = (left + right + up + down) / 4
                }
            }
        }
    }
}
