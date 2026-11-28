import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// The collision pass's own grid: it offers every pair of disks that touch,
/// each once, whatever the mix of sizes; a pile of one size is offered the
/// pairs a single grid offers, in that grid's order; and what a small disk
/// costs does not grow with the largest disk in the world.
@Suite("The disk collision pass")
struct DiskPassTests {

    struct Disk {
        var x: Double, y: Double, radius: Double
    }

    /// `count` disks over a square `span` wide around `center`.
    static func scatter(count: Int, seed: UInt64, span: Double = 600, center: Double = 300,
                        radius: (inout SplitMix64) -> Double) -> [Disk] {
        var rng = SplitMix64(seed: seed)
        return (0 ..< count).map { _ in
            let r = radius(&rng)
            return Disk(x: center + Double.random(in: -0.5 ..< 0.5, using: &rng) * span,
                        y: center + Double.random(in: -0.5 ..< 0.5, using: &rng) * span, radius: r)
        }
    }

    static func pass(over disks: [Disk]) -> DiskPass {
        var pass = DiskPass()
        for (index, disk) in disks.enumerated() {
            pass.add(x: disk.x, y: disk.y, radius: disk.radius, weight: 1, index: index)
        }
        pass.build()
        return pass
    }

    /// Every pair that overlaps, by comparing each disk with every other.
    static func touching(_ disks: [Disk]) -> Set<[Int]> {
        var pairs = Set<[Int]>()
        for i in disks.indices {
            for j in disks.indices where j > i {
                let dx = disks[j].x - disks[i].x, dy = disks[j].y - disks[i].y
                let reach = disks[i].radius + disks[j].radius
                if dx * dx + dy * dy < reach * reach { pairs.insert([i, j]) }
            }
        }
        return pairs
    }

