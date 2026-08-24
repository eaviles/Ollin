import Foundation

/// Where water goes on a `Heightfield`, and the river network that comes out
/// of it.
///
/// Rivers are not drawn on a landscape. They are worked out from it, and the
/// rule is small enough to say in a sentence: water on any cell runs to
/// whichever of its eight neighbors is steepest downhill, and the flow through
/// a cell is the count of every cell that eventually runs through it. Follow
/// that everywhere and the valleys fill with lines by themselves, branching the
/// way real ones branch, because the shape of the ground is what decides it.
///
/// ```swift
/// let land = Heightfield(columns: 257, rows: 257).diamondSquare(seed: 7)
///     .eroded(.hydraulic())
/// let water = land.drainage()
/// for river in water.rivers(minimumFlow: 60, in: frame) {
///     strokeWeight(Double(river.order))
///     drawPolyline(river.points)
/// }
/// ```
///
/// One thing has to happen before any of it works, and it is the reason this
/// is not ten lines. A landscape is full of hollows with no way out, and water
/// arriving in one has nowhere to go, so the network stops there. Every hollow
/// is filled first, until the whole field drains to its own edge, which is
/// exactly what a real basin does once it has brimmed over. `drainage()` does
/// that for you; `filled()` is the same pass on its own.
///
/// Written from the published D8 and Priority-Flood results (see
/// `ATTRIBUTION.md`).
public struct Drainage: Sendable {
    /// The grid this was worked out on.
    public let columns: Int

    /// The grid this was worked out on.
    public let rows: Int

    /// For each cell, the index of the cell it runs into, or `-1` where the
    /// water leaves the field.
    public let downstream: [Int]

    /// For each cell, how many cells run through it, itself counted. A cell no
    /// water reaches but its own reads 1, and the number climbs down a valley.
    public let flow: [Double]

    /// For each cell, which outlet its water reaches in the end, as an index
    /// into ``outlets``.
    public let basin: [Int]

    /// The cells the water leaves by, in basin order.
    public let outlets: [Int]
}

// MARK: - Reading it

public extension Drainage {
    /// How many cells run through this one, itself counted.
    func flow(_ x: Int, _ y: Int) -> Double {
        guard x >= 0, y >= 0, x < columns, y < rows else { return 0 }
        return flow[y * columns + x]
    }

    /// Which outlet this cell's water reaches, as an index into ``outlets``.
    func basin(_ x: Int, _ y: Int) -> Int {
        guard x >= 0, y >= 0, x < columns, y < rows else { return -1 }
        return basin[y * columns + x]
    }

    /// The flow as a field of its own, so it can be imaged, contoured, or
    /// sampled like any other. The numbers are cell counts, so
    /// `.normalized()` before imaging, and a logarithm reads better than the
    /// raw count: a trunk carries thousands of times what a headwater does.
    var flowField: Heightfield {
        Heightfield(columns: columns, rows: rows, values: flow)
    }

    /// The cell the water leaves by for the basin this cell belongs to.
    func outlet(of x: Int, _ y: Int) -> Int? {
        let which = basin(x, y)
        guard which >= 0, which < outlets.count else { return nil }
        return outlets[which]
    }
}

// MARK: - The network

/// One reach of a river network: an unbroken run of cells from a source, or
/// from a meeting of two rivers, down to where it meets the next one.
public struct River: Sendable {
    /// The run itself, in the frame it was asked for.
    public var points: [Vector2]

    /// Strahler's order for this reach. A headwater is 1. Two reaches of equal
    /// order meeting make the next one up, and an unequal pair makes the
    /// larger of the two, so the number counts how much of the branching
    /// upstream is behind it rather than how far it has come.
    public var order: Int

    /// The flow at the lowest end of the reach, in cells.
    public var flow: Double
}

public extension Drainage {
    /// The river network, as runs of points laid out in `frame`.
    ///
    /// A cell joins the network when at least `minimumFlow` cells run through
    /// it, so the threshold is the whole difference between a few great rivers
    /// and a fine tracery of creeks. It has a real meaning: it is the smallest
    /// catchment you are willing to call a river, measured in cells.
    ///
    /// Each reach is traced once. A run starts at a source, or just below a
    /// meeting, and stops at the next meeting, sharing that cell with the reach
    /// below it so the lines join. A reach is two points or more, except for
    /// the odd one-cell case: a cell over the threshold that leaves the field
    /// at once, fed only by ground too small to be called a river. Ordering follows Strahler, which is what
    /// ``River/order`` carries, and stroking by it draws a network that
    /// thickens downstream.
    func rivers(minimumFlow: Double, in frame: Rectangle) -> [River] {
        let inNetwork = flow.map { $0 >= minimumFlow }
        guard inNetwork.contains(true) else { return [] }

        // Who runs into whom, inside the network only.
        var feeders = [[Int]](repeating: [], count: columns * rows)
        for cell in 0 ..< columns * rows where inNetwork[cell] {
            let next = downstream[cell]
            if next >= 0, inNetwork[next] { feeders[next].append(cell) }
        }

        let order = strahlerOrders(inNetwork: inNetwork, feeders: feeders)

        // A reach ends where the line stops being a single line: at a meeting,
        // or where the network itself ends. Every other cell is interior to a
        // reach, so walking up from each end covers the network exactly once.
        var reaches: [River] = []
        for cell in 0 ..< columns * rows where inNetwork[cell] {
            let next = downstream[cell]
            let isMeeting = feeders[cell].count >= 2
            let isEnd = next < 0 || !inNetwork[next]
            guard isMeeting || isEnd else { continue }

            // A cell over the threshold with nothing over it and nowhere left
            // to go: a river that reaches the edge fed only by ground too small
            // to be called a river. It is one cell long, and it is kept so the
            // network is covered rather than quietly short.
            if feeders[cell].isEmpty {
                reaches.append(reach(cells: [cell], order: order, frame: frame))
                continue
            }

            for feeder in feeders[cell] {
                var chain = [cell, feeder]
                var walker = feeder
                while feeders[walker].count == 1 {
                    walker = feeders[walker][0]
                    chain.append(walker)
                }
                reaches.append(reach(cells: chain.reversed(), order: order, frame: frame))
            }
        }
        return reaches
    }

