import Foundation

/// A sequence that carries on the way a sequence it was shown carried on.
///
/// Show it a melody and it learns what tends to follow what; ask it for notes
/// and it gives you new ones with the same habits.
///
/// ```swift
/// var chain = MarkovChain(learning: [0, 2, 4, 2, 0, 7, 4, 2], seed: 7)
/// let degree = chain.next()!
/// ```
///
/// `order` is how far back it looks. At order 1 each element is chosen from
/// what followed the one before it; at order 2 it looks at the last two, which
/// tracks the source more closely and invents less. When a context has never
/// been seen it falls back to a shorter one, and finally to how often each
/// element appeared at all, so it always has an answer.
///
/// It is seeded, so the same chain fed the same seed produces the same
/// sequence, and it keeps its own generator rather than drawing on the
/// sketch's: adding one cannot shift anything else the sketch does at random.
public struct MarkovChain<Element: Hashable & Sendable>: Sendable {

    /// How many elements back it looks when choosing the next one.
    public let order: Int

    /// Every element it has seen, in the order it first saw them.
    public private(set) var vocabulary: [Element] = []

    /// The elements it will choose the next one from.
    public private(set) var context: [Element] = []

    private var table: [[Element]: Transitions] = [:]
    private var random: CompositionRandom
    private let seed: Int

    /// An empty chain, ready to be shown something.
    public init(order: Int = 1, seed: Int = 0) {
        self.order = max(1, order)
        self.seed = seed
        self.random = CompositionRandom(seed: seed)
    }

    /// A chain that has already been shown a sequence.
    public init(learning sequence: [Element], order: Int = 1, seed: Int = 0, loops: Bool = false) {
        self.init(order: order, seed: seed)
        learn(sequence, loops: loops)
    }

    // MARK: Learning

    /// Adds a sequence to what the chain has seen.
    ///
    /// Several sequences can be learned one after another, and the same one
    /// twice counts twice, which is how one phrase is made more likely than
    /// another.
    ///
    /// - Parameters:
    ///   - sequence: the elements, in order.
    ///   - loops: whether the sequence comes round again, so that what follows
    ///     the last element is the first. Use it for a repeating figure.
    public mutating func learn(_ sequence: [Element], loops: Bool = false) {
        guard !sequence.isEmpty else { return }

        // Looping is a matter of what each element gets to look back at, so the
        // tail is pasted on the front and only the real elements are recorded
        // as targets.
        let lookBack = loops ? Array(sequence.suffix(min(order, sequence.count))) : []
        let extended = lookBack + sequence
        let firstTarget = lookBack.count

        for index in firstTarget..<extended.count {
            let element = extended[index]
            if !vocabulary.contains(element) { vocabulary.append(element) }
            // Every context length is recorded at once, the empty one included.
            // The empty context is how often each element turns up at all,
            // which is the answer of last resort when nothing else matches.
            for length in 0...order where index >= length {
                record(Array(extended[(index - length)..<index]), leadsTo: element)
            }
        }
    }

    private mutating func record(_ context: [Element], leadsTo element: Element) {
        var transitions = table[context] ?? Transitions()
        if let slot = transitions.successors.firstIndex(of: element) {
            transitions.counts[slot] += 1
        } else {
            transitions.successors.append(element)
            transitions.counts.append(1)
        }
        transitions.total += 1
        table[context] = transitions
    }

    /// Whether the chain has been shown anything yet.
    public var isEmpty: Bool { vocabulary.isEmpty }

    // MARK: Walking

    /// The next element, chosen from what followed this context before.
    ///
    /// Returns nil only when the chain has been shown nothing at all.
    public mutating func next() -> Element? {
        var length = min(order, context.count)
        while length >= 0 {
            let key = Array(context.suffix(length))
            if let transitions = table[key], transitions.total > 0 {
                let element = choose(from: transitions)
                context.append(element)
                if context.count > order { context.removeFirst(context.count - order) }
                return element
            }
            length -= 1
        }
        return nil
    }

    /// The next `count` elements.
    public mutating func next(_ count: Int) -> [Element] {
        var result = [Element]()
        result.reserveCapacity(max(0, count))
        for _ in 0..<max(0, count) {
            guard let element = next() else { break }
            result.append(element)
        }
        return result
    }

    /// Puts the chain somewhere in particular before asking it to carry on.
    public mutating func start(at element: Element) {
        context = [element]
    }

    /// The same, where the chain looks back more than one element.
    public mutating func start(with elements: [Element]) {
        context = Array(elements.suffix(order))
    }

    /// Forgets where it is, keeping what it learned, and rewinds its
    /// randomness so the same walk comes out again.
    public mutating func reset() {
        context = []
        random = CompositionRandom(seed: seed)
    }

    // MARK: Reading it

    /// What can follow a context, and how likely each one is.
    ///
    /// Sorted from most likely down, so a sketch can draw the chain: what it
    /// learned is a picture as much as a sound.
    public func continuations(after context: [Element]) -> [(element: Element, probability: Double)] {
        var length = min(order, context.count)
        while length >= 0 {
            let key = Array(context.suffix(length))
            if let transitions = table[key], transitions.total > 0 {
                let total = Double(transitions.total)
                return zip(transitions.successors, transitions.counts)
                    .map { (element: $0, probability: Double($1) / total) }
                    // Ties break by the order the elements were first seen,
                    // never by the table's own order, so the answer is the same
                    // on every run.
                    .enumerated()
                    .sorted {
                        $0.element.probability == $1.element.probability
                            ? $0.offset < $1.offset
                            : $0.element.probability > $1.element.probability
                    }
                    .map(\.element)
            }
            length -= 1
        }
        return []
    }

    /// What can follow the element the chain is on now.
    public var continuations: [(element: Element, probability: Double)] {
        continuations(after: context)
    }

    private mutating func choose(from transitions: Transitions) -> Element {
        var roll = Int(random.next(below: UInt64(transitions.total)))
        for (index, count) in transitions.counts.enumerated() {
            roll -= count
            if roll < 0 { return transitions.successors[index] }
        }
        return transitions.successors[transitions.successors.count - 1]
    }

    /// What followed one context, kept in the order the successors were first
    /// seen so that choosing from it never depends on the table's own layout.
    private struct Transitions: Sendable {
        var successors: [Element] = []
        var counts: [Int] = []
        var total = 0
    }
}

/// The seeded generator the composition types keep to themselves.
///
/// Small, allocation free, and deliberately not the sketch's own randomness, so
/// that adding a chain or an arpeggio cannot move anything else a sketch rolls.
struct CompositionRandom: Sendable {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(below bound: UInt64) -> UInt64 {
        bound > 0 ? next() % bound : 0
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
