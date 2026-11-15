import Foundation

/// A grid that carries on the way the grids it was shown carried on.
///
/// Show it a picture as rows of cells (a tile map, a weave, a drawing in two
/// inks) and it counts what each cell held beside the cells already settled
/// around it. Ask it for rows and it writes new ones with the same habits, as
/// wide and as many as you like.
///
/// ```swift
/// var weave = try MarkovGrid(learning: picture, seed: 7)
/// let field = weave.nextRows(40, columns: 60)
/// ```
///
/// A picture is read the way a page is, a row at a time from the top and each
/// row from its start. So when a cell is reached, four of the cells around it
/// are already settled, and those are what it is counted against, nearest
/// first: the cell before it in its row, the cell above it, the cell above
/// and before, and the cell above and after. `order` is how many of the four
/// are read. At 1 a row only remembers along itself, as a `MarkovChain` does;
/// at 2 the rows line up under one another; at 4 a shape keeps both of its
/// sides and its corners.
///
/// When the cells around a place make an arrangement the pictures never
/// showed, the farthest cell is forgotten and the question asked again, down
/// to how often each value appeared at all, so there is always an answer. A
/// place off the grid counts as a value of its own, which is how the edges of
/// what is written come to behave as the edges of the pictures did.
///
/// What it knows can be declared as well as shown:
/// `learn(_:around:times:)` records one arrangement a number of times.
///
/// It is seeded, so the same grid fed the same seed writes the same rows, and
/// it keeps its own generator rather than drawing on the sketch's: adding one
/// cannot shift anything else the sketch does at random.
public struct MarkovGrid<Element: Hashable & Sendable>: Sendable {

    /// How many of the settled cells around a place are read, from 1 to 4.
    public let order: Int

    /// Every value it has seen, in the order it first saw them, after any the
    /// grid was made with.
    public private(set) var vocabulary: [Element] = []

    private var indices: [Element: Int] = [:]
    /// The counts, as a tree: the root holds how often each value appeared at
    /// all, and each step down adds one more cell of the arrangement, nearest
    /// first. A cell is counted at every node on its way down, so the node an
    /// arrangement stops at already holds the answer for forgetting the rest.
    private var nodes: [Node] = [Node()]
    private var children: [Step: Int] = [:]
    /// The last row written, as places in the vocabulary. Nil at the top.
    private var above: [Int]?
    private var random: SplitMix64
    private let seed: Int

    /// An empty grid, ready to be shown something.
    ///
    /// - Parameters:
    ///   - vocabulary: values to know before any are seen, in a fixed order.
    ///     A roll walks the values in vocabulary order, so naming them here
    ///     makes what a seed writes depend on the counts alone, whatever order
    ///     the pictures were shown in.
    ///   - order: how many of the four settled cells around a place are read.
    ///   - seed: the seed of its own generator.
    public init(vocabulary: [Element] = [], order: Int = 4, seed: Int = 0) {
        self.order = min(max(order, 1), 4)
        self.seed = seed
        self.random = Self.generator(seed: seed)
        for element in vocabulary { _ = place(of: element) }
    }

    /// A grid that has already been shown a picture.
    ///
    /// Throws a `MarkovGridError` when the picture has no cells or its rows
    /// are not all one length.
    public init(learning picture: [[Element]], order: Int = 4, seed: Int = 0) throws {
        self.init(order: order, seed: seed)
        try learn(picture)
    }

    // MARK: Learning

    /// Adds a picture to what the grid has seen, given as its rows from the
    /// top.
    ///
    /// Several pictures can be learned one after another, and the same one
    /// twice counts twice. They need not be the same size as each other.
    /// Throws a `MarkovGridError`, and learns nothing, when the picture has
    /// no cells or its rows are not all one length.
    public mutating func learn(_ picture: [[Element]]) throws {
        guard let width = picture.first?.count, width > 0 else { throw MarkovGridError.empty }
        for (index, row) in picture.enumerated() where row.count != width {
            throw MarkovGridError.ragged(row: index, count: row.count, expected: width)
        }
        var previous: [Int]?
        for row in picture {
            let places = row.map { place(of: $0) }
            count(places, after: previous)
            previous = places
        }
    }

