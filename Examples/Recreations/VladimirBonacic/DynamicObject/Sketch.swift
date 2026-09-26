//  Recreation after Vladimir Bonačić - Dynamic Object GF.E 32-S 69/70 (Zagreb,
//  1969 to 1970): a square of 32 by 32 lamps behind aluminum tubes, lit one
//  pattern at a time by a special-purpose computer inside the object that
//  walks through the Galois field of 2^32 elements.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://www.jstor.org/stable/1572890
//
//  An original Ollin interpretation, written from the arithmetic the artist
//  published with the object in Leonardo 7:3 (1974). Nothing was ported: the
//  object was a machine of lamps and logic built in Zagreb, and its program
//  was the field itself.

import Ollin

/// A dynamic object (Vladimir Bonačić, 1969 to 1970). A square panel of 1,024
/// lamps, each at the back of a square aluminum tube, and a computer behind
/// it that lights them a pattern at a time. The patterns are not random, and
/// that was the point of the piece: every one of them is an element of a
/// finite field, and the sequence is the field's own arithmetic.
///
/// Two pieces of algebra make the picture, both as the artist published them.
///
/// The first decides which lamps belong together. Number the lamps 0 to 1023
/// down the columns, write each number as a polynomial over GF(2) with ten
/// terms, and reduce it modulo x^5 + 1. What is left has five bits, so it
/// names one of 32 *residue classes*, and the lamps of one class always flash
/// together. Reducing modulo x^5 + 1 folds the top five bits onto the bottom
/// five, so a lamp's class is its row and its column combined bit by bit,
/// `row ^ column`. Each class holds 32 lamps, one in every row and every
/// column. Class 0 is the diagonal and class 31 the other diagonal; the rest
/// are diagonals broken into blocks, and that is where the rings, the pairs of
/// squares and the split triangles in the patterns come from. Every pattern is
/// symmetric about the diagonal, because the XOR of a row and a column does
/// not care which is which.
///
/// The second decides which classes are lit. The pattern is an element of
/// GF(2^32), the field of polynomials over GF(2) reduced modulo
/// x^32 + x^22 + x^2 + x + 1, which is irreducible and primitive: bit i of the
/// element lights class i. At every tick of the clock the element is
/// multiplied by x. Because the polynomial is primitive, x reaches every
/// nonzero element before it comes back, so the object shows 2^32 - 1
/// patterns without repeating one. At one pattern every two seconds that is
/// more than 270 years.
///
/// On the back of the object were the manual controls: start and stop, a
/// clock the visitor could set anywhere from a tenth of a second to five, and
/// a row of 32 indicator lamps with 32 push buttons, so the pattern on the
/// front could be read in binary or set by hand. They are drawn along the
/// bottom here, the highest bit on the left. Click a button to flip its bit.
/// Any pattern set that way is still a step of the same walk, since every
/// nonzero element is, and the walk carries on from it; only the dark
/// pattern, zero, is refused, because x times zero is zero forever. Space
/// starts and stops the clock.
@main
final class DynamicObject: Sketch {
    /// Seconds each pattern stays up. The object's own clock went from 0.1 to 5,
    /// and two seconds is the rate the artist reckoned its cycle at.
    @Param(0.1 ... 5, icon: "metronome") var clock = 2.0
    /// Whether the clock is running: the start and stop on the back.
    @Param(icon: "playpause") var isRunning = true

    /// x^32 + x^22 + x^2 + x + 1 without its leading term: what x^32 is equal
    /// to in this field, and what folds back in when a product overflows.
    static let feedback: UInt32 = 1 << 22 | 1 << 2 | 1 << 1 | 1

    /// The field element on the lamps. Bit i lights residue class i.
    var element: UInt32 = 1
    /// How far into the current tick the clock is, in ticks.
    var phase = 0.0
    /// How brightly each class's lamps glow, from 0 to 1. A filament takes a
    /// moment to warm and a little longer to cool, and every lamp of a class is
    /// switched together, so one level per class is all the panel needs.
    var glow = [Double](repeating: 0, count: 32)

    let room = Color(hex: 0x0A0A0C)
    let aluminum = Color(hex: 0x3C3F44)
    let darkTube = Color(hex: 0x131416)
    let filament = Color(hex: 0xFFF4DE)
    let indicatorOff = Color(hex: 0x2A1712)
    let indicatorOn = Color(hex: 0xFF8A4C)
    let buttonColor = Color(hex: 0x6E7176)

