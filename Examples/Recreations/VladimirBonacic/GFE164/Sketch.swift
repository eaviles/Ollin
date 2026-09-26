//  Recreation after Vladimir Bonačić - Dynamic Object GF.E (16,4) 69/71
//  (Zagreb, 1969 to 1971): a relief of 1,024 squares of colored glass at the
//  ends of tubes of four lengths, lit by three Galois field generators, with
//  sixty-four tones sounded from the same arithmetic.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://www.jstor.org/stable/1572890
//
//  An original Ollin interpretation, written from the arithmetic the artist
//  published with the object in Leonardo 7:3 (1974). The mask, the raster,
//  the relief, the three generators and the table of tones are his; the
//  sixteen colors, which depth takes which tube length, how loud each tone
//  is, and the room are ours. Nothing was ported: the object was glass, lamps
//  and logic built in Zagreb, and its program was the field itself.

import Ollin
import OllinAudio

/// Dynamic Object GF.E (16,4) 69/71 (Vladimir Bonačić, 1969 to 1971). A
/// square relief 178 centimeters across and half a ton in weight: a 32 by 32
/// matrix of squares of colored glass, each 4.5 centimeters across, at the
/// ends of tubes 8, 12, 16 and 20 centimeters long, with a lamp in every
/// tube. It was shown at the Paris Biennale in 1971 and then at UNESCO.
///
/// Everything below is from the appendix of the artist's article, which
/// prints the object's arithmetic in full.
///
/// **The raster.** The panel is four planes woven together: plane A holds the
/// squares on even rows and even columns, B the even rows and odd columns, C
/// the odd rows and even columns, D the odd rows and odd columns, 256 squares
/// each. Number a plane's squares down its columns and the planes one after
/// another, and every square has a number d from 0 to 1023, ten bits. His
/// 4 by 10 mask turns those ten bits into four: the square's *residue class*,
/// 0 to 15, and the class is the square's color. Each plane holds sixteen
/// squares of every color, which is the article's own sentence: "16 squares
/// of the same color flash simultaneously in one plane."
///
/// **The relief.** A square's depth is two bits of its class (his M = [I, O]),
/// so every square of one color stands at the same depth, and the relief is
/// a pattern of the same arithmetic as the colors. The article prints the top
/// left corner of the panel with each square's plane and depth, and a table
/// of one plane's classes beside their depths; the rules above give both,
/// cell for cell.
///
/// **The generators.** A lamp lights only when two generators both say so.
/// The first is an element of GF(2^16), the polynomials modulo
/// x^16 + x^12 + x^3 + x + 1, which is primitive: bit i sets the squares of
/// class i. The second has four bits, one per plane; his polynomial for it is
/// "variable", and `planeRule` chooses. Every step multiplies both by x. The
/// third generator is the rhythm: a shorter register whose top bit opens and
/// shuts a gate on the clock, so the pattern moves on some ticks and waits on
/// others. The article allows "a short or a long sequence", and `rhythm`
/// picks one, or none.
///
/// **The tones.** Each color has a tone in each plane, sixty-four in all, and
/// a tone sounds when its square could light: class i sets tone i in every
/// plane, and the plane generator lets a plane's octaves through. His table
/// gives the frequencies: a plane is two octaves, eight tones to an octave,
/// from 64 hertz in plane I to 15,360 in plane IV. "Instead of the octaves of
/// the tempered scale, I have simply doubled frequencies of each succeeding
/// octave", so every tone is a whole multiple of 8 hertz and the chord is
/// always a stretch of one harmonic series. How loud each plane sounds is
/// ours: the high planes are kept quieter than the low.
///
/// **What a visitor could change.** The volume, the speed, the rhythm, the
/// exclusion of some tones, and the replay of a sequence, "manually or by
/// remote control". Not the patterns: "The patterns and their sequence cannot
/// be altered." `volume`, `clock`, `rhythm` and `isRunning` are the parameters;
/// the keys 1 to 4 silence or restore a plane's tones, R replays the sequence
/// from where the object was switched on, and space starts and stops it.
///
/// `view` picks how it is seen: `room` walks slowly past it in a dark room,
/// `face` is straight on, and `plan` is the flat drawing of its squares (the
/// frame round each glass is its depth, lighter for a longer tube), which
/// `--export-svg` writes. The row of indicators along the bottom is the
/// console: the sixteen bits of the first generator, the four of the second,
/// and the rhythm register.
@main
final class GFE164: Sketch {
    enum View: String, CaseIterable, ParamOption { case room, face, plan }
    enum RhythmRule: String, CaseIterable, ParamOption { case long, short, none }
    enum PlaneRule: String, CaseIterable, ParamOption { case primitive, reversed, short }

