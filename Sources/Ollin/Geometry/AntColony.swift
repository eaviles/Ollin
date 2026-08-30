import Foundation

/// Ant-colony optimization: a colony solves "visit every city once, briefly"
/// by talking through the floor. Each iteration every ant walks a full tour,
/// choosing its next city by pheromone strength and closeness; then the whole
/// trail map evaporates a little and each ant lays fresh pheromone along its
/// tour, more for shorter tours. Good edges get reinforced, bad ones fade,
/// and the web of trails condenses onto a short route.
///
/// It's a stateful stepper you hold: `step()` runs one full iteration (every
/// ant walks, then the pheromone updates), `step(_:)` a batch. Seed it for a
/// reproducible search. The living material is `trails`, the pheromone web
/// with normalized strengths, beside `bestTour` for the answer so far.
///
/// ```swift
/// let colony = AntColony(cities: points, seed: 7)
///
/// override func draw() {
///     colony.step()
///     background(.black)
///     for trail in colony.trails {
///         stroke(Color.white.withAlpha(trail.strength * 0.8))
///         drawLine(trail.a, trail.b)
///     }
/// }
/// ```
public final class AntColony {
    /// The cities being toured.
    public let cities: [Vector2]
    /// How strongly pheromone counts when an ant chooses (the trail's pull).
    public var alpha: Double
    /// How strongly closeness counts (the greedy pull). Higher values make
    /// ants near-greedy; `0` makes them wander on pheromone alone.
    public var beta: Double
    /// The fraction of every trail that evaporates each iteration (`0...1`).
    /// High values forget fast and keep exploring; low values commit early.
    public var evaporation: Double
    /// How many extra deposits the best-so-far tour receives each iteration
    /// (the paper's elitist ants). `0` runs the plain colony.
    public var elitism: Double

    /// The shortest tour found so far, as city indices in visiting order.
    public private(set) var bestTour: [Int] = []
    /// The length of `bestTour` (closed, back to its start).
    public private(set) var bestLength: Double = .infinity
    /// Full stepCount run so far.
    public private(set) var stepCount = 0

    private let ants: Int
    private var pheromone: [Double]
    private var distances: [Double]
    private let depositScale: Double
    private var rng: SplitMix64

    /// A colony over `cities`. `ants` defaults to one per city (the paper's
    /// choice). The pheromone starts level, so the first stepCount explore
    /// on closeness and the web differentiates as tours come in.
    public init(cities: [Vector2], ants: Int? = nil, alpha: Double = 1,
                beta: Double = 4, evaporation: Double = 0.5,
                elitism: Double = 0, seed: UInt64 = 0) {
        self.cities = cities
        self.ants = Swift.max(1, ants ?? cities.count)
        self.alpha = alpha
        self.beta = beta
        self.evaporation = Swift.min(Swift.max(evaporation, 0), 1)
        self.elitism = Swift.max(0, elitism)
        self.rng = SplitMix64(seed: seed)

        let n = cities.count
        self.pheromone = [Double](repeating: 1, count: n * n)
        self.distances = [Double](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in 0..<n {
                distances[i * n + j] = cities[i].distance(to: cities[j])
            }
        }
        // Deposits are scaled by a greedy tour's length, so a decent tour
        // lays about one unit of pheromone and the numbers stay tame at any
        // canvas size.
        self.depositScale = AntColony.greedyLength(cities: cities, distances: distances)
    }

    /// One full iteration: every ant walks a tour from its own random start,
    /// the trail map evaporates, every tour deposits (shorter lays more),
    /// and the best-so-far is updated (and reinforced, when `elitism` says
    /// so).
    public func step() {
        let n = cities.count
        guard n > 1 else { return }

        var tours: [[Int]] = []
        var lengths: [Double] = []
        tours.reserveCapacity(ants)
        for _ in 0..<ants {
            let tour = walkTour()
            let length = self.length(of: tour)
            tours.append(tour)
            lengths.append(length)
            if length < bestLength {
                bestLength = length
                bestTour = tour
            }
        }

        for i in 0..<pheromone.count { pheromone[i] *= 1 - evaporation }
        for (tour, length) in zip(tours, lengths) {
            deposit(along: tour, amount: depositScale / length)
        }
        if elitism > 0, !bestTour.isEmpty {
            deposit(along: bestTour, amount: elitism * depositScale / bestLength)
        }
        stepCount += 1
    }

