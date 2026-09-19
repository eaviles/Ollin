import Foundation
import Ollin
@testable import OllinPhysics
import Testing

/// Worlds built and torn down from several threads at once.
///
/// The rigid solver keeps its worlds in one process-global table, and it is the
/// only piece of state a `World` does not own outright: claiming a free slot and
/// giving one back are both reads and writes of that table. Two threads doing it
/// at the same moment can walk away holding the same slot, and then the first
/// teardown invalidates the other one's handle while it is still in use, which
/// ends the whole process rather than one test. A sketch builds its world on the
/// main thread, so this is the test suite's own shape: several suites, each with
/// worlds of its own, running side by side.
@Suite
struct WorldSlotTests {

    /// Many threads, each building a world, working it, and letting it go, over
    /// and over. Every world must stay its own: a body dropped in one lands
    /// where that world's gravity says, whatever the neighbors are doing.
    @Test func worldsBuiltAtTheSameMomentStayTheirOwn() {
        let threads = 8
        let rounds = 40
        let landed = OSAllocatedUnfairLockBox()

        DispatchQueue.concurrentPerform(iterations: threads) { _ in
            for _ in 0 ..< rounds {
                let world = World()
                world.gravity = Vector2(0, 1000)
                let body = world.addBody(.circle(radius: 10), at: Vector2(0, 0))
                for _ in 0 ..< 10 { world.advance(by: 1.0 / 60) }
                if body.position.y > 0 { landed.increment() }
            }
        }

        #expect(landed.value == threads * rounds)
    }
}

/// A counter several threads share, so the test's own bookkeeping is not the
/// thing that races.
private final class OSAllocatedUnfairLockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
