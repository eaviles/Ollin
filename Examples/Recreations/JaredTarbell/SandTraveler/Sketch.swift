//  Recreation after Jared Tarbell - "Sand Traveler" (2004), made for Sónar
//  2004 in Barcelona and shown in his Gallery of Computation: travelers thrown
//  out from the middle of the sheet, each one chasing another, with sand laid
//  between a chaser and the one it follows. A homage, not a reproduction, and
//  not affiliated with or endorsed by the artist.
//  http://www.complexification.net/gallery/machines/sandTraveler/
//
//  An original Ollin interpretation written from his own description of the
//  piece (traveling particles, each in pursuit of another, their routes
//  showing up over time as sweeping paths of color, and three ways of laying
//  the color: evenly, with his sand stroke, and with the sand stroke turned a
//  quarter turn) and from his pictures of it. He gives the Processing source
//  away in modifiable form and states no license for it. It was read once to
//  understand how the piece works and is not ported: the code, its numbers,
//  and the palette are this sketch's own.

import Ollin

/// "Sand Traveler" (Jared Tarbell, 2004) is a chase. The travelers start
/// close together in the middle of the sheet and are thrown outward along a
/// spiral. Each one follows another, a traveler a little way ahead of it in
/// the order, so the throw turns into long curving pursuits that fold back
/// toward the middle and tighten into a knot.
///
/// The travelers are never drawn. The sheet shows only what lies between a
/// chaser and the one it follows, while the two are within sight of each
/// other, and it keeps everything, so a route swept once is a faint veil and
/// a route the chase keeps returning to becomes a band.
///
/// He showed three ways of laying that color, and `laying` picks one. `even`
/// scatters grains evenly along the line in the color of the one being
/// followed, which gives smooth bands. `stroke` uses his sand painters: each
/// traveler has three, each with a color, a place along the line that
/// wanders, and a spread that drifts, so the bands break up and change color
/// as they go. `across` turns each painter's line a quarter turn about its
/// middle, so the sand lies across the chase, the most restless of the three.
///
/// Try it: `chaseSeed` is the whole piece. `travelers` is how many there are,
/// `lead` how far ahead in the order a traveler may pick the one it follows,
/// and `sight` how far apart the two can be and still lay sand. A click rolls
/// the next seed.
@main
final class SandTraveler: Sketch {

    /// How the color between a chaser and the one it follows is laid.
    enum Laying: String, CaseIterable, ParamOption { case even, stroke, across }

    /// How many travelers there are.
    @Param(3...400) var travelers = 200
    /// How far ahead in the order a traveler may pick the one it follows, as
    /// a share of the travelers.
    @Param(0.02...0.5) var lead = 0.2
    /// How far apart a chaser and the one it follows can be and still lay
    /// sand, as a share of the sheet's side.
    @Param(0.05...1.5) var sight = 0.26
    @Param var laying = Laying.stroke
    /// Steps of the chase a second.
    @Param(30...300) var pace = 75.0
    /// Seconds for one lap: the chase, a hold, and the sheet going back to
    /// paper.
    @Param(10...120) var cycle = 24.0
    @Param(1...9999, icon: "dice") var chaseSeed = 7

    override var loopDuration: Double? { cycle }

    // MARK: The chase

    /// One traveler: where it is, how it is moving, and whom it follows.
    struct Traveler {
        var at: Vector2
        var velocity: Vector2
        var follows: Int
        var color: Int
    }

    /// One sand painter: a color from the palette, a place along the line
    /// that wanders, and a spread that drifts.
    struct Painter {
        var color: Int
        var place: Double
        var spread: Double
    }

    /// The painters each traveler carries.
    static let paintersEach = 3
    /// How many times around the middle the starting spiral goes.
    static let turns = 2.2
    /// The speed the first and the last traveler are thrown out with, in
    /// sheet units a step. A traveler starts four times its speed from the
    /// middle.
    static let slowest = 0.01, fastest = 0.028
    /// The share of the way to the one it follows that a traveler adds to
    /// its speed at each step.
    static let chase = 0.00025
    /// The share of its speed a traveler keeps from one step to the next.
    static let drag = 0.9675
    /// The widest a painter's spread may drift, and the most a spread or a
    /// place changes in one sweep.
    static let widest = 0.22, drift = 0.05
    /// Grains to each side of a painter's place in one sweep.
    static let grains = 11
    /// Grains one traveler scatters along its line in a step of the even
    /// laying, and how opaque each is.
    static let scattered = 22, scatteredAlpha = 0.19
    /// How long a painter's line is in the `across` laying, as a share of
    /// the line from chaser to chased.
    static let crossing = 0.42

    /// The travelers at the start, and their painters, rolled from one seed
    /// in one order: the angle the spiral starts at; then for each traveler
    /// how far ahead the one it follows is, its own color, and its painters
    /// (a color, a place, a spread each).
    static func start(seed: UInt64, travelers count: Int, lead: Double,
                      colors: Int) -> (travelers: [Traveler], painters: [Painter]) {
        var generator = SplitMix64(seed: seed)
        func roll() -> Double { Double(generator.next() >> 11) * 0x1p-53 }

        let first = roll() * 2 * Double.pi
        let most = max(1, Int(lead * Double(count)))
        var travelers: [Traveler] = []
        var painters: [Painter] = []
        for index in 0 ..< count {
            let along = Double(index) / Double(count)
            let turn = first + turns * 2 * Double.pi * along
            let speed = slowest + (fastest - slowest) * along
            let out = Vector2(cos(turn), sin(turn))
            let ahead = 1 + Int(roll() * Double(most))
            let color = Int(roll() * Double(colors))
            travelers.append(Traveler(at: Vector2(0.5, 0.5) + out * (4 * speed), velocity: out * speed,
                                      follows: (index + ahead) % count, color: color))
            for _ in 0 ..< paintersEach {
                let color = Int(roll() * Double(colors))
                let place = roll()
                painters.append(Painter(color: color, place: place, spread: 0.01 + 0.09 * roll()))
            }
        }
        return (travelers, painters)
    }