    /// Run a batch of stepCount (the usual per-frame call is one or two).
    public func step(_ steps: Int) {
        for _ in 0..<Swift.max(0, steps) { step() }
    }

    /// The pheromone web as drawable edges: every city pair whose trail
    /// still matters, with `strength` normalized so the strongest edge reads
    /// 1. Edges below about half a percent are dropped, so early frames show
    /// a full faint web and late frames only the condensed route.
    public var trails: [(a: Vector2, b: Vector2, strength: Double)] {
        let n = cities.count
        var top = 0.0
        for i in 0..<n {
            for j in (i + 1)..<n {
                top = Swift.max(top, pheromone[i * n + j] + pheromone[j * n + i])
            }
        }
        guard top > 0 else { return [] }
        var out: [(a: Vector2, b: Vector2, strength: Double)] = []
        for i in 0..<n {
            for j in (i + 1)..<n {
                let strength = (pheromone[i * n + j] + pheromone[j * n + i]) / top
                if strength > 0.005 {
                    out.append((cities[i], cities[j], strength))
                }
            }
        }
        return out
    }

    /// The trail strength between two cities (symmetric).
    public func pheromone(between i: Int, and j: Int) -> Double {
        let n = cities.count
        guard i >= 0, j >= 0, i < n, j < n else { return 0 }
        return (pheromone[i * n + j] + pheromone[j * n + i]) / 2
    }

    /// The best tour as positions, ready for `drawPolyline(closed: true)`.
    public var bestTourPoints: [Vector2] { bestTour.map { cities[$0] } }

    // MARK: - The walk

    /// One ant's tour: from a random start, repeatedly choose the next
    /// unvisited city with probability proportional to
    /// `pheromone^alpha * (1/distance)^beta`.
    private func walkTour() -> [Int] {
        let n = cities.count
        var tour = [Int]()
        tour.reserveCapacity(n)
        var visited = [Bool](repeating: false, count: n)
        var current = Int.random(in: 0..<n, using: &rng)
        tour.append(current)
        visited[current] = true

        var weights = [Double](repeating: 0, count: n)
        for _ in 1..<n {
            var total = 0.0
            for j in 0..<n where !visited[j] {
                let d = Swift.max(distances[current * n + j], 1e-9)
                let w = pow(pheromone[current * n + j], alpha) * pow(1 / d, beta)
                weights[j] = w
                total += w
            }
            var next = -1
            if total > 0 {
                var mark = Double.random(in: 0..<total, using: &rng)
                for j in 0..<n where !visited[j] {
                    mark -= weights[j]
                    if mark <= 0 { next = j; break }
                }
            }
            if next < 0 {
                for j in 0..<n where !visited[j] { next = j; break }
            }
            tour.append(next)
            visited[next] = true
            current = next
        }
        return tour
    }

    private func length(of tour: [Int]) -> Double {
        let n = cities.count
        var total = 0.0
        for (i, city) in tour.enumerated() {
            total += distances[city * n + tour[(i + 1) % tour.count]]
        }
        return total
    }

    private func deposit(along tour: [Int], amount: Double) {
        let n = cities.count
        for (i, city) in tour.enumerated() {
            let next = tour[(i + 1) % tour.count]
            pheromone[city * n + next] += amount
            pheromone[next * n + city] += amount
        }
    }

    /// A nearest-neighbor tour's length, the deposit yardstick.
    private static func greedyLength(cities: [Vector2], distances: [Double]) -> Double {
        let n = cities.count
        guard n > 1 else { return 1 }
        var visited = [Bool](repeating: false, count: n)
        var current = 0
        visited[0] = true
        var total = 0.0
        for _ in 1..<n {
            var best = -1
            var bestDistance = Double.infinity
            for j in 0..<n where !visited[j] && distances[current * n + j] < bestDistance {
                best = j
                bestDistance = distances[current * n + j]
            }
            total += bestDistance
            visited[best] = true
            current = best
        }
        total += distances[current * n]
        return Swift.max(total, 1e-9)
    }
}