    @Param(icon: "eye") var view = View.room
    /// Seconds per tick of the clock. The long rhythm lets 16 ticks in 31
    /// through, so a second a tick is a change about every two seconds, the
    /// rate the artist reckoned with.
    @Param(0.1 ... 5, icon: "metronome") var clock = 1.0
    /// The rhythm register: x^5 + x^2 + 1 (long), x^3 + x + 1 (short), or none,
    /// when every tick is a step.
    @Param(icon: "waveform.path") var rhythm = RhythmRule.long
    /// The plane generator's polynomial: x^4 + x + 1 or its mirror
    /// x^4 + x^3 + 1, both primitive, or x^4 + x^3 + x^2 + x + 1, whose walk
    /// comes back after five steps.
    @Param(icon: "square.3.layers.3d") var planeRule = PlaneRule.primitive
    /// Whether the clock is running: the start and stop.
    @Param(icon: "playpause") var isRunning = true
    /// How loud the tones are; 0 is silence.
    @Param(0 ... 1, icon: "speaker.wave.2") var volume = 0.4

    // MARK: The arithmetic, from the article

    /// His mask M_p, a column per bit of a square's number: entry k is column
    /// k + 1 of the printed matrix, its bit m the matrix's row m + 1.
    static let mask = [9, 11, 15, 7, 14, 5, 10, 13, 3, 6]

    struct Square {
        let row: Int
        let column: Int
        /// 0 to 3 for the planes A to D.
        let plane: Int
        /// The residue class, 0 to 15: the color, and the tone.
        let color: Int
        /// 0 to 3, the two low bits of the class.
        let depth: Int
    }

    static let squares: [Square] = (0 ..< 32).flatMap { row in
        (0 ..< 32).map { column in square(row, column) }
    }

    static func square(_ row: Int, _ column: Int) -> Square {
        let plane = 2 * (row & 1) + (column & 1)
        let number = 256 * plane + 16 * (column >> 1) + (row >> 1)
        var residue = 0
        for bit in 0 ..< 10 where number >> bit & 1 == 1 {
            residue ^= mask[bit]
        }
        return Square(row: row, column: column, plane: plane, color: residue, depth: residue & 3)
    }

    /// x^16 + x^12 + x^3 + x + 1 without its leading term.
    static let fieldFeedback: UInt16 = 1 << 12 | 1 << 3 | 1 << 1 | 1

    static func fieldTimesX(_ value: UInt16) -> UInt16 {
        value & 0x8000 != 0 ? (value << 1) ^ fieldFeedback : value << 1
    }

    /// The plane polynomial's low terms, by rule.
    var planeFeedback: UInt8 {
        switch planeRule {
        case .primitive: return 0b0011
        case .reversed: return 0b1001
        case .short: return 0b1111
        }
    }

    func planesTimesX(_ value: UInt8) -> UInt8 {
        let shifted = value << 1
        return shifted & 0x10 != 0 ? (shifted & 0xF) ^ planeFeedback : shifted
    }

    /// The rhythm register's degree and low terms: x^5 + x^2 + 1 (31 ticks,
    /// 16 of them steps) or x^3 + x + 1 (7 ticks, 4 steps).
    var rhythmRegister: (degree: Int, feedback: UInt8) {
        rhythm == .short ? (3, 0b011) : (5, 0b00101)
    }

    /// The frequency of class `color`'s tone in `plane`, from his Table 1.
    static func tone(color: Int, plane: Int) -> Double {
        Double(8 * (8 + color % 8)) * Double(1 << (2 * plane + color / 8))
    }

    // MARK: State

