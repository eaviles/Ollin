import Ollin

/// The medial axis: letterforms reduced to their bones. Each glyph of the
/// word is skeletonized with `medialAxis(of:spacing:prune:)`, the branches
/// are stroked as the centerline the pen would have taken, and because
/// every skeleton point carries the radius of its inscribed disk, a bead
/// rolls along each bone at exactly the letter's local thickness, swelling
/// through the fat strokes and thinning into the serifs and joins.
///
/// ```sh
/// swift run Example-Shapes-MedialAxis --export-loop /tmp/bones.gif
/// ```
///
/// The skeleton is extracted once in `setup()` and held; drawing it is just
/// polylines and circles, so `--export-svg` writes plotter-ready line work.
@main
final class MedialAxis_Example: Sketch {
    private let period = 8.0
    override var loopDuration: Double? { period }

    private let paper = Color(hex: 0xF4EFE6)
    private let ink = Color(hex: 0x2F3B52)
    private let accent = Color(hex: 0xC2542E)

    private var glyphs: [Shape] = []
    private var skeletons: [MedialAxis] = []

    override func setup() {
        textFont(OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold)
        textAlign(.center, .middle)
        textSize(300)
        glyphs = textToShapes("bones", at: Vector2(width / 2, height * 0.46))
        skeletons = glyphs.map { medialAxis(of: $0, spacing: 3, prune: 10) }
    }

    override func draw() {
        background(paper)

        // The letterforms as faint outlines, the flesh around the bones.
        noFill()
        stroke(ink.withAlpha(0.35))
        strokeWeight(1.2 * scale)
        for glyph in glyphs { drawShape(glyph) }

        // Every skeleton branch, plus a sparse run of inscribed disks so the
        // clearance the axis carries stays visible as structure.
        stroke(ink)
        for skeleton in skeletons {
            strokeWeight(2.4 * scale)
            for branch in skeleton.branches {
                drawPolyline(branch.points, closed: branch.isClosed)
            }
            strokeWeight(0.7 * scale)
            for branch in skeleton.branches {
                for (i, pair) in zip(branch.points, branch.radii).enumerated()
                where pair.1 > 8 && i % 6 == 0 {
                    drawCircle(center: pair.0, radius: pair.1)
                }
            }
        }

        // One bead per long bone, rolling at the letter's local thickness.
        let t = loopProgress(over: period)
        noStroke()
        fill(accent.withAlpha(0.85))
        for skeleton in skeletons {
            for branch in skeleton.branches where branch.contour.length > 60 {
                let phase = branch.isClosed ? t : pingPong(over: period)
                let index = Int(phase * Double(branch.points.count - 1))
                drawCircle(center: branch.points[index],
                           radius: max(branch.radii[index], 3))
            }
        }

        drawCaption("medial axis: every letter reduced to its bones")
    }
}
