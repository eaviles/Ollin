// figure: frame=0
//
// Guide figure (Chapter 20): crumpled holographic foil, and the sheet under it.
// The left panel fills a heart with the foil filter over a FacetField. The
// right panel draws that same sheet in geometry, each facet shaded by how
// squarely it faces the light and every crease inked, with each facet cut to
// the panel by the half-plane clips, so the reader sees the facets the filter
// read and where its creases come from.
import Ollin

final class CrumpledFoil: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        let tile = 420.0, gap = 20.0, top = 24.0
        let left = (width - tile * 2 - gap) / 2
        let panel = Rectangle(x: 0, y: 0, width: tile, height: tile)
        let sheet = FacetField.crumpled(in: panel, spacing: 46, crinkle: 0.7, seed: 6)
        let light = (angle: -2.1, elevation: 0.85)

        // Left: the foil over a heart silhouette, the sheet handed in.
        let heart = makeRenderTarget(width: Int(tile), height: Int(tile))
        withTarget(heart) {
            noStroke()
            fill(.white)
            drawHeart(tile / 2, tile / 2 + 14, tile * 0.82)
        }
        drawImage(heart.filtered(.holographicFoil(facets: sheet, bandWidth: 30,
                                                  lightAngle: light.angle,
                                                  lightElevation: light.elevation,
                                                  phase: 1.1)).image, left, top)

        // Right: the same sheet in geometry, each facet shaded by its facing
        // and cut to the panel, every crease inked.
        withState {
            translate(left + tile + gap, top)
            let direction = FacetField.lightDirection(angle: light.angle, elevation: light.elevation)
            let inside = [HalfPlane(point: .zero, inward: Vector2(1, 0)),
                          HalfPlane(point: .zero, inward: Vector2(0, 1)),
                          HalfPlane(point: Vector2(tile, tile), inward: Vector2(-1, 0)),
                          HalfPlane(point: Vector2(tile, tile), inward: Vector2(0, -1))]
            noStroke()
            for facet in sheet.facets {
                let piece = inside.reduce(facet.shape) { $0.clipped(to: $1) }
                guard !piece.contours.isEmpty else { continue }
                fill(Color(white: 0.22 + 0.68 * facet.facing(direction)))
                drawShape(piece)
            }
            stroke(Color(hex: 0x0C0E13))
            strokeWeight(1)
            noFill()
            for edge in sheet.edges where panel.contains(edge.start) && panel.contains(edge.end) {
                drawLine(edge)
            }
        }

        textFont(.system)
        noStroke()
        fill(Color(white: 0.5))
        textSize(17)
        textAlign(.center, .top)
        drawText("the foil", left + tile / 2, top + tile + 10)
        drawText("the sheet it read, lit by the same light", left + tile * 1.5 + gap, top + tile + 10)
    }
}