    /// The first generator: bit i sets the squares of class i.
    var field: UInt16 = 1
    /// The second: bit k lets plane k light and sound.
    var planes: UInt8 = 1
    /// The rhythm; its top bit says whether a tick is a step.
    var beat: UInt8 = 1
    /// Where the object was switched on, for the replay.
    var switchedOn: (field: UInt16, planes: UInt8, beat: UInt8) = (1, 1, 1)
    var phase = 0.0
    /// Planes whose tones are silenced from the console.
    var silenced = [false, false, false, false]
    /// How brightly each color glows in each plane, color * 4 + plane.
    var glow = [Double](repeating: 0, count: 64)

    let synth = Synth(Voice(waveform: .sine,
                            envelope: Envelope(attack: 0.02, decay: 0, sustain: 1, release: 0.12)),
                      polyphony: 64)
    var sounding: [Int: PlayingNote] = [:]
    /// Quieter the higher the plane.
    let planeLoudness = [1.0, 0.6, 0.34, 0.16]

    // MARK: Look

    let room = Color(hex: 0x070708)
    let tubeColor = Color(hex: 0x5A301F)
    let frameGreys = [Color(hex: 0x24211F), Color(hex: 0x3A3532), Color(hex: 0x534C47), Color(hex: 0x70675F)]
    let indicatorOff = Color(hex: 0x2A1712)
    let indicatorOn = Color(hex: 0xFF8A4C)
    /// The sixteen glasses. The article gives their number, not their colors;
    /// these are read from photographs of the object, whites and blues and
    /// greens beside yellows, oranges and reds.
    let glasses: [Color] = [
        Color(hex: 0xFFF1D6), Color(hex: 0xE4F3FF), Color(hex: 0x9FE6FF), Color(hex: 0x52B6F2),
        Color(hex: 0x3563D8), Color(hex: 0x33C3AE), Color(hex: 0x3DB24C), Color(hex: 0xA6E07A),
        Color(hex: 0xF6E14E), Color(hex: 0xF7B235), Color(hex: 0xF08A26), Color(hex: 0xE8562B),
        Color(hex: 0xD2302C), Color(hex: 0x9E2030), Color(hex: 0xF07EA2), Color(hex: 0x8C5ECB),
    ]

    /// Where the plan's squares are drawn, and the console under them.
    let face = Rectangle(x: 100, y: 36, width: 880, height: 880)
    var pitch: Double { face.width / 32 }
    var consoleY: Double { face.y + face.height + 58 }