    /// Strahler's order for every cell of the network, and 0 for every cell
    /// outside it.
    func strahlerOrders(minimumFlow: Double) -> [Int] {
        let inNetwork = flow.map { $0 >= minimumFlow }
        var feeders = [[Int]](repeating: [], count: columns * rows)
        for cell in 0 ..< columns * rows where inNetwork[cell] {
            let next = downstream[cell]
            if next >= 0, inNetwork[next] { feeders[next].append(cell) }
        }
        return strahlerOrders(inNetwork: inNetwork, feeders: feeders)
    }

    /// Where a cell sits in `frame`.
    func point(_ x: Int, _ y: Int, in frame: Rectangle) -> Vector2 {
        frame.point(u: columns > 1 ? Double(x) / Double(columns - 1) : 0.5,
                    v: rows > 1 ? Double(y) / Double(rows - 1) : 0.5)
    }

    // MARK: private

    private func reach(cells: [Int], order: [Int], frame: Rectangle) -> River {
        let points = cells.map { point($0 % columns, $0 / columns, in: frame) }
        let last = cells[cells.count - 1]
        return River(points: points, order: max(1, order[last]), flow: flow[last])
    }

    private func strahlerOrders(inNetwork: [Bool], feeders: [[Int]]) -> [Int] {
        var order = [Int](repeating: 0, count: columns * rows)
        // Work upstream first. Flow only grows downstream, so sorting the
        // network by flow is a topological order for free.
        let network = (0 ..< columns * rows).filter { inNetwork[$0] }
            .sorted { flow[$0] < flow[$1] }
        for cell in network {
            var best = 0, seconds = 0
            for feeder in feeders[cell] {
                let o = order[feeder]
                if o > best { seconds = best; best = o }
                else if o > seconds { seconds = o }
            }
            order[cell] = best == 0 ? 1 : (best == seconds ? best + 1 : best)
        }
        return order
    }
}

// MARK: - Working it out

public extension Heightfield {
    /// Where the water goes.
    ///
    /// Every cell runs to whichever of its eight neighbors is steepest
    /// downhill, measured as drop over distance so a diagonal step is not
    /// unfairly favored, and the flow through a cell counts every cell that
    /// ends up running through it. Hollows are filled first unless you ask for
    /// them to be left, since water arriving in an unfilled one has nowhere to
    /// go and the network stops dead there.
    func drainage(fillingHollows: Bool = true, minimumDrop: Double = 1e-7) -> Drainage {
        let flood = fillingHollows ? flooded(minimumDrop: minimumDrop) : nil
        let ground = flood.map { Heightfield(columns: columns, rows: rows, values: $0.heights) } ?? self
        let count = columns * rows

        // Steepest descent, by drop over distance. A cell the filling raised is
        // under water, and a lake has no shape of its own to follow, so it
        // takes the way the flood came in instead: that link leads to the point
        // the hollow brims over at, which is where the water really leaves.
        // Reading a slope there instead gives a lake drained by a fan of
        // straight parallel lines, which is the flood's own front showing
        // through.
        var downstream = [Int](repeating: -1, count: count)
        let diagonal = 1 / 2.0.squareRoot()
        for y in 0 ..< rows {
            for x in 0 ..< columns {
                let here = y * columns + x
                if let flood, flood.heights[here] > values[here] {
                    downstream[here] = flood.parent[here]
                    continue
                }
                let height = ground.values[here]
                var bestSlope = 0.0
                for step in 0 ..< 8 {
                    let nx = x + Drainage.stepX[step], ny = y + Drainage.stepY[step]
                    guard nx >= 0, ny >= 0, nx < columns, ny < rows else { continue }
                    let there = ny * columns + nx
                    let drop = height - ground.values[there]
                    guard drop > 0 else { continue }
                    let slope = (step & 1) == 1 ? drop * diagonal : drop
                    if slope > bestSlope { bestSlope = slope; downstream[here] = there }
                }
            }
        }

        // Flow, counted from the tops down. Every step is strictly downhill, so
        // the cells form a forest and a cell can be counted the moment
        // everything above it has been.
        var feeding = [Int](repeating: 0, count: count)
        for next in downstream where next >= 0 { feeding[next] += 1 }
        var flow = [Double](repeating: 1, count: count)
        var ready = (0 ..< count).filter { feeding[$0] == 0 }
        var head = 0
        while head < ready.count {
            let cell = ready[head]; head += 1
            let next = downstream[cell]
            guard next >= 0 else { continue }
            flow[next] += flow[cell]
            feeding[next] -= 1
            if feeding[next] == 0 { ready.append(next) }
        }

        // Which outlet each cell reaches, by following the water down once and
        // writing the answer back along the way.
        var outlets: [Int] = []
        var basinOf = [Int](repeating: -1, count: count)
        var path: [Int] = []
        for start in 0 ..< count where basinOf[start] < 0 {
            path.removeAll(keepingCapacity: true)
            var walker = start
            while basinOf[walker] < 0, downstream[walker] >= 0 {
                path.append(walker)
                walker = downstream[walker]
            }
            let which: Int
            if basinOf[walker] >= 0 {
                which = basinOf[walker]
            } else {
                which = outlets.count
                outlets.append(walker)
                basinOf[walker] = which
            }
            for cell in path { basinOf[cell] = which }
        }

        return Drainage(columns: columns, rows: rows, downstream: downstream,
                        flow: flow, basin: basinOf, outlets: outlets)
    }

