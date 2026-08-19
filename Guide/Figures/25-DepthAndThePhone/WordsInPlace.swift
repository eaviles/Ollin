// figure: frame=0
//
// Guide figure (Chapter 25): two lines from the phone's text stream, drawn as
// wire-frame stroke type inside framed panels. The word OLLIN stands upright on
// an implied wall; the word hello lies flat on a small table slab. Each line's
// worldTransform places its panel, so the same drawing code serves both.
//
// The lines are staged rather than read, the way this chapter's other figures
// stage a depth camera: the same PhoneText a phone fills in, built by hand from
// a PhoneTextSample so the figure renders anywhere.
import Foundation
import simd
import Ollin
import OllinPhone

final class WordsInPlace: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    let inkColor = Color(hex: 0xFFC46B)
    let frameColor = Color(hex: 0x5E708F)

    /// A staged line: the image corners matter little here (the figure draws the
    /// world side), so they mirror the world quad loosely.
    static func stagedLine(_ text: String, corners: [SIMD3<Float>]) -> PhoneText {
        PhoneText(PhoneTextSample(
            tracked: true, timestamp: 0, text: text, confidence: 0.95,
            corners: [SIMD2<Float>(0.3, 0.7), SIMD2<Float>(0.7, 0.7),
                      SIMD2<Float>(0.7, 0.6), SIMD2<Float>(0.3, 0.6)],
            hasWorldCorners: true, worldCorners: corners))
    }

    /// OLLIN, hanging on a wall behind the table, facing the camera.
    let wallSign = stagedLine("OLLIN", corners: [
        SIMD3<Float>(-0.45, 1.7, -1.2), SIMD3<Float>(0.45, 1.7, -1.2),
        SIMD3<Float>(0.45, 1.45, -1.2), SIMD3<Float>(-0.45, 1.45, -1.2),
    ])

    /// hello, lying flat on the table slab, read from this side.
    let tablePage = stagedLine("hello", corners: [
        SIMD3<Float>(-0.28, 0.75, 0.06), SIMD3<Float>(0.22, 0.75, 0.06),
        SIMD3<Float>(0.22, 0.75, 0.3), SIMD3<Float>(-0.28, 0.75, 0.3),
    ])

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: Vector3(0, 1.05, -0.35), radius: 2.5,
                         azimuth: 0.42, elevation: 0.3, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.0).lightingOnly())

        // The surfaces the lines sit on, hinted: a wall pane and a table slab.
        material(.clay)
        fill(Color(white: 0.16))
        withState {
            translate(0, 1.35, -1.23)
            drawBox(width: 1.5, height: 1.0, depth: 0.03)
        }
        withState {
            translate(-0.03, 0.71, 0.18)
            drawBox(width: 0.85, height: 0.06, depth: 0.5)
        }

        for line in [wallSign, tablePage] { drawLine(line) }

        drawCaption("WordsInPlace: one worldTransform per line places both panels")
    }

    /// The same drawing the PhoneWorldText example does: the panel outline on the
    /// line's quad, and the stroke-font contours scaled to its width in meters.
    private func drawLine(_ line: PhoneText) {
        guard let placement = line.worldTransform else { return }
        let width = line.worldWidth
        let height = line.worldHeight
        let type = wireType(of: line.text)
        withState {
            transform(placement)
            material(.clay)
            fill(frameColor)
            drawTube([Vector3(-width / 2, -height / 2, 0), Vector3(width / 2, -height / 2, 0),
                      Vector3(width / 2, height / 2, 0), Vector3(-width / 2, height / 2, 0)],
                     radius: 0.008, sides: 5, closed: true)
            fill(inkColor)
            for polyline in type {
                let path = polyline.map { Vector3($0.x * width, $0.y * width, 0.012) }
                drawTube(path, radius: 0.009, sides: 6)
            }
        }
    }

    /// Stroke-font contours of one string, normalized to a unit-width, y-up box
    /// centered on the origin (the example caches these; a still figure just
    /// builds them).
    private func wireType(of text: String) -> [[Vector2]] {
        textSize(120)
        var polylines: [[Vector2]] = []
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for shape in textToShapes(text, 0, 0) {
            for contour in shape.contours where contour.points.count >= 2 {
                polylines.append(contour.points)
                for p in contour.points {
                    minX = min(minX, p.x); maxX = max(maxX, p.x)
                    minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
        }
        guard maxX > minX else { return [] }
        let s = 1 / (maxX - minX)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        return polylines.map { $0.map { Vector2(($0.x - cx) * s, (cy - $0.y) * s) } }
    }
}
