import Ollin
import Foundation

// The sculpt block: combine mode and melt amount as mutable state, so a form reads
// top to bottom like working clay. Shapes add() on (the default) or carve() away,
// melting over the current blend(_:) radius, and flipping one verb turns a bump into
// a dent. A little vessel thrown a line at a time: body, melted-on foot and lip,
// a carved hollow, two hard handles, and a scooped pour spout.
@main
final class RaymarchedClay: Sketch {
    override func draw() {
        raymarchResolution(0.5)
        background(Color(hex: 0x131018))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.35), target: Vector3(0, 0.1, 0), radius: 6.2,
                    elevation: 0.3, fieldOfView: .pi / 4, near: 0.1, far: 40)

        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.15, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.clay)

        let breathe = 1.0 + sin(t * 1.1) * 0.06

        sculpt {
            // The body, then a foot and a lip melt on.
            blend(0.3)
            fill(Color(hex: 0xd96f4e))
            withState { scale(breathe); drawSphere(radius: 1.0) }
            withState { translate(0, -1.0, 0); drawCylinder(radius: 0.55, height: 0.5) }
            fill(Color(hex: 0xe8a06a))
            withState { translate(0, 0.95, 0); drawTorus(radius: 0.5, tube: 0.16) }

            // Carve the hollow, softly; then a crisp scoop for the pour spout.
            carve()
            withState { translate(0, 1.1, 0); drawSphere(radius: 0.52) }
            blend(0.08)
            withState {
                translate(0.62, 1.05, 0)
                rotateZ(-0.5)
                drawBox(width: 0.5, height: 0.3, depth: 0.34)
            }

            // Back to adding, hard: two little handles that stay crisp.
            add()
            blend(0.05)
            fill(Color(hex: 0x8a5a44))
            for side in [-1.0, 1.0] {
                withState {
                    translate(0, 0.35, side * 1.05)
                    rotateX(.pi / 2)
                    drawTorus(radius: 0.34, tube: 0.09)
                }
            }
        }
    }
}