    /// The same field with every hollow filled to the level it would brim over
    /// at, so water anywhere on it has a way to the edge.
    ///
    /// The field is flooded inward from its own edges, lowest first. A cell the
    /// flood reaches is raised to the level of whatever let the water in, which
    /// is the brim of the hollow holding it, and nothing else moves. A field
    /// that already drains everywhere comes back unchanged.
    ///
    /// `minimumDrop` is the hair of slope a filled cell keeps over the one that
    /// flooded it. Without it a filled hollow is dead flat, and a flat has no
    /// downhill neighbor at all, so the water would stop there exactly as it
    /// did in the hollow.
    func filled(minimumDrop: Double = 1e-7) -> Heightfield {
        Heightfield(columns: columns, rows: rows, values: flooded(minimumDrop: minimumDrop).heights)
    }

    /// The filling pass itself, which knows one thing more than the heights it
    /// hands back: which cell let the water into each cell it raised. Inside a
    /// filled hollow that link is the only honest direction there is.
    internal func flooded(minimumDrop: Double) -> (heights: [Double], parent: [Int]) {
        let count = columns * rows
        var result = values
        var parent = [Int](repeating: -1, count: count)
        var closed = [Bool](repeating: false, count: count)
        var queue = CellHeap()

        for y in 0 ..< rows {
            for x in 0 ..< columns where x == 0 || y == 0 || x == columns - 1 || y == rows - 1 {
                let cell = y * columns + x
                closed[cell] = true
                queue.push(height: result[cell], cell: cell)
            }
        }

        while let (height, cell) = queue.pop() {
            let x = cell % columns, y = cell / columns
            for step in 0 ..< 8 {
                let nx = x + Drainage.stepX[step], ny = y + Drainage.stepY[step]
                guard nx >= 0, ny >= 0, nx < columns, ny < rows else { continue }
                let there = ny * columns + nx
                guard !closed[there] else { continue }
                closed[there] = true
                parent[there] = cell
                result[there] = max(result[there], height + minimumDrop)
                queue.push(height: result[there], cell: there)
            }
        }
        return (result, parent)
    }
}

// MARK: - The neighborhood, and a queue to flood with

extension Drainage {
    /// The eight neighbors, starting east and going around. Odd steps are the
    /// diagonals, which is what the slope measurement leans on.
    static let stepX = [1, 1, 0, -1, -1, -1, 0, 1]
    static let stepY = [0, 1, 1, 1, 0, -1, -1, -1]
}

/// A smallest-first queue of cells, which is what makes the flood come in
/// lowest-first and therefore fill each hollow exactly to its own brim.
private struct CellHeap {
    private var heights: [Double] = []
    private var cells: [Int] = []

    mutating func push(height: Double, cell: Int) {
        heights.append(height); cells.append(cell)
        var child = heights.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard heights[child] < heights[parent] else { break }
            heights.swapAt(child, parent); cells.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard let height = heights.first, let cell = cells.first else { return nil }
        heights[0] = heights[heights.count - 1]; heights.removeLast()
        cells[0] = cells[cells.count - 1]; cells.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1, right = left + 1
            var smallest = parent
            if left < heights.count, heights[left] < heights[smallest] { smallest = left }
            if right < heights.count, heights[right] < heights[smallest] { smallest = right }
            guard smallest != parent else { break }
            heights.swapAt(parent, smallest); cells.swapAt(parent, smallest)
            parent = smallest
        }
        return (height, cell)
    }
}
