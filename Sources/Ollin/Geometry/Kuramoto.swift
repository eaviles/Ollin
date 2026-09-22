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
/// is a lag. A crowd made with `columns` and `rows` sits on a **lattice**, square
/// or hex, and listens within `range` rings of it, so patches fall into step and
/// waves of agreement cross the field; `neighbors` takes a graph of your own. Any
/// crowd can hold several `layers` of oscillators per site, each layer coupled
/// over the same neighborhoods and the layers of one site pulled together by
/// `layerCoupling`. `localCoherence` reads where the crowd has locked, one value
/// per oscillator. Integrated by fixed substeps, so a run is a pure function of
/// its seed and parameters and replays exactly.
public final class Kuramoto {

    /// Every oscillator's phase, in radians, kept in `0 ..< 2 * .pi`. Read to draw;
    /// set to kick a phase. Oscillator `i` is site `i / layers`, layer `i % layers`.
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
    /// when fully locked, and on a ring or a lattice a lag is what makes patterns
    /// travel.
    public var lag: Double
    /// How far an oscillator listens: neighbors each way on a ring, or rings of
    /// neighbors on a lattice. 0 means everyone listens to everyone (the mean
    /// field). With a range the pull is averaged over those neighbors, so
    /// `coupling` means the same per neighbor. Not read while `neighbors` holds a
    /// graph of your own.
    public var range: Int {
        didSet {
            range = Swift.max(0, range)
            if range != oldValue { latticeLists = nil }
        }
    }
    /// The center of the natural frequencies this crowd was made with, in radians
    /// per second.
    public let frequency: Double
    /// The standard deviation of the natural frequencies this crowd was made with,
    /// in radians per second.
    public let spread: Double
    /// How many oscillators sit at each site, 1 unless the crowd was made with
    /// more. Every layer is a copy of the crowd's neighborhoods: an oscillator is
    /// pulled by the same layer on its neighbors, and by the other layers of its
    /// own site through `layerCoupling`.
    public let layers: Int
    /// How hard the layers of one site pull on each other, in radians per second,
    /// averaged over the other layers and with no lag; 0 leaves the layers
    /// independent. Read only when there is more than one layer.
    public var layerCoupling: Double
    /// The lattice the crowd was laid on, or nil for a crowd made by `count` or by
    /// `neighbors`. Its `index(column:row:)` names the site at a cell.
    public let lattice: Lattice?

    /// A graph of your own, one list of neighbor sites per site, and `nil` where
    /// the lattice or the ring lists in force were derived.
    private var graph: [[Int]]?
    /// The lattice's neighbor lists at the current `range`, worked out on first use.
    private var latticeLists: [[Int]]?

