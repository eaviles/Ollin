//  Recreation after Miguel Ángel Vidal - the generative paintings of the
//  1960s built from families of straight lines, read from Focos de luz
//  (1969, acrylic on canvas, 130 x 130 cm) in the Buffalo AKG Art Museum,
//  Homenaje a Albers (1967, oil on canvas, 96.6 x 96.6 cm) in the Museo de
//  Arte Moderno de Buenos Aires, and the untitled screenprint of 1969 in the
//  Victoria and Albert Museum, made from a plotter drawing of a triangle
//  turned about four points. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or his estate.
//  https://buffaloakg.org/artworks/k19707-focos-de-luz-lightbulbs
//  https://collections.vam.ac.uk/item/O152198/print-vidal-miguel-angel/
//
//  An original Ollin interpretation, written from the paintings and from the
//  1960 manifesto's own glossary, where a generator is "the line or figure
//  that by its movement engenders in its turn a different or new geometric
//  body". Nothing was ported: the pictures were ruled on tracing paper and
//  painted by hand with a fine brush. The proportions, the looks, and the
//  motion are this sketch's own.

import Foundation
import Ollin

/// Focos (Miguel Ángel Vidal, Buenos Aires, from 1960). Where Mac Entyre's
/// generator was a circle, Vidal's was the straight line, and he moved it
/// two ways. Slid parallel to itself by one constant step, it rules a face:
/// a chevron drawn again and again a little nearer the middle, so four faces
/// meeting at a point read as a pyramid seen from above, the Albers squares
/// of his 1967 homage raised into a solid. Turned about a point by one
/// constant angle, it makes a fan, and where the fan's lines are densest the
/// canvas seems to give off light. The points are his lightbulbs, the focos
/// de luz of the 1969 painting: a body of nested chevrons on deep blue with
/// a fan of white and gold lines spread from each corner and from a second
/// point on each diagonal, the fans crossing the faces and each other.
///
/// This sketch deals a body from the seed: an octagon with a vertex at the
/// top, the bottom, and the two sides, and a lit corner between each pair.
/// The four faces are kites from an outer vertex through two corners to the
/// middle, and each one is ruled with chevrons parallel to its two outer
/// edges, one `step` apart, as many as fit before the middle. At each corner
/// a fan of `rays` lines opens across the corner's own angle, a constant
/// angle apart, every line running from the corner to the far side of the
/// body. A second light on each diagonal, part of the way to the middle,
/// opens a fan of its own. `look` picks the ground and the paints. Over one
/// cycle of `seconds` the chevrons advance toward the middle by one step,
/// the outermost fading in and the innermost fading out, and every fan
/// sweeps by one of its own steps the same way, so the picture flows and
/// comes back to itself. A press deals the next body.
///
/// `--export-svg` gives the body back as a polygon and every line as a line
/// at its own two ends, so the families can be read from the file: the
/// chevrons of a face are parallel to its outer edges one step apart, with
/// their ends on the face's axis and inner edges; the lines of a fan all
/// leave one point one constant angle apart and end on the body's outline.
@main
final class Focos: Sketch {
    /// The ground and the paints, after three of the paintings.
    enum Look: String, CaseIterable, ParamOption {
        /// 1969: white and gold on deep blue.
        case azul
        /// 1967: white, orange, and red on black.
        case negro
        /// A later canvas: pale lines on dark violet.
        case violeta
    }

    @Param(icon: "paintpalette") var look = Look.azul
    @Param(8 ... 30, icon: "arrow.down.to.line") var step = 14.0
    @Param(16 ... 120, icon: "light.max") var rays = 40
    @Param(4 ... 60, icon: "clock") var seconds = 12.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    /// A ruled face: a kite from an outer vertex through two corners to the middle.
    struct Face {
        var outer: Vector2
        var left: Vector2
        var right: Vector2
        var color: Color
    }

    /// A light: a fan of lines from one point, one angle apart.
    struct Light {
        var point: Vector2
        var start: Double
        var sweep: Double
        /// The two faces that meet at the light's corner, as one outline:
        /// a ray ends where it leaves them.
        var reach: [Vector2]
        var color: Color
        var weight: Double
    }

