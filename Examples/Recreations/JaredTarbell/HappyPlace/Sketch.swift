//  Recreation after Jared Tarbell - "Happy Place" (March 2004), from his
//  Gallery of Computation: a ring of nodes with friendships rolled between
//  them, each node stepping toward its friends and away from everyone else,
//  and every friendship drawn as sand while the nodes move. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.
//  http://www.complexification.net/gallery/machines/happyPlace/
//
//  An original Ollin interpretation written from his own description of the
//  piece (the nodes start on a circle; friendships are rolled with a
//  preference for nodes close by; a node moves close to its friends but no
//  closer than some distance, and keeps away from the rest; the connections
//  are drawn with a sand stroke) and from his pictures of it. He gives the
//  Processing source away in modifiable form and states no license for it. It
//  was read once to understand how the piece works and is not ported: the
//  code, its numbers, and the palette are this sketch's own.

import Ollin

/// "Happy Place" (Jared Tarbell, 2004) starts with nodes on a circle. Chance
/// makes some of them friends, more often two that sit near each other on the
/// ring. From then on every node wants two things: to be close to its friends,
/// though no closer than a distance it is comfortable with, and to keep that
/// same distance from everyone who is not a friend. Nobody can have both, so
/// the ring folds in on itself, groups form and drift, and the whole thing
/// keeps rearranging without ever coming to rest.
///
/// The picture is a record of that. The nodes themselves are hardly drawn.
/// What is drawn is every friendship, as a line of translucent sand laid
/// again at each step, so a friendship that swings across the sheet leaves a
/// fan and one that holds still builds up a dark seam.
///
/// The sand comes from painters. Each node has three, each with a color, a
/// place along the line, and a spread that drifts. At every step a painter
/// lays a few grains on each of its node's friendships, crowded at its place
/// and thinning to both sides, and it is the drifting spread that gives the
/// bands their grain.
///
/// Try it: `placeSeed` is the whole piece. `friends` is how many nodes there
/// are, `bonds` how many friendships are rolled for each, and `neighborhood`
/// how far around the ring a friendship may reach. `distance` is the middle
/// of the distances the nodes are comfortable with. Turn `exposure` off to see
/// what is doing the painting: the nodes as squares, larger for more friends,
/// and the friendships as thin lines. A click rolls the next seed.
@main
final class HappyPlace: Sketch {

    /// How many nodes stand on the circle.
    @Param(2...200) var friends = 64
    /// Friendships rolled for each node. A roll that names two nodes who are
    /// friends already, or one with no room left, makes nothing.
    @Param(0.5...5) var bonds = 2.2
    /// How many places around the ring a friendship may reach.
    @Param(1...60) var neighborhood = 21
    /// The middle of the distances the nodes like to keep, as a share of the
    /// sheet's side. Each node rolls its own around it.
    @Param(0.02...0.2) var distance = 0.07
    /// Steps of the system a second.
    @Param(30...300) var pace = 120.0
    /// On: the friendships lay sand and the sheet keeps it. Off: the nodes
    /// and their friendships, drawn fresh every frame.
    @Param var exposure = true
    /// Seconds for one lap: the painting, a hold, and the sheet going back to
    /// paper.
    @Param(10...120) var cycle = 30.0
    @Param(1...9999, icon: "dice") var placeSeed = 2

    override var loopDuration: Double? { cycle }

    // MARK: The system

    /// One node: where it is, how it is moving, the distance it likes to
    /// keep, and who its friends are.
    struct Node {
        var at: Vector2
        var velocity = Vector2(0, 0)
        var reach: Double
        var friends: [Int] = []
    }

    /// One sand painter: a color from the palette, a place along the line,
    /// and a spread that drifts from sweep to sweep.
    struct Painter {
        var color: Int
        var place: Double
        var spread: Double
    }

    /// The most friends a node can have.
    static let room = 10
    /// The painters each node carries.
    static let paintersEach = 3
    /// The radius of the circle the nodes start on, in sheet units.
    static let ring = 0.4
    /// What a friend farther off than a node's distance adds to its speed at
    /// each step, in sheet units.
    static let pull = 0.0001
    /// What a stranger inside a node's distance adds to its speed at each
    /// step, for each unit it stands too close.
    static let push = 0.012
    /// The share of its speed a node keeps from one step to the next.
    static let drag = 0.92
    /// The widest a painter's spread may drift, and the most it changes in
    /// one sweep.
    static let widest = 0.22, drift = 0.05
    /// Grains to each side of a painter's place in one sweep.
    static let grains = 11

