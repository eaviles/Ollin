import Ollin

/// A network laying itself out as it grows: nodes repel, edges pull, and the
/// graph continually untangles itself into an even web with no coordinates
/// ever given (`ForceLayout`). A new node joins every stretch of frames,
/// linking to old nodes with a preference for the already-popular ones, so
/// hubs emerge and the web keeps reflowing to make room.
///
/// Drag any node and the rest of the graph reflows around your hand; let go
/// and it settles again. Node size is degree: the big disks are the hubs the
/// growth rule made rich.
@main
final class ForceGraph: Sketch {
    private var layout: ForceLayout?
    private var degrees: [Int] = []
    /// Every edge end once, so a uniform pick lands on a node in proportion
    /// to its degree (the rich-get-richer rule).
    private var stubs: [Int] = []
    private var grabbed: Int?

    private let paper = Color(hex: 0xF3F0E7)
    private let ink = Color(hex: 0x22364A)
    private let accent = Color(hex: 0xA83C51)
    private let maxNodes = 110

    override func draw() {
        let frame = canvasRectangle.inset(by: .all(100 * scale))
        if layout == nil {
            let seeded = ForceLayout(count: 3, edges: [(0, 1), (1, 2), (2, 0)],
                                     in: frame, seed: UInt64(variation))
            seeded.idealDistance = spacing(for: 3, in: frame)
            seeded.gravity = 0.008
            layout = seeded
            degrees = [2, 2, 2]
            stubs = [0, 1, 1, 2, 2, 0]
        }
        guard let layout else { return }

        // Growth: every so often a newcomer appears beside a parent picked
        // by degree, sometimes closing a loop to a second one.
        if frameCount % 22 == 0, layout.count < maxNodes {
            let parent = stubs[Int(random(0, Double(stubs.count)))]
            let offset = Vector2(angle: random(0, .tau), length: 26 * scale)
            let newcomer = layout.addNode(at: layout.positions[parent] + offset)
            connect(layout, newcomer, parent)
            if random(0, 1) < 0.35 {
                let second = stubs[Int(random(0, Double(stubs.count)))]
                if second != newcomer, second != parent {
                    connect(layout, newcomer, second)
                }
            }
            // Re-derive the spacing for the new population, so the web keeps
            // filling the frame as it fills in.
            layout.idealDistance = spacing(for: layout.count, in: frame)
            layout.reheat(0.25)
        }

        // A grabbed node rides the mouse; the reheat keeps the web following.
        if let grabbed, mouseIsPressed {
            layout.positions[grabbed] = Vector2(mouseX, mouseY)
            layout.reheat(0.15)
        }
        layout.step()

        background(paper)
        stroke(ink.withAlpha(0.55))
        strokeWeight(1.3 * scale)
        for edge in layout.edges {
            drawLine(layout.positions[edge.a], layout.positions[edge.b])
        }
        noStroke()
        for i in 0 ..< layout.count {
            fill(i == grabbed ? accent : ink)
            let radius = (3.4 + Double(degrees[i]).squareRoot() * 2.6) * scale
            drawCircle(center: layout.positions[i], radius: radius)
        }

        drawCaption("\(layout.count) nodes" + (layout.count < maxNodes ? ", growing" : "")
                    + (grabbed != nil ? ", dragging" : ", drag a node"))
    }

    override func mousePressed() {
        guard let layout, let nearest = layout.nearestNode(to: Vector2(mouseX, mouseY)),
              layout.positions[nearest].distance(to: Vector2(mouseX, mouseY)) < 80 * scale
        else { return }
        grabbed = nearest
        layout.pinned[nearest] = true
    }

    override func mouseReleased() {
        if let grabbed { layout?.pinned[grabbed] = false }
        grabbed = nil
        layout?.reheat(0.3)
    }

    /// The frame-filling spacing for `count` nodes: the `√(area / count)`
    /// default opened up (a big sparse web compresses well below its spacing
    /// constant), capped so the youngest graph doesn't slam its three nodes
    /// into the corners.
    private func spacing(for count: Int, in frame: Rectangle) -> Double {
        min(220 * scale,
            1.6 * (frame.width * frame.height / Double(max(count, 1))).squareRoot())
    }

    private func connect(_ layout: ForceLayout, _ a: Int, _ b: Int) {
        layout.connect(a, b)
        while degrees.count < layout.count { degrees.append(0) }
        degrees[a] += 1
        degrees[b] += 1
        stubs.append(a)
        stubs.append(b)
    }
}