    /// A crowd of `count` oscillators at random phases, their natural frequencies
    /// drawn around `frequency` with the standard deviation `spread`, coupled to
    /// the mean field or, with a `range`, to their neighbors on a ring.
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
        let sigma = Swift.max(0, spread)
        self.coupling = coupling
        self.frequency = frequency
        self.spread = sigma
        self.lag = lag
        self.range = Swift.max(0, range)
        self.layers = 1
        self.layerCoupling = 0
        self.lattice = nil
        let n = Swift.max(count, 0)
        (phases, frequencies) = Kuramoto.deal(n, frequency: frequency, spread: sigma, seed: seed)
    }

    /// A crowd on a lattice of `columns` by `rows` sites, each oscillator pulled by
    /// the sites within `range` rings of its own: four, eight, or six neighbors a
    /// ring by `layout`. The sites are row-major, so site `row * columns + column`
    /// is the cell at that column and row (`lattice.index(column:row:)` spells
    /// it), and a hex lattice shares `HexGrid`'s addressing, odd rows shifted half
    /// a cell to the right, so the cell `hexGrid(columns:rows:)[i]` draws is site
    /// `i`. With `wraps` the lattice is a torus.
    ///
    /// - Parameters:
    ///   - columns: Sites across.
    ///   - rows: Sites down.
    ///   - layout: `.square(.vonNeumann)` couples the four edge-sharers a ring,
    ///     `.square(.moore)` the eight, and `.hex` the six of a honeycomb.
    ///   - wraps: Whether the lattice joins its edges into a torus. A hex lattice
    ///     wraps cleanly when `rows` is even.
    ///   - layers: Oscillators per site; see `layers`.
    ///   - coupling: How hard the neighbors pull on each phase (K), per neighbor.
    ///   - frequency: The center of the natural frequencies, in radians per second.
    ///   - spread: The standard deviation of the natural frequencies.
    ///   - lag: The phase lag in the pull, in radians.
    ///   - range: Rings of neighbors an oscillator listens to, or 0 for the mean
    ///     field of its layer.
    ///   - layerCoupling: How hard the layers of one site pull on each other.
    ///   - seed: Picks the phases and the frequencies.
    public init(columns: Int, rows: Int, layout: Layout = .square(.vonNeumann), wraps: Bool = false,
                layers: Int = 1, coupling: Double = 1, frequency: Double = 1, spread: Double = 0.5,
                lag: Double = 0, range: Int = 1, layerCoupling: Double = 0, seed: Int = 0) {
        let sigma = Swift.max(0, spread)
        let lattice = Lattice(columns: columns, rows: rows, layout: layout, wraps: wraps)
        self.coupling = coupling
        self.frequency = frequency
        self.spread = sigma
        self.lag = lag
        self.range = Swift.max(0, range)
        self.layers = Swift.max(1, layers)
        self.layerCoupling = layerCoupling
        self.lattice = lattice
        (phases, frequencies) = Kuramoto.deal(lattice.count * self.layers,
                                              frequency: frequency, spread: sigma, seed: seed)
    }

    /// A crowd coupled over a graph of your own: one list per site naming the sites
    /// that pull on it, the pull averaged over the list so `coupling` means the
    /// same per neighbor. A site with an empty list runs at its own pace. The lists
    /// need not be symmetric.
    ///
    /// - Parameters:
    ///   - neighbors: For each site, the sites it listens to, as indices into the
    ///     same array.
    ///   - layers: Oscillators per site; see `layers`.
    ///   - coupling: How hard the neighbors pull on each phase (K), per neighbor.
    ///   - frequency: The center of the natural frequencies, in radians per second.
    ///   - spread: The standard deviation of the natural frequencies.
    ///   - lag: The phase lag in the pull, in radians.
    ///   - layerCoupling: How hard the layers of one site pull on each other.
    ///   - seed: Picks the phases and the frequencies.
    public init(neighbors: [[Int]], layers: Int = 1, coupling: Double = 1, frequency: Double = 1,
                spread: Double = 0.5, lag: Double = 0, layerCoupling: Double = 0, seed: Int = 0) {
        let sigma = Swift.max(0, spread)
        self.coupling = coupling
        self.frequency = frequency
        self.spread = sigma
        self.lag = lag
        self.range = 0
        self.layers = Swift.max(1, layers)
        self.layerCoupling = layerCoupling
        self.lattice = nil
        self.graph = Kuramoto.checked(neighbors)
        (phases, frequencies) = Kuramoto.deal(neighbors.count * self.layers,
                                              frequency: frequency, spread: sigma, seed: seed)
    }

    /// The phases and the frequencies of `n` oscillators under `seed`.
    private static func deal(_ n: Int, frequency: Double, spread: Double,
                             seed: Int) -> ([Double], [Double]) {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let phases = (0 ..< n).map { _ in Double.random(in: 0 ..< 2 * .pi, using: &rng) }
        let frequencies = (0 ..< n).map { _ in frequency + spread * gaussian(using: &rng) }
        return (phases, frequencies)
    }

    /// The lists as given, with every index checked against the site count: a
    /// neighbor the crowd does not have is a programming error, said here rather
    /// than as a bad read in the middle of a frame.
    private static func checked(_ lists: [[Int]]) -> [[Int]] {
        let sites = lists.count
        for list in lists {
            for j in list {
                precondition(j >= 0 && j < sites,
                             "Kuramoto neighbors name site \(j), which is outside 0 ..< \(sites)")
            }
        }
        return lists
    }

    /// The number of oscillators: the sites times the `layers`.
    public var count: Int { phases.count }

    /// The number of sites, the oscillators divided by the `layers`.
    public var sites: Int { phases.count / layers }

    /// Who pulls on whom: for each site, the sites it listens to, as the lists in
    /// force. On a ring or a lattice they are derived from `range`, and `nil` is
    /// the mean field. Set it to hand the crowd a graph of your own (one list per
    /// site, every entry a site index, the pull averaged over the list), which the
    /// crowd then keeps whatever `range` says; set `nil` to go back to the ring,
    /// the lattice, or the mean field it was made with.
    public var neighbors: [[Int]]? {
        get {
            if let graph { return graph }
            if lattice != nil { return range > 0 ? currentLatticeLists() : nil }
            let n = sites
            let reach = Swift.min(range, (n - 1) / 2)
            guard reach > 0 else { return nil }
            return (0 ..< n).map { i in
                var list: [Int] = []
                list.reserveCapacity(2 * reach)
                for k in 1 ... reach {
                    list.append((i + k) % n)
                    list.append((i - k + n) % n)
                }
                return list
            }
        }
        set {
            guard let lists = newValue else { graph = nil; return }
            precondition(lists.count == sites,
                         "Kuramoto neighbors holds \(lists.count) lists for \(sites) sites")
            graph = Kuramoto.checked(lists)
        }
    }

    /// The order parameter r, the length of the mean of every phase's unit vector:
    /// 0 when the phases are spread evenly around the circle, 1 when they all
    /// agree. The measure to watch as a crowd locks. Taken over every oscillator
    /// of every layer.
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

    /// The order parameter of every oscillator's own neighborhood, itself
    /// included: 1 where an oscillator and the oscillators it listens to agree, near
    /// 0 where they are scattered. It is where the crowd has locked, drawn as a
    /// map: on a lattice a patch in step reads 1 while the seam between two
    /// patches out of step reads low. Under the mean field it is the order
    /// parameter of the oscillator's whole layer, so every oscillator of a layer
    /// reads the same. Worked out when read, at the cost of one pass over the
    /// neighbor lists.
    public var localCoherence: [Double] {
        let n = phases.count
        let L = layers
        let S = n / L
        var out = [Double](repeating: 0, count: n)
        guard n > 0, S > 0 else { return out }
        if let lists = neighbors {
            for s in 0 ..< S {
                for k in 0 ..< L {
                    let i = s * L + k
                    var x = cos(phases[i]), y = sin(phases[i])
                    for j in lists[s] {
                        let p = phases[j * L + k]
                        x += cos(p)
                        y += sin(p)
                    }
                    let m = Double(lists[s].count + 1)
                    out[i] = ((x * x + y * y).squareRoot()) / m
                }
            }
        } else {
            for k in 0 ..< L {
                let r = layerOrder(k, sites: S).r
                for s in 0 ..< S { out[s * L + k] = r }
            }
        }
        return out
    }

    /// Advance the crowd by `dt` seconds (one frame at 60 fps by default). The
    /// interval is split into fixed substeps, so a bigger `dt` costs more substeps
    /// rather than accuracy, and every phase is wrapped back into `0 ..< 2 * .pi`.
    public func advance(by dt: Double = 1.0 / 60.0) {
        let n = Swift.min(phases.count, frequencies.count)
        let L = layers
        let S = n / L
        guard dt > 0, S > 0 else { return }
        let substeps = Swift.max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(substeps)
        let turn = 2 * Double.pi
        // Which pull is in force: a graph or lattice list per site, the ring's
        // reach, or the mean field of each layer.
        let lists: [[Int]]?
        var reach = 0
        if let graph {
            lists = graph
        } else if lattice != nil {
            lists = range > 0 ? currentLatticeLists() : nil
        } else {
            lists = nil
            reach = Swift.min(range, (S - 1) / 2)
        }
        let layered = L > 1 && layerCoupling != 0
        let layerWeight = layered ? layerCoupling / Double(L - 1) : 0
        var rates = [Double](repeating: 0, count: S * L)
        var order = [(r: Double, psi: Double)](repeating: (0, 0), count: L)
        for _ in 0 ..< substeps {
            if lists == nil, reach == 0 {
                for k in 0 ..< L { order[k] = layerOrder(k, sites: S) }
            }
            for s in 0 ..< S {
                for k in 0 ..< L {
                    let i = s * L + k
                    let theta = phases[i]
                    var pull = 0.0
                    if let lists {
                        let list = lists[s]
                        if !list.isEmpty {
                            var sum = 0.0
                            for j in list { sum += sin(phases[j * L + k] - theta - lag) }
                            pull = coupling / Double(list.count) * sum
                        }
                    } else if reach > 0 {
                        var sum = 0.0
                        for d in 1 ... reach {
                            sum += sin(phases[((s + d) % S) * L + k] - theta - lag)
                            sum += sin(phases[((s - d + S) % S) * L + k] - theta - lag)
                        }
                        pull = coupling / Double(2 * reach) * sum
                    } else {
                        let o = order[k]
                        pull = coupling * o.r * sin(o.psi - theta - lag)
                    }
                    if layered {
                        var sum = 0.0
                        for m in 0 ..< L where m != k { sum += sin(phases[s * L + m] - theta) }
                        pull += layerWeight * sum
                    }
                    rates[i] = frequencies[i] + pull
                }
            }
            for i in 0 ..< S * L {
                var p = (phases[i] + rates[i] * h).truncatingRemainder(dividingBy: turn)
                if p < 0 { p += turn }
                phases[i] = p
            }
        }
    }

    /// The lattice's lists at the current `range`, built once per range.
    private func currentLatticeLists() -> [[Int]] {
        if let latticeLists { return latticeLists }
        let lists = lattice?.neighbors(within: range) ?? []
        latticeLists = lists
        return lists
    }

    /// The mean unit vector of every phase: its length and its direction.
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

    /// The mean unit vector of one layer's phases over `sites` sites.
    private func layerOrder(_ layer: Int, sites: Int) -> (r: Double, psi: Double) {
        guard sites > 0 else { return (0, 0) }
        let L = layers
        var x = 0.0, y = 0.0
        for s in 0 ..< sites {
            let p = phases[s * L + layer]
            x += cos(p)
            y += sin(p)
        }
        x /= Double(sites)
        y /= Double(sites)
        return ((x * x + y * y).squareRoot(), atan2(y, x))
    }

    /// One standard normal draw, by the Box-Muller transform.
    private static func gaussian<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        let u1 = 1 - Double.random(in: 0 ..< 1, using: &rng)   // (0, 1], so the log is finite
        let u2 = Double.random(in: 0 ..< 1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

// MARK: - The lattice

extension Kuramoto {
    /// How the sites of a lattice crowd neighbor each other.
    public enum Layout: Equatable, Hashable, Sendable {
        /// A square lattice: `.vonNeumann` couples the four edge-sharers a ring (a
        /// diamond further out), `.moore` the eight with the corners (a full block
        /// further out), the same shapes the grid automata use.
        case square(CellNeighborhood)
        /// A honeycomb: six neighbors a ring. Rows are staggered as `HexGrid` lays
        /// them, odd rows shifted half a cell to the right.
        case hex
    }

    /// The sites of a lattice crowd: `columns` by `rows`, row-major, neighboring
    /// by `layout`, joined into a torus when it `wraps`. Made by
    /// `Kuramoto(columns:rows:...)` and read back as `lattice`; its neighbor lists
    /// are also yours to draw links from, through `neighbors(of:within:)`.
    public struct Lattice: Equatable, Hashable, Sendable {
        public let columns: Int
        public let rows: Int
        public let layout: Layout
        public let wraps: Bool

        public init(columns: Int, rows: Int, layout: Layout = .square(.vonNeumann), wraps: Bool = false) {
            self.columns = Swift.max(1, columns)
            self.rows = Swift.max(1, rows)
            self.layout = layout
            self.wraps = wraps
        }

        /// The number of sites.
        public var count: Int { columns * rows }

        /// The site at a cell.
        public func index(column: Int, row: Int) -> Int { row * columns + column }

        /// The column of a site.
        public func column(of site: Int) -> Int { site % columns }

        /// The row of a site.
        public func row(of site: Int) -> Int { site / columns }

        /// The sites within `range` steps of `site`, itself left out, in ascending
        /// order. On a square lattice a step is to an edge-sharer, or to a corner
        /// too under `.moore`; on a hex lattice to any of the six. Off a lattice that
        /// does not wrap the rim has fewer.
        public func neighbors(of site: Int, within range: Int) -> [Int] {
            guard range > 0, site >= 0, site < count else { return [] }
            let c = column(of: site), r = row(of: site)
            var found = Set<Int>()
            switch layout {
            case let .square(neighborhood):
                for dr in -range ... range {
                    for dc in -range ... range {
                        if neighborhood == .vonNeumann, abs(dr) + abs(dc) > range { continue }
                        add(column: c + dc, row: r + dr, to: &found)
                    }
                }
            case .hex:
                // Walk the hex ball in axial coordinates, then turn each back into
                // a column and a row, so the stagger is read once and one way.
                let q0 = c - (r - (r & 1)) / 2
                for dq in -range ... range {
                    for dr in Swift.max(-range, -dq - range) ... Swift.min(range, -dq + range) {
                        let q = q0 + dq, rr = r + dr
                        add(column: q + (rr - (rr & 1)) / 2, row: rr, to: &found)
                    }
                }
            }
            found.remove(site)
            return found.sorted()
        }

        /// Every site's neighbors within `range` steps, one list per site.
        public func neighbors(within range: Int) -> [[Int]] {
            (0 ..< count).map { neighbors(of: $0, within: range) }
        }

        /// Record the site at a cell, wrapped onto the torus or dropped past the rim.
        private func add(column: Int, row: Int, to found: inout Set<Int>) {
            var c = column, r = row
            if wraps {
                c = ((c % columns) + columns) % columns
                r = ((r % rows) + rows) % rows
            } else if c < 0 || c >= columns || r < 0 || r >= rows {
                return
            }
            found.insert(index(column: c, row: r))
        }
    }
}
