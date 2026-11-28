import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// A seeded pile of colliding disks, settled and read back as one number, so
/// a change to which pairs the collision pass resolves, or in what order,
/// shows as a different number.
enum DiskPile {

    /// `count` disks dropped into a box under gravity, their radii drawn by
    /// `radius`, stepped `steps` times at a sixtieth of a second.
    static func settled(count: Int, seed: UInt64, steps: Int = 180,
                        radius: (inout SplitMix64) -> Double) -> World {
        var rng = SplitMix64(seed: seed)
        let world = World()
        world.gravity = Vector2(0, 900)
        world.particlesCollide = true
        world.iterations = 4
        world.bounds = Rectangle(x: 0, y: 0, width: 600, height: 600)
        for _ in 0 ..< count {
            let r = radius(&rng)
            let x = Double.random(in: 0 ..< 600, using: &rng)
            let y = Double.random(in: 0 ..< 600, using: &rng)
            world.addParticle(at: Vector2(x, y), radius: r, mass: r * r)
        }
        for _ in 0 ..< steps { world.advance(by: 1.0 / 60) }
        return world
    }

    /// Every position's bits folded into one number (FNV-1a over the words).
    static func digest(_ world: World) -> UInt64 {
        var digest: UInt64 = 0xcbf2_9ce4_8422_2325
        for particle in world.particles {
            for bits in [particle.position.x.bitPattern, particle.position.y.bitPattern] {
                digest = (digest ^ bits) &* 0x0000_0100_0000_01b3
            }
        }
        return digest
    }

    static func oneSize() -> World { settled(count: 400, seed: 11) { _ in 9 } }

    static func nearlyOneSize() -> World {
        settled(count: 400, seed: 12) { rng in Double.random(in: 6 ..< 11, using: &rng) }
    }

    /// Radii from 3 to 60, most of them small.
    static func mixed() -> World {
        settled(count: 400, seed: 13) { rng in
            3 + 57 * pow(Double.random(in: 0 ..< 1, using: &rng), 6)
        }
    }
}

@Suite("A settled pile of disks")
struct DiskPileTests {

    // A single grid as wide as the largest disk, kept in a dictionary of
    // cells, settles these two piles on these numbers. A pile whose disks are
    // all within a factor of two of the largest has one level, which is that
    // grid with that grid's order, so it must settle on the same bits.
    @Test("A pile of one size settles where it always did")
    func oneSizeKeepsItsBits() {
        let digest = DiskPile.digest(DiskPile.oneSize())
        #expect(digest == 0x7cc3_ab8e_1320_2cbd, "the pile settled on \(String(digest, radix: 16))")
    }

    @Test("A pile of nearly one size settles where it always did")
    func nearlyOneSizeKeepsItsBits() {
        let digest = DiskPile.digest(DiskPile.nearlyOneSize())
        #expect(digest == 0x5def_0a98_58c7_faed, "the pile settled on \(String(digest, radix: 16))")
    }

    // A fixed number, so a second process and another machine are held to it
    // as well as a second run. Mixed sizes are where the several cell sizes
    // and a single grid take the pairs in different orders: a single grid
    // settles this pile on 95fb92021cc90cf4.
    @Test("A pile of mixed sizes settles the same on every run")
    func mixedSizesRepeat() {
        let first = DiskPile.digest(DiskPile.mixed())
        let second = DiskPile.digest(DiskPile.mixed())
        #expect(first == second, "two runs in one process settled apart")
        #expect(first == 0xbea3_4098_1e0e_568a, "the pile settled on \(String(first, radix: 16))")
    }
}
