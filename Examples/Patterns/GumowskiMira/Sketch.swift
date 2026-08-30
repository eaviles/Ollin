import Ollin

/// A Gumowski-Mira blossom drawn as an accumulating density field. The map is
/// nearly area-preserving with a whisper of damping, so any one orbit slowly
/// decays onto a few islands; the classic pictures superimpose many. Each
/// frame starts a fresh orbit from a seeded random point in the sea, plots its
/// long wander in faint additive dots onto a canvas that never clears, and the
/// layered transients fill in the many-petaled filigree.
///
/// `ChaoticMap.gumowskiMira()` is the particle-beam recurrence
/// `x' = y + a·(1 - b·y²)·y + G(x)`, `y' = G(x') - x`; nudging `mu` reshapes
/// the blossom completely. The hue leans between ember and violet from orbit
/// to orbit, so the layers read as depth. Seeded, so the piece reproduces.
@main
final class GumowskiMira: Sketch {
    let map = ChaoticMap.gumowskiMira()
    let perOrbit = 60_000

    override func setup() {
        noClear()
        noStroke()
    }

    override func draw() {
        if frameCount == 1 {
            seed(7)
            background(.black)
        }

        let reach = Double(shortSide) * 0.052
        let cx = width / 2, cy = height / 2

        // A fresh orbit each frame, from a random start in the wide sea.
        var point = Vector2(random(-3, 3), random(-3, 3))
        var points = [Vector2]()
        points.reserveCapacity(perOrbit)
        for _ in 0..<perOrbit {
            point = map.next(point)
            points.append(Vector2(cx + point.x * reach, cy + point.y * reach))
        }

        let ember = Color(red: 1.0, green: 0.62, blue: 0.30, alpha: 0.045)
        let violet = Color(red: 0.62, green: 0.44, blue: 1.0, alpha: 0.045)
        blendMode(.add)
        fill(Color.mix(ember, violet, random(0, 1)))
        pointSize(1.0 * scale)
        drawPoints(points)
    }
}