    private struct Dealt: Equatable { var look: Look; var seed: Int }
    private var dealtFor: Dealt?
    private var body: [Vector2] = []
    private var faces: [Face] = []
    private var lights: [Light] = []
    private var pressed = false

    private var middle: Vector2 { Vector2(width / 2, height / 2) }

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(look: look, seed: variation)
        if dealtFor != wanted {
            dealtFor = wanted
            deal()
        }
        let phase = (time / max(1, seconds)).truncatingRemainder(dividingBy: 1)

        switch look {
        case .azul:    background(Color(hex: 0x0E3F8C))
        case .negro:   background(Color(hex: 0x0A0808))
        case .violeta: background(Color(hex: 0x2A1040))
        }
        noFill()
        strokeCap(.butt)

        // The body's outline.
        stroke(faces.first?.color ?? .white)
        strokeWeight(0.9)
        drawPolygon(body)

        // The faces: chevrons parallel to the outer edges, one step apart,
        // advancing toward the middle by one step over the cycle.
        for face in faces {
            drawChevrons(of: face, phase: phase)
        }

        // The lights: fans one angle apart, sweeping one step over the cycle.
        for light in lights {
            drawFan(light, phase: phase)
        }
    }

    /// The chevrons of a face. Each is the two outer edges moved inward by
    /// the same distance, so it stays parallel to them; its apex is on the
    /// face's axis and its arms end on the face's inner edges.
    private func drawChevrons(of face: Face, phase: Double) {
        let m = middle
        let axis = (m - face.outer).normalized
        // A chevron `d` in from the outer edges has its apex `d / sin(half)`
        // along the axis, where `half` is the angle between the axis and an
        // outer edge, so consecutive chevrons are `step` apart across the arms.
        let half = acos(max(-1, min(1, axis.dot((face.left - face.outer).normalized))))
        guard half > 0.01 else { return }
        let apexPerStep = step / sin(half)
        let reach = (m - face.outer).length
        let count = Int((reach - 1e-9) / apexPerStep)
        guard count > 0 else { return }
        strokeWeight(0.9)
        for k in 0 ..< count {
            let along = (Double(k) + phase) * apexPerStep
            let apex = face.outer + axis * along
            let fade = min(1, min(Double(k) + phase, Double(count) - (Double(k) + phase)))
            stroke(face.color.withAlpha(fade))
            // Each arm runs from the apex parallel to an outer edge until it
            // meets the inner edge from that side's corner to the middle.
            for (corner, edge) in [(face.left, face.left - face.outer), (face.right, face.right - face.outer)] {
                if let end = Self.hit(from: apex, along: edge, segment: (corner, m)) {
                    drawLine(apex, end)
                }
            }
        }
    }

    /// The fan of a light: `rays` lines from its point across its sweep, one
    /// angle apart, each cut where it leaves the body.
    private func drawFan(_ light: Light, phase: Double) {
        let n = max(2, rays)
        let angleStep = light.sweep / Double(n)
        strokeWeight(light.weight)
        for k in 0 ..< n {
            let along = Double(k) + phase
            let fade = min(1, min(along, Double(n) - along))
            stroke(light.color.withAlpha(fade))
            let angle = light.start + along * angleStep
            if let end = Self.exit(from: light.point, angle: angle, polygon: light.reach) {
                drawLine(light.point, end)
            }
        }
    }

    /// Where a line from `from` along `direction` meets the segment, if it
    /// does ahead of `from`.
    static func hit(from: Vector2, along direction: Vector2, segment: (Vector2, Vector2)) -> Vector2? {
        let (a, b) = segment
        let e = b - a
        let denominator = direction.cross(e)
        guard abs(denominator) > 1e-12 else { return nil }
        let t = (a - from).cross(e) / denominator
        let u = (a - from).cross(direction) / denominator
        guard t > 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        return from + direction * t
    }

    /// Where a ray from `from` at `angle` first leaves the polygon ahead of
    /// `from`, which may itself sit on the outline.
    static func exit(from: Vector2, angle: Double, polygon: [Vector2]) -> Vector2? {
        let direction = Vector2(angle: angle)
        var nearest: (t: Double, point: Vector2)?
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if let p = hit(from: from, along: direction, segment: (a, b)) {
                let t = (p - from).dot(direction)
                if t > 1e-6, nearest == nil || t < nearest!.t { nearest = (t, p) }
            }
        }
        return nearest?.point
    }

    /// Deals the body, its faces, and its lights from the seed.
    private func deal() {
        randomSeed(variation)
        let m = middle
        let s = shortSide
        // The octagon: a diamond's four vertices and a rectangle's four corners.
        let tall = s * random(0.40, 0.46)
        let wide = tall * random(0.9, 1.05)
        let cornerX = wide * random(0.62, 0.78)
        let cornerY = tall * random(0.62, 0.78)
        let top = m + Vector2(0, -tall), bottom = m + Vector2(0, tall)
        let left = m + Vector2(-wide, 0), right = m + Vector2(wide, 0)
        let ul = m + Vector2(-cornerX, -cornerY), ur = m + Vector2(cornerX, -cornerY)
        let lr = m + Vector2(cornerX, cornerY), ll = m + Vector2(-cornerX, cornerY)
        body = [top, ur, right, lr, bottom, ll, left, ul]

        let paints: [Color]
        let gold: Color
        switch look {
        case .azul:    paints = [Color(hex: 0xF4F1E8), Color(hex: 0xF4F1E8), Color(hex: 0xE9D9A6), Color(hex: 0xF4F1E8)]; gold = Color(hex: 0xEFD9A0)
        case .negro:   paints = [Color(hex: 0xF4F1E8), Color(hex: 0xF08A2E), Color(hex: 0xE8402A), Color(hex: 0xF4F1E8)]; gold = Color(hex: 0xF0BE7A)
        case .violeta: paints = [Color(hex: 0xEDE4F7), Color(hex: 0xC9B6E8), Color(hex: 0xEDE4F7), Color(hex: 0xF0C8E0)]; gold = Color(hex: 0xF6DDF0)
        }
        faces = [
            Face(outer: top, left: ul, right: ur, color: paints[0]),
            Face(outer: right, left: ur, right: lr, color: paints[1]),
            Face(outer: bottom, left: lr, right: ll, color: paints[2]),
            Face(outer: left, left: ll, right: ul, color: paints[3]),
        ]

        // A fan at each corner, pointed into the body across part of the
        // corner's own angle, kept to the two faces that meet there; a second
        // light part of the way in along the diagonal, with the same sweep.
        lights = []
        let inward = random(0.3, 0.5)
        let narrowing = random(0.12, 0.22)
        let corners: [(point: Vector2, before: Vector2, after: Vector2, farBefore: Vector2, farAfter: Vector2)] = [
            (ur, top, right, ul, lr), (lr, right, bottom, ur, ll),
            (ll, bottom, left, lr, ul), (ul, left, top, ll, ur),
        ]
        for corner in corners {
            // The corner's interior angle, and its bisector, which points
            // into the body since the body is convex.
            let before = (corner.before - corner.point).normalized
            let after = (corner.after - corner.point).normalized
            let sweep = acos(max(-1, min(1, before.dot(after))))
            let bisector = (before + after).angle
            let trimmed = sweep * (1 - 2 * narrowing)
            let start = bisector - trimmed / 2
            // The two faces as one outline: out along one edge to the next
            // corner, in to the middle, out to the other next corner, back.
            let reach = [corner.point, corner.before, corner.farBefore, m, corner.farAfter, corner.after]
            lights.append(Light(point: corner.point, start: start, sweep: trimmed, reach: reach,
                                color: paints[0], weight: 0.65))
            let inner = corner.point + (m - corner.point) * inward
            lights.append(Light(point: inner, start: start, sweep: trimmed, reach: reach,
                                color: gold.withAlpha(0.75), weight: 0.5))
        }
    }
}
