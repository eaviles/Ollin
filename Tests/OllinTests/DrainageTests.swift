@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on drainage. A river network drawn over a landscape looks
/// convincing long before it is right, because branching lines in valleys read
/// as rivers whatever the numbers behind them say. So none of these look at
/// the picture.
///
/// Two laws carry the suite. `aTiltedPlaneCountsItsOwnRows` is an arrangement
/// with one correct answer that can be written down without running anything:
/// on a plane leaning one way, every cell runs straight down its own column, so
/// the flow at row `y` is `y + 1` and nothing else. `flowIsTheTotalOfEveryPath`
/// reaches the same totals by a route the counting never takes: a cell adds one
/// to every cell on its way out, so the flow summed over the field must equal
/// the lengths of all those ways added up, walked one at a time.
@Suite
struct DrainageTests {

    /// A plane leaning one way only. Everything in a row sits at the same
    /// height, so nothing runs sideways: the step straight down the slope is
    /// the steepest one and the two diagonals lose to it over their own longer
    /// distance.
    private func tiltedPlane(columns: Int = 12, rows: Int = 9) -> Heightfield {
        Heightfield(columns: columns, rows: rows) { _, v in 1 - v * 0.9 }
    }

    /// A bowl in the middle of an otherwise sloping field: one hollow with no
    /// way out until it is filled.
    private func bowl(columns: Int = 21, rows: Int = 21) -> Heightfield {
        Heightfield(columns: columns, rows: rows) { u, v in
            let toMiddle = Vector2(u - 0.5, v - 0.5).length
            let slope = 1 - v * 0.4
            return toMiddle < 0.25 ? slope - (0.25 - toMiddle) * 2 : slope
        }
    }

    // MARK: - The counting

    /// The load-bearing arrangement, because its answer is known in advance. A
    /// plane leaning one way sends every cell straight down its own column, so
    /// the flow at row `y` is exactly the `y + 1` cells above it.
    @Test func aTiltedPlaneCountsItsOwnRows() {
        let water = tiltedPlane().drainage()
        for y in 0 ..< 9 {
            for x in 0 ..< 12 {
                #expect(water.flow(x, y) == Double(y + 1))
            }
        }
        // And every cell of the lowest row lets the water off the field.
        for x in 0 ..< 12 {
            #expect(water.downstream[8 * 12 + x] == -1)
        }
    }

    /// The same totals, worked out a second way. Each cell adds one to every
    /// cell it passes through on its way out, itself included, so the flow
    /// added up over the whole field is the total length of all those ways.
    @Test func flowIsTheTotalOfEveryPath() {
        for field in [tiltedPlane(), bowl(), Heightfield.diamondSquare(size: 33, seed: 5)] {
            let water = field.drainage()
            var walked = 0.0
            for start in 0 ..< water.columns * water.rows {
                var walker = start, steps = 0
                while walker >= 0 {
                    steps += 1
                    walker = water.downstream[walker]
                    #expect(steps <= water.columns * water.rows)   // never a loop
                }
                walked += Double(steps)
            }
            #expect(abs(water.flow.reduce(0, +) - walked) < 1e-6)
        }
    }