    /// The nodes on their circle with their friendships, and their painters,
    /// rolled from one seed in one order: for each node its distance and then
    /// its painters (a color, a place, a spread each), then the friendships
    /// (a node and how many places around the ring its friend sits).
    static func place(seed: UInt64, friends count: Int, bonds: Double, neighborhood: Int,
                      distance: Double, colors: Int) -> (nodes: [Node], painters: [Painter]) {
        var generator = SplitMix64(seed: seed)
        func roll() -> Double { Double(generator.next() >> 11) * 0x1p-53 }

        var nodes: [Node] = []
        var painters: [Painter] = []
        for index in 0 ..< count {
            let turn = 2 * Double.pi * Double(index) / Double(count)
            nodes.append(Node(at: Vector2(0.5 + ring * cos(turn), 0.5 + ring * sin(turn)),
                              reach: distance * (0.3 + 1.4 * roll())))
            for _ in 0 ..< paintersEach {
                let color = Int(roll() * Double(colors))
                let place = roll()
                painters.append(Painter(color: color, place: place, spread: 0.01 + 0.09 * roll()))
            }
        }

        for _ in 0 ..< Int((bonds * Double(count)).rounded()) {
            let one = Int(roll() * Double(count))
            let other = (one + 1 + Int(roll() * Double(neighborhood))) % count
            guard one != other, !nodes[one].friends.contains(other),
                  nodes[one].friends.count < room, nodes[other].friends.count < room else { continue }
            nodes[one].friends.append(other)
            nodes[other].friends.append(one)
        }
        return (nodes, painters)
    }

    /// One step. A node gains speed toward every friend farther off than its
    /// own distance, always by the same amount, and away from every stranger
    /// inside that distance, by more the closer the stranger stands. All the
    /// nodes read the places as they were, and then all of them move.
    static func step(_ nodes: inout [Node]) {
        var gains = [Vector2](repeating: Vector2(0, 0), count: nodes.count)
        for one in nodes.indices {
            let reach = nodes[one].reach
            var gain = Vector2(0, 0)
            for other in nodes.indices where other != one {
                let offset = nodes[other].at - nodes[one].at
                let apart = offset.length
                guard apart > 0 else { continue }
                if nodes[one].friends.contains(other) {
                    if apart > reach { gain = gain + offset * (pull / apart) }
                } else if apart < reach {
                    gain = gain - offset * (push * (reach - apart) / apart)
                }
            }
            gains[one] = gain
        }
        for one in nodes.indices {
            nodes[one].velocity = (nodes[one].velocity + gains[one]) * drag
            nodes[one].at = nodes[one].at + nodes[one].velocity
        }
    }

    /// Where one sweep of a painter puts its grains along a line, as shares
    /// of the line counted from its far end, each with its opacity. One grain
    /// at the painter's place, then `grains` pairs stepping out to both sides
    /// as far as the spread, fainter with each step. A share is read through
    /// a sine, which crowds the grains toward the near end of the line and
    /// stops short of it.
    static func sweep(place: Double, spread: Double) -> [(share: Double, alpha: Double)] {
        var laid = [(share: sin(place), alpha: 0.11)]
        for grain in 0 ..< grains {
            let out = sin(Double(grain) * spread / Double(grains - 1))
            let alpha = 0.1 * (1 - Double(grain) / Double(grains))
            laid.append((sin(place + out), alpha))
            laid.append((sin(place - out), alpha))
        }
        return laid
    }

    // MARK: The lap

    /// Where the painting ends and where the hold ends, as shares of the lap.
    /// The rest is the sheet going back to paper.
    static let painted = 0.84, held = 0.93
    /// The most steps one frame of a window takes.
    static let most = 3

    /// Warm grays, browns, and creams, with black and white weighted in.
    let palette: [Color] = [
        0x2B2623, 0x4A413B, 0x6B5F55, 0x8A7B6C, 0xA89A88, 0xC4B8A6, 0xDDD3C2, 0xEFE8DA,
        0x7A6652, 0x9C7F5F, 0xB79A74, 0x5E5A57, 0x8C8A86, 0xB5B3AE, 0x3A3A3C, 0x6E6A70,
        0x000000, 0x000000, 0x000000, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
    ].map { Color(hex: $0) }
    let paper = Color.white

    private var nodes: [Node] = []
    private var painters: [Painter] = []
    private var sand = SplitMix64(seed: 0)
    private var builtFrom: [Double] = []
    private var origin = 0.0
    private var behind = 0.0
    private var lapNumber = 0
    private var stepsDone = 0
    private var inkLeft = 1.0
    private var needsPaper = true

