// figure: frame=0
//
// Guide figure (Chapter 22): the scattering transmittance. Three skin bodies with
// the key light *behind* them and a shadow caster on, so the faces we see are
// their dark sides: a slab as thin as a leaf floods through blood-red, a deep
// slab stays dark except where the crossing is short at its rim, and a ball
// carries a warm crescent where its edge thins. The thin one is the point.
import Ollin

final class Translucency: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0x14161C))
        camera(.perspective(eye: Vector3(0, 1.0, 8.2), target: Vector3(0, 0.75, 0),
                            fieldOfView: .pi / 4.3))
        toneMap(.aces, exposure: 1.1)
        // The key travels toward the camera, so every body shows its unlit side;
        // the caster is what lets the material measure its own thickness.
        directionalLight(.white, direction: Vector3(0.18, -0.22, 1), intensity: 1.45)
        castShadows()
        noStroke()

        fill(Color(red: 0.92, green: 0.72, blue: 0.62))
        material(.skin(radius: 0.12))
        let bodies: [(String, Double)] = [("thin", 0.16), ("deep", 1.7)]
        for (index, body) in bodies.enumerated() {
            withState {
                translate(Double(index) * 2.3 - 2.5, 1.05, 0)
                drawBox(width: 1.8, height: 2.1, depth: body.1)
                label(body.0, at: Vector3(0, -1.26, 0))
            }
        }
        withState {
            translate(2.4, 0.55, 0.4)
            drawSphere(radius: 0.62)
            label("round", at: Vector3(0, -0.76, 0))
        }
        withState {
            translate(0, -0.55, 0)
            fill(Color(white: 0.35)); material(.roughPlastic)
            drawBox(width: 24, height: 0.3, depth: 14)
        }
    }

    private func label(_ text: String, at position: Vector3) {
        withBillboard(at: position) {
            noStroke()
            fill(.white)
            textSize(22)
            textAlign(.center, .middle)
            drawText(text, 0, 0)
        }
    }
}
