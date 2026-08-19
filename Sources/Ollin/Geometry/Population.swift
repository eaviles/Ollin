import Foundation

/// A bag of numbers between 0 and 1 that a sketch reads as whatever it likes: a radius,
/// a hue, how many arms a shape has, which of three ways to draw it. Nothing in a
/// `Genome` knows what it means, which is exactly what lets one be mutated and mated
/// without the framework knowing what is being evolved.
///
/// Read a gene through one of the `value` forms rather than by hand, so the mapping
/// from 0…1 into what you actually want stays in one place:
///
/// ```swift
/// let radius = g.value(0, in: 20 ... 180)
/// let hue    = g.value(1, in: 0.0 ... 1.0)
/// let arms   = g.value(2, in: 3 ... 9)
/// let style  = g.value(3, among: [Style.solid, .hollow, .dashed])
/// ```
///
/// Genes past the end wrap round to the start rather than trapping, so a sketch that
/// grows a new trait still draws while you widen the genome. Two traits reading the
/// same gene move together, which is worth knowing if a drawing suddenly starts
/// rhyming with itself.
public struct Genome: Sendable, Hashable, RandomAccessCollection {

    /// The genes, each 0…1.
    public private(set) var genes: [Double]

    /// A genome from values you already have. Anything outside 0…1 is clamped in.
    public init(_ genes: [Double]) {
        self.genes = genes.map { Swift.min(Swift.max($0, 0), 1) }
    }

    /// A random genome of `count` genes.
    public init<G: RandomNumberGenerator>(count: Int, using generator: inout G) {
        precondition(count > 0, "A Genome needs at least one gene")
        genes = (0..<count).map { _ in Double.random(in: 0..<1, using: &generator) }
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { genes.count }

    /// Gene `index`, 0…1. Past the end it wraps.
    public subscript(index: Int) -> Double {
        genes[((index % genes.count) + genes.count) % genes.count]
    }

    /// Gene `index` spread over `range`.
    public func value(_ index: Int, in range: ClosedRange<Double>) -> Double {
        range.lowerBound + self[index] * (range.upperBound - range.lowerBound)
    }

    /// Gene `index` as a whole number in `range`, ends included.
    public func value(_ index: Int, in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        return range.lowerBound + Swift.min(Int(self[index] * Double(span)), span - 1)
    }

    /// Gene `index` as one of `choices`, evenly divided.
    public func value<T>(_ index: Int, among choices: [T]) -> T {
        precondition(!choices.isEmpty, "value(_:among:) needs at least one choice")
        return choices[Swift.min(Int(self[index] * Double(choices.count)), choices.count - 1)]
    }

    /// Gene `index` as a yes or no, true `chance` of the time.
    public func flag(_ index: Int, chance: Double = 0.5) -> Bool { self[index] < chance }

    /// A copy with one gene set (clamped to 0…1). For nudging a genome by hand.
    public func setting(_ index: Int, to value: Double) -> Genome {
        var copy = self
        copy.genes[((index % genes.count) + genes.count) % genes.count] = Swift.min(Swift.max(value, 0), 1)
        return copy
    }
}

/// A population of genomes that breeds from the ones you like, or from the ones that
/// score well: the other half of evolution from `Evolution`, for when a generation is
/// twenty candidates a person looks at rather than thirty thousand flights a GPU runs.
///
/// The interactive form is the older idea and the more surprising one. Draw the
/// population as a grid, let someone pick their favorites, and breed:
///
/// ```swift
/// var pool: Population!
/// var chosen: Set<Int> = []
///
/// override func setup() { pool = population(count: 16, genes: 6) }
///
/// override func draw() {
///     for (i, g) in pool.enumerated() { drawCandidate(g, at: i, picked: chosen.contains(i)) }
/// }
///
/// override func keyPressed() {
///     if key == " " { pool.breed(from: chosen); chosen = [] }
/// }
/// ```
///
/// Nobody wrote down what makes a good one. The only measure is that a person kept
/// looking at it, which is why this method reaches things no fitness function would
/// have been written for.
///
/// The other form scores every genome with a closure and breeds by fitness, using the
/// wheel-of-fortune method: a genome's share of the next generation's parents is its
/// share of the total score. That needs the total, which is exactly why the GPU tier
/// uses tournaments instead, and it is worth knowing which you are looking at when the
/// two behave differently.
///
/// A population owns its own random stream, seeded when you build it, so a run
/// reproduces from its seed and breeding never touches the sketch's `random`.
public struct Population: Sendable, RandomAccessCollection {