    /// Water only gathers. Every cell carries at least itself, and the cell
    /// below always carries strictly more than the cell above it.
    @Test func flowOnlyGrowsDownhill() {
        let water = Heightfield.diamondSquare(size: 33, seed: 11).drainage()
        for cell in 0 ..< water.columns * water.rows {
            #expect(water.flow[cell] >= 1)
            let next = water.downstream[cell]
            if next >= 0 { #expect(water.flow[next] > water.flow[cell]) }
        }
    }

    /// A step is always downhill, and it is the steepest one available, with a
    /// diagonal measured over its own longer distance rather than treated as if
    /// it were a straight step.
    @Test func everyStepIsTheSteepestOneDownhill() {
        let field = Heightfield.diamondSquare(size: 17, seed: 3).filled()
        let water = field.drainage(fillingHollows: false)
        let diagonal = 1 / 2.0.squareRoot()
        let side = field.columns
        for y in 0 ..< side {
            for x in 0 ..< side {
                let here = y * side + x
                var best = 0.0
                for step in 0 ..< 8 {
                    let nx = x + Drainage.stepX[step], ny = y + Drainage.stepY[step]
                    guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                    let drop = field[x, y] - field[nx, ny]
                    guard drop > 0 else { continue }
                    best = max(best, (step & 1) == 1 ? drop * diagonal : drop)
                }
                let next = water.downstream[here]
                if best == 0 {
                    #expect(next == -1)
                } else {
                    #expect(next >= 0)
                    let nx = next % side, ny = next / side
                    let drop = field[x, y] - field[nx, ny]
                    let taken = (abs(nx - x) == 1 && abs(ny - y) == 1) ? drop * diagonal : drop
                    #expect(abs(taken - best) < 1e-12)
                }
            }
        }
    }

    // MARK: - Filling the hollows

    /// The whole reason the filling pass exists. Water arriving in a hollow has
    /// nowhere to go, so an unfilled field strands it in the middle; a filled
    /// one lets it out at the edge.
    @Test func aHollowStrandsWaterUntilItIsFilled() {
        let land = bowl()
        let middle = 10 * 21 + 10

        let raw = land.drainage(fillingHollows: false)
        #expect(raw.downstream[middle] == -1)                       // stranded
        #expect(raw.outlets.contains(middle))
        let strandedBasin = raw.basin[middle]
        #expect(raw.outlets[strandedBasin] == middle)

        let full = land.drainage()
        #expect(full.downstream[middle] >= 0)                       // it flows now
        var walker = middle, steps = 0
        while full.downstream[walker] >= 0 { walker = full.downstream[walker]; steps += 1 }
        let x = walker % 21, y = walker / 21
        #expect(x == 0 || y == 0 || x == 20 || y == 20)             // and reaches the edge
        #expect(steps > 5)
    }

    /// Filling only ever raises ground, and it leaves a field that already
    /// drains completely alone.
    @Test func fillingRaisesGroundAndNothingElse() {
        let land = bowl()
        let full = land.filled()
        for cell in 0 ..< land.values.count {
            #expect(full.values[cell] >= land.values[cell] - 1e-12)
        }
        // Only the hollow moved: the corners of a sloping field are untouched.
        #expect(full[0, 0] == land[0, 0])
        #expect(full[20, 20] == land[20, 20])

        // A field with no hollow comes back exactly as it went in.
        let plane = tiltedPlane()
        #expect(plane.filled().values == plane.values)
    }

    /// After filling, no interior cell is a hollow: every one has a neighbor
    /// strictly below it, which is the property the counting leans on.
    @Test func nothingIsLeftWithNowhereToGo() {
        let full = Heightfield.diamondSquare(size: 33, seed: 9).filled()
        for y in 1 ..< full.rows - 1 {
            for x in 1 ..< full.columns - 1 {
                var lower = false
                for step in 0 ..< 8 {
                    let nx = x + Drainage.stepX[step], ny = y + Drainage.stepY[step]
                    if full[nx, ny] < full[x, y] { lower = true; break }
                }
                #expect(lower)
            }
        }
    }

    /// A lake has no shape of its own, so a cell the filling raised follows the
    /// way the flood came in rather than a slope that is not really there. That
    /// link leads to the point the hollow brims over at. Reading a slope
    /// instead drains a lake as a fan of straight parallel lines, which is the
    /// flood front showing through the picture.
    @Test func aFilledHollowFollowsTheWayTheWaterCameIn() {
        let land = bowl()
        let flood = land.flooded(minimumDrop: 1e-7)
        let water = land.drainage()

        var raised = 0
        for cell in 0 ..< land.values.count where flood.heights[cell] > land.values[cell] {
            raised += 1
            #expect(water.downstream[cell] == flood.parent[cell])
        }
        #expect(raised > 20)                       // the hollow really was filled

        // Every cell under that water gets out of the hollow, and every door
        // it uses is a real one. A hollow can have more than one: the flood
        // fills it from whichever low place on its rim it reaches first, and a
        // rim with several equally low places is entered at several of them.
        // This bowl is a circle on a slope, so it has four.
        let under = (0 ..< land.values.count).filter { flood.heights[$0] > land.values[$0] }
        for cell in under {
            var walker = cell, steps = 0
            while flood.heights[walker] > land.values[walker] {
                walker = water.downstream[walker]
                steps += 1
                #expect(walker >= 0)
                #expect(steps <= under.count)
                if walker < 0 { break }
            }
        }
        let doors = Set(under.map { water.basin[$0] })
        #expect(!doors.isEmpty)
        for door in doors { #expect(water.downstream[water.outlets[door]] == -1) }
    }

    // MARK: - Basins

    /// A basin is the set of cells that leave by the same place, so a cell and
    /// the cell below it are always in the same one, and every named outlet is
    /// a cell the water actually leaves by.
    @Test func aBasinIsWhoeverLeavesByTheSameDoor() {
        let water = Heightfield.diamondSquare(size: 33, seed: 4).drainage()
        for cell in 0 ..< water.columns * water.rows {
            #expect(water.basin[cell] >= 0)
            let next = water.downstream[cell]
            if next >= 0 { #expect(water.basin[next] == water.basin[cell]) }
        }
        for (which, outlet) in water.outlets.enumerated() {
            #expect(water.downstream[outlet] == -1)
            #expect(water.basin[outlet] == which)
        }
        // Every cell belongs to exactly one basin, so the parts add up to the
        // whole field.
        var counted = [Int](repeating: 0, count: water.outlets.count)
        for cell in water.basin { counted[cell] += 1 }
        #expect(counted.reduce(0, +) == water.columns * water.rows)
    }

    // MARK: - The network

    /// The network is what the threshold says it is, and it hangs together:
    /// every reach ends where another begins, or at the edge of the field.
    @Test func theNetworkIsConnectedAndAboveTheThreshold() {
        let frame = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let water = Heightfield.diamondSquare(size: 33, seed: 6).drainage()
        let threshold = 25.0
        let rivers = water.rivers(minimumFlow: threshold, in: frame)
        #expect(rivers.count > 4)

        // Everything drawn is a cell over the threshold, and the reaches cover
        // every such cell exactly once but for the meetings they share.
        let expected = water.flow.filter { $0 >= threshold }.count
        var drawn = Set<Vector2Key>()
        var total = 0
        for river in rivers {
            #expect(river.flow >= threshold)
            // A single point is legal only where the river leaves the field
            // with nothing above it in the network.
            if river.points.count < 2 { #expect(river.order == 1) }
            total += river.points.count
            for point in river.points { drawn.insert(Vector2Key(point)) }
        }
        #expect(drawn.count == expected)
        #expect(total > expected)                      // meetings are shared, so drawn twice
    }

    /// Strahler's rule, checked where it is decided: a source is 1, two equal
    /// orders meeting make the next one up, and an unequal pair keeps the
    /// larger. Nothing else changes the number.
    @Test func orderFollowsStrahlersRule() {
        let water = Heightfield.diamondSquare(size: 33, seed: 6).drainage()
        let threshold = 25.0
        let order = water.strahlerOrders(minimumFlow: threshold)

        var feeders = [[Int]](repeating: [], count: water.columns * water.rows)
        for cell in 0 ..< water.columns * water.rows where water.flow[cell] >= threshold {
            let next = water.downstream[cell]
            if next >= 0, water.flow[next] >= threshold { feeders[next].append(cell) }
        }

        var meetings = 0, increments = 0
        for cell in 0 ..< water.columns * water.rows {
            guard water.flow[cell] >= threshold else {
                #expect(order[cell] == 0)
                continue
            }
            #expect(order[cell] >= 1)
            let incoming = feeders[cell].map { order[$0] }.sorted(by: >)
            if incoming.isEmpty {
                #expect(order[cell] == 1)                       // a source
            } else if incoming.count == 1 || incoming[0] > incoming[1] {
                #expect(order[cell] == incoming[0])             // carried through
            } else {
                meetings += 1
                #expect(order[cell] == incoming[0] + 1)         // two equals make the next up
                increments += 1
            }
            // And it never falls going downstream.
            let next = water.downstream[cell]
            if next >= 0, water.flow[next] >= threshold { #expect(order[next] >= order[cell]) }
        }
        #expect(meetings > 0)                                   // the rule was exercised
        #expect(increments == meetings)
    }

    /// Raising the threshold can only take rivers away, never add them, since
    /// it is a test each cell passes or fails on its own.
    @Test func aHigherThresholdKeepsFewerCells() {
        let frame = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let water = Heightfield.diamondSquare(size: 33, seed: 8).drainage()
        var previous = Int.max
        for threshold in [10.0, 25, 60, 150, 400] {
            let cells = water.flow.filter { $0 >= threshold }.count
            #expect(cells <= previous)
            previous = cells
            let rivers = water.rivers(minimumFlow: threshold, in: frame)
            for river in rivers { #expect(river.flow >= threshold) }
        }
    }

    /// The smallest and flattest fields answer sensibly rather than crashing.
    /// A field is at least two by two by its own rule, and one that small is
    /// all edge, so every cell of it lets water off.
    @Test func theSmallestAndFlattestFieldsAnswerSensibly() {
        let tiny = Heightfield(columns: 0, rows: 0)              // clamped to 2x2
        let water = tiny.drainage()
        #expect(water.flow == [1, 1, 1, 1])
        #expect(water.outlets.count == 4)
        // Asked for every cell, it answers with four one-cell reaches, since
        // each corner leaves the field on its own with nothing above it.
        let all = water.rivers(minimumFlow: 1, in: Rectangle(x: 0, y: 0, width: 1, height: 1))
        #expect(all.count == 4)
        #expect(all.allSatisfy { $0.points.count == 1 })
        #expect(water.rivers(minimumFlow: 2, in: Rectangle(x: 0, y: 0, width: 1, height: 1)).isEmpty)
        #expect(tiny.filled().values == tiny.values)

        // A flat field has no downhill anywhere, so every cell keeps its own
        // single count.
        let flat = Heightfield(columns: 6, rows: 6, repeating: 0.5)
        let still = flat.drainage(fillingHollows: false)
        #expect(still.flow.allSatisfy { $0 == 1 })
        #expect(still.outlets.count == 36)
    }
}

/// A point that can go in a set, for counting cells a network drew.
private struct Vector2Key: Hashable {
    let x: Double, y: Double
    init(_ point: Vector2) { x = point.x; y = point.y }
}