    /// The front of the object.
    let face = Rectangle(x: 100, y: 36, width: 880, height: 880)
    /// Where the rear panel's indicators and buttons sit, left to right from
    /// bit 31 down to bit 0, under the matching width of the face.
    var indicatorY: Double { face.y + face.height + 46 }
    var buttonY: Double { face.y + face.height + 96 }
    var pitch: Double { face.width / 32 }

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        // Switched on somewhere along its walk; the seed says where.
        element = UInt32(random(1, 4_294_967_295))
        for bit in 0..<32 {
            glow[bit] = isLit(bit) ? 1 : 0
        }
    }

    /// One tick of the generator: multiply by x, modulo the polynomial. The
    /// product has a term in x^32 only when bit 31 was set, and that term is
    /// replaced by what x^32 equals here.
    static func timesX(_ value: UInt32) -> UInt32 {
        let overflows = value & 0x8000_0000 != 0
        return overflows ? (value << 1) ^ feedback : value << 1
    }

    func isLit(_ bit: Int) -> Bool {
        element >> UInt32(bit) & 1 == 1
    }

    override func draw() {
        if isRunning {
            phase += deltaTime / clock
            while phase >= 1 {
                phase -= 1
                element = Self.timesX(element)
            }
        }
        for bit in 0..<32 {
            let target = isLit(bit) ? 1.0 : 0.0
            let settle = target > glow[bit] ? 0.045 : 0.11
            glow[bit] += (target - glow[bit]) * (1 - exp(-deltaTime / settle))
        }

        background(room)
        noStroke()
        drawFace()
        drawRearPanel()
        postProcess(.bloom(threshold: 0.72, amount: 0.4, radius: 3))
    }

    /// The front: an aluminum lattice of square tubes, a lamp at the back of
    /// each. The tube keeps each lamp's light to its own square, which is why
    /// the patterns read as crisp cells rather than as a glow.
    func drawFace() {
        fill(aluminum)
        drawRect(face)
        let wall = pitch * 0.085
        let side = pitch - 2 * wall
        for column in 0..<32 {
            for row in 0..<32 {
                let level = glow[row ^ column]
                let corner = Vector2(face.x + Double(column) * pitch + wall,
                                     face.y + Double(row) * pitch + wall)
                fill(darkTube.mixed(with: filament, level))
                drawRect(corner: corner, width: side, height: side)
                // The bulb itself: a dull glass disc when it is dark, and when it
                // is lit the brightest spot in its tube.
                let bulb = Color(hex: 0x24252A).mixed(with: .white, level)
                fill(bulb)
                drawCircle(center: corner + Vector2(side / 2, side / 2), radius: side * 0.2)
            }
        }
    }

    /// The back of the object, brought round to the front: 32 indicators that
    /// show the element in binary, and 32 push buttons that set it.
    func drawRearPanel() {
        for bit in 0..<32 {
            let x = slotX(bit)
            fill(indicatorOff.mixed(with: indicatorOn, glow[bit]))
            drawCircle(center: Vector2(x, indicatorY), radius: pitch * 0.2)
            fill(buttonColor)
            drawRect(center: Vector2(x, buttonY), width: pitch * 0.56, height: pitch * 0.56,
                     cornerRadius: pitch * 0.08)
        }
        drawText("x³² + x²² + x² + x + 1", face.x + face.width, buttonY + 44,
                 size: 17, color: Color(white: 0.42), align: .right)
        drawText(isRunning ? "running" : "stopped", face.x, buttonY + 44,
                 size: 17, color: Color(white: 0.42), align: .left)
    }

    /// The x of bit `bit`'s indicator and button: bit 31 on the left.
    func slotX(_ bit: Int) -> Double {
        face.x + (Double(31 - bit) + 0.5) * pitch
    }

    override func mousePressed() {
        guard abs(mouse.y - buttonY) < pitch * 0.5 else { return }
        let slot = Int(((mouse.x - face.x) / pitch).rounded(.down))
        guard (0..<32).contains(slot) else { return }
        let flipped = element ^ (1 << UInt32(31 - slot))
        if flipped != 0 {
            element = flipped
        }
    }

    override func keyPressed() {
        if key == " " {
            isRunning.toggle()
        }
    }
}