    /// The current generation's genomes.
    public private(set) var genomes: [Genome]

    /// How many generations have been bred. The first is 0.
    public private(set) var generation = 0

    /// The chance a gene is nudged as it is copied into a child.
    ///
    /// The default is far higher than the few percent a run scored by a measure wants,
    /// and that is on purpose: a person judges maybe twenty candidates a
    /// generation and will sit through maybe twenty generations, so a few hundred
    /// looks have to cover the ground a scored run covers in millions. Variation has to
    /// arrive fast enough to be worth looking at.
    public var mutationRate = 0.2

    /// How far a nudge may reach, added to the gene rather than replacing it.
    public var mutationAmount = 0.4

    /// How two parents are mixed.
    public var crossover: Crossover = .independent

    /// The ways two genomes can make a third.
    public enum Crossover: Sendable, Equatable, CaseIterable {
        /// Each gene comes from one parent or the other with an even chance. Mixes the
        /// two most thoroughly, and the usual choice.
        case independent
        /// Genes before a random point come from one parent, the rest from the other.
        /// Keeps runs of genes together, which matters when neighboring genes work as
        /// a group.
        case split
        /// Every gene lands part way between the parents. Makes a child that looks like
        /// a blend of them rather than a mixture of their parts, which suits genes that
        /// are quantities rather than choices.
        case blend
    }

    /// Whether the genomes you chose are carried into the next generation untouched,
    /// before their children fill the rest. On by default: with twenty candidates and a
    /// person doing the judging, one breeding is a large step, and without this the
    /// thing you just picked can be gone the moment you pick it.
    public var keepsParents = true

    private var rng: SplitMix64
    private let geneCount: Int

    /// Build `count` random genomes of `genes` genes each. `seed` makes the opening
    /// generation, and everything bred from it, reproducible.
    public init(count: Int, genes: Int, seed: UInt64) {
        precondition(count > 0, "A Population needs at least one genome")
        precondition(genes > 0, "A Population needs at least one gene")
        geneCount = genes
        var generator = SplitMix64(seed: seed)
        genomes = (0..<count).map { _ in Genome(count: genes, using: &generator) }
        rng = generator
    }

