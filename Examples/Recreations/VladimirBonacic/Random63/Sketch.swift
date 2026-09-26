//  Recreation after Vladimir Bonačić - Random 63 (Zagreb, 1969): a metal
//  panel 76 centimeters square carrying sixty-three bulbs, each switched by
//  a source of true randomness of its own, the one work of his made from
//  chance.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://digitalna-umjetnost-u-hrvatskoj.eu/en/autori/vladimir-bonacic
//
//  An original Ollin interpretation, written from the published accounts of
//  the object and a photograph of it. The polynomial behind the arrangement
//  is our reading of that photograph, the chance here is a seeded imitation
//  of it, and the panel beside it, the same bulbs driven by the field, is
//  ours. Nothing was ported: the object was bulbs and starters on metal.

import Ollin
import OllinDMX

/// Random 63 (Vladimir Bonačić, 1969). Bonačić distrusted chance in art. A
/// program run through a random generator, he wrote, reaches "maximal
/// originality" whatever its result, and "the random generator creates the
/// accidental and unique presentation, which has neither value nor
/// importance for human beings." Every other dynamic object he built runs on
/// the patterns of a Galois field, each one a lawful consequence of the one
/// before, so that the law can in principle be watched. Random 63 is the
/// exception, made in the same year as the critique: a metal panel 76 by 76
/// by 7 centimeters with sixty-three tube-shaped 10 watt bulbs, each driven
/// by an independent generator of true randomness. The generators were
/// fluorescent-lamp starters, a small glow bulb with a bimetal strip that the
/// glow heats until it bends and closes a contact, then cools and lets go,
/// never in quite the same time twice.
///
/// **The arrangement.** The accounts say the geometry of the bulbs "was
/// deliberately generated with the use of the pseudo-random Galois field by
/// an exact method." In a photograph of the object the bulbs sit on a grid of
/// sixteen by sixteen, and their sixty-three places are exactly the powers of
/// x modulo x^8 + x^5 + x^2 + x + 1: write x^k as eight bits, and the low four
/// count the row down from the top while the high four count the column in
/// from the right. No other polynomial of degree eight puts a bulb in all
/// sixty-three places (its mirror image aside), so the identification is
/// ours, read off the photograph. The polynomial is reducible,
/// (x^2 + x + 1)(x^6 + x^5 + 1), which is why its powers come back to 1
/// after sixty-three steps and not 255: there are as many bulbs as the walk
/// has places. So even the one work built on chance hangs its chance on the
/// field.
///
/// **Chance, here.** A sketch has no starters, so each bulb gets a generator
/// of its own, seeded apart from the others: a pseudo-random imitation of
/// chance, by the arithmetic he distrusted, and said so. Each starter has its
/// own pace (a quick one blinks often, a slow one seldom), and every interval
/// is drawn fresh. How the starters were wired to the bulbs is not recorded.
/// The photograph shows fifty-two of the sixty-three lit at once, so here a
/// bulb burns for a while and goes dark for a moment, burning four fifths of
/// the time.
///
/// **The field, beside it.** The second panel is not his. It carries the same
/// bulbs in the same places, driven the way his other objects are: bulb k,
/// the one at x^k, is lit while x^(k + t) lies in the left half of the panel,
/// where t counts the ticks of a clock. Every bulb there blinks one and the
/// same sequence, each a tick behind the bulb after it, and every sixty-three
/// ticks the left half is lit and nothing else. Side by side, the two panels
/// are the argument of the piece: one can be watched for its law, the other
/// can only be enjoyed.
///
/// `view` shows the pair, or either panel alone. `clock` is the seconds per
/// tick of the field's panel. Set `sendsToWall` and the bulbs go out as DMX
/// over sACN, universe 1, read from the drawn picture: channels 1 to 63 the
/// panel of chance and 64 to 126 the field's, each in the order of the powers
/// of x. `wallAddress` names one node, or leave it empty to multicast.
@main
final class Random63: Sketch {
    enum View: String, CaseIterable, ParamOption { case pair, chance, field }

