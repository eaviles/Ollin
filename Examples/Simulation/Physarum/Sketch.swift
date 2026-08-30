import Ollin

/// Physarum (Jones, 2010): a couple hundred thousand agents that lay down a chemical
/// trail and steer toward it, and out of that stigmergy grow the branching transport
/// networks of slime mold. Each agent sniffs three points ahead (left, center, right),
/// turns toward the strongest, steps forward, and deposits a little trail; the trail map
/// then blurs and fades a touch each step. No agent talks to another directly.
///
/// Unlike Particle Life and PPS, this one needs no neighbor search: the agents
/// communicate only through the trail field you see. They start in a central disc facing
/// out, so a radial web of veins reaches across the canvas over the first few seconds.
@main
final class Physarum_Example: Sketch {
    var slime: Physarum!

    override func setup() {
        slime = makePhysarum(agents: 220_000, resolution: 1024)
    }

    override func draw() {
        updatePhysarum(slime)
        drawImage(slime.image, in: bounds)

        drawCaption("Physarum · 220,000 agents growing a transport network")
    }
}
