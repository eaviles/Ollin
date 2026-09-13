import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the state automata (`.cyclic`, `.excitable`,
/// `.briansBrain`, `.hodgepodge`, `.forestFire`, `.wireworld`, `.schelling`), run
/// headless on a 64-texel field and compared
/// **cell for cell** against a plain sequential CPU reference stepping the same
/// published rule from the same start. The match pins the shared state encoding
/// (s/(levels-1) in .r, decoded with rint), the exact neighbor counts under both
/// neighborhood shapes, the toroidal wrap, and the injects: the full-texel stamps
/// override the seeded-noise start everywhere they land, so the initial state is
/// known by construction (abutting unit rects tile seamlessly under the
/// inside-biased fill ramp, which is what makes per-texel stamping exact).
///
/// A stamp's gray is chosen in sRGB so it lands on the wanted linear level, and
/// the readback decodes each texel to the nearest expected level; the levels used
/// here sit tens of 8-bit steps apart, far past the present pass's ±1 dither.
@Suite
@MainActor
struct StateAutomataTests {

    // MARK: The rules, against the reference

    @Test(.enabled(if: Snapshot.hasMetal))
    func cyclicMatchesTheSequentialReference() throws {
        // Six states, threshold 2, the eight-cell block: exercises the corner taps
        // and the threshold path. Every texel is stamped, so the start is known.
        let states = 6
        let start = randomGrid(levels: states, seed: 7)
        let sketch = probe(.cyclic(states: states, threshold: 2, range: 1,
                                   neighborhood: .moore, seed: 3),
                           stamps: fullStamps(start, levels: states))
        let gpu = try grid(sketch, generations: 12, levels: states)
        var reference = start
        for _ in 0 ..< 12 {
            reference = stepCyclic(reference, states: states, threshold: 2,
                                   range: 1, moore: true)
        }
        #expect(gpu == reference)
        #expect(gpu != start)   // the run must actually advance
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func excitableWaveMatchesTheReference() throws {
        // A four-state cycle sparked at a handful of cells: the rings the rule
        // grows (and the refractory tails behind them) must match step for step.
        let states = 4
        let sparks = [(10, 10), (40, 22), (41, 22), (20, 47)]
        let sketch = probe(.excitable(states: states),
                           stamps: sparks.map { (x: $0.0, y: $0.1, white: 1.0) })
        let gpu = try grid(sketch, generations: 9, levels: states)
        var reference = emptyGrid()
        for (x, y) in sparks { reference[y][x] = 1 }
        for _ in 0 ..< 9 {
            reference = stepExcitable(reference, states: states, threshold: 1,
                                      range: 1, moore: false)
        }
        #expect(gpu == reference)
        // And the wave is real: excitation left the stamped cells behind.
        #expect(gpu.joined().filter { $0 == 1 }.count > sparks.count)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func briansBrainMatchesTheReference() throws {
        // A deterministic sprinkle of firing cells; the boil must match exactly.
        var rng = LCG(seed: 11)
        var cells: Set<Int> = []
        while cells.count < 60 { cells.insert(rng.next(4096)) }
        let sparks = cells.sorted().map { (x: $0 % 64, y: $0 / 64, white: 1.0) }
        let sketch = probe(.briansBrain(), stamps: sparks)
        let gpu = try grid(sketch, generations: 8, levels: 3)
        var reference = emptyGrid()
        for s in sparks { reference[s.y][s.x] = 2 }
        for _ in 0 ..< 8 { reference = stepBrain(reference) }
        #expect(gpu == reference)
        #expect(gpu.joined().contains(2))   // still firing somewhere
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func hodgepodgeMatchesTheSequentialReference() throws {
        // Eleven levels (n = 10) keep the readback unambiguous; k1/k2/g exercise
        // all three branches (catch, worsen with the averaged sum, recover).
        let n = 10
        let start = randomGrid(levels: n + 1, seed: 19)
        let sketch = probe(.hodgepodge(states: n, infectedDivisor: 2, illDivisor: 3, infectionRate: 3,
                                       neighborhood: .moore, seed: 5),
                           stamps: fullStamps(start, levels: n + 1))
        let gpu = try grid(sketch, generations: 10, levels: n + 1)
        var reference = start
        for _ in 0 ..< 10 {
            reference = stepHodgepodge(reference, n: n, k1: 2, k2: 3, g: 3, moore: true)
        }
        #expect(gpu == reference)
        #expect(gpu != start)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anUntouchedExcitableFieldStaysAtRest() throws {
        // Rest is a fixed point for the draw-to-spark pair: no inject garbage, no
        // noise fill where none was asked for.
        let excitable = try grid(probe(.excitable(), stamps: []), generations: 20, levels: 3)
        let brain = try grid(probe(.briansBrain(), stamps: []), generations: 20, levels: 3)
        #expect(excitable.allSatisfy { $0.allSatisfy { $0 == 0 } })
        #expect(brain.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    // MARK: The forest fire

    /// With both rates at zero the rule is fully deterministic: fire spreads to
    /// neighboring trees and burns out, and nothing grows back. That is the half a
    /// reference can check cell for cell, since the coin the other half throws is a
    /// GPU hash no CPU reproduces bit for bit.
    @Test(.enabled(if: Snapshot.hasMetal))
    func forestFireSpreadMatchesTheSequentialReference() throws {
        var start = randomGrid(levels: 2, seed: 23)   // a patchy stand of trees
        start[32][32] = 2                             // one of them alight
        start[8][40] = 2
        let sketch = probe(.forestFire(growth: 0, lightning: 0), stamps: fullStamps(start, levels: 3))
        let gpu = try grid(sketch, generations: 14, levels: 3)
        var reference = start
        for _ in 0 ..< 14 { reference = stepForestFire(reference, moore: false) }
        #expect(gpu == reference)
        #expect(gpu != start)                          // the fire actually ran
        #expect(gpu.joined().contains(0))              // and left bare ground behind
    }

    /// The neighborhood shape decides whether a fire crosses a corner. Two trees
    /// touching only at a diagonal are one cell apart under `.moore` and two apart
    /// under `.vonNeumann`, so this is the sharpest test of which taps are counted.
    @Test(.enabled(if: Snapshot.hasMetal))
    func fireCrossesACornerOnlyForTheEightCellBlock() throws {
        // A lit tree at (20,20) and a lone tree touching it at the corner, with
        // nothing orthogonally between them.
        var start = [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64)
        start[20][20] = 2
        start[21][21] = 1
        let stamps = fullStamps(start, levels: 3)
        let near = try grid(probe(.forestFire(growth: 0, lightning: 0, neighborhood: .vonNeumann),
                                  stamps: stamps), generations: 3, levels: 3)
        let corners = try grid(probe(.forestFire(growth: 0, lightning: 0, neighborhood: .moore),
                                     stamps: stamps), generations: 3, levels: 3)
        #expect(near[21][21] == 1)       // the four edge sharers never reach it
        #expect(corners[21][21] == 0)    // the block does: it caught and burned out
    }

    /// The two rates at their limits are deterministic too, and they pin which
    /// branch each state takes: every empty cell grows, and every tree catches.
    @Test(.enabled(if: Snapshot.hasMetal))
    func certainGrowthFillsTheFieldAndCertainLightningBurnsIt() throws {
        let grown = try grid(probe(.forestFire(growth: 1, lightning: 0), stamps: []),
                             generations: 2, levels: 3)
        #expect(grown.allSatisfy { $0.allSatisfy { $0 == 1 } })

        // Trees everywhere, then a strike in every one of them: all burning after
        // one step, all bare after the next.
        let forest = [[Int]](repeating: [Int](repeating: 1, count: 64), count: 64)
        let stamps = fullStamps(forest, levels: 3)
        let alight = try grid(probe(.forestFire(growth: 0, lightning: 1), stamps: stamps),
                              generations: 1, levels: 3)
        let after = try grid(probe(.forestFire(growth: 0, lightning: 1), stamps: stamps),
                             generations: 2, levels: 3)
        #expect(alight.allSatisfy { $0.allSatisfy { $0 == 2 } })
        #expect(after.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    /// A field with no lightning and no fire drawn into it can only fill up, and it
    /// starts bare rather than from seeded noise, so this also pins the rest state.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aForestWithNoLightningOnlyGrows() throws {
        let early = try grid(probe(.forestFire(growth: 0.3, lightning: 0), stamps: []),
                             generations: 1, levels: 3)
        let later = try grid(probe(.forestFire(growth: 0.3, lightning: 0), stamps: []),
                             generations: 30, levels: 3)
        let bare = early.joined().count { $0 == 0 }
        #expect(bare > 2000 && bare < 4096)          // one step in, most of it is still bare
        #expect(!early.joined().contains(2))         // and nothing is burning
        #expect(later.joined().count { $0 == 1 } > 4000)   // thirty steps in, it is a forest
        #expect(!later.joined().contains(2))
    }

    /// The point of the rule: with lightning far rarer than growth, the field neither
    /// fills up nor burns out. It settles between the two and keeps throwing fires.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theForestSettlesBetweenBareAndFull() throws {
        let field = try grid(probe(.forestFire(growth: 0.06, lightning: 0.0008), stamps: []),
                             generations: 200, levels: 3)
        let trees = Double(field.joined().count { $0 == 1 }) / 4096
        let bare = Double(field.joined().count { $0 == 0 }) / 4096
        #expect(trees > 0.1 && trees < 0.95)
        #expect(bare > 0.02)
        // A run at that ratio is never quiet for long: something is alight.
        let burning = (150 ... 200).contains { generation in
            (try? grid(probe(.forestFire(growth: 0.06, lightning: 0.0008), stamps: []),
                       generations: generation, levels: 3))?.joined().contains(2) ?? false
        }
        #expect(burning)
    }

    // MARK: Wireworld

    /// The circuit the Wireworld tests stamp, typed the way these circuits are
    /// shared: a nine-by-five ring carrying one electron, tapped from its right side
    /// into a wire that runs through a diode and on to a dead end. The ring's corners
    /// are cut by the eight-cell neighborhood, so the electron laps it in twenty.
    private static let circuit = [
        "...#tH######....................",
        "...#.......#........##..........",
        "...#.......##########.##########",
        "...#.......#........##..........",
        "...#########....................",
    ]

    private static let wireLevels: [Character: Int] = [".": 0, "#": 1, "t": 2, "H": 3]

    /// A text circuit laid onto the empty grid with its top-left corner at (x, y).
    private func wired(_ rows: [String], at x: Int, _ y: Int) -> [[Int]] {
        var grid = emptyGrid()
        for (dy, row) in rows.enumerated() {
            for (dx, ch) in row.enumerated() { grid[y + dy][x + dx] = Self.wireLevels[ch]! }
        }
        return grid
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func wireworldMatchesTheSequentialReference() throws {
        // Sixty generations of the tapped clock: three laps of the ring, three
        // electrons sent down the wire, each through the diode to the dead end.
        let start = wired(Self.circuit, at: 12, 24)
        let sketch = probe(.wireworld(), stamps: levelStamps(start, levels: 4))
        let gpu = try grid(sketch, generations: 60, levels: 4)
        var reference = start
        for _ in 0 ..< 60 { reference = stepWireworld(reference) }
        #expect(gpu == reference)
        #expect(gpu.joined().contains(3))   // the clock is still running
        #expect(gpu != start)
    }

    /// The whole machine is in one clause: a conductor fires on one or two heads and
    /// not on three. Sent the right way, the electron reaches the diode's bar as
    /// two heads and crosses the gap; sent the wrong way it lights the bar as three
    /// and stops there.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDiodePassesOneWayAndBlocksTheOther() throws {
        let forward = ["...........##..........",
                       "tH##########.##########",
                       "...........##.........."]
        // The same diode, the electron sent in from the far end.
        let reversed = ["...........##..........",
                        "############.########Ht",
                        "...........##.........."]
        let goes = try grid(probe(.wireworld(), stamps: levelStamps(wired(forward, at: 20, 30), levels: 4)),
                            generations: 20, levels: 4)
        let stops = try grid(probe(.wireworld(), stamps: levelStamps(wired(reversed, at: 20, 30), levels: 4)),
                             generations: 24, levels: 4)
        // Past the gap (column 12 of the pattern) the forward wire carries an
        // electron; the reversed wire's left half never sees one.
        let pastForward = (33 ... 42).contains { goes[31][$0] == 2 || goes[31][$0] == 3 }
        let pastReversed = (20 ... 29).contains { stops[31][$0] == 2 || stops[31][$0] == 3 }
        #expect(pastForward)
        #expect(!pastReversed)
        // And the reversed electron died at the bar: nothing is alight anywhere.
        #expect(!stops.joined().contains(3))
        #expect(!stops.joined().contains(2))
    }

    /// A ring with one electron on it is a clock, and its period is the ring's
    /// length less its four corners, which the eight-cell neighborhood lets the
    /// electron cut.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aClockRepeatsWithTheLengthOfItsLoopLessItsCorners() throws {
        let ring = ["#tH######",
                    "#.......#",
                    "#.......#",
                    "#.......#",
                    "#########"]
        let stamps = levelStamps(wired(ring, at: 20, 20), levels: 4)
        let at10 = try grid(probe(.wireworld(), stamps: stamps), generations: 10, levels: 4)
        let at20 = try grid(probe(.wireworld(), stamps: stamps), generations: 20, levels: 4)
        let at30 = try grid(probe(.wireworld(), stamps: stamps), generations: 30, levels: 4)
        #expect(at10 == at30)
        #expect(at10 != at20)
        #expect(at30.joined().count { $0 == 3 } >= 1)
    }

    /// Wire with no electron on it is still, and so is an empty field: the rule
    /// only ever moves a head.
    @Test(.enabled(if: Snapshot.hasMetal))
    func wireWithNoElectronIsStill() throws {
        let wire = ["#########", "#.......#", "#########"]
        let start = wired(wire, at: 10, 10)
        let later = try grid(probe(.wireworld(), stamps: levelStamps(start, levels: 4)),
                             generations: 20, levels: 4)
        #expect(later == start)
        let empty = try grid(probe(.wireworld(), stamps: []), generations: 20, levels: 4)
        #expect(empty.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    // MARK: Schelling

    /// A board a quarter empty, the rest an even mix of the two kinds.
    private func board(seed: UInt64) -> [[Int]] {
        var rng = LCG(seed: seed)
        return (0 ..< 64).map { _ in
            (0 ..< 64).map { _ in
                let r = rng.next(100)
                return r < 25 ? 0 : (r < 62 ? 1 : 2)
            }
        }
    }

    /// At full mobility every unhappy agent with somewhere to go moves, and the rule
    /// is fully deterministic: the block walk, the raster pairing, the content test
    /// with the mover's own cell vacated, and the board's edges all match a
    /// sequential reference cell for cell, twenty-four passes in.
    @Test(.enabled(if: Snapshot.hasMetal))
    func schellingAtFullMobilityMatchesTheSequentialReference() throws {
        let start = board(seed: 31)
        let sketch = probe(.schelling(preference: 0.3, mobility: 1, passes: 4),
                           stamps: levelStamps(start, levels: 3))
        let gpu = try grid(sketch, generations: 6, levels: 3)
        var reference = start
        for generation in 1 ... 6 {
            reference = stepSchelling(reference, generation: generation, passes: 4, preference: 0.3)
        }
        #expect(gpu == reference)
        #expect(gpu != start)
    }

    /// The other limit: at mobility 0 nobody moves, and the stamped board holds,
    /// which also pins that a full stamp overrides the seeded random start.
    @Test(.enabled(if: Snapshot.hasMetal))
    func withNoMobilityNobodyMoves() throws {
        let start = board(seed: 5)
        let later = try grid(probe(.schelling(preference: 0.5, mobility: 0),
                                   stamps: levelStamps(start, levels: 3)),
                             generations: 8, levels: 3)
        #expect(later == start)
    }

    /// A board where everyone is content is a fixed point: at a preference of 0
    /// any neighbor will do, and two kinds kept apart by an empty street never
    /// see each other.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aContentBoardIsAFixedPoint() throws {
        let mixed = board(seed: 9)
        let easy = try grid(probe(.schelling(preference: 0, mobility: 1),
                                  stamps: levelStamps(mixed, levels: 3)),
                            generations: 8, levels: 3)
        #expect(easy == mixed)

        var streets = emptyGrid()
        for y in 0 ..< 64 {
            for x in 0 ..< 64 { streets[y][x] = x < 30 ? 1 : (x > 33 ? 2 : 0) }
        }
        let apart = try grid(probe(.schelling(preference: 0.5, mobility: 1),
                                   stamps: levelStamps(streets, levels: 3)),
                             generations: 8, levels: 3)
        #expect(apart == streets)
    }

    /// The point of the model: from an even mix, a mild preference sorts the board
    /// into patches. The like share climbs well past the half it started at, and
    /// nearly everyone ends content.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBoardSortsItself() throws {
        let start = board(seed: 17)
        let sorted = try grid(probe(.schelling(preference: 0.3, mobility: 1),
                                    stamps: levelStamps(start, levels: 3)),
                              generations: 12, levels: 3)
        let before = likeShare(start), after = likeShare(sorted)
        #expect(before.share > 0.45 && before.share < 0.55)
        #expect(after.share > 0.62)
        #expect(after.unhappy < 0.05)
        // Nobody was lost or made: the counts of each kind are what they were.
        for kind in 0 ... 2 {
            #expect(sorted.joined().count { $0 == kind } == start.joined().count { $0 == kind })
        }
    }

    /// The seeded start honors the vacancy asked for, and splits the rest evenly.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSeededStartHoldsTheVacancyAsked() throws {
        let quarter = try grid(probe(.schelling(vacancy: 0.25, mobility: 0), stamps: []),
                               generations: 1, levels: 3)
        let empties = Double(quarter.joined().count { $0 == 0 }) / 4096
        let first = Double(quarter.joined().count { $0 == 1 }) / 4096
        let second = Double(quarter.joined().count { $0 == 2 }) / 4096
        #expect(empties > 0.21 && empties < 0.29)
        #expect(first > 0.33 && first < 0.42)
        #expect(second > 0.33 && second < 0.42)

        let full = try grid(probe(.schelling(vacancy: 0, mobility: 0), stamps: []),
                            generations: 1, levels: 3)
        #expect(!full.joined().contains(0))
        let bare = try grid(probe(.schelling(vacancy: 1, mobility: 0), stamps: []),
                            generations: 1, levels: 3)
        #expect(bare.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    /// The mean share of like neighbors over the agents that have any, and the
    /// share of agents unhappy at a preference of 0.3.
    private func likeShare(_ g: [[Int]]) -> (share: Double, unhappy: Double) {
        var total = 0.0, counted = 0.0, unhappy = 0.0, agents = 0.0
        for y in 0 ..< 64 {
            for x in 0 ..< 64 where g[y][x] > 0 {
                agents += 1
                var like = 0.0, occupied = 0.0
                for dy in -1 ... 1 {
                    for dx in -1 ... 1 where !(dx == 0 && dy == 0) {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < 64, ny < 64, g[ny][nx] > 0 else { continue }
                        occupied += 1
                        if g[ny][nx] == g[y][x] { like += 1 }
                    }
                }
                if occupied > 0 { total += like / occupied; counted += 1 }
                if like < 0.3 * occupied { unhappy += 1 }
            }
        }
        return (total / max(1, counted), unhappy / max(1, agents))
    }

    // MARK: Probes and readback

    private func probe(_ sim: Sim, stamps: [(x: Int, y: Int, white: Double)])
    -> AutomatonProbeSketch {
        let sketch = AutomatonProbeSketch()
        sketch.probeSim = sim
        sketch.stamps = stamps
        return sketch
    }

    /// Every texel stamped with its wanted state, as an sRGB gray that lands on
    /// the state's linear level.
    private func fullStamps(_ grid: [[Int]], levels: Int) -> [(x: Int, y: Int, white: Double)] {
        var stamps: [(x: Int, y: Int, white: Double)] = []
        for y in 0 ..< 64 {
            for x in 0 ..< 64 {
                stamps.append((x: x, y: y,
                               white: srgb(Double(grid[y][x]) / Double(levels - 1))))
            }
        }
        return stamps
    }

    /// Every texel stamped with its wanted state as the plain gray of that level,
    /// for the rules whose injects snap a mark in sRGB terms (`WireworldCell` and
    /// `SchellingCell` name these same grays).
    private func levelStamps(_ grid: [[Int]], levels: Int) -> [(x: Int, y: Int, white: Double)] {
        var stamps: [(x: Int, y: Int, white: Double)] = []
        for y in 0 ..< 64 {
            for x in 0 ..< 64 {
                stamps.append((x: x, y: y, white: Double(grid[y][x]) / Double(levels - 1)))
            }
        }
        return stamps
    }

    /// The rendered field decoded back to integer states: each texel's red byte
    /// matched to the nearest expected level. The levels used by these tests sit
    /// tens of bytes apart, so the present pass's ±1 dither cannot flip one.
    /// The headless drive renders draws 0...frame inclusive and the sim steps once
    /// per draw, so a probe read at `frame: g - 1` holds exactly `g` generations
    /// past its frame-1 stamp.
    private func grid(_ sketch: Sketch, generations: Int, levels: Int) throws -> [[Int]] {
        let image = try #require(OllinApp.image(of: sketch, frame: generations - 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let bytes = (0 ..< levels).map { Int((srgb(Double($0) / Double(levels - 1)) * 255).rounded()) }
        return (0 ..< h).map { y in
            (0 ..< w).map { x in
                let v = Int(data[(y * w + x) * 4])
                return bytes.indices.min(by: { abs(bytes[$0] - v) < abs(bytes[$1] - v) })!
            }
        }
    }

    /// Linear light → the sRGB curve (the standard piecewise transfer), used both
    /// to pick a stamp's gray and to predict a level's readback byte.
    private func srgb(_ l: Double) -> Double {
        l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    // MARK: Sequential references (toroidal, like the shader)

    private func emptyGrid() -> [[Int]] {
        [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64)
    }

    private func randomGrid(levels: Int, seed: UInt64) -> [[Int]] {
        var rng = LCG(seed: seed)
        return (0 ..< 64).map { _ in (0 ..< 64).map { _ in rng.next(levels) } }
    }

    /// The neighborhood's offsets: the block within `range`, or the diamond.
    private func offsets(range: Int, moore: Bool) -> [(Int, Int)] {
        var list: [(Int, Int)] = []
        for dy in -range ... range {
            for dx in -range ... range where !(dx == 0 && dy == 0) {
                if moore || abs(dx) + abs(dy) <= range { list.append((dx, dy)) }
            }
        }
        return list
    }

    /// The forest fire with both rates at zero: a burning cell empties, a tree with
    /// a burning neighbor catches, and nothing else moves.
    private func stepForestFire(_ g: [[Int]], moore: Bool) -> [[Int]] {
        let taps = offsets(range: 1, moore: moore)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                let s = g[y][x]
                if s == 2 { return 0 }
                if s == 0 { return 0 }
                let alight = taps.contains { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == 2 }
                return alight ? 2 : 1
            }
        }
    }

    private func stepCyclic(_ g: [[Int]], states: Int, threshold: Int,
                            range: Int, moore: Bool) -> [[Int]] {
        let taps = offsets(range: range, moore: moore)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                let next = (g[y][x] + 1) % states
                let count = taps.count { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == next }
                return count >= threshold ? next : g[y][x]
            }
        }
    }

    private func stepExcitable(_ g: [[Int]], states: Int, threshold: Int,
                               range: Int, moore: Bool) -> [[Int]] {
        let taps = offsets(range: range, moore: moore)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                let s = g[y][x]
                if s == 0 {
                    let firing = taps.count { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == 1 }
                    return firing >= threshold ? 1 : 0
                }
                return (s + 1) % states
            }
        }
    }

    /// 0 ready, 1 resting, 2 firing.
    private func stepBrain(_ g: [[Int]]) -> [[Int]] {
        let taps = offsets(range: 1, moore: true)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                switch g[y][x] {
                case 2: return 1
                case 1: return 0
                default:
                    let firing = taps.count { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == 2 }
                    return firing == 2 ? 2 : 0
                }
            }
        }
    }

    private func stepHodgepodge(_ g: [[Int]], n: Int, k1: Int, k2: Int,
                                g growth: Int, moore: Bool) -> [[Int]] {
        let taps = offsets(range: 1, moore: moore)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                let s = g[y][x]
                var infected = 0, ill = 0, sum = s
                for (dx, dy) in taps {
                    let v = g[(y + dy + 64) % 64][(x + dx + 64) % 64]
                    sum += v
                    if v == n { ill += 1 } else if v > 0 { infected += 1 }
                }
                let ns: Int
                if s == 0 { ns = infected / k1 + ill / k2 }
                else if s == n { ns = 0 }
                else { ns = sum / (infected + 1) + growth }
                return min(ns, n)
            }
        }
    }

    /// Wireworld: 0 empty, 1 conductor, 2 tail, 3 head. A head becomes a tail, a
    /// tail conductor, and a conductor a head on exactly one or two head neighbors.
    private func stepWireworld(_ g: [[Int]]) -> [[Int]] {
        let taps = offsets(range: 1, moore: true)
        return (0 ..< 64).map { y in
            (0 ..< 64).map { x in
                switch g[y][x] {
                case 3: return 2
                case 2: return 1
                case 1:
                    let heads = taps.count { g[(y + $0.1 + 64) % 64][(x + $0.0 + 64) % 64] == 3 }
                    return (heads == 1 || heads == 2) ? 3 : 1
                default: return 0
                }
            }
        }
    }

    /// One generation of Schelling's board at full mobility: `passes` passes over
    /// the 8x8 block tiling, the block origin walking half a block in x every pass
    /// and in y every second pass, with the pass count running on from the field's
    /// age (the stamp lands on the field's second frame, so generation k after it
    /// runs passes k * passes ... k * passes + passes - 1). Within a block the
    /// unhappy agents, in raster order, each take the first free empty cell where
    /// they would be content with their own cell vacated, else the first free empty
    /// cell. The board has edges: off it nobody lives.
    private func stepSchelling(_ g: [[Int]], generation: Int, passes: Int, preference: Float) -> [[Int]] {
        var g = g
        for i in 0 ..< passes { g = schellingPass(g, pass: generation * passes + i, preference: preference) }
        return g
    }

    private func schellingPass(_ g: [[Int]], pass: Int, preference: Float) -> [[Int]] {
        var out = g
        let ox = (pass % 2) * 4, oy = ((pass / 2) % 2) * 4
        func at(_ x: Int, _ y: Int) -> Int { (x < 0 || y < 0 || x >= 64 || y >= 64) ? -1 : g[y][x] }
        func content(_ x: Int, _ y: Int, kind: Int, skip: (Int, Int)?) -> Bool {
            var like: Float = 0, occupied: Float = 0
            for dy in -1 ... 1 {
                for dx in -1 ... 1 where !(dx == 0 && dy == 0) {
                    let nx = x + dx, ny = y + dy
                    if let s = skip, s.0 == nx, s.1 == ny { continue }
                    let v = at(nx, ny)
                    if v > 0 {
                        occupied += 1
                        if v == kind { like += 1 }
                    }
                }
            }
            return like >= preference * occupied
        }
        var by = oy - 8
        while by < 64 {
            var bx = ox - 8
            while bx < 64 {
                var movers: [(Int, Int)] = [], holes: [(Int, Int)] = []
                for y in by ..< by + 8 {
                    for x in bx ..< bx + 8 {
                        let v = at(x, y)
                        if v > 0 && !content(x, y, kind: v, skip: nil) { movers.append((x, y)) }
                        if v == 0 { holes.append((x, y)) }
                    }
                }
                var taken = [Bool](repeating: false, count: holes.count)
                for (mx, my) in movers {
                    let kind = g[my][mx]
                    var pick = holes.indices.first {
                        !taken[$0] && content(holes[$0].0, holes[$0].1, kind: kind, skip: (mx, my))
                    }
                    if pick == nil { pick = holes.indices.first { !taken[$0] } }
                    guard let p = pick else { break }
                    taken[p] = true
                    out[holes[p].1][holes[p].0] = kind
                    out[my][mx] = 0
                }
                bx += 8
            }
            by += 8
        }
        return out
    }
}