    /// Adds one row of a picture, given the row above it.
    ///
    /// This is a picture learned a row at a time, for a sketch that shows the
    /// counts growing as the picture is scanned, or that reads its rows from
    /// somewhere they arrive one by one. Pass nil for a picture's first row.
    /// Throws a `MarkovGridError`, and learns nothing, when the row has no
    /// cells or is not as long as the row above it.
    public mutating func learn(_ row: [Element], after previous: [Element]?) throws {
        guard !row.isEmpty else { throw MarkovGridError.empty }
        if let previous, previous.count != row.count {
            throw MarkovGridError.ragged(row: 1, count: row.count, expected: previous.count)
        }
        let before = previous.map { $0.map { place(of: $0) } }
        count(row.map { place(of: $0) }, after: before)
    }

    /// Records that `element` sat among `cells`, `times` times.
    ///
    /// This is how a grid is declared rather than shown. `cells` are the
    /// settled cells around the place, nearest first: the cell before it in
    /// its row, the cell above, the cell above and before, the cell above and
    /// after, with nil for a place off the grid. Each call counts exactly as
    /// that many cells of a learned picture would, so the counts land under
    /// every shorter arrangement too, the empty one included. Only the first
    /// `order` cells are read, and a `times` below 1 records nothing.
    ///
    /// ```swift
    /// var bricks = MarkovGrid<String>(order: 2, seed: 3)
    /// bricks.learn("brick", around: ["brick", "mortar"], times: 12)
    /// bricks.learn("mortar", around: ["brick", "brick"], times: 2)
    /// ```
    public mutating func learn(_ element: Element, around cells: [Element?], times: Int = 1) {
        guard times > 0 else { return }
        let value = place(of: element)
        var node = 0
        nodes[node].add(value, times: times)
        for cell in cells.prefix(order) {
            node = child(of: node, at: cell.map { place(of: $0) + 1 } ?? 0)
            nodes[node].add(value, times: times)
        }
    }

    /// Whether the grid has been shown anything yet.
    public var isEmpty: Bool { nodes[0].total == 0 }

    // MARK: Writing

    /// The next row, `columns` cells long, written under the last one.
    ///
    /// The first row asked for is a top row: the cells above it are off the
    /// grid. Each call after that writes the row below, so calling it for as
    /// long as a sketch runs gives a strip without end. Returns an empty row
    /// when `columns` is below 1 or the grid has been shown nothing at all.
    public mutating func nextRow(columns: Int) -> [Element] {
        guard columns > 0, !isEmpty else { return [] }
        var row: [Int] = []
        row.reserveCapacity(columns)
        for place in 0 ..< columns {
            var node = 0
            for cell in 0 ..< order {
                let code: Int
                switch cell {
                case 0: code = place > 0 ? row[place - 1] + 1 : 0
                case 1: code = Self.code(above, place)
                case 2: code = Self.code(above, place - 1)
                default: code = Self.code(above, place + 1)
                }
                // An arrangement the pictures never showed stops here, and the
                // node reached so far answers for the cells it kept.
                guard code >= 0, let next = children[Step(node: node, code: code)] else { break }
                node = next
            }
            row.append(choose(from: nodes[node]))
        }
        above = row
        return row.map { vocabulary[$0] }
    }

    /// The next `count` rows, each `columns` cells long: a whole grid when it
    /// is the first thing asked for, and more of the strip after that.
    public mutating func nextRows(_ count: Int, columns: Int) -> [[Element]] {
        var rows: [[Element]] = []
        rows.reserveCapacity(max(0, count))
        for _ in 0 ..< max(0, count) {
            let row = nextRow(columns: columns)
            guard !row.isEmpty else { break }
            rows.append(row)
        }
        return rows
    }

    /// Puts the grid under a row of your own before asking it to carry on, so
    /// what it writes grows out of that row.
    public mutating func start(after row: [Element]) {
        // A value the grid never saw matches nothing, so the cells beside it
        // fall back to the ones they do know.
        above = row.map { indices[$0] ?? -2 }
    }

    /// Goes back to the top, keeping what it learned, and rewinds its
    /// randomness so the same rows come out again.
    public mutating func reset() {
        above = nil
        random = Self.generator(seed: seed)
    }

    // MARK: Reading it