    /// The pairs a single grid as wide as the largest disk offers, in the
    /// order it offers them: disks by index, the nine cells around each in a
    /// fixed scan, a cell's disks by index, the higher index only.
    static func singleGridPairs(_ disks: [Disk]) -> [[Int]] {
        struct Cell: Hashable { var x: Int, y: Int }
        let size = (disks.map(\.radius).max() ?? 0) * 2
        var grid: [Cell: [Int]] = [:]
        for (i, disk) in disks.enumerated() {
            grid[Cell(x: Int((disk.x / size).rounded(.down)), y: Int((disk.y / size).rounded(.down))), default: []].append(i)
        }
        var pairs: [[Int]] = []
        for (i, disk) in disks.enumerated() {
            let cx = Int((disk.x / size).rounded(.down)), cy = Int((disk.y / size).rounded(.down))
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    for j in grid[Cell(x: cx + dx, y: cy + dy)] ?? [] where j > i { pairs.append([i, j]) }
                }
            }
        }
        return pairs
    }

    static let mixes: [(name: String, disks: [Disk])] = [
        ("one size", scatter(count: 900, seed: 1) { _ in 7 }),
        ("nearly one size", scatter(count: 900, seed: 2) { rng in Double.random(in: 5 ..< 9, using: &rng) }),
        ("3 to 60, mostly small", scatter(count: 900, seed: 3) { rng in 3 + 57 * pow(Double.random(in: 0 ..< 1, using: &rng), 6) }),
        ("two sizes, half and half", scatter(count: 900, seed: 4) { rng in Bool.random(using: &rng) ? 2 : 37 }),
        ("every size from 0.01 to 80", scatter(count: 900, seed: 5) { rng in 0.01 * pow(8000, Double.random(in: 0 ..< 1, using: &rng)) }),
        ("far from the origin, on both sides of it", scatter(count: 900, seed: 6, span: 900, center: -1.0e7) { rng in
            Double.random(in: 4 ..< 30, using: &rng)
        }),
        ("across the axes", scatter(count: 900, seed: 7, span: 500, center: 0) { rng in Double.random(in: 2 ..< 25, using: &rng) }),
        ("one huge disk over many small ones", scatter(count: 899, seed: 8) { _ in 3 } + [Disk(x: 300, y: 300, radius: 2000)]),
        ("smaller than the finest level reaches", scatter(count: 300, seed: 9, span: 4) { _ in 1.0e-11 } + [Disk(x: 300, y: 300, radius: 40)])
    ]

    @Test("Every pair of disks that touch is offered, once, the lower index first",
          arguments: mixes.indices)
    func everyTouchingPairOnce(mix: Int) {
        let (name, disks) = Self.mixes[mix]
        var pass = Self.pass(over: disks)
        let offered = pass.candidatePairs()
        var seen = Set<[Int]>()
        for (i, j) in offered {
            #expect(i < j, "\(name): a pair came higher index first")
            #expect(seen.insert([i, j]).inserted, "\(name): the pair \(i), \(j) was offered twice")
        }
        let touching = Self.touching(disks)
        #expect(!touching.isEmpty, "\(name): nothing touches, so this proved nothing")
        let missed = touching.subtracting(seen)
        #expect(missed.isEmpty, "\(name): \(missed.count) of \(touching.count) touching pairs were never offered")
    }

    @Test("A pile within a factor of two of its largest disk is offered a single grid's pairs, in its order",
          arguments: [0, 1])
    func oneLevelIsTheSingleGrid(mix: Int) {
        let (name, disks) = Self.mixes[mix]
        var pass = Self.pass(over: disks)
        let offered = pass.candidatePairs().map { [$0.0, $0.1] }
        #expect(offered == Self.singleGridPairs(disks), "\(name)")
    }

    @Test("A large disk filed under a small one's cell numbers, in its bucket, is offered once")
    func twoLevelsSharingACellNumberAndABucket() throws {
        // Two disks make a table of sixteen buckets. Find a level whose cell
        // (cx, cy) lands in the bucket the coarsest level's cell of the same
        // numbers lands in: there the bucket and the cell numbers both match,
        // and only the level tells the two entries apart.
        var found: (level: Int, cx: Int64, cy: Int64)?
        search: for level in 1 ... DiskPass.finestLevel {
            for cx in [Int64(0), -1] {
                for cy in [Int64(0), -1] where DiskPass.bucket(0, cx, cy, bits: 4) == DiskPass.bucket(level, cx, cy, bits: 4) {
                    found = (level, cx, cy)
                    break search
                }
            }
        }
        let (level, cx, cy) = try #require(found, "no level shares a bucket with the coarsest one at these cells")
        let large = 64.0, top = 128.0
        let fine = top / pow(2, Double(level))
        let disks = [
            Disk(x: (Double(cx) + 0.5) * fine, y: (Double(cy) + 0.5) * fine, radius: large / pow(2, Double(level))),
            Disk(x: (Double(cx) + 0.5) * top, y: (Double(cy) + 0.5) * top, radius: large)
        ]
        var pass = Self.pass(over: disks)
        #expect(pass.tableBits == 4)
        #expect(Int(pass.disks[0].level) == level && pass.disks[1].level == 0)
        #expect(pass.disks[0].cellX == pass.disks[1].cellX && pass.disks[0].cellY == pass.disks[1].cellY)
        let offered = pass.candidatePairs().map { [$0.0, $0.1] }
        #expect(offered == [[0, 1]], "the pair was offered as \(offered)")
    }

    @Test("A small disk's cost does not grow with the largest disk")
    func aHugeDiskCostsTheSmallOnesNothing() {
        let small = Self.scatter(count: 2000, seed: 21) { _ in 3 }
        var alone = Self.pass(over: small)
        var beside = Self.pass(over: small + [Disk(x: 300, y: 300, radius: 2000)])
        let before = alone.candidatePairs().count
        let after = beside.candidatePairs().count
        // The huge disk touches every small one, and those 2,000 pairs are
        // what it adds. The small ones' own cells are sized from the largest
        // disk by halving, so beside it they are up to twice as wide as they
        // were alone and hold up to four times the pairs, and no more. A
        // single grid as wide as the huge disk offers every pair of the 2,001.
        let amongTheSmall = after - small.count
        #expect(amongTheSmall <= 4 * before, "\(amongTheSmall) pairs among the small disks beside the huge one, \(before) alone")
        #expect(after < 6 * small.count, "\(after) pairs for \(small.count) small disks and a huge one")
        #expect(Self.singleGridPairs(small + [Disk(x: 300, y: 300, radius: 2000)]).count == 2001 * 2000 / 2)
    }

    @Test("A mixed pile is offered a small multiple of its disks, where a single grid offers hundreds each")
    func mixedSizesStayCheap() {
        let disks = Self.scatter(count: 900, seed: 31, span: 1500) { rng in 3 + 57 * pow(Double.random(in: 0 ..< 1, using: &rng), 6) }
        var pass = Self.pass(over: disks)
        let offered = pass.candidatePairs().count
        let single = Self.singleGridPairs(disks).count
        // Measured: 3,150 pairs offered for 900 disks (448 of them touch),
        // where a single grid as wide as the largest disk offers 20,314.
        #expect(offered < 5 * disks.count, "\(offered) pairs for \(disks.count) disks, touching \(Self.touching(disks).count)")
        #expect(single > 5 * offered, "a single grid offered \(single) against \(offered)")
    }

    @Test("Overlapping disks of very different sizes are pushed apart")
    func aSmallDiskLeavesALargeOne() {
        let world = World()
        world.gravity = .zero
        world.particlesCollide = true
        let large = world.addParticle(at: Vector2(0, 0), radius: 200).pin()
        let small = world.addParticle(at: Vector2(150, 0), radius: 2)
        for _ in 0 ..< 30 { world.advance(by: 1.0 / 60) }
        #expect(small.position.distance(to: large.position) >= 202 - 0.5)
        #expect(large.position == .zero)
    }

    @Test("A position that is not a number traps nothing and the rest still separate")
    func aBrokenPositionIsSurvived() {
        let world = World()
        world.gravity = .zero
        world.particlesCollide = true
        let a = world.addParticle(at: Vector2(0, 0), radius: 10)
        let b = world.addParticle(at: Vector2(8, 0), radius: 10)
        world.addParticle(at: Vector2(.nan, 4), radius: 6)
        world.addParticle(at: Vector2(.infinity, -.infinity), radius: 3)
        world.addParticle(at: Vector2(1.0e300, -1.0e300), radius: 0.001)
        for _ in 0 ..< 40 { world.advance(by: 1.0 / 60) }
        #expect(a.position.distance(to: b.position) >= 20 - 0.5)
    }

    @Test("A disk of unbounded radius traps nothing")
    func anUnboundedRadiusIsSurvived() {
        let world = World()
        world.gravity = .zero
        world.particlesCollide = true
        world.addParticle(at: Vector2(0, 0), radius: 10)
        world.addParticle(at: Vector2(8, 0), radius: .infinity).pin()
        for _ in 0 ..< 3 { world.advance(by: 1.0 / 60) }
    }
}

