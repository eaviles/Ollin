import Ollin

/// Shape morphing: one outline tweened into another, with every in-between a
/// real vector shape. Three `ShapeMorph`s prepared in `setup()` chain a star
/// into a wavy blob, the blob into a donut (watch the hole grow out of the
/// center: an unmatched contour scales in rather than popping), and the donut
/// back into the star. The faint outlines are the same morph read a little
/// earlier, which is the point of geometry-first morphing: an in-between can
/// be stroked, hatched, or exported like anything else. The cycle declares
/// `loopDuration`, so `--export-loop morph.gif` renders one seamless lap.
@main
final class Morphing: Sketch {
    @Param("Ghosts", 0 ... 12) var ghosts = 5
    @Param("Show fill") var showFill = true

    let period = 12.0
    override var loopDuration: Double? { period }

    var morphs: [ShapeMorph] = []

    override func setup() {
        let c = bounds.center
        let r = 300 * scale

        // Three key shapes, all plain math so the loop reproduces exactly.
        let star = Shape((0 ..< 10).map { i in
            let angle = Double(i) / 10 * .tau - .tau / 4
            return c + Vector2(angle: angle, length: i.isMultiple(of: 2) ? r : r * 0.44)
        })
        let blob = Shape((0 ..< 120).map { i in
            let angle = Double(i) / 120 * .tau
            let wobble = 0.16 * sin(3 * angle + 1.2) + 0.09 * sin(7 * angle + 0.4)
            return c + Vector2(angle: angle, length: r * (0.82 + wobble))
        })
        let donut = Shape(outer: (0 ..< 96).map { c + Vector2(angle: Double($0) / 96 * .tau, length: r * 0.9) },
                          holes: [(0 ..< 64).map { c + Vector2(angle: Double($0) / 64 * .tau, length: r * 0.42) }])

        morphs = [ShapeMorph(from: star, to: blob),
                  ShapeMorph(from: blob, to: donut),
                  ShapeMorph(from: donut, to: star)]
    }

    /// The blended shape at a phase measured in legs (one unit per morph),
    /// wrapping around the cycle so a lagging read is always valid.
    func snapshot(at phase: Double) -> Shape {
        guard !morphs.isEmpty else { return Shape([]) }
        var p = phase.truncatingRemainder(dividingBy: Double(morphs.count))
        if p < 0 { p += Double(morphs.count) }
        let leg = min(Int(p), morphs.count - 1)
        return morphs[leg].shape(at: Easing.easeInOut(p - Double(leg)))
    }

    override func draw() {
        background(Color(hex: 0x10151B))
        let phase = loopProgress(over: period) * Double(morphs.count)

        // Echoes of the recent past, oldest and faintest first.
        noFill()
        if ghosts > 0 {
            for g in stride(from: ghosts, through: 1, by: -1) {
                let age = Double(g) / Double(ghosts)      // 1 = oldest
                strokeWeight(1.2 * scale)
                stroke(Color(hex: 0x5F7A8C, alpha: 0.06 + 0.22 * (1 - age)))
                drawShape(snapshot(at: phase - 0.30 * age))
            }
        }

        // The morph itself.
        if showFill {
            fill(Color(hex: 0xE8B25C))
        } else {
            noFill()
        }
        stroke(Color(hex: 0xF4EAD6))
        strokeWeight(3 * scale)
        drawShape(snapshot(at: phase))
    }
}
