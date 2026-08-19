// figure: gif duration=6 fps=15 width=560
//
// Guide figure (Chapter 19): a light with a body. One warm rect panel over a
// small set, breathing between a small square and a large one while its
// radiance scales down to keep the poured light steady. Everything soft
// follows the size together: the highlight on the sphere is the panel's own
// reflection growing, the shading wraps further past the terminator, and the
// cast shadows spread from crisp to broad.
import Ollin

final class LightWithABody: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    // A flat single-color matcap for the glowing panel prop (an emissive look
    // that ignores the scene lighting), cached because an Image keeps its texture.
    let panelGlow = Image(width: 1, height: 1,
                          color: Color(hue: 0.09, saturation: 0.22, brightness: 1.0))

    override func draw() {
        background(Color(hex: 0x141821))
        camera(.perspective(eye: Vector3(0, 4.2, 9.6), target: Vector3(0, 1.1, 0),
                            fieldOfView: .pi / 4.2))
        ambientLight(Color(white: 0.07))

        // The softbox breathes; dividing the intensity by its area keeps the
        // total light steady, so only the softness changes.
        let side = 1.0 + pingPong(over: 6) * 2.2
        let facing = Vector3(0.55, -0.58, 0.6)          // aimed down across the set
        rectLight(Color(hue: 0.09, saturation: 0.22, brightness: 1.0),
                  at: Vector3(-3.4, 4.8, -1.2), direction: facing,
                  width: side, height: side, intensity: 70 / (side * side))
        castShadows()
        shadowSamples(8)

        fill(Color(hex: 0x8A94A6))
        material(.matte)
        withState { translate(0, -0.02, 0); drawMesh(Mesh.plane(width: 15, depth: 10)) }

        // A glossy sphere (its highlight is the panel's reflection) and a matte
        // pillar (its shadow fans out and softens as it falls away).
        withState {
            translate(1.1, 0.8, 0.7)
            fill(Color(hex: 0xE2643C))
            material(.glossy)
            drawSphere(radius: 0.8)
        }
        withState {
            translate(-1.0, 1.05, -0.7)
            rotateY(0.4)
            fill(Color(hex: 0x2C8C86))
            material(.plastic)
            drawBox(width: 0.9, height: 2.1, depth: 0.9)
        }

        // The panel itself, drawn as a glowing slab in the same pose so its
        // changing size is visible in frame (the yaw/pitch compose to `facing`).
        // It sits a step *behind* the emitting plane: a casting panel treats any
        // geometry in front of that plane, its own prop included, as an
        // occluder, so a slab drawn exactly on it would shadow the whole set.
        let prop = Vector3(-3.4, 4.8, -1.2) - facing * 0.15
        withState {
            translate(prop.x, prop.y, prop.z)
            rotateY(0.742)
            rotateX(0.619)
            fill(.white)
            matcap(panelGlow)
            drawBox(width: side, height: side, depth: 0.05)
        }
    }
}
