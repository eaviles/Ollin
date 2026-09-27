// figure: frame=420
//
// Guide payoff (Chapter 17): a monogram brushed over a marbled heart. A
// scatter of stones is combed into a feathered ground, a bull's-eye with a
// core of paper color is dropped over it, and one stylus pulled down through
// the eye bends its rings into a heart. The initials are written into the
// core by a pretend hand that slows into and out of every stroke, through a
// broad nib, over a spray of gold. The hand writes for four seconds and rests
// for four; the render is taken seven seconds in, with the letters finished.
import Ollin

final class Monogram: Sketch {
    @Param var initials = "OL"

    let paper = Color(hex: 0xEFE7D6)
    let navy = Color(hex: 0x1F2A44)
    let red = Color(hex: 0xA43B2A)
    let gold = Color(hex: 0xC8912F)
    let green = Color(hex: 0x3A6B5C)

    var bath = Marbling()
    var strokes: [StrokeMark] = []
    var written = ""

    var sheet: Rectangle { bounds.inset(by: .all(70)) }

    override func setup() {
        seed(4)
        bath = Marbling()
        let inks = [navy, red, gold, green]

        // The ground: stones scattered over the sheet, combed down and back up.
        for _ in 0 ..< 70 {
            bath.drop(at: randomVector(in: sheet), radius: random(20, 55),
                      color: randomChoice(inks))
        }
        bath.comb(through: Vector2(0, height / 2), direction: .unitY,
                  spacing: 90, strength: 200, falloff: 26)
        bath.comb(through: Vector2(45, height / 2), direction: -.unitY,
                  spacing: 90, strength: 140, falloff: 20)

        // The bull's-eye, with a core of paper color to write in. Every drop
        // pushes the ground outward, so a small eye keeps the feathering in view.
        let eye = Vector2(540, 420)
        for ring in 0 ..< 6 {
            bath.drop(at: eye, radius: 200 - Double(ring) * 15, color: inks[ring % 4])
        }
        bath.drop(at: eye, radius: 100, color: paper)

        // One stylus pulled down through the eye makes the heart.
        bath.tine(through: eye, direction: .unitY, strength: 240, falloff: 160)
    }

    // A pretend hand: slow into each stroke and out of it, quick through the
    // middle, so the speed brush swells the ends and thins the run.
    func handwrite(_ path: Contour) -> StrokeMark {
        var mark = StrokeMark(.speed(reference: 1200, fast: 0.45), smoothing: 0.4)
        let points = path.resampled(spacing: 3).points
        for (i, p) in points.enumerated() {
            let t = Double(i) / Double(max(1, points.count - 1))
            let pause = 1 + 3 * (1 - sin(.pi * t))
            mark.record(p, deltaTime: pause / 400)
        }
        return mark
    }

    // The initials as single pen lines, each line written by the hand.
    func letter() {
        textFont(StrokeFont.builtIn)
        textSize(120)
        textAlign(.center, .middle)
        strokes = textToShapes(initials, 540, 600)
            .flatMap { $0.contours }
            .map { handwrite($0) }
        written = initials
    }

    override func draw() {
        if written != initials { letter() }
        background(paper)

        noStroke()
        withClip(sheet) { drawMarbling(bath) }

        // A dotted rule around the sheet.
        noFill()
        stroke(navy)
        strokeWeight(5)
        strokeCap(.round)
        strokeDash(.dots(spacing: 16))
        drawRect(bounds.inset(by: .all(48)))
        noStrokeDash()

        // The hand writes for four seconds, rests for four, and starts again.
        let lap = time.truncatingRemainder(dividingBy: 8)
        let total = strokes.reduce(0) { $0 + $1.samples.count }
        var left = Int(min(1, lap / 4) * Double(total))
        var shown: [StrokeMark] = []
        for mark in strokes where left > 1 {
            let part = StrokeMark(samples: Array(mark.samples.prefix(left)))
            shown.append(part)
            left -= part.samples.count
        }

        // Gold dust first, then the ink through a broad nib.
        stroke(gold.withAlpha(0.6))
        strokeWeight(34)
        strokeBrush(.spray(seed: 7))
        for part in shown { drawMark(part) }
        noStrokeBrush()

        stroke(navy)
        strokeWeight(22)
        strokeProfile(.nib(angle: .pi / 5))
        for part in shown { drawMark(part) }
        noStrokeProfile()
    }
}