    /// Both panels side by side, or one alone.
    @Param(icon: "eye") var view = View.pair
    /// Seconds per tick of the field's panel; chance keeps its own time.
    @Param(0.25 ... 4, icon: "metronome") var clock = 1.0
    @Param(icon: "antenna.radiowaves.left.and.right") var sendsToWall = false
    @Param(icon: "network") var wallAddress = ""

    /// x^8 + x^5 + x^2 + x + 1.
    static let polynomial = 0b1_0010_0111

    /// x^0 to x^62 modulo the polynomial, as eight-bit numbers.
    static let powers: [Int] = {
        var value = 1
        var powers: [Int] = []
        for _ in 0 ..< 63 {
            powers.append(value)
            value <<= 1
            if value & 0x100 != 0 { value ^= polynomial }
        }
        return powers
    }()

    /// Bulb k's place, from x^k: the low four bits the row from the top, the
    /// high four the column from the right.
    static func place(_ bulb: Int) -> (row: Int, column: Int) {
        let power = powers[bulb]
        return (power & 15, 15 - power >> 4)
    }

    /// A starter: the glow, the strip, and its own generator.
    struct Starter {
        var state: UInt64
        /// Its pace: every interval it draws is scaled by this.
        var pace = 1.0
        var isLit = true
        /// When it next changes, in seconds since the panel was switched on.
        var nextChange = 0.0
        var glow = 1.0

        /// A number in (0, 1) from its own stream.
        mutating func uniform() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return (Double(z >> 11) + 0.5) / 9_007_199_254_740_992
        }

