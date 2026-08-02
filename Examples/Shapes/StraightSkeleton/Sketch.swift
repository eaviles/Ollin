import Ollin

/// The straight skeleton as a topographic survey: a noise-grown island with
/// a lake is built once, `straightSkeleton(of:)` extracts its ridge network,
/// and the animated contour ladder is nothing but `inset(by:)` at a drifting
/// family of distances, each ring the island mitered inward, splitting where
/// the land pinches and circling the lake as it widens. Corner arcs run in
/// ink, the true ridges (both ends off the coast) in accent, and every mark
/// is real geometry, so `--export-svg` writes a plotter-ready contour map.
/// Each `variation` grows a new island.
///
/// ```sh
/// swift run Example-Shapes-StraightSkeleton --export-loop /tmp/ridges.gif
/// ```
@main
final class StraightSkeleton_Example: Sketch {
    private let period = 6.0
    override var loopDuration: Double? { period }

    private let paper = Color(hex: 0xF4EFE6)
    private let ink = Color(hex: 0x2F3B52)
    private let accent = Color(hex: 0xC2542E)
    private let water = Color(hex: 0x7A99B8)

    private var island = Shape(contours: [])
    private var skeleton = StraightSkeleton(arcs: [], faces: [], maxInset: 0)
    private let rungs = 12

    override func setup() {
        let center = Vector2(width / 2, height * 0.52)
        let coast = (0 ..< 40).map { i in
            let u = Double(i) / 40
            let angle = u * .tau
            let r = 330 + signedNoise(3, loop: u, radius: 1.7) * 110
            return center + Vector2(cos(angle), sin(angle)) * r
        }
        let lakeCenter = center + Vector2(random(-90, 90), random(-90, 90))
        let lake = (0 ..< 18).map { i in
            let u = Double(i) / 18
            let angle = u * .tau
            let r = 80 + signedNoise(11, loop: u, radius: 1.2) * 24
            return lakeCenter + Vector2(cos(angle), sin(angle)) * r
        }
        island = Shape(outer: coast, holes: [lake])
        skeleton = straightSkeleton(of: island)
    }

    override func draw() {
        background(paper)

        // Each face washed by how deep its edge's territory runs.
        noStroke()
        for face in skeleton.faces {
            let depth = (face.distances.max() ?? 0) / max(skeleton.maxInset, 1)
            fill(ink.withAlpha(0.04 + depth * 0.06))
            drawShape(Shape(face.points))
        }

        // The contour ladder: mitered insets at distances that drift inward
        // one rung per loop, fading in at the coast and out at the ridge.
        noFill()
        let phase = loopProgress(over: period)
        let step = skeleton.maxInset / Double(rungs)
        for rung in 0 ..< rungs {
            let depth = (Double(rung) + phase) * step
            let fade = min(depth / (step * 1.5), 1 - depth / skeleton.maxInset)
            guard fade > 0.01 else { continue }
            stroke(ink.withAlpha(0.65 * min(fade, 1)))
            strokeWeight(1.3 * scale)
            drawShape(skeleton.inset(by: depth))
        }

        // The skeleton: coast-to-ridge corner arcs faint, true ridges strong.
        strokeWeight(1 * scale)
        for arc in skeleton.arcs where arc.startDistance == 0 {
            stroke(ink.withAlpha(0.22))
            drawLine(arc.start, arc.end)
        }
        strokeWeight(2.4 * scale)
        for arc in skeleton.arcs where arc.startDistance > 0 {
            stroke(accent)
            drawLine(arc.start, arc.end)
        }

        // The coastline and the lake.
        stroke(ink)
        strokeWeight(2.6 * scale)
        drawShape(island)
        noStroke()
        fill(water.withAlpha(0.5))
        if island.contours.count > 1 {
            drawShape(Shape(contours: [island.contours[1]]))
        }

        drawCaption("straight skeleton: mitered insets ladder up to the ridge line")
    }
}
