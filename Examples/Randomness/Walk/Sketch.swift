import Ollin

/// A seeded random walk revealed step by step: every frame redraws the same
/// path from its first step (the seed holds it still) while the clock decides
/// how many steps are visible, so the walk grows without boiling and comes to
/// rest after ten seconds. **Click** for a fresh walk in a newly picked color.
///
/// Demonstrates the walk idiom (accumulate nudges instead of re-rolling),
/// `randomSeed` replaying a path, and a seeded `randomChoice` from a palette.
@main
final class Walk: Sketch {
    var walkSeed = 7
    var startedAt = 0.0

    let inks: [Color] = [
        Color(hex: 0x64DFDF, alpha: 0.8), Color(hex: 0xFFB703, alpha: 0.8),
        Color(hex: 0xE56B6F, alpha: 0.8), Color(hex: 0x5E60CE, alpha: 0.8),
    ]

    override func draw() {
        background(Color(hex: 0x0E1116))
        randomSeed(walkSeed)
        stroke(randomChoice(inks))
        strokeWeight(2.5 * scale)

        var x = width / 2
        var y = height / 2
        let steps = min(2400, Int((time - startedAt) * 240))
        for _ in 0..<steps {
            let nx = x + random(-16, 16) * scale
            let ny = y + random(-16, 16) * scale
            drawLine(x, y, nx, ny)
            x = nx
            y = ny
        }

        noStroke()
        fill(.white)
        drawCircle(x, y, 9 * scale)
    }

    override func mousePressed() {
        walkSeed += 1
        startedAt = time
    }
}