    /// What a cell among `cells` may hold, and how likely each value is.
    ///
    /// `cells` are the settled cells around the place, nearest first, with
    /// nil for a place off the grid, as `learn(_:around:times:)` takes them.
    /// An arrangement never seen forgets its farthest cells, as writing does.
    /// Sorted from most likely down, so a sketch can draw what was learned.
    public func continuations(around cells: [Element?]) -> [(element: Element, probability: Double)] {
        var node = 0
        for cell in cells.prefix(order) {
            let code = cell.map { indices[$0].map { $0 + 1 } ?? -1 } ?? 0
            guard code >= 0, let next = children[Step(node: node, code: code)] else { break }
            node = next
        }
        let tally = nodes[node]
        guard tally.total > 0 else { return [] }
        let total = Double(tally.total)
        // Ties keep vocabulary order, so the answer is the same on every run.
        return zip(tally.values, tally.counts)
            .map { (element: vocabulary[$0], probability: Double($1) / total) }
            .enumerated()
            .sorted {
                $0.element.probability == $1.element.probability
                    ? $0.offset < $1.offset
                    : $0.element.probability > $1.element.probability
            }
            .map(\.element)
    }

    /// How many times `element` was seen among exactly these `cells`.
    ///
    /// Nothing is forgotten here: an arrangement the pictures never showed
    /// counts 0. Fewer cells than `order` reads the counts kept under that
    /// shorter arrangement, and no cells at all how often the value appeared.
    public func count(of element: Element, around cells: [Element?]) -> Int {
        guard let value = indices[element] else { return 0 }
        var node = 0
        for cell in cells.prefix(order) {
            let code = cell.map { indices[$0].map { $0 + 1 } ?? -1 } ?? 0
            guard code >= 0, let next = children[Step(node: node, code: code)] else { return 0 }
            node = next
        }
        return nodes[node].count(of: value)
    }

    // MARK: The counts

    /// Counts one row against the row above it, every cell under its whole
    /// arrangement and under each shorter one.
    private mutating func count(_ row: [Int], after previous: [Int]?) {
        for (place, value) in row.enumerated() {
            var node = 0
            nodes[node].add(value, times: 1)
            for cell in 0 ..< order {
                let code: Int
                switch cell {
                case 0: code = place > 0 ? row[place - 1] + 1 : 0
                case 1: code = Self.code(previous, place)
                case 2: code = Self.code(previous, place - 1)
                default: code = Self.code(previous, place + 1)
                }
                node = child(of: node, at: code)
                nodes[node].add(value, times: 1)
            }
        }
    }

    /// What a place of a row reads as: 0 off the grid, a value's place in the
    /// vocabulary plus one, or below 0 for a value the grid never saw.
    private static func code(_ row: [Int]?, _ place: Int) -> Int {
        guard let row, row.indices.contains(place) else { return 0 }
        return row[place] + 1
    }

    private mutating func place(of element: Element) -> Int {
        if let known = indices[element] { return known }
        indices[element] = vocabulary.count
        vocabulary.append(element)
        return vocabulary.count - 1
    }

    private mutating func child(of node: Int, at code: Int) -> Int {
        let step = Step(node: node, code: code)
        if let known = children[step] { return known }
        children[step] = nodes.count
        nodes.append(Node())
        return nodes.count - 1
    }

    private mutating func choose(from tally: Node) -> Int {
        var roll = Int(random.next() % UInt64(tally.total))
        for (index, count) in tally.counts.enumerated() {
            roll -= count
            if roll < 0 { return tally.values[index] }
        }
        return tally.values[tally.values.count - 1]
    }

    private static func generator(seed: Int) -> SplitMix64 {
        SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
    }

    /// One more cell of an arrangement, from the node that holds the cells
    /// before it.
    private struct Step: Hashable, Sendable {
        let node: Int
        let code: Int
    }

    /// What was seen after one arrangement: the values, kept in vocabulary
    /// order so that choosing among them never depends on the order they
    /// turned up in, and how often each came.
    private struct Node: Sendable {
        var values: [Int] = []
        var counts: [Int] = []
        var total = 0

        mutating func add(_ value: Int, times: Int) {
            total += times
            var slot = 0
            while slot < values.count, values[slot] < value { slot += 1 }
            if slot < values.count, values[slot] == value {
                counts[slot] += times
            } else {
                values.insert(value, at: slot)
                counts.insert(times, at: slot)
            }
        }

        func count(of value: Int) -> Int {
            values.firstIndex(of: value).map { counts[$0] } ?? 0
        }
    }
}

/// What was wrong with a picture handed to a `MarkovGrid`.
public enum MarkovGridError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The picture had no rows, or its rows had no cells.
    case empty
    /// A row was not as long as the rows before it. `row` counts from 0 at
    /// the first row handed in.
    case ragged(row: Int, count: Int, expected: Int)

    public var description: String {
        switch self {
        case .empty:
            "The picture has no cells to learn from."
        case let .ragged(row, count, expected):
            "Row \(row + 1) of the picture has \(count) cells where the rows before it have \(expected)."
        }
    }
}