    /// Build a population from genomes you already have: the ones you kept from a run,
    /// or a starting point you wrote out by hand. They must all be the same length; a
    /// shorter one is padded and a longer one trimmed to the first genome's.
    public init(_ genomes: [Genome], seed: UInt64) {
        precondition(!genomes.isEmpty, "A Population needs at least one genome")
        let width = genomes[0].count
        geneCount = width
        self.genomes = genomes.map { g in
            g.count == width ? g : Genome((0..<width).map { g[$0] })
        }
        rng = SplitMix64(seed: seed)
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { genomes.count }
    public subscript(index: Int) -> Genome { genomes[index] }

    /// Replace the population with the children of the genomes at `chosen`.
    ///
    /// One chosen genome makes a generation of mutated copies of it; two or more mate
    /// in pairs. Choosing nothing does nothing at all, on the grounds that a generation
    /// nobody liked is still the only generation there is: pick something, or call
    /// `reroll()` to start again from scratch.
    public mutating func breed(from chosen: some Sequence<Int>) {
        let parents = chosen.filter { $0 >= 0 && $0 < genomes.count }.sorted()
        guard !parents.isEmpty else { return }

        var next: [Genome] = []
        next.reserveCapacity(genomes.count)
        if keepsParents {
            for i in parents.prefix(genomes.count) { next.append(genomes[i]) }
        }
        while next.count < genomes.count {
            let mum = genomes[parents.randomElement(using: &rng)!]
            let dad = genomes[parents.randomElement(using: &rng)!]
            next.append(mutated(crossed(mum, dad)))
        }
        genomes = next
        generation += 1
    }

    /// Replace the population with the children of whoever scored well, picking parents
    /// by the wheel-of-fortune method: a genome's share of the parents is its share of
    /// the total score.
    ///
    /// A score below zero counts as zero, since a share cannot be negative. When every
    /// score is zero there is nothing to choose between, so parents are picked evenly,
    /// which keeps a run that has not got started yet from freezing on genome 0.
    public mutating func breed(scoredBy score: (Genome) -> Double) {
        let scores = genomes.map { Swift.max(score($0), 0) }
        let total = scores.reduce(0, +)

        var next: [Genome] = []
        next.reserveCapacity(genomes.count)
        while next.count < genomes.count {
            let mum = genomes[pick(scores, total: total)]
            let dad = genomes[pick(scores, total: total)]
            next.append(mutated(crossed(mum, dad)))
        }
        genomes = next
        generation += 1
    }

    /// Throw the whole population away and start from fresh random genomes, keeping the
    /// generation count so you can see how long the search has run.
    public mutating func reroll() {
        genomes = genomes.map { _ in Genome(count: geneCount, using: &rng) }
        generation += 1
    }

    // MARK: The three steps

    /// Walk the population, taking each genome's share of the total as its share of the
    /// wheel. Reading it as a walk rather than building a pool of repeated entries is
    /// what lets a score be any positive number rather than a whole one.
    private mutating func pick(_ scores: [Double], total: Double) -> Int {
        guard total > 0 else { return Int.random(in: 0..<genomes.count, using: &rng) }
        var mark = Double.random(in: 0..<total, using: &rng)
        for (i, s) in scores.enumerated() {
            mark -= s
            if mark <= 0 { return i }
        }
        return scores.count - 1     // only reachable on a rounding crumb at the very end
    }

    private mutating func crossed(_ a: Genome, _ b: Genome) -> Genome {
        var genes = [Double](repeating: 0, count: geneCount)
        switch crossover {
        case .independent:
            for i in 0..<geneCount { genes[i] = Bool.random(using: &rng) ? a[i] : b[i] }
        case .split:
            let cut = Int.random(in: 0...geneCount, using: &rng)
            for i in 0..<geneCount { genes[i] = i < cut ? a[i] : b[i] }
        case .blend:
            let t = Double.random(in: 0...1, using: &rng)
            for i in 0..<geneCount { genes[i] = a[i] + (b[i] - a[i]) * t }
        }
        return Genome(genes)
    }

    private mutating func mutated(_ genome: Genome) -> Genome {
        var genes = genome.genes
        for i in 0..<genes.count where Double.random(in: 0..<1, using: &rng) < mutationRate {
            let nudge = Double.random(in: -mutationAmount...mutationAmount, using: &rng)
            genes[i] = Swift.min(Swift.max(genes[i] + nudge, 0), 1)
        }
        return Genome(genes)
    }
}

public extension Sketch {
    /// Make a `Population` of `count` random genomes, `genes` genes each, seeded from
    /// `seed` (this sketch's `variation` by default). Build it in `setup()`, draw its
    /// genomes however you like, and `breed` when someone has picked their favorites.
    /// See `Population`.
    func population(count: Int, genes: Int, seed: UInt64? = nil) -> Population {
        Population(count: count, genes: genes, seed: seed ?? UInt64(variation))
    }
}
