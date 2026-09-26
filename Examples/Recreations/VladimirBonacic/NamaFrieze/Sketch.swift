//  Recreation after Vladimir Bonačić - DIN. PR 18 (Zagreb, 1969): a light
//  frieze 36 meters long on the front of the NaMa department store on
//  Kvaternik Square, eighteen panels of lamps stepping through the nonzero
//  states of an 18-bit Galois field.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://digitalna-umjetnost-u-hrvatskoj.eu/en/autori/vladimir-bonacic
//
//  An original Ollin interpretation, written from the published accounts of
//  the installation and from the artist's own article on his method
//  (Leonardo 7:3, 1974). Nothing was ported: the frieze was lamps and custom
//  logic, and how its eighteen bits reached its lamps is not recorded in
//  anything we could find, so the reading here is ours.

import Ollin
import OllinDMX

/// DIN. PR 18 (Vladimir Bonačić, 1969). For the fourth New Tendencies in
/// Zagreb, a frieze of eighteen light panels went up across the front of the
/// NaMa department store on Kvaternik Square, a store that had opened the
/// year before. Each panel was 48 by 88 centimeters, a grid of five rows of
/// three lamps, and the eighteen of them ran 36 meters. The square was dark
/// then, with little street lighting, so the frieze was also a lamp for the
/// square: when it lit up, so did the pavement.
///
/// It flashed the patterns of an irreducible polynomial of degree 18,
/// x^18 + x^5 + x^2 + x + 1, and the accounts give the count: 262,143 images
/// in a variable rhythm, never faster than one every 200 milliseconds. That
/// count is 2^18 - 1, every nonzero state of an 18-bit register, which is what
/// multiplying by x in a field with a *primitive* polynomial walks through
/// before it comes back to where it began. Eighteen bits and eighteen panels:
/// the reading here gives each panel one bit, its fifteen lamps lit together,
/// so an image is which panels are on. Image 1 is the element 1, a single
/// panel at the left, and the images after it are that panel running the
/// length of the frieze until the polynomial folds back in and the patterns
/// take over. The frieze is switched on wherever the seed puts it on the walk,
/// and the count in the corner says which image it is showing.
///
/// The rhythm is a second, shorter generator. The artist's article draws the
/// clock of his dynamic objects passing through a gate, with a Galois sequence
/// holding it open or shut, so the pattern moves on some ticks and waits on
/// others. Here the gate is the degree-4 register over x^4 + x + 1: fifteen
/// ticks carry eight steps and seven waits, in the same irregular order every
/// time round, so the frieze has a pulse rather than a beat.
///
/// Set `sendsToWall` and the panels go out as DMX over sACN, universe 1,
/// channels 1 to 18, one dimmer per panel from the left, at the level the
/// lamps are drawn at here (their warming and cooling included). Leave
/// `wallAddress` empty to multicast to any node listening on universe 1, or
/// give one node's address. Eighteen dimmer channels and eighteen lamps, or
/// eighteen strips of LEDs, are a frieze of your own.
@main
final class NamaFrieze: Sketch {
    /// Seconds per tick of the clock. The frieze could go no faster than 0.2.
    @Param(0.2 ... 3, icon: "metronome") var clock = 0.45
    /// Whether the rhythm generator gates the clock. Off, every tick is a step.
    @Param(icon: "waveform.path") var usesRhythm = true
    /// Whether the panels go out over DMX.
    @Param(icon: "antenna.radiowaves.left.and.right") var sendsToWall = false
    /// Where they go: empty multicasts sACN to universe 1, an address sends to
    /// one node.
    @Param(icon: "network") var wallAddress = ""

    /// x^18 + x^5 + x^2 + x + 1 without its leading term.
    static let feedback: UInt32 = 1 << 5 | 1 << 2 | 1 << 1 | 1
    /// Every nonzero state of the register, and so every image.
    static let images = 262_143
    /// x^4 + x + 1 without its leading term, for the rhythm.
    static let rhythmFeedback: UInt8 = 1 << 1 | 1

    /// The frieze's field element. Bit i lights panel i, counted from the left.
    var element: UInt32 = 1
    /// The rhythm register; its top bit says whether this tick is a step.
    var rhythm: UInt8 = 1
    /// How many steps along the walk the frieze is: it shows image `steps + 1`.
    var steps = 0
    /// How far into the current tick the clock is.
    var phase = 0.0
    /// Each panel's lamps, warming and cooling, from 0 to 1.
    var glow = [Double](repeating: 0, count: 18)

    var sender: DMXSender?
    var senderAddress = ""

    let sky = Color(hex: 0x05070D)
    let wall = Color(hex: 0x1A1918)
    let glass = Color(hex: 0x0B0D10)
    let pavement = Color(hex: 0x111110)
    let housing = Color(hex: 0x0E0E0F)
    let lamp = Color(hex: 0xFFE9C4)

    /// The drawing is to scale: fifty pixels to the meter.
    let meter = 50.0
    let frieze = Rectangle(x: 60, y: 300, width: 1800, height: 44)
    let roofline = 176.0
    let canopy = 700.0
    let ground = 930.0

    override var canvasSize: CanvasSize { .size(1920, 1080) }

    override func setup() {
        // Switched on somewhere along its walk; the seed says where.
        steps = Int(random(0, Double(Self.images)))
        for _ in 0..<steps {
            element = Self.timesX(element)
        }
        for panel in 0..<18 {
            glow[panel] = isLit(panel) ? 1 : 0
        }
    }