/// A tiny deterministic generator for the reference grids (no wall clock, no
/// process state, so a rerun stamps the same start).
private struct LCG {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}

/// A 64-texel automaton field stamped once, on frame 1, with full-texel unit
/// rects (abutting fills tile seamlessly, so every stamped texel reads exactly
/// its gray), then left to evolve and drawn 1:1.
@MainActor
private final class AutomatonProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    var probeSim: Sim = .gameOfLife()
    var stamps: [(x: Int, y: Int, white: Double)] = []

    private var field: SimField!

    override func setup() {
        field = makeSimField(probeSim, scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {
            if frameCount == 1 {
                noStroke()
                for s in stamps {
                    fill(Color(white: s.white))
                    // A polygon, not a drawRect: the polygon renders on the
                    // triangle path, whose MSAA coverage is purely geometric, so
                    // the stamped texel resolves to alpha 1 and its neighbors to
                    // exactly 0. An SDF rect's analytic halo is about one render
                    // pixel wide, which at one texel per pixel leaves the
                    // edge-adjacent texels hovering right at the injects' 0.5
                    // alpha gate.
                    let x = Double(s.x), y = Double(s.y)
                    drawPolygon([Vector2(x, y), Vector2(x + 1, y),
                                 Vector2(x + 1, y + 1), Vector2(x, y + 1)])
                }
            }
        }
        drawImage(field.image, 0, 0)
    }
}