/// Removing many particles, or many springs, in one call leaves the world as
/// the same removals made one at a time leave it.
@Suite("Removing many at once")
struct BatchRemovalTests {

    /// A world with loose disks, a chain of springs over some of them, and a
    /// soft body, built the same way on every call.
    static func world() throws -> World {
        let world = World()
        world.gravity = .zero
        var rng = SplitMix64(seed: 5)
        for _ in 0 ..< 60 {
            world.addParticle(at: Vector2(Double.random(in: 0 ..< 400, using: &rng), Double.random(in: 0 ..< 400, using: &rng)),
                              radius: Double.random(in: 2 ..< 9, using: &rng))
        }
        for i in 0 ..< 40 { world.connect(world.particles[i], world.particles[i + 7]) }
        let ring = Shape(contours: [Circle(center: Vector2(700, 200), radius: 60).contour(segments: 24)])
        let body = try world.addSoftBody(from: ring, spacing: 20)
        // A spring from a loose particle to the soft body, which goes with
        // whichever end leaves.
        world.connect(world.particles[3], body.particles[0])
        for _ in 0 ..< 10 {
            world.addParticle(at: Vector2(Double.random(in: 0 ..< 400, using: &rng), 500))
        }
        return world
    }

    /// What is left of a world, by where each thing sat when it was built:
    /// the particles' places in the original list, and each spring's ends.
    static func remains(of world: World, against original: [Particle]) -> (particles: [Int], springs: [[Int]], bodies: Int) {
        var place: [ObjectIdentifier: Int] = [:]
        for (index, particle) in original.enumerated() { place[ObjectIdentifier(particle)] = index }
        return (world.particles.map { place[ObjectIdentifier($0)] ?? -1 },
                world.springs.map { [place[ObjectIdentifier($0.a)] ?? -1, place[ObjectIdentifier($0.b)] ?? -1] },
                world.softBodies.count)
    }

