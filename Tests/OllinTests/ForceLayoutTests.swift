import Ollin
import Testing

/// Pure-CPU checks on `ForceLayout`: the layout is deterministic, cools to a
/// standstill, spaces a ring's edges evenly, respects pins and the frame, and
/// keeps non-neighbors apart. No GPU.
@Suite
struct ForceLayoutTests {
    private let frame = Rectangle(x: 0, y: 0, width: 400, height: 400)

    /// A cycle of `n` nodes, the graph whose settled form is unambiguous.
    private func ring(_ n: Int, seed: UInt64 = 3) -> ForceLayout {
        ForceLayout(count: n, edges: (0 ..< n).map { ($0, ($0 + 1) % n) },
                    in: frame, seed: seed)
    }

    private func edgeLengths(_ layout: ForceLayout) -> [Double] {
        layout.edges.map { layout.positions[$0.a].distance(to: layout.positions[$0.b]) }
    }

    /// The same seed replays the same run, step for step.
    @Test func sameSeedReplaysExactly() {
        let a = ring(24, seed: 11)
        let b = ring(24, seed: 11)
        a.step(80)
        b.step(80)
        #expect(a.positions == b.positions)
        a.settle()
        b.settle()
        #expect(a.positions == b.positions)
    }

    /// A different seed starts differently.
    @Test func differentSeedsDiffer() {
        let a = ring(24, seed: 1)
        let b = ring(24, seed: 2)
        #expect(a.positions != b.positions)
    }

    /// Cooling reaches zero, and a settled layout stops moving entirely.
    @Test func settledMeansFrozen() {
        let layout = ring(16)
        layout.settle()
        #expect(layout.isSettled)
        let before = layout.positions
        layout.step(10)
        #expect(layout.positions == before)
    }

    /// A settled ring's edges come out nearly uniform: the even-edge-length
    /// aesthetic the forces exist to produce.
    @Test func ringSettlesToUniformEdges() {
        let layout = ring(24)
        layout.settle()
        let lengths = edgeLengths(layout)
        let mean = lengths.reduce(0, +) / Double(lengths.count)
        #expect(mean > 10)
        for length in lengths {
            #expect(abs(length - mean) / mean < 0.15)
        }
    }

    /// Every node stays inside the frame through the whole run.
    @Test func nodesStayInBounds() {
        let layout = ring(40, seed: 9)
        for _ in 0 ..< 60 {
            layout.step()
            for p in layout.positions {
                #expect(p.x >= frame.x && p.x <= frame.x + frame.width)
                #expect(p.y >= frame.y && p.y <= frame.y + frame.height)
            }
        }
    }

    /// A pinned node never moves, while the rest of the graph does.
    @Test func pinnedNodeHolds() {
        let layout = ring(12, seed: 4)
        let anchor = layout.positions[0]
        layout.pinned[0] = true
        layout.step(120)
        #expect(layout.positions[0] == anchor)
        #expect(layout.positions[1] != anchor)
    }

    /// Repulsion keeps unconnected nodes from ending up on top of each
    /// other: the settled minimum pair distance is a healthy fraction of the
    /// ideal distance.
    @Test func repulsionKeepsNodesApart() {
        let layout = ForceLayout(count: 20, edges: [], in: frame, seed: 6)
        layout.settle()
        var minimum = Double.infinity
        for i in 0 ..< layout.count - 1 {
            for j in (i + 1) ..< layout.count {
                minimum = min(minimum, layout.positions[i].distance(to: layout.positions[j]))
            }
        }
        #expect(minimum > layout.idealDistance * 0.3)
    }

    /// Two coincident nodes part instead of dividing by zero, and the tie
    /// breaks the same way every run.
    @Test func coincidentNodesPart() {
        let make: () -> ForceLayout = {
            let layout = ForceLayout(positions: [Vector2(200, 200), Vector2(200, 200)],
                                     edges: [], in: self.frame)
            layout.step(40)
            return layout
        }
        let a = make()
        let b = make()
        #expect(a.positions[0].distance(to: a.positions[1]) > 1)
        #expect(a.positions == b.positions)
    }

    /// Growing the graph keeps the arrays in step, and a reheat lets the
    /// layout absorb the newcomer.
    @Test func growingKeepsArraysInStep() {
        let layout = ring(8)
        layout.settle()
        let i = layout.addNode(at: frame.center)
        layout.connect(0, i)
        #expect(layout.count == 9)
        #expect(layout.pinned.count == 9)
        #expect(layout.isSettled)
        layout.reheat(0.3)
        #expect(!layout.isSettled)
        let before = layout.positions[i]
        layout.step(30)
        #expect(layout.positions[i] != before)
    }

    /// Gravity pulls a disconnected pair off the walls and toward the
    /// middle, compared to the same run without it.
    @Test func gravityCentersDisconnectedPieces() {
        let loose = ForceLayout(count: 2, edges: [], in: frame, seed: 5)
        loose.settle()
        let held = ForceLayout(count: 2, edges: [], in: frame, seed: 5)
        held.gravity = 0.6
        held.settle()
        let center = frame.center
        let looseSpread = loose.positions.map { $0.distance(to: center) }.reduce(0, +)
        let heldSpread = held.positions.map { $0.distance(to: center) }.reduce(0, +)
        #expect(heldSpread < looseSpread)
    }

    /// `nearestNode` picks the closest node; an empty layout returns nil.
    @Test func nearestNodeFinds() {
        let layout = ForceLayout(positions: [Vector2(10, 10), Vector2(300, 300)],
                                 edges: [], in: frame)
        #expect(layout.nearestNode(to: Vector2(0, 0)) == 0)
        #expect(layout.nearestNode(to: Vector2(280, 310)) == 1)
        let empty = ForceLayout(count: 0, in: frame)
        #expect(empty.nearestNode(to: .zero) == nil)
    }
}