    /// One step. Every traveler adds a share of the way to the one it follows
    /// to its speed, loses a little speed, and moves. All of them read the
    /// places as they were, and then all of them move.
    static func step(_ travelers: inout [Traveler]) {
        let places = travelers.map(\.at)
        for index in travelers.indices {
            let toward = places[travelers[index].follows] - places[index]
            travelers[index].velocity = (travelers[index].velocity + toward * chase) * drag
            travelers[index].at = places[index] + travelers[index].velocity
        }
    }

    /// Where one sweep of a painter puts its grains along a line, as shares
    /// of the line counted from its far end, each with its opacity. One grain
    /// at the painter's place, then `grains` pairs stepping out to both sides
    /// as far as the spread, fainter with each step. A share is read through
    /// a sine, which crowds the grains toward the near end of the line and
    /// stops short of it.
    static func sweep(place: Double, spread: Double) -> [(share: Double, alpha: Double)] {
        var laid = [(share: sin(place), alpha: 0.09)]
        for grain in 0 ..< grains {
            let out = sin(Double(grain) * spread / Double(grains - 1))
            let alpha = 0.1 * (1 - Double(grain) / Double(grains))
            laid.append((sin(place + out), alpha))
            laid.append((sin(place - out), alpha))
        }
        return laid
    }

    /// The line a painter sweeps for a chaser at `here` following one at
    /// `there`: the line between them, or in the `across` laying a shorter
    /// one through its middle at a right angle to it.
    static func line(from there: Vector2, to here: Vector2, laying: Laying) -> (from: Vector2, to: Vector2) {
        guard laying == .across else { return (there, here) }
        let middle = (there + here) * 0.5
        let half = (here - there).perpendicular * (crossing / 2)
        return (middle - half, middle + half)
    }

    // MARK: The lap

    /// Where the chase ends and where the hold ends, as shares of the lap.
    /// The rest is the sheet going back to paper.
    static let painted = 0.84, held = 0.93
    /// The most steps one frame of a window takes.
    static let most = 3

    /// Dark browns, rusts, ochres, creams, a sage, and a dusty violet, with
    /// black and white weighted in.
    let palette: [Color] = [
        0x2E1F1A, 0x4B3226, 0x6E4A33, 0x8A4B24, 0xB5652F, 0xC98A45, 0xDDB173, 0xEFE3BF,
        0xF7F2DC, 0xCFCBBF, 0x9AA79A, 0x7F9183, 0x8E84A6, 0x6F6488,
        0x000000, 0x000000, 0x000000, 0x000000, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
    ].map { Color(hex: $0) }
    let paper = Color.white

    private var chasers: [Traveler] = []
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

    /// A click rolls the next chase.
    override func mousePressed() {
        chaseSeed = chaseSeed >= 9999 ? 1 : chaseSeed + 1
    }

    private func begin() {
        (chasers, painters) = Self.start(seed: UInt64(chaseSeed), travelers: travelers, lead: lead,
                                         colors: palette.count)
        sand = SplitMix64(seed: UInt64(chaseSeed) &* 0x9E37_79B9 &+ 1)
        stepsDone = 0
        inkLeft = 1
        needsPaper = true
    }

    override func draw() {
        // A changed setting starts the piece again, and so does the end of a
        // lap.
        let settings = [Double(travelers), lead, sight, pace, cycle, Double(chaseSeed),
                        Double(Laying.allCases.firstIndex(of: laying) ?? 0), width, height]
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

        if needsPaper {
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
            Self.step(&chasers)
            stepsDone += 1
            laySand(corner: corner, side: side, grain: grain)
        }

        // The sheet goes back to paper: each frame covers the share of the
        // ink that should have gone since the last one.
        if lap > Self.held {
            let gone = (lap - Self.held) / (1 - Self.held)
            let left = 1 - gone * gone * (3 - 2 * gone)
            fill(paper.withAlpha(1 - left / max(inkLeft, 1e-9)))
            drawRect(0, 0, width, height)
            inkLeft = left
        }
    }

    private func roll() -> Double { Double(sand.next() >> 11) * 0x1p-53 }

    /// One step of sand: every traveler within sight of the one it follows
    /// lays its color between them.
    private func laySand(corner: Vector2, side: Double, grain: Double) {
        for (index, chaser) in chasers.enumerated() {
            let followed = chasers[chaser.follows]
            guard (followed.at - chaser.at).length < sight else { continue }
            let here = corner + chaser.at * side, there = corner + followed.at * side

            if laying == .even {
                fill(palette[followed.color].withAlpha(Self.scatteredAlpha))
                for _ in 0 ..< Self.scattered {
                    drawPoint(at: there + (here - there) * roll(), size: grain)
                }
                continue
            }

            let line = Self.line(from: there, to: here, laying: laying)
            for slot in 0 ..< Self.paintersEach {
                let which = index * Self.paintersEach + slot
                painters[which].spread = min(max(painters[which].spread + (roll() * 2 - 1) * Self.drift,
                                                 -Self.widest), Self.widest)
                painters[which].place = min(max(painters[which].place + (roll() * 2 - 1) * Self.drift, 0), 1)
                let color = palette[painters[which].color]
                for laid in Self.sweep(place: painters[which].place, spread: painters[which].spread) {
                    fill(color.withAlpha(laid.alpha))
                    drawPoint(at: line.from + (line.to - line.from) * laid.share, size: grain)
                }
            }
        }
    }
}