    static let picks: [(name: String, indices: [Int])] = [
        ("loose particles", [0, 5, 6, 12, 30, 59]),
        ("one of a soft body's particles", [2, 62, 40]),
        ("a soft body named twice and a particle named twice", [61, 64, 9, 9, 70]),
        ("every particle", Array(0 ..< 200)),
        ("none", [])
    ]

    @Test("Removing a list of particles equals removing each in turn", arguments: picks.indices)
    func aListEqualsEachInTurn(pick: Int) throws {
        let (name, indices) = Self.picks[pick]
        let together = try Self.world(), inTurn = try Self.world()
        let originalTogether = together.particles, originalInTurn = inTurn.particles
        #expect(originalTogether.count == originalInTurn.count)
        let valid = indices.filter { $0 < originalTogether.count }

        together.remove(valid.map { originalTogether[$0] })
        for index in valid { inTurn.remove(originalInTurn[index]) }

        let a = Self.remains(of: together, against: originalTogether)
        let b = Self.remains(of: inTurn, against: originalInTurn)
        #expect(a.particles == b.particles, "\(name)")
        #expect(a.springs == b.springs, "\(name)")
        #expect(a.bodies == b.bodies, "\(name)")
        if !valid.isEmpty {
            #expect(a.particles.count < originalTogether.count, "\(name): nothing left the world")
        }
    }

    @Test("A particle of another world takes its springs here and nothing else")
    func aStrangerIsHarmless() throws {
        let world = try Self.world(), other = World()
        let stranger = other.addParticle(at: .zero)
        let spring = world.connect(world.particles[0], stranger)
        let particles = world.particles.count, springs = world.springs.count
        world.remove([stranger])
        #expect(world.particles.count == particles)
        #expect(world.springs.count == springs - 1)
        #expect(!world.springs.contains { $0 === spring })
    }

    @Test("Removing a list of springs equals removing each in turn")
    func springsTogether() throws {
        let together = try Self.world(), inTurn = try Self.world()
        let picked = [0, 3, 3, 17, 39]
        let springsTogether = together.springs, springsInTurn = inTurn.springs
        together.remove(picked.map { springsTogether[$0] })
        for index in picked { inTurn.remove(springsInTurn[index]) }
        let a = Self.remains(of: together, against: together.particles)
        let b = Self.remains(of: inTurn, against: inTurn.particles)
        #expect(a.springs == b.springs)
        #expect(together.springs.count == springsTogether.count - 4)
        #expect(together.particles.count == inTurn.particles.count)
        together.remove([Spring]())
        #expect(together.springs.count == springsTogether.count - 4)
    }
}
