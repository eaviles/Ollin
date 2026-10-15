import Foundation
import Ollin
import OllinPhysics

/// Nine soft blobs in a box, each made from its outline in one call. Gravity
/// swings slowly from side to side, so the pile sloshes across the floor: the
/// blobs squash against the walls and each other, keep their area, and spring
/// back toward their own lumpy shapes. **Move the mouse** through them to
/// shove them around.
///
/// Each blob starts as a `Shape`, a circle whose radius wanders with looping
/// noise, and `addSoftBody(from:)` turns it into a ring of particles that
/// holds its area and keeps every other outline out. The blob draws from its
/// own particles as a smooth closed curve, so what you see is exactly what
/// the simulation holds.
@main
final class Blobs: Sketch {
    let world = World()

    /// One blob: the body and the color it draws in.
    struct Blob {
        let body: SoftBody
        let color: Color
    }

    var blobs: [Blob] = []

    let palette: [Color] = [
        Color(red: 0.96, green: 0.44, blue: 0.40),   // coral
        Color(red: 0.98, green: 0.76, blue: 0.30),   // amber
        Color(red: 0.36, green: 0.78, blue: 0.72),   // teal
        Color(red: 0.62, green: 0.52, blue: 0.90),   // violet
        Color(red: 0.66, green: 0.84, blue: 0.36),   // lime
        Color(red: 0.42, green: 0.72, blue: 0.94),   // sky
        Color(red: 0.94, green: 0.58, blue: 0.74),   // rose
        Color(red: 0.98, green: 0.62, blue: 0.36),   // tangerine
        Color(red: 0.55, green: 0.80, blue: 0.86)    // aqua
    ]

    override func setup() throws {
        world.bounds = bounds
        world.drag = 0.02

        // Three rows of three, each blob a lumpy circle of its own.
        for (k, color) in palette.enumerated() {
            let radius = random(95, 135) * scale
            let center = Vector2((Double(k % 3) + 0.5) * width / 3,
                                 (Double(k / 3) + 0.5) * height / 3.6)
            let lumpiness = random(0.1, 0.3)
            let seed = random(100)
            let outline = (0 ..< 64).map { i in
                let turn = Double(i) / 64
                let wobble = 1 + lumpiness * (noise(seed, loop: turn) - 0.5) * 2
                return center + Vector2(angle: turn * .tau, length: radius * wobble)
            }
            let body = try world.addSoftBody(from: Shape(outline), spacing: 10 * scale,
                                             stiffness: 0.7, shapeMemory: 0.15)
            blobs.append(Blob(body: body, color: color))
        }
    }

    override func draw() {
        background(Color(white: 0.1))

        // Down, swinging half a right angle either way every twenty seconds.
        let tilt = sin(time * .tau / 20) * .pi / 4
        world.gravity = Vector2(angle: .pi / 2 + tilt, length: 1400 * scale)
        shoveFromCursor()
        world.advance(by: deltaTime)

        strokeWeight(2 * scale)
        stroke(Color(white: 0, alpha: 0.25))
        for blob in blobs {
            fill(blob.color)
            drawCurve(blob.body.shape.contours[0].points, closed: true)
        }

        // A soft highlight so the blobs read as glossy.
        noStroke()
        fill(Color(white: 1, alpha: 0.18))
        for blob in blobs {
            drawCircle(center: blob.body.center + Vector2(-14, -18) * scale, radius: 12 * scale)
        }
    }

    /// Push particles away from the mouse, falling off with distance, so a
    /// sweep of the cursor scatters the blobs.
    func shoveFromCursor() {
        guard mouseX != 0 || mouseY != 0 else { return }   // the mouse has not moved yet
        let reach = 160 * scale
        for blob in blobs {
            for p in blob.body.particles {
                let away = p.position - mouse
                let distance = away.length
                guard distance > 0, distance < reach else { continue }
                let falloff = 1 - distance / reach
                p.push(away.normalized * (falloff * falloff * 6 * scale))
            }
        }
    }
}