        /// How long it burns, or rests: a sum of three waits, so an interval
        /// is never quite nothing and seldom very long.
        mutating func interval(lit: Bool) -> Double {
            let mean = (lit ? 3.2 : 0.8) * pace
            return -mean / 3 * (log(uniform()) + log(uniform()) + log(uniform()))
        }
    }

    var starters: [Starter] = []
    /// Seconds since the panel was switched on.
    var now = 0.0
    /// The field's panel: its ticks, and how far into the next one it is.
    var ticks = 0
    var phase = 0.0
    var fieldGlow = [Double](repeating: 0, count: 63)

    var wall: LEDMap?
    var wallSender: DMXSender?
    var wallAddressInUse = ""
    var wallLayout = ""

    let wallColor = Color(hex: 0x5D5B58)
    let metal = Color(hex: 0x46423F)
    let socket = Color(hex: 0x1A1817)
    let socketRim = Color(hex: 0x6C6660)
    let darkGlass = Color(hex: 0x3D3631)
    let glassLit = Color(hex: 0xFFD49A)
    let filament = Color(hex: 0xFFF6E4)
    let warmLight = Color(hex: 0xFFB872)
    let ledgeTop = 902.0

    override var canvasSize: CanvasSize { .size(1920, 1080) }

    override func setup() {
        // Each starter seeded apart from the others, all of them from the seed.
        starters = (0 ..< 63).map { bulb in
            var starter = Starter(state: UInt64(bitPattern: Int64(variation)) &* 0x100 &+ UInt64(bulb))
            starter.pace = 0.6 + starter.uniform()
            starter.isLit = starter.uniform() < 0.8
            starter.nextChange = starter.interval(lit: starter.isLit) * starter.uniform()
            starter.glow = starter.isLit ? 1 : 0
            return starter
        }
        // The field's panel is switched on somewhere along its walk too.
        ticks = Int(random(0, 63))
        for bulb in 0 ..< 63 {
            fieldGlow[bulb] = fieldLit(bulb) ? 1 : 0
        }
    }

    /// Whether the field lights bulb `bulb`: x^(bulb + ticks) in the left half,
    /// its top bit set.
    func fieldLit(_ bulb: Int) -> Bool {
        Self.powers[(bulb + ticks) % 63] & 0x80 != 0
    }

    override func draw() {
        now += deltaTime
        for bulb in starters.indices {
            while starters[bulb].nextChange <= now {
                starters[bulb].isLit.toggle()
                starters[bulb].nextChange += starters[bulb].interval(lit: starters[bulb].isLit)
            }
            starters[bulb].glow = warmed(starters[bulb].glow, toward: starters[bulb].isLit)
        }
        phase += deltaTime / clock
        while phase >= 1 {
            phase -= 1
            ticks += 1
        }
        for bulb in 0 ..< 63 {
            fieldGlow[bulb] = warmed(fieldGlow[bulb], toward: fieldLit(bulb))
        }

        background(wallColor)
        noStroke()
        drawLedge()
        let panels = self.panels
        // The room's light on the wall behind every panel first, so no panel's
        // light is drawn over its neighbor.
        for panel in panels {
            drawWallLight(behind: panel.frame)
        }
        for (index, panel) in panels.enumerated() {
            let levels = panel.isChance ? starters.map(\.glow) : fieldGlow
            drawPanel(panel.frame, levels: levels, mottleSeed: index)
        }
        drawCaptions(panels)
        updateWall(panels)
        postProcess(.bloom(threshold: 0.8, amount: 0.7, radius: 12))
    }

    /// A filament warms in a moment and cools a little slower.
    func warmed(_ level: Double, toward lit: Bool) -> Double {
        let target = lit ? 1.0 : 0.0
        let settle = lit ? 0.05 : 0.12
        return level + (target - level) * (1 - exp(-deltaTime / settle))
    }

    /// The panels on show and where they hang: side by side, or one alone.
    var panels: [(frame: Rectangle, isChance: Bool)] {
        switch view {
        case .pair:
            let side = 760.0
            return [(Rectangle(x: 120, y: ledgeTop - side, width: side, height: side), true),
                    (Rectangle(x: width - 120 - side, y: ledgeTop - side, width: side, height: side), false)]
        case .chance, .field:
            let side = 820.0
            return [(Rectangle(x: (width - side) / 2, y: ledgeTop - side, width: side, height: side),
                     view == .chance)]
        }
    }

    /// The center of bulb `bulb` on a panel: sixteen places a side, 5.5 percent
    /// of the panel apart, the grid centered.
    func bulbCenter(_ bulb: Int, on frame: Rectangle) -> Vector2 {
        let (row, column) = Self.place(bulb)
        let pitch = frame.width * 0.055
        let margin = (frame.width - 15 * pitch) / 2
        return Vector2(frame.x + margin + Double(column) * pitch, frame.y + margin + Double(row) * pitch)
    }

    /// The white ledge the panels stand on.
    func drawLedge() {
        fill(Color(hex: 0x3E3C3A))
        drawRect(0, ledgeTop + 24, width, 10)
        fill(Color(hex: 0xC9C6C1))
        drawRect(0, ledgeTop, width, 24)
    }

    /// The lamp over a panel, falling on the wall round it.
    func drawWallLight(behind frame: Rectangle) {
        let center = frame.center - Vector2(0, frame.height * 0.1)
        fill(Gradient.radial(center: center, radius: frame.width * 0.95,
                             (0 ... 8).map { step in
                                 let r = Double(step) / 8
                                 return Color(hex: 0xA6A29C).withAlpha((1 - r * r) * (1 - r))
                             }))
        drawCircle(center: center, radius: frame.width * 0.95)
    }

    func drawPanel(_ frame: Rectangle, levels: [Double], mottleSeed: Int) {
        // Its shadow on the wall.
        for step in 0 ..< 4 {
            let spread = Double(step) * 5
            fill(Color(white: 0, alpha: 0.08))
            drawRect(frame.x + 10 - spread, frame.y + 16 - spread, frame.width + 2 * spread,
                     frame.height + 2 * spread - 16)
        }

        // The metal: a little lighter where the room's lamp falls on it, and
        // the marks of its weathering, the same on every run.
        fill(Gradient.radial(center: Vector2(frame.center.x, frame.y + frame.height * 0.3),
                             radius: frame.width * 0.9, [metal.lighter(by: 0.08), metal.darker(by: 0.12)]))
        drawRect(frame)
        var mottle = Starter(state: UInt64(mottleSeed + 7) &* 0x9E37)
        withClip(frame) {
            for _ in 0 ..< 60 {
                let spot = Vector2(frame.x + mottle.uniform() * frame.width,
                                   frame.y + mottle.uniform() * frame.height)
                let tone = mottle.uniform() < 0.55 ? Color(hex: 0x5E4B3C) : Color(hex: 0x262423)
                let depth = 0.1 + 0.12 * mottle.uniform()
                let reach = frame.width * (0.03 + 0.11 * mottle.uniform())
                fill(Gradient.radial(center: spot, radius: reach, [tone.withAlpha(depth), tone.withAlpha(0)]))
                drawCircle(center: spot, radius: reach)
            }
        }
        noFill()
        stroke(Color(hex: 0x2B2826))
        strokeWeight(6)
        drawRect(frame.x + 3, frame.y + 3, frame.width - 6, frame.height - 6)
        noStroke()

        let pitch = frame.width * 0.055
        // What each lit bulb throws on the metal round it.
        blendMode(.add)
        for bulb in 0 ..< 63 where levels[bulb] > 0.002 {
            let center = bulbCenter(bulb, on: frame)
            let reach = pitch * 1.7
            fill(Gradient.radial(center: center, radius: reach,
                                 (0 ... 8).map { step in
                                     let r = Double(step) / 8
                                     return warmLight.withAlpha(0.22 * levels[bulb] * exp(-4 * r * r) * (1 - r))
                                 }))
            drawCircle(center: center, radius: reach)
        }
        blendMode(.normal)

        for bulb in 0 ..< 63 {
            let center = bulbCenter(bulb, on: frame)
            let level = levels[bulb]
            // The socket's metal rim, the bulb's glass end in it, and a glint on
            // the glass that the glow drowns when the bulb is lit.
            fill(socketRim)
            drawCircle(center: center, radius: pitch * 0.33)
            fill(socket)
            drawCircle(center: center, radius: pitch * 0.3)
            fill(darkGlass.mixed(with: glassLit, level))
            drawCircle(center: center, radius: pitch * 0.26)
            fill(filament.withAlpha(level))
            drawCircle(center: center, radius: pitch * 0.15)
            fill(Color(white: 0.75, alpha: 0.3 * (1 - level)))
            drawCircle(center: center + Vector2(-pitch * 0.08, -pitch * 0.08), radius: pitch * 0.05)
        }
    }

    func drawCaptions(_ panels: [(frame: Rectangle, isChance: Bool)]) {
        for panel in panels {
            let text = panel.isChance
                ? "sixty-three starters"
                : "x⁸ + x⁵ + x² + x + 1, tick \(ticks % 63 + 1) of 63"
            drawText(text, panel.frame.center.x, ledgeTop + 88, size: 22, color: Color(white: 0.2),
                     align: .center)
        }
    }

    /// The bulbs as dimmers, read off the drawn picture, when the wall is on.
    func updateWall(_ panels: [(frame: Rectangle, isChance: Bool)]) {
        guard sendsToWall else {
            wall?.removeAll()
            wallLayout = ""
            return
        }
        if wall == nil || wallAddressInUse != wallAddress {
            wall?.removeAll()
            wallSender?.close()
            let sender = wallAddress.isEmpty ? DMXSender() : DMXSender(sACN: wallAddress)
            let map = LEDMap(sender: sender)
            extend(map)
            wall = map
            wallSender = sender
            wallAddressInUse = wallAddress
            wallLayout = ""
        }
        let layout = "\(view)"
        guard layout != wallLayout, let wall else { return }
        wall.removeAll()
        for panel in panels {
            let points = (0 ..< 63).map { bulbCenter($0, on: panel.frame) }
            wall.addPoints(points, universe: 1, address: panel.isChance ? 1 : 64, layout: [.dimmer],
                           sampleRadius: panel.frame.width * 0.004)
        }
        wallLayout = layout
    }
}
