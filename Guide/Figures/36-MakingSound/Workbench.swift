// figure: frame=0
//
// Guide payoff (Chapter 36): the workbench, an instrument you play with the
// mouse. Three drawn outlines are measured for the tones they ring at, and
// under each one a row of bars shows which of those tones answer where the
// pointer is. Six strings are plucked where you click along them, and the
// last, thicker string is bowed for as long as you hold it, the speed of the
// drag being the bow's speed. Everything plays through one chain: a chorus,
// an echo, a room drawn from a rule, and a limiter, and the room's answer to
// a click is drawn across the top. Frame 0 is the bench at rest, with the
// bars read at the middle of each outline, since nothing has been played.
import Ollin
import OllinAudio

final class Workbench: Sketch {
    struct Plate {
        let outline: Shape
        let modes: StruckShape
        let note: Pitch
    }

    // A room drawn from a rule: noise between two close walls, so the sound
    // comes back in a burst every eighth of a second as it fades.
    let room = ImpulseResponse(seconds: 2.5) { t, noise in
        let slap = t.truncatingRemainder(dividingBy: 0.125) < 0.02 ? 1.0 : 0.3
        return noise * slap * exp(-2.2 * t)
    }
    let hands = Synth(.steel)
    let bow = Synth(.cello)

    var plates: [Plate] = []
    let strings: [Pitch] = ["E2", "A2", "D3", "G3", "B3", "E4"]
    var plucks: [Int: (along: Double, time: Double)] = [:]
    var ripples: [(at: Vector2, time: Double)] = []
    var roomOutline: [Double] = []
    var bowing = false
    var bowSpeed = 0.0

    let left = 120.0, right = 960.0, bowY = 980.0
    func stringY(_ i: Int) -> Double { 620 + Double(i) * 56 }

    override func setup() {
        let chain: [Effect] = [
            .chorus(Chorus(rate: 0.6, depth: 0.3)),
            .delay(Delay(time: 0.3, feedback: 0.35, mix: 0.2)),
            .reverb(Reverb(room, mix: 0.35)),
            .limiter(Limiter()),
        ]
        hands.effects = chain
        bow.effects = chain

        // Three outlines to strike: a drum, a plate, and a shape drawn by hand.
        // Measuring each one is the slow part, so it happens once, here.
        let drum = Shape((0..<48).map { i in
            Vector2(230, 330) + Vector2(cos(Double(i) / 48 * .tau), sin(Double(i) / 48 * .tau)) * 130
        }, closed: true)
        let plate = Shape([Vector2(430, 210), Vector2(660, 230), Vector2(640, 440), Vector2(410, 420)],
                          closed: true)
        let blob = Shape(curveThrough: [Vector2(780, 210), Vector2(930, 240), Vector2(960, 380),
                                        Vector2(840, 450), Vector2(740, 340)], closed: true)
        for (outline, note) in [(drum, "C3"), (plate, "G3"), (blob, "D4")] as [(Shape, Pitch)] {
            if let modes = StruckShape(outline) {
                plates.append(Plate(outline: outline, modes: modes, note: note))
            }
        }

        // The room's answer to a click, as one peak per column across the top.
        let samples = room.channels[0]
        let step = samples.count / 840
        roomOutline = (0..<840).map { c in
            Double(samples[c * step ..< (c + 1) * step].map { abs($0) }.max() ?? 0)
        }
        let top = roomOutline.max() ?? 1
        roomOutline = roomOutline.map { $0 / top }
    }

    override func mousePressed() {
        let hand = Vector2(mouseX, mouseY)
        // An outline rings where you strike it, and that decides which tones answer.
        for plate in plates where plate.outline.contains(hand) {
            hands.voice = Voice(struck: plate.modes.body(struckAt: hand))
            hands.play(plate.note, for: 3)
            ripples.append((hand, time))
            return
        }
        // A string is plucked where you click along it, and that decides its tone.
        for (i, note) in strings.enumerated() where abs(mouseY - stringY(i)) < 20 {
            let along = (mouseX - left) / (right - left)
            guard along > 0.02, along < 0.98 else { return }
            var string = PluckedString.steel
            string.position = along
            hands.voice = Voice(plucked: string)
            hands.play(note, for: 4)
            plucks[i] = (along, time)
            return
        }
        // The last string sounds for as long as you hold it.
        if abs(mouseY - bowY) < 24 {
            bow.noteOn("G2")
            bowing = true
        }
    }

    override func mouseReleased() {
        if bowing { bow.noteOff("G2") }
        bowing = false
    }

    override func draw() {
        background(Color(hex: 0x16141C))
        let ink = Color(hex: 0xE9DCC4)

        // The bow: how fast you drag is how fast the bow moves.
        bowSpeed = bowSpeed * 0.85 + abs(mouseX - previousMouse.x) * 0.15
        bow.pressure = bowing ? min(1, bowSpeed / 10) : 0

        // The room across the top.
        stroke(ink.withAlpha(0.5))
        strokeWeight(1)
        for (c, peak) in roomOutline.enumerated() {
            let x = left + Double(c)
            drawLine(x, 90 - peak * 50, x, 90 + peak * 50)
        }

        // The outlines, each with the tones it rings at drawn below it. The
        // taller a bar, the more that tone answers a strike at the pointer.
        for (n, plate) in plates.enumerated() {
            noFill()
            stroke(ink)
            strokeWeight(3)
            drawShape(plate.outline)
            let middle = plate.outline.bounds?.center ?? .zero
            let hand = Vector2(mouseX, mouseY)
            let at = plate.outline.contains(hand) ? hand : middle
            let gains = plate.modes.gains(struckAt: at)
            let x0 = 120 + Double(n) * 310
            strokeWeight(4)
            for (ratio, gain) in zip(plate.modes.ratios, gains) where ratio <= 4 {
                let x = x0 + (ratio - 1) / 3 * 220
                drawLine(x, 540, x, 540 - gain * 60)
            }
        }

        // A strike leaves a ring that spreads and fades.
        ripples = ripples.filter { time - $0.time < 1.5 }
        for ripple in ripples {
            let age = time - ripple.time
            stroke(ink.withAlpha(1 - age / 1.5))
            strokeWeight(2)
            drawCircle(ripple.at.x, ripple.at.y, 10 + age * 120)
        }

        // The strings. A plucked one keeps the bend of the pluck, shrinking as it rings.
        for i in strings.indices {
            let y = stringY(i)
            var bend = 0.0, along = 0.5
            if let pluck = plucks[i] {
                let age = time - pluck.time
                bend = 16 * exp(-age * 1.4) * cos(age * 40)
                along = pluck.along
            }
            stroke(ink.withAlpha(0.8))
            strokeWeight(3 - Double(i) * 0.3)
            let apex = left + along * (right - left)
            drawLine(left, y, apex, y + bend)
            drawLine(apex, y + bend, right, y)
        }

        // The bowed string shakes as long as the bow is moving.
        let shake = 10 * bow.pressure
        let bowed = (0...60).map { k -> Vector2 in
            let a = Double(k) / 60
            return Vector2(left + a * (right - left), bowY + sin(a * .pi) * shake * sin(time * 70))
        }
        stroke(Color(hex: 0xD9A441))
        strokeWeight(4)
        drawPolyline(bowed)
    }
}