    /// Multiply by x, modulo the degree-18 polynomial.
    static func timesX(_ value: UInt32) -> UInt32 {
        let shifted = value << 1
        return shifted & 1 << 18 != 0 ? (shifted ^ (1 << 18)) ^ feedback : shifted
    }

    /// One tick of the rhythm register, and whether it lets the pattern step.
    static func rhythmTick(_ value: UInt8) -> (next: UInt8, steps: Bool) {
        let steps = value & 0b1000 != 0
        let shifted = value << 1
        let next = shifted & 1 << 4 != 0 ? (shifted ^ (1 << 4)) ^ rhythmFeedback : shifted
        return (next, steps)
    }

    func isLit(_ panel: Int) -> Bool {
        element >> UInt32(panel) & 1 == 1
    }

    override func draw() {
        phase += deltaTime / clock
        while phase >= 1 {
            phase -= 1
            let tick = Self.rhythmTick(rhythm)
            rhythm = tick.next
            if tick.steps || !usesRhythm {
                element = Self.timesX(element)
                steps += 1
            }
        }
        for panel in 0..<18 {
            let target = isLit(panel) ? 1.0 : 0.0
            let settle = target > glow[panel] ? 0.05 : 0.14
            glow[panel] += (target - glow[panel]) * (1 - exp(-deltaTime / settle))
        }

        drawStreet()
        drawFrieze()
        drawCaption()
        sendToWall()
        postProcess(.bloom(threshold: 0.6, amount: 0.7, radius: 22))
    }

    /// The x of a panel's center: one every two meters, eighteen of them.
    func panelX(_ panel: Int) -> Double {
        frieze.x + (Double(panel) + 0.5) * 2 * meter
    }

    /// The building and the square at night, lit only by the frieze.
    func drawStreet() {
        background(sky)
        noStroke()
        fill(wall)
        drawRect(0, roofline, width, canopy - roofline)
        // The joints of the cladding, barely there.
        fill(Color(white: 0.13))
        var x = 30.0
        while x < width {
            drawRect(x, roofline, 1.5, canopy - roofline)
            x += 1.2 * meter
        }
        // The shop front under the canopy: dark glass, closed for the night.
        fill(Color(white: 0.07))
        drawRect(0, canopy, width, 16)
        fill(glass)
        drawRect(0, canopy + 16, width, ground - canopy - 16)
        fill(Color(white: 0.1))
        x = 0
        while x < width {
            drawRect(x, canopy + 16, 3, ground - canopy - 16)
            x += 2.4 * meter
        }
        fill(pavement)
        drawRect(0, ground, width, height - ground)

        // What the frieze lights: the wall round each panel and the square in
        // front of it, both falling off softly with distance.
        blendMode(.add)
        for panel in 0..<18 where glow[panel] > 0.002 {
            let level = glow[panel]
            let x = panelX(panel)
            withClip(Rectangle(x: 0, y: roofline, width: width, height: canopy - roofline)) {
                fill(Gradient.radial(center: Vector2(x, frieze.center.y), radius: 190,
                                     falloff(0.16 * level)))
                drawCircle(center: Vector2(x, frieze.center.y), radius: 190)
            }
            withState(at: Vector2(x, ground + 78)) {
                scale(1, 0.22)
                fill(Gradient.radial(center: .zero, radius: 300, falloff(0.16 * level)))
                drawCircle(center: .zero, radius: 300)
            }
        }
        blendMode(.normal)
    }

    /// A light that fades to nothing at its rim: most of it near the center,
    /// a long thin tail, and no edge to see.
    func falloff(_ peak: Double) -> [Color] {
        (0...12).map { step in
            let r = Double(step) / 12
            return lamp.withAlpha(peak * exp(-4.5 * r * r) * (1 - r))
        }
    }

    /// The eighteen panels: a dark housing each, five rows of three lamps.
    func drawFrieze() {
        noStroke()
        let panelWidth = 0.48 * meter
        let panelHeight = 0.88 * meter
        for panel in 0..<18 {
            let center = Vector2(panelX(panel), frieze.center.y)
            fill(housing)
            drawRect(center: center, width: panelWidth, height: panelHeight)
            let level = glow[panel]
            fill(Color(hex: 0x2A2724).mixed(with: lamp, level))
            for row in 0..<5 {
                for column in 0..<3 {
                    let lampCenter = center + Vector2((Double(column) - 1) * panelWidth / 3,
                                                      (Double(row) - 2) * panelHeight / 5)
                    drawCircle(center: lampCenter, radius: 3.1)
                }
            }
        }
    }

    func drawCaption() {
        let image = steps % Self.images + 1
        drawText("image \(image.formatted()) of \(Self.images.formatted())",
                 60, 90, size: 20, color: Color(white: 0.38), align: .left)
        let route = wallAddress.isEmpty ? "sACN multicast" : "sACN to \(wallAddress)"
        let right = sendsToWall
            ? "universe 1, channels 1 to 18, \(route)"
            : "x¹⁸ + x⁵ + x² + x + 1"
        drawText(right, width - 60, 90, size: 20, color: Color(white: 0.38),
                 align: .right)
    }

    /// The panels as eighteen dimmer channels, when the wall is on.
    func sendToWall() {
        guard sendsToWall else {
            sender?.close()
            sender = nil
            return
        }
        if sender == nil || senderAddress != wallAddress {
            sender?.close()
            sender = wallAddress.isEmpty ? DMXSender() : DMXSender(sACN: wallAddress)
            senderAddress = wallAddress
        }
        var universe = DMXUniverse()
        for panel in 0..<18 {
            universe.set(panel + 1, level: glow[panel])
        }
        sender?.send(universe)
    }
}
