import Ollin

/// Regular tilings of the hyperbolic plane, seen through the Poincaré disk:
/// identical tiles meeting the same way at every vertex, repeating forever
/// into a circular horizon. The camera pans across the tiling on a slow
/// loop, so tiles grow as they reach the middle and shrink away again.
/// Click or press a key for the next tiling.
@main
final class HyperbolicDisk: Sketch {
    override var loopDuration: Double? { 24 }

    private let presets: [(sides: Int, meeting: Int, name: String)] = [
        (7, 3, "heptagons, three to a corner"),
        (5, 4, "pentagons, four to a corner"),
        (6, 4, "hexagons, four to a corner"),
        (4, 5, "squares, five to a corner"),
        (3, 7, "triangles, seven to a corner"),
        (8, 3, "octagons, three to a corner"),
    ]
    private var index = 0

    override func draw() {
        background(Color(hex: 0x0B0D12))
        let preset = presets[index]

        // Pan on a small closed circuit of the hyperbolic plane, so the
        // loop comes back to its start exactly.
        let t = loopProgress(over: 24) * 2 * .pi
        let viewpoint = Vector2(angle: t) * 0.32

        let disk = canvasRectangle.inset(by: 60)
        let tiles = hyperbolicTiling(sides: preset.sides, meeting: preset.meeting,
                                     in: disk, viewpoint: viewpoint, minEdge: 4)

        let checkerboard = preset.meeting.isMultiple(of: 2)
        noStroke()
        for tile in tiles {
            if checkerboard {
                fill(tile.parity == 0 ? Color(hex: 0xF2E9DC) : Color(hex: 0x24476B))
            } else {
                // Fade with distance from the central tile instead.
                let fade = min(Double(tile.depth) / 9, 1)
                fill(Color.mix(Color(hex: 0xF2E9DC), Color(hex: 0x24476B), t: fade))
            }
            drawShape(tile.shape)
        }

        // The geodesic lace over the fills, and the horizon itself.
        noFill()
        stroke(Color(hex: 0x0B0D12).withAlpha(0.85))
        strokeWeight(1.5)
        for tile in tiles {
            drawPolyline(tile.points, closed: true)
        }
        stroke(Color(hex: 0xF2D398).withAlpha(0.6))
        strokeWeight(2)
        drawCircle(center: disk.center, radius: min(disk.width, disk.height) / 2)

        drawCaption("{\(preset.sides),\(preset.meeting)}: \(preset.name); click or press a key for the next")
    }

    override func mousePressed() { advance() }
    override func keyPressed() { advance() }

    private func advance() {
        index = (index + 1) % presets.count
    }
}