    override func setup() {
        noClear()
    }

    /// A click rolls the next place.
    override func mousePressed() {
        placeSeed = placeSeed >= 9999 ? 1 : placeSeed + 1
    }

    private func begin() {
        (nodes, painters) = Self.place(seed: UInt64(placeSeed), friends: friends, bonds: bonds,
                                       neighborhood: neighborhood, distance: distance,
                                       colors: palette.count)
        sand = SplitMix64(seed: UInt64(placeSeed) &* 0x9E37_79B9 &+ 1)
        stepsDone = 0
        inkLeft = 1
        needsPaper = true
    }

    override func draw() {
        // A changed setting starts the piece again, and so does the end of a
        // lap.
        let settings = [Double(friends), bonds, Double(neighborhood), distance, pace,
                        exposure ? 1 : 0, cycle, Double(placeSeed), width, height]
        if settings != builtFrom {
            builtFrom = settings
            origin = time
            behind = 0
            lapNumber = 0
            begin()
        }
        let clock = time - origin - behind
        let turn = Int(clock / cycle)
        if turn != lapNumber {
            lapNumber = turn
            begin()
        }
        let seconds = clock - Double(turn) * cycle
        let lap = seconds / cycle

        let side = min(width, height)
        let corner = center - Vector2(side / 2, side / 2)
        let grain = side / 500
        noStroke()

        if needsPaper || !exposure {
            background(paper)
            needsPaper = false
        }

        // The steps owed by now. A written frame takes all of them. A window
        // takes a few, and when that is not enough the piece's clock waits
        // for the machine, so a slow one paints the same picture more slowly.
        var due = Int(min(seconds, Self.painted * cycle) * pace + 1e-6) - stepsDone
        if !isExporting, due > Self.most {
            behind += Double(due - Self.most) / pace
            due = Self.most
        }
        for _ in 0 ..< max(due, 0) {
            Self.step(&nodes)
            stepsDone += 1
            if exposure { laySand(corner: corner, side: side, grain: grain) }
        }
        if !exposure { drawSystem(corner: corner, side: side) }

        // The sheet goes back to paper: each frame covers the share of the
        // ink that should have gone since the last one.
        if lap > Self.held {
            let gone = (lap - Self.held) / (1 - Self.held)
            let left = 1 - gone * gone * (3 - 2 * gone)
            fill(paper.withAlpha(exposure ? 1 - left / max(inkLeft, 1e-9) : 1 - left))
            drawRect(0, 0, width, height)
            inkLeft = left
        }
    }

    /// One step of sand: every painter of every node sweeps each of the
    /// node's friendships, from the friend toward the node, and the node
    /// leaves a dark grain with a pale one beside it.
    private func laySand(corner: Vector2, side: Double, grain: Double) {
        for (index, node) in nodes.enumerated() {
            let here = corner + node.at * side
            for friend in node.friends {
                let there = corner + nodes[friend].at * side
                for slot in 0 ..< Self.paintersEach {
                    let which = index * Self.paintersEach + slot
                    let change = (Double(sand.next() >> 11) * 0x1p-53 * 2 - 1) * Self.drift
                    painters[which].spread = min(max(painters[which].spread + change, -Self.widest),
                                                 Self.widest)
                    let color = palette[painters[which].color]
                    for laid in Self.sweep(place: painters[which].place, spread: painters[which].spread) {
                        fill(color.withAlpha(laid.alpha))
                        drawPoint(at: there + (here - there) * laid.share, size: grain)
                    }
                }
            }
            fill(Color.black.withAlpha(0.28))
            drawPoint(at: here, size: grain * 1.3)
            fill(Color.white.withAlpha(0.2))
            drawPoint(at: here - Vector2(grain, grain) * 0.7, size: grain)
        }
    }

    /// The system itself: every friendship once as a thin line, and every
    /// node as a square in its first painter's color, larger for more
    /// friends.
    private func drawSystem(corner: Vector2, side: Double) {
        noFill()
        stroke(Color(hex: 0x333333).withAlpha(0.7))
        strokeWeight(scale)
        for (index, node) in nodes.enumerated() {
            for friend in node.friends where friend > index {
                drawLine(corner + node.at * side, corner + nodes[friend].at * side)
            }
        }
        noStroke()
        for (index, node) in nodes.enumerated() {
            fill(palette[painters[index * Self.paintersEach].color])
            let across = (4 + 2 * Double(node.friends.count)) * scale
            drawRect(center: corner + node.at * side, width: across, height: across)
        }
    }
}