    /// The object in meters: squares 4.5 centimeters apart, the matrix's
    /// middle 1.05 meters off the floor.
    let spacing = 0.045
    let middle = 1.05

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        // Switched on somewhere along its walk; the seed says where.
        field = UInt16(random(1, 65_536))
        planes = UInt8(random(1, 16))
        beat = UInt8(random(1, 32))
        switchedOn = (field, planes, beat)
        for index in glow.indices {
            glow[index] = isLit(color: index / 4, plane: index % 4) ? 1 : 0
        }
    }

    func isLit(color: Int, plane: Int) -> Bool {
        field >> UInt16(color) & 1 == 1 && planes >> UInt8(plane) & 1 == 1
    }

    // MARK: Running

    /// One tick of the clock: the rhythm decides, and a step multiplies both
    /// generators by x.
    func tick() {
        var steps = true
        if rhythm != .none {
            let (degree, feedback) = rhythmRegister
            let full = UInt8(1) << UInt8(degree)
            // A register left over from the other length keeps only its bits.
            beat &= full - 1
            if beat == 0 { beat = 1 }
            steps = beat & full >> 1 != 0
            let shifted = beat << 1
            beat = shifted & full != 0 ? (shifted ^ full) ^ feedback : shifted
        }
        if steps {
            field = Self.fieldTimesX(field)
            planes = planesTimesX(planes)
        }
    }

    override func draw() {
        if isRunning {
            phase += deltaTime / clock
            while phase >= 1 {
                phase -= 1
                tick()
            }
        }
        for index in glow.indices {
            let target = isLit(color: index / 4, plane: index % 4) ? 1.0 : 0.0
            let settle = target > glow[index] ? 0.045 : 0.11
            glow[index] += (target - glow[index]) * (1 - exp(-deltaTime / settle))
        }
        sound()

        background(room)
        if view == .plan {
            drawPlan()
        } else {
            drawObject()
        }
        drawConsole()
        postProcess(.bloom(threshold: 0.9, amount: 0.8, radius: 9))
    }

    /// Starts the tones that should sound and stops the ones that should not.
    func sound() {
        synth.gain = volume * 0.14
        var wanted: Set<Int> = []
        for color in 0 ..< 16 where field >> UInt16(color) & 1 == 1 {
            for plane in 0 ..< 4 where planes >> UInt8(plane) & 1 == 1 && !silenced[plane] {
                wanted.insert(color * 4 + plane)
            }
        }
        for (key, note) in sounding where !wanted.contains(key) {
            synth.noteOff(note)
            sounding[key] = nil
        }
        for key in wanted where sounding[key] == nil {
            let pitch = Pitch(frequency: Self.tone(color: key / 4, plane: key % 4))
            sounding[key] = synth.noteOn(pitch, velocity: 0.8 * planeLoudness[key % 4])
        }
    }

    // MARK: Drawing

    func glassColor(_ square: Square, dimmed: Double = 0.16) -> Color {
        let level = glow[square.color * 4 + square.plane]
        let glass = glasses[square.color]
        return Color(hex: 0x0B0B0D).mixed(with: glass, dimmed + (1 - dimmed) * level)
    }

    /// The glass as the room sees it: dark and tinted when its lamp is off,
    /// and brighter than white when it is on, so the bloom takes it.
    func litGlass(_ square: Square) -> Color {
        let level = glow[square.color * 4 + square.plane]
        let glass = glasses[square.color].linearRGB
        return Color(linear: glass * (0.012 + 1.7 * level) + SIMD3(repeating: 0.004))
    }

    /// The plan: every square flat, the frame round each glass as light as its
    /// tube is long.
    func drawPlan() {
        noStroke()
        let inset = pitch * 0.17
        for square in Self.squares {
            let corner = Vector2(face.x + Double(square.column) * pitch, face.y + Double(square.row) * pitch)
            fill(frameGreys[square.depth])
            drawRect(corner: corner + Vector2(0.5, 0.5), width: pitch - 1, height: pitch - 1)
            fill(glassColor(square))
            drawRect(corner: corner + Vector2(inset, inset), width: pitch - 2 * inset, height: pitch - 2 * inset)
        }
    }

    /// The object in its room.
    func drawObject() {
        if view == .face {
            ortho(eye: Vector3(0, middle - 0.13, 5), target: Vector3(0, middle - 0.13, 0), height: 1.86)
        } else {
            // A slow walk past it, from well off to one side to nearly in
            // front, so the tubes' lengths show.
            let sway = 0.62 + sin(time * 2 * .pi / 44) * 0.3
            let eye = Vector3(sin(sway) * 3.8, 1.3, cos(sway) * 3.8)
            perspective(eye: eye, target: Vector3(0, middle - 0.02, 0), fieldOfView: 0.6)
        }

        ambientLight(Color(white: 0.03))
        directionalLight(Color(hex: 0xFFE2C0), direction: Vector3(-0.45, -0.6, -0.65), intensity: 0.13)
        lightTheBlocks()

        // The floor, the plinth, and the housing the tubes stand out from.
        noStroke()
        fill(Color(hex: 0x141312))
        drawPlane(width: 12, depth: 12)
        withState {
            translate(0, 0.14, -0.2)
            fill(Color(hex: 0x171311))
            drawBox(width: 1.7, height: 0.28, depth: 0.5)
        }
        withState {
            translate(0, middle, -0.04)
            fill(Color(hex: 0x1B1917))
            drawBox(width: 1.5, height: 1.5, depth: 0.08)
        }

        // A copy's color multiplies the fill, so the fill goes back to white.
        fill(.white)
        let tube = Mesh.box(size: 1)
        var bodies: [MeshInstance] = []
        var glassFaces: [MeshInstance] = []
        bodies.reserveCapacity(1024)
        glassFaces.reserveCapacity(1024)
        for square in Self.squares {
            let length = 0.08 + 0.04 * Double(square.depth)
            let x = (Double(square.column) - 15.5) * spacing
            let y = middle + (15.5 - Double(square.row)) * spacing
            bodies.append(MeshInstance(position: Vector3(x, y, length / 2),
                                       scale: Vector3(spacing * 0.96, spacing * 0.96, length),
                                       color: tubeColor))
            glassFaces.append(MeshInstance(position: Vector3(x, y, length + 0.0015),
                                           scale: Vector3(spacing * 0.9, spacing * 0.9, 0.003),
                                           color: litGlass(square)))
        }
        drawMesh(tube, instances: bodies)
        // The glass is its own light, so it is drawn flat.
        withoutLights {
            drawMesh(tube, instances: glassFaces)
        }
    }

    /// What the lit glass throws on the tubes round it: one lamp for each
    /// four by four block, the color and strength of what is lit there.
    func lightTheBlocks() {
        for blockRow in 0 ..< 8 {
            for blockColumn in 0 ..< 8 {
                var sum = SIMD3<Double>(0, 0, 0)
                for row in blockRow * 4 ..< blockRow * 4 + 4 {
                    for column in blockColumn * 4 ..< blockColumn * 4 + 4 {
                        let square = Self.squares[row * 32 + column]
                        sum += glasses[square.color].linearRGB * glow[square.color * 4 + square.plane]
                    }
                }
                let strength = (sum.x + sum.y + sum.z) / 3
                guard strength > 0.01 else { continue }
                let x = (Double(blockColumn * 4) + 1.5 - 15.5) * spacing
                let y = middle + (15.5 - Double(blockRow * 4) - 1.5) * spacing
                pointLight(Color(linear: sum / max(sum.x, sum.y, sum.z)), at: Vector3(x, y, 0.26),
                           intensity: strength * 2.2, reach: 0.34)
            }
        }
    }

    /// The console: the first generator's sixteen bits, the second's four, and
    /// the rhythm, each lit bit an amber lamp; the highest bit on the left.
    func drawConsole() {
        noStroke()
        for bit in 0 ..< 16 {
            indicator(slot: 15 - bit, lit: field >> UInt16(bit) & 1 == 1)
        }
        for bit in 0 ..< 4 {
            indicator(slot: 21 - bit, lit: planes >> UInt8(bit) & 1 == 1)
            // A plane's tones: a dot under it, hollow while they are silenced.
            let x = slotX(21 - bit)
            fill(silenced[bit] ? Color(white: 0.16) : Color(white: 0.5))
            drawCircle(center: Vector2(x, consoleY + 22), radius: 2.5)
        }
        if rhythm != .none {
            let degree = rhythmRegister.degree
            for bit in 0 ..< degree {
                indicator(slot: 24 + degree - 1 - bit, lit: beat >> UInt8(bit) & 1 == 1)
            }
        }
        let label = Color(white: 0.42)
        drawText("x¹⁶ + x¹² + x³ + x + 1", face.x, consoleY + 48, size: 16, color: label, align: .left)
        let planeLabel: String
        switch planeRule {
        case .primitive: planeLabel = "x⁴ + x + 1"
        case .reversed: planeLabel = "x⁴ + x³ + 1"
        case .short: planeLabel = "x⁴ + x³ + x² + x + 1"
        }
        drawText(planeLabel, slotX(18) - pitch / 2, consoleY + 48, size: 16, color: label, align: .left)
        let rhythmLabel = rhythm == .none ? "no rhythm" : rhythm == .short ? "x³ + x + 1" : "x⁵ + x² + 1"
        drawText(rhythmLabel, face.x + face.width, consoleY + 48, size: 16, color: label, align: .right)
    }

    func slotX(_ slot: Int) -> Double {
        face.x + (Double(slot) + 0.5) * pitch
    }

    func indicator(slot: Int, lit: Bool) {
        fill(lit ? indicatorOn : indicatorOff)
        drawCircle(center: Vector2(slotX(slot), consoleY), radius: pitch * 0.2)
    }

    // MARK: The visitor's controls

    override func keyPressed() {
        switch key {
        case " ":
            isRunning.toggle()
        case "r", "R":
            // The replay: back to where it was switched on.
            (field, planes, beat) = switchedOn
            phase = 0
        case "1", "2", "3", "4":
            if let plane = key?.wholeNumberValue {
                silenced[plane - 1].toggle()
            }
        default:
            break
        }
    }
}
