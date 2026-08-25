import Ollin

/// A Clifford attractor drawn as an accumulating density field: each frame
/// iterates the map forward another 80k steps and adds them, in faint additive
/// dots, onto a canvas that never clears. Where the orbit returns again and
/// again the dots pile into bright filaments; the sparse outskirts stay dim, so
/// the structure paints itself in over a few seconds.
///
/// `ChaoticMap.clifford()` is the iterated map `x' = sin(a·y) + c·cos(a·x)`,
/// `y' = sin(b·x) + d·cos(b·y)`, whose orbit stays within roughly ±2 on each
/// axis. Continuing one long orbit across frames (carrying `current` over) plus
/// `blendMode(.add)` over `noClear()` is the sandpainting build-up the float
/// pipeline is made for.
@main
final class CliffordAttractor: Sketch {
    let map = ChaoticMap.clifford()
    let perFrame = 80_000

    var current = Vector2(0.1, 0.1)      // the orbit position, carried across frames

    override func setup() {
        noClear()                         // pile onto a persistent canvas
        noStroke()
    }

    override func draw() {
        if frameCount == 1 { background(.black) }     // wipe once, then accumulate

        let reach = Double(shortSide) * 0.22
        let cx = width / 2, cy = height / 2

        var points = [Vector2]()
        points.reserveCapacity(perFrame)
        for _ in 0..<perFrame {
            current = map.next(current)
            points.append(Vector2(cx + current.x * reach, cy + current.y * reach))
        }

        blendMode(.add)
        fill(Color(red: 0.42, green: 0.74, blue: 1.0, alpha: 0.05))
        pointSize(1.0 * scale)
        drawPoints(points)
    }
}
